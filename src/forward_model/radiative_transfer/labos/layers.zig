const std = @import("std");
const math = std.math;
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../root.zig");
const Trace = @import("../../performance_trace.zig");

const phase_odd_reciprocal = blk: {
    var values: [basis.max_phase_coef]f64 = undefined;
    for (&values, 0..) |*value, idx| {
        const idx_f: f64 = @floatFromInt(idx);
        value.* = 1.0 / (2.0 * idx_f + 1.0);
    }
    break :blk values;
};

pub const LayerRT = basis.LayerRT;

fn locateLowerIndex(values: []const f64, target: f64) usize {
    if (values.len <= 1) return 0;
    var index: usize = 0;
    while (index + 1 < values.len and values[index + 1] < target) : (index += 1) {}
    return index;
}

// PUB FOR TEST: re-exported via labos/internal.zig.
pub fn zeroFourierIntegral(
    zplus: *const basis.Mat,
    zmin: *const basis.Mat,
    geo: *const basis.Geometry,
    column_index: usize,
) f64 {
    const column_weight = @max(geo.w[column_index], 1.0e-30);
    var integral: f64 = 0.0;
    for (0..geo.n_gauss) |imu| {
        const row_weight = @max(geo.w[imu], 1.0e-30);
        integral += geo.wg[imu] *
            ((zplus.get(imu, column_index) + zmin.get(imu, column_index)) /
                (row_weight * column_weight));
    }
    return integral;
}

// PUB FOR TEST: re-exported via labos/internal.zig.
pub fn renormalizeZeroFourierPhaseKernel(
    geo: *const basis.Geometry,
    zplus: *basis.Mat,
    zmin: *basis.Mat,
) void {
    if (geo.n_gauss == 0 or geo.nmutot == 0) return;

    var zp = [_][basis.max_nmutot]f64{.{0.0} ** basis.max_nmutot} ** basis.max_nmutot;
    for (0..geo.nmutot) |imu0| {
        const column_weight = @max(geo.w[imu0], 1.0e-30);
        for (0..geo.nmutot) |imu| {
            const row_weight = @max(geo.w[imu], 1.0e-30);
            zp[imu][imu0] = zplus.data[imu * zplus.n + imu0] / (row_weight * column_weight);
        }
    }

    for (0..geo.n_gauss) |imu0| {
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.data[imu * zmin.n + imu0] / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const denominator = zp[imu0][imu0] * geo.wg[imu0];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = (2.0 - integral) / denominator;
        zp[imu0][imu0] *= 1.0 + fraction;
    }

    for (geo.n_gauss..geo.nmutot) |imu0| {
        const target_mu = geo.u[imu0];
        var integral: f64 = 0.0;
        for (0..geo.n_gauss) |imu| {
            integral += geo.wg[imu] * (zp[imu][imu0] + zmin.data[imu * zmin.n + imu0] / (@max(geo.w[imu], 1.0e-30) * @max(geo.w[imu0], 1.0e-30)));
        }
        const delta = 2.0 - integral;

        if (target_mu > geo.ug[0] and target_mu < geo.ug[geo.n_gauss - 1]) {
            const low = @min(locateLowerIndex(geo.ug[0..geo.n_gauss], target_mu), geo.n_gauss - 2);
            const high = low + 1;
            const span = geo.ug[high] - geo.ug[low];
            if (span <= 0.0) continue;
            const low_weight = (target_mu - geo.ug[low]) / span;
            const high_weight = (geo.ug[high] - target_mu) / span;
            const low_denominator = zp[imu0][low] * geo.wg[low];
            const high_denominator = zp[imu0][high] * geo.wg[high];
            if (@abs(low_denominator) > 1.0e-30) {
                const fraction = low_weight * delta / low_denominator;
                zp[imu0][low] *= 1.0 + fraction;
                zp[low][imu0] = zp[imu0][low];
            }
            if (@abs(high_denominator) > 1.0e-30) {
                const fraction = high_weight * delta / high_denominator;
                zp[imu0][high] *= 1.0 + fraction;
                zp[high][imu0] = zp[imu0][high];
            }
            continue;
        }

        const edge = if (target_mu < geo.ug[0]) 0 else geo.n_gauss - 1;
        const denominator = zp[imu0][edge] * geo.wg[edge];
        if (@abs(denominator) <= 1.0e-30) continue;
        const fraction = delta / denominator;
        zp[imu0][edge] *= 1.0 + fraction;
        zp[edge][imu0] = zp[imu0][edge];
    }

    for (0..geo.nmutot) |imu0| {
        const column_weight = geo.w[imu0];
        for (0..geo.nmutot) |imu| {
            zplus.data[imu * zplus.n + imu0] = zp[imu][imu0] * geo.w[imu] * column_weight;
        }
    }
}

