const std = @import("std");
const math = std.math;
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const basis = @import("basis.zig");
const attenuation = @import("attenuation.zig");
const common = @import("../root.zig");

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
        const trace_r = gaussTrace(n, n_gauss, R);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

        const D = if (q_is_zero) blk: {
            break :blk T.*;
        } else blk: {
            const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
            break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
        };

        var rd: basis.Mat = undefined;
        basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);

        const U = basis.semulAdd(n, R, E, &rd);

        var tu: basis.Mat = undefined;
        basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);

        const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);

        var td: basis.Mat = undefined;
        basis.smulInto(&td, n, n_gauss, threshold_mul, T, &D);

        const T_new = basis.esmulSemulAdd(n, E, &D, T, &td);

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
            for (0..geo.nmutot) |imu| {
                const e = E.data[imu];
                E.data[imu] = e * e;
            }
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

pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_max_indices: ?[]const usize,
    phase_kernel_cache: ?[]basis.PhaseKernel,
    phase_kernel_valid: ?[]bool,
    rt_active: ?[]bool,
) void {
    const nlayer = layers.len;
    rt[0] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[0] = false;
    if (phase_kernel_valid) |valid| @memset(valid, false);

    for (0..nlayer) |layer_idx| {
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];
        if (i_fourier >= basis.max_phase_coef) {
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            continue;
        }

        const phase_coefs = layer.phase_coefficients;
        const max_phase_index = if (layer_phase_max_indices) |indices|
            indices[layer_idx]
        else
            phase_functions.maxPhaseCoefficientIndex(phase_coefs);
        if (i_fourier > max_phase_index) {
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            continue;
        }
        if (layer.optical_depth < 1.0e-20 or layer.scattering_optical_depth <= 0.0 or layer.single_scatter_albedo <= 0.0) {
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            if (rt_active) |active| active[rt_idx] = false;
            continue;
        }

        var z = basis.fillZplusZminFromBasisLimited(
            i_fourier,
            phase_coefs,
            max_phase_index,
            geo,
            plm_basis,
        );
        if (phase_kernel_cache) |cache| {
            cache[rt_idx] = z;
            if (phase_kernel_valid) |valid| valid[rt_idx] = true;
        }
        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        var max_beta_eff: f64 = 0.0;
        for (i_fourier..max_phase_index + 1) |ic| {
            const icf: f64 = @floatFromInt(ic);
            const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
            if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
        }
        const a_eff = a * max_beta_eff;

        var use_doubling = false;
        var b_start = b;
        var ndouble: usize = 0;

        if (controls.scattering == .multiple and a_eff * b > controls.threshold_doubl) {
            // DECISION:
            //   Trigger doubling only when the scaled optical thickness crosses
            //   the configured threshold.
            use_doubling = true;
            var bd = b;
            for (0..60) |_| {
                bd /= 2.0;
                ndouble += 1;
                if (a_eff * bd < controls.threshold_doubl) break;
            }
            b_start = bd;
        }

        var E = basis.Vec.zero(geo.nmutot);
        for (0..geo.nmutot) |imu| {
            E.data[imu] = math.exp(-b_start / @max(geo.u[imu], 1.0e-12));
        }

        var R = singleScatterR(a, &E, &z.Zmin, geo);
        var T = singleScatterT(a, b_start, &E, &z.Zplus, geo);

        if (use_doubling) {
            if (i_fourier == 0 and controls.renorm_phase_function) {
                renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
                R = singleScatterR(a, &E, &z.Zmin, geo);
                T = singleScatterT(a, b_start, &E, &z.Zplus, geo);
            }
            doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E);
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