// Rsingle: single-scattering reflection for a homogeneous layer.
fn singleScatterR(
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    if (n == 12) return singleScatterR12(a, E, Zmin, geo);
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;
        for (0..n) |i| {
            const eer = E.data[i] * ej;
            result.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += n;
        }
    }
    return result;
}

fn singleScatterR12(
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    var result = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;
        inline for (0..12) |i| {
            const eer = E.data[i] * ej;
            result.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += 12;
        }
    }
    return result;
}

// Tsingle: single-scattering transmission for a homogeneous layer.
fn singleScatterT(
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    const n = geo.nmutot;
    if (n == 12) return singleScatterT12(a, b, E, Zplus, geo);
    var result = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;
        for (0..n) |i| {
            var eet: f64 = undefined;
            if (geo.dmu_same[idx]) {
                eet = b * E.data[i];
            } else {
                eet = E.data[i] - ej;
            }
            result.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += n;
        }
    }
    return result;
}

fn singleScatterT12(
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) basis.Mat {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    var result = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;
        inline for (0..12) |i| {
            var eet: f64 = undefined;
            if (geo.dmu_same[idx]) {
                eet = b * E.data[i];
            } else {
                eet = E.data[i] - ej;
            }
            result.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += 12;
        }
    }
    return result;
}

fn gaussTrace(n: usize, n_gauss: usize, mat: *const basis.Mat) f64 {
    if (n == 12 and n_gauss == 10) {
        var trace = mat.data[0];
        trace += mat.data[13];
        trace += mat.data[26];
        trace += mat.data[39];
        trace += mat.data[52];
        trace += mat.data[65];
        trace += mat.data[78];
        trace += mat.data[91];
        trace += mat.data[104];
        trace += mat.data[117];
        return trace;
    }
    var trace: f64 = 0.0;
    for (0..n_gauss) |k| trace += mat.data[k * n + k];
    return trace;
}

inline fn squareAttenuation(n: usize, E: *basis.Vec) void {
    if (n == basis.max_nmutot) return squareAttenuation12(E);

    for (0..n) |imu| {
        const e = E.data[imu];
        E.data[imu] = e * e;
    }
}

inline fn squareAttenuation12(E: *basis.Vec) void {
    inline for (0..basis.max_nmutot) |imu| {
        const e = E.data[imu];
        E.data[imu] = e * e;
    }
}

// Perform ndouble doubling steps on R, T, E for a layer.
fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    geo: *const basis.Geometry,
    b_start: f64,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
) void {
    var b = b_start;
    for (0..ndouble) |_| {
        Trace.plotU("doubling_steps", 1);
        const trace_r = gaussTrace(n, n_gauss, R);
        const trace_t = gaussTrace(n, n_gauss, T);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

        const D = if (q_is_zero) blk: {
            Trace.plotU("doubling_qseries_skipped", 1);
            break :blk T.*;
        } else blk: {
            Trace.plotU("doubling_qseries_nonzero", 1);
            Trace.plotU("matrix_qseries", 1);
            Trace.plotU("matrix_smul_q_product", 1);
            Trace.plotU("matrix_smul_add_semul3", 1);
            const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
            break :blk basis.smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, &Q, E, T, trace_t);
        };
        const trace_d = if (q_is_zero) trace_t else gaussTrace(n, n_gauss, &D);

        Trace.plotU("matrix_smul_rd", 1);
        var rd: basis.Mat = undefined;
        const rd_nonzero = basis.smulIntoKnownTracesIfNonzero(&rd, n, n_gauss, threshold_mul, trace_r, trace_d, R, &D);

        const U = if (rd_nonzero) blk: {
            Trace.plotU("matrix_smul_rd_nonzero", 1);
            Trace.plotU("matrix_semul_add", 1);
            break :blk basis.semulAdd(n, R, E, &rd);
        } else blk: {
            Trace.plotU("matrix_semul", 1);
            break :blk basis.semul(n, R, E);
        };
        const trace_u = gaussTrace(n, n_gauss, &U);

        Trace.plotU("matrix_smul_tu", 1);
        var tu: basis.Mat = undefined;
        const tu_nonzero = basis.smulIntoKnownTracesIfNonzero(&tu, n, n_gauss, threshold_mul, trace_t, trace_u, T, &U);

        const R_new = if (tu_nonzero) blk: {
            Trace.plotU("matrix_smul_tu_nonzero", 1);
            Trace.plotU("matrix_mat_add_esmul3", 1);
            break :blk basis.matAddEsmul3(n, R, E, &U, &tu);
        } else blk: {
            Trace.plotU("matrix_mat_add_esmul", 1);
            break :blk basis.matAddEsmul(n, R, E, &U);
        };

        Trace.plotU("matrix_smul_td", 1);
        var td: basis.Mat = undefined;
        const td_nonzero = basis.smulIntoKnownTracesIfNonzero(&td, n, n_gauss, threshold_mul, trace_t, trace_d, T, &D);

        const T_new = if (td_nonzero) blk: {
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            break :blk basis.esmulSemulAdd(n, E, &D, T, &td);
        } else blk: {
            Trace.plotU("matrix_esmul_semul", 1);
            break :blk basis.esmulSemul(n, E, &D, T);
        };

        // PARITY: DISAMAR's whole-array assignments evaluate both RHS values
        // from the pre-step operators before storing the doubled layer state.
        R.* = R_new;
        T.* = T_new;

        b *= 2.0;
        if (b < 0.001) {
            for (0..geo.nmutot) |imu| {
                E.data[imu] = math.exp(-b / @max(geo.u[imu], 1.0e-12));
            }
        } else {
            Trace.plotU("doubling_square_evals", @intCast(n));
            squareAttenuation(n, E);
        }
    }
}

fn maxLayerPhaseCoefficientIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |layer| {
        max_index = @max(max_index, phase_functions.maxPhaseCoefficientIndex(layer.phase_coefficients));
    }
    return max_index;
}

pub fn fillLayerPhaseMaxIndices(
    layer_phase_max_indices: []usize,
    layers: []const common.LayerInput,
) void {
    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    for (layers, layer_phase_max_indices[0..layers.len]) |layer, *max_index| {
        max_index.* = phase_functions.maxPhaseCoefficientIndex(layer.phase_coefficients);
    }
}

pub fn fillLayerEffectiveScatteringSuffixes(
    suffixes: []f64,
    layers: []const common.LayerInput,
    layer_phase_max_indices: []const usize,
) void {
    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    std.debug.assert(suffixes.len >= layers.len * basis.max_phase_coef);
    for (layers, layer_phase_max_indices[0..layers.len], 0..) |layer, max_phase_index, layer_idx| {
        const layer_suffixes = suffixes[layer_idx * basis.max_phase_coef ..][0..basis.max_phase_coef];
        @memset(layer_suffixes, 0.0);
        var suffix: f64 = 0.0;
        var reverse_index = @min(max_phase_index + 1, basis.max_phase_coef);
        while (reverse_index > 0) {
            reverse_index -= 1;
            const beta_eff = @abs(layer.phase_coefficients[reverse_index]) * phase_odd_reciprocal[reverse_index];
            suffix = @max(suffix, beta_eff);
            layer_suffixes[reverse_index] = suffix;
        }
    }
}

pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_max_indices: ?[]const usize,
    layer_effective_scattering_suffixes: ?[]const f64,
    phase_kernel_cache: ?[]basis.PhaseKernel,
    phase_kernel_valid: ?[]bool,
    rt_active: ?[]bool,
) void {
    const nlayer = layers.len;
    rt[0] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[0] = false;
    if (phase_kernel_valid) |valid| @memset(valid, false);

    for (0..nlayer) |layer_idx| {
        Trace.plotU("layer_visits", 1);
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];
        if (i_fourier >= basis.max_phase_coef) {
            Trace.plotU("layer_skipped_fourier_out_of_range", 1);
            if (rt_active) |active| active[rt_idx] = false;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            continue;
        }

        const phase_coefs = layer.phase_coefficients;
        const max_phase_index = if (layer_phase_max_indices) |indices|
            indices[layer_idx]
        else
            phase_functions.maxPhaseCoefficientIndex(phase_coefs);
        if (i_fourier > max_phase_index) {
            Trace.plotU("layer_skipped_fourier_out_of_range", 1);
            if (rt_active) |active| active[rt_idx] = false;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            continue;
        }
        if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0 or layer.single_scatter_albedo <= 0.0) {
            Trace.plotU("layer_skipped_empty_optics", 1);
            if (rt_active) |active| active[rt_idx] = false;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            continue;
        }

        var z = z: {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.phase_matrix");
            defer zone.end();
            break :z basis.fillZplusZminFromBasisLimited(
                i_fourier,
                phase_coefs,
                max_phase_index,
                geo,
                plm_basis,
            );
        };
        Trace.plotU("phase_matrix_builds", 1);
        if (phase_kernel_cache) |cache| {
            cache[rt_idx] = z;
            if (phase_kernel_valid) |valid| valid[rt_idx] = true;
        }
        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        const max_beta_eff = max_beta_eff: {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.effective_scattering");
            defer zone.end();
            if (layer_effective_scattering_suffixes) |suffixes| {
                std.debug.assert(suffixes.len >= layers.len * basis.max_phase_coef);
                break :max_beta_eff suffixes[layer_idx * basis.max_phase_coef + i_fourier];
            }
            var suffix: f64 = 0.0;
            var scanned_terms: usize = 0;
            var nonzero_terms: usize = 0;
            for (i_fourier..max_phase_index + 1) |ic| {
                scanned_terms += 1;
                if (phase_coefs[ic] != 0.0) nonzero_terms += 1;
                const beta_eff = @abs(phase_coefs[ic]) * phase_odd_reciprocal[ic];
                if (beta_eff > suffix) suffix = beta_eff;
            }
            Trace.plotU("phase_coeff_terms_scanned", @intCast(scanned_terms));
            Trace.plotU("phase_coeff_terms_nonzero", @intCast(nonzero_terms));
            break :max_beta_eff suffix;
        };
        const a_eff = a * max_beta_eff;

        var use_doubling = false;
        var b_start = b;
        var ndouble: usize = 0;

        if (controls.scattering == .multiple and a_eff * b > controls.performance_thresholds.threshold_doubl) {
            // DECISION:
            //   Trigger doubling only when the scaled optical thickness crosses
            //   the configured threshold.
            use_doubling = true;
            var bd = b;
            for (0..60) |_| {
                bd /= 2.0;
                ndouble += 1;
                if (a_eff * bd < controls.performance_thresholds.threshold_doubl) break;
            }
            b_start = bd;
        }

        var E = basis.Vec.zero(geo.nmutot);
        {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.initial_exponential");
            defer zone.end();
            for (0..geo.nmutot) |imu| {
                E.data[imu] = math.exp(-b_start / @max(geo.u[imu], 1.0e-12));
            }
        }
        Trace.plotU("initial_exp_evals", @intCast(geo.nmutot));

        var R: basis.Mat = undefined;
        var T: basis.Mat = undefined;
        {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.single_scatter");
            defer zone.end();
            R = singleScatterR(a, &E, &z.Zmin, geo);
            T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
        }
        Trace.plotU("single_scatter_r", 1);
        Trace.plotU("single_scatter_t", 1);

        if (use_doubling) {
            Trace.plotU("doubled_layers", 1);
            if (i_fourier == 0 and controls.renorm_phase_function) {
                {
                    const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.phase_renormalization");
                    defer zone.end();
                    renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
                }
                Trace.plotU("phase_renormalizations", 1);
                {
                    const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.single_scatter");
                    defer zone.end();
                    R = singleScatterR(a, &E, &z.Zmin, geo);
                    T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
                }
                Trace.plotU("single_scatter_r", 1);
                Trace.plotU("single_scatter_t", 1);
            }
            {
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.doubling");
                defer zone.end();
                doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.performance_thresholds.threshold_mul, geo, b_start, &R, &T, &E);
            }
        }

        rt[rt_idx].R = R;
        rt[rt_idx].T = T;
        if (rt_active) |active| active[rt_idx] = a != 0.0;
    }
}

pub fn calcRTlayersTangentIntoWithBasis(
    rt_tangent: []LayerRT,
    layers: []const common.LayerInput,
    state: common.Jacobian.State,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
) void {
    const nlevel = layers.len + 1;
    std.debug.assert(rt_tangent.len >= nlevel);
    for (rt_tangent[0..nlevel]) |*layer_rt| layer_rt.* = zeroLayerRt(geo.nmutot);
    const eps: f64 = 1.0e-5;
    const inv_span = 0.5 / eps;
    for (layers, 0..) |layer, layer_idx| {
        const d_optical_depth = common.Jacobian.get(layer.optical_depth_jacobian, state);
        const d_scattering_optical_depth = common.Jacobian.get(layer.scattering_optical_depth_jacobian, state);
        const d_single_scatter_albedo = common.Jacobian.get(layer.single_scatter_albedo_jacobian, state);
        if (d_optical_depth == 0.0 and d_scattering_optical_depth == 0.0 and d_single_scatter_albedo == 0.0) continue;

        var plus_layer = layer;
        plus_layer.optical_depth = @max(layer.optical_depth + eps * d_optical_depth, 0.0);
        plus_layer.scattering_optical_depth = @max(layer.scattering_optical_depth + eps * d_scattering_optical_depth, 0.0);
        plus_layer.single_scatter_albedo = std.math.clamp(layer.single_scatter_albedo + eps * d_single_scatter_albedo, 0.0, 1.0);
        var minus_layer = layer;
        minus_layer.optical_depth = @max(layer.optical_depth - eps * d_optical_depth, 0.0);
        minus_layer.scattering_optical_depth = @max(layer.scattering_optical_depth - eps * d_scattering_optical_depth, 0.0);
        minus_layer.single_scatter_albedo = std.math.clamp(layer.single_scatter_albedo - eps * d_single_scatter_albedo, 0.0, 1.0);

        const plus_layers = [_]common.LayerInput{plus_layer};
        const minus_layers = [_]common.LayerInput{minus_layer};
        var plus_rt: [2]LayerRT = undefined;
        var minus_rt: [2]LayerRT = undefined;
        calcRTlayersIntoWithBasis(
            &plus_rt,
            &plus_layers,
            i_fourier,
            geo,
            controls,
            plm_basis,
            null,
            null,
            null,
            null,
            null,
        );
        calcRTlayersIntoWithBasis(
            &minus_rt,
            &minus_layers,
            i_fourier,
            geo,
            controls,
            plm_basis,
            null,
            null,
            null,
            null,
            null,
        );
        rt_tangent[layer_idx + 1] = layerRtDifferenceScaled(plus_rt[1], minus_rt[1], inv_span);
    }
}

fn layerRtDifferenceScaled(plus: LayerRT, minus: LayerRT, scale: f64) LayerRT {
    return .{
        .R = matDifferenceScaled(plus.R, minus.R, scale),
        .T = matDifferenceScaled(plus.T, minus.T, scale),
    };
}

fn matDifferenceScaled(plus: basis.Mat, minus: basis.Mat, scale: f64) basis.Mat {
    var result = basis.Mat{ .data = undefined, .n = plus.n };
    for (0..plus.n * plus.n) |index| {
        result.data[index] = (plus.data[index] - minus.data[index]) * scale;
    }
    return result;
}

fn zeroLayerRt(n: usize) LayerRT {
    return .{
        .R = basis.Mat.zero(n),
        .T = basis.Mat.zero(n),
    };
}

pub fn calcRTlayersInto(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
) void {
    const plm_basis = basis.FourierPlmBasis.init(
        i_fourier,
        maxLayerPhaseCoefficientIndex(layers),
        geo,
    );
    calcRTlayersIntoWithBasis(
        rt,
        layers,
        i_fourier,
        geo,
        controls,
        &plm_basis,
        null,
        null,
        null,
        null,
        null,
    );
}

pub fn calcRTlayers(
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
) [attenuation.AttenArray.max_levels]LayerRT {
    var rt: [attenuation.AttenArray.max_levels]LayerRT = undefined;
    calcRTlayersInto(rt[0 .. layers.len + 1], layers, i_fourier, geo, controls);
    return rt;
}

pub fn fillSurface(
    i_fourier: usize,
    albedo: f64,
    geo: *const basis.Geometry,
) LayerRT {
    const n = geo.nmutot;
    var result: LayerRT = .{
        .R = basis.Mat.zero(n),
        .T = basis.Mat.zero(n),
    };

    if (i_fourier == 0) {
        for (0..n) |j| {
            for (0..n) |i| {
                result.R.set(i, j, geo.w[i] * albedo * geo.w[j]);
            }
        }
    }

    return result;
}
