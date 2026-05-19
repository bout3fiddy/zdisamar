const std = @import("std");
const math = std.math;
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
// hot path:
//   when: during zero-Fourier phase preparation before RT layer construction
//   work: normalizes phase coefficients across layers and scattering streams
//   data: layer phase coefficients, Gaussian stream geometry, normalization factors
//   follow: phase coefficient order consumed by fillZplusZmin and layer-doubling
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
// hot path:
//   when: RT layer construction builds single-scatter reflection matrices
//   work: fills R matrix entries from attenuation, Z- phase matrix, and scattering albedo
//   data: output matrix, E attenuation vector, Zmin phase matrix, stream geometry
//   follow: fixed 12x12 variant and calcRTlayersIntoWithBasis
fn fillSingleScatterR(
    out: *basis.Mat,
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    const n = geo.nmutot;
    if (n == 12) return fillSingleScatterR12(out, a, E, Zmin, geo);
    out.* = basis.Mat.zero(n);

    for (0..n) |j| {
        const ej = E.data[j];
        var idx = j;
        for (0..n) |i| {
            const eer = E.data[i] * ej;
            out.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += n;
        }
    }
}

fn fillSingleScatterR12(
    out: *basis.Mat,
    a: f64,
    E: *const basis.Vec,
    Zmin: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    out.* = basis.Mat{ .data = undefined, .n = 12 };

    inline for (0..12) |j| {
        const ej = E.data[j];
        var idx = j;
        inline for (0..12) |i| {
            const eer = E.data[i] * ej;
            out.data[idx] = a * Zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += 12;
        }
    }
}

// Tsingle: single-scattering transmission for a homogeneous layer.
// hot path:
//   when: RT layer construction builds single-scatter transmission matrices
//   work: fills T matrix entries from attenuation, Z+ phase matrix, optical depth, and scattering albedo
//   data: output matrix, E attenuation vector, Zplus phase matrix, stream geometry
//   follow: fixed 12x12 variant and calcRTlayersIntoWithBasis
fn fillSingleScatterT(
    out: *basis.Mat,
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    const n = geo.nmutot;
    if (n == 12) return fillSingleScatterT12(out, a, b, E, Zplus, geo);
    out.* = basis.Mat.zero(n);

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
            out.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += n;
        }
    }
}

fn fillSingleScatterT12(
    out: *basis.Mat,
    a: f64,
    b: f64,
    E: *const basis.Vec,
    Zplus: *const basis.Mat,
    geo: *const basis.Geometry,
) void {
    // INVARIANT: the fixed 12x12 loops assign every active matrix element.
    out.* = basis.Mat{ .data = undefined, .n = 12 };

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
            out.data[idx] = a * Zplus.data[idx] * eet * geo.dmu_min[idx];
            idx += 12;
        }
    }
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
// hot path:
//   when: dynamic-shape LABOS layer doubling is used for a layer/Fourier term
//   work: updates reflection/transmission matrices through q-series products
//   data: R/T matrices, q-series temporaries, stream counts, thresholded matrix products
//   follow: qseriesKnownNonzeroProductInto and smul matrix helpers
fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
) void {
    if (n == basis.max_nmutot and n_gauss == basis.max_gauss) {
        doDouble12x10(ndouble, threshold_mul, R, T, E);
        return;
    }

    var r_storage: basis.Mat = undefined;
    var t_storage: basis.Mat = undefined;
    var current_r = R;
    var current_t = T;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..ndouble) |_| {
        Trace.plotU("doubling_steps", 1);
        const trace_r = gaussTrace(n, n_gauss, current_r);
        const trace_t = gaussTrace(n, n_gauss, current_t);
        const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

        var d_storage: basis.Mat = undefined;
        const D = if (q_is_zero) blk: {
            Trace.plotU("doubling_qseries_skipped", 1);
            break :blk current_t;
        } else blk: {
            Trace.plotU("doubling_qseries_nonzero", 1);
            Trace.plotU("matrix_qseries", 1);
            Trace.plotU("matrix_smul_q_product", 1);
            Trace.plotU("matrix_smul_add_semul3", 1);
            var Q: basis.Mat = undefined;
            basis.qseriesKnownNonzeroProductInto(&Q, n, n_gauss, current_r, current_r);
            basis.smulAddSemul3KnownRightTraceInto(&d_storage, n, n_gauss, threshold_mul, &Q, E, current_t, trace_t);
            break :blk &d_storage;
        };
        const trace_d = if (q_is_zero) trace_t else gaussTrace(n, n_gauss, D);

        Trace.plotU("matrix_smul_rd", 1);
        const rd_nonzero = @abs(trace_r * trace_d) > threshold_mul;

        var U: basis.Mat = undefined;
        if (rd_nonzero) {
            Trace.plotU("matrix_smul_rd_nonzero", 1);
            Trace.plotU("matrix_semul_add", 1);
            basis.semulAddProductKnownNonzeroInto(&U, n, n_gauss, current_r, E, D);
        } else {
            Trace.plotU("matrix_semul", 1);
            basis.semulInto(&U, n, current_r, E);
        }
        const trace_u = gaussTrace(n, n_gauss, &U);

        Trace.plotU("matrix_smul_tu", 1);
        const tu_nonzero = @abs(trace_t * trace_u) > threshold_mul;

        if (tu_nonzero) {
            Trace.plotU("matrix_smul_tu_nonzero", 1);
            Trace.plotU("matrix_mat_add_esmul3", 1);
            basis.matAddEsmul3ProductKnownNonzeroInto(next_r, n, n_gauss, current_r, E, &U, current_t);
        } else {
            Trace.plotU("matrix_mat_add_esmul", 1);
            basis.matAddEsmulInto(next_r, n, current_r, E, &U);
        }

        Trace.plotU("matrix_smul_td", 1);
        const td_nonzero = @abs(trace_t * trace_d) > threshold_mul;

        if (td_nonzero) {
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            if (q_is_zero) {
                basis.esmulSemulSelfAddProductKnownNonzeroInto(next_t, n, n_gauss, E, current_t);
            } else {
                basis.esmulSemulAddProductKnownNonzeroInto(next_t, n, n_gauss, E, D, current_t);
            }
        } else {
            Trace.plotU("matrix_esmul_semul", 1);
            if (q_is_zero) {
                basis.esmulSemulSelfInto(next_t, n, E, current_t);
            } else {
                basis.esmulSemulInto(next_t, n, E, D, current_t);
            }
        }

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        Trace.plotU("doubling_square_evals", @intCast(n));
        squareAttenuation(n, E);
    }

    if (final_in_scratch) {
        R.* = current_r.*;
        T.* = current_t.*;
    }
}

// hot path:
//   when: fixed 12x10 LABOS layer doubling is used for the O2 A route
//   work: updates reflection/transmission matrices through fixed-shape q-series products
//   data: fixed matrix cells, q-series temporaries, precomputed stream geometry
//   follow: doDouble12x10Step and qseriesFromProduct12x10Into
fn doDouble12x10(
    ndouble: usize,
    threshold_mul: f64,
    R: *basis.Mat,
    T: *basis.Mat,
    E: *basis.Vec,
) void {
    var r_storage: basis.Mat = undefined;
    var t_storage: basis.Mat = undefined;
    var current_r = R;
    var current_t = T;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..ndouble) |_| {
        Trace.plotU("doubling_steps", 1);
        doDouble12x10Step(threshold_mul, current_r, current_t, E, next_r, next_t);

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        Trace.plotU("doubling_square_evals", basis.max_nmutot);
        squareAttenuation12(E);
    }

    if (final_in_scratch) {
        R.* = current_r.*;
        T.* = current_t.*;
    }
}

inline fn doDouble12x10Step(
    threshold_mul: f64,
    current_r: *const basis.Mat,
    current_t: *const basis.Mat,
    E: *const basis.Vec,
    next_r: *basis.Mat,
    next_t: *basis.Mat,
) void {
    const trace_r = gaussTrace(basis.max_nmutot, basis.max_gauss, current_r);
    const trace_t = gaussTrace(basis.max_nmutot, basis.max_gauss, current_t);
    const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

    var d_storage: basis.Mat = undefined;
    const D = if (q_is_zero) blk: {
        Trace.plotU("doubling_qseries_skipped", 1);
        break :blk current_t;
    } else blk: {
        Trace.plotU("doubling_qseries_nonzero", 1);
        Trace.plotU("matrix_qseries", 1);
        Trace.plotU("matrix_smul_q_product", 1);
        Trace.plotU("matrix_smul_add_semul3", 1);
        var Q: basis.Mat = undefined;
        basis.qseriesKnownNonzeroProductInto(&Q, basis.max_nmutot, basis.max_gauss, current_r, current_r);
        basis.smulAddSemul3KnownRightTraceInto(&d_storage, basis.max_nmutot, basis.max_gauss, threshold_mul, &Q, E, current_t, trace_t);
        break :blk &d_storage;
    };
    const trace_d = if (q_is_zero) trace_t else gaussTrace(basis.max_nmutot, basis.max_gauss, D);

    Trace.plotU("matrix_smul_rd", 1);
    const rd_nonzero = @abs(trace_r * trace_d) > threshold_mul;

    var U: basis.Mat = undefined;
    if (rd_nonzero) {
        Trace.plotU("matrix_smul_rd_nonzero", 1);
        Trace.plotU("matrix_semul_add", 1);
        basis.semulAddProductKnownNonzeroInto(&U, basis.max_nmutot, basis.max_gauss, current_r, E, D);
    } else {
        Trace.plotU("matrix_semul", 1);
        basis.semulInto(&U, basis.max_nmutot, current_r, E);
    }
    const trace_u = gaussTrace(basis.max_nmutot, basis.max_gauss, &U);

    Trace.plotU("matrix_smul_tu", 1);
    const tu_nonzero = @abs(trace_t * trace_u) > threshold_mul;

    if (tu_nonzero) {
        Trace.plotU("matrix_smul_tu_nonzero", 1);
        Trace.plotU("matrix_mat_add_esmul3", 1);
        basis.matAddEsmul3ProductKnownNonzeroInto(next_r, basis.max_nmutot, basis.max_gauss, current_r, E, &U, current_t);
    } else {
        Trace.plotU("matrix_mat_add_esmul", 1);
        basis.matAddEsmulInto(next_r, basis.max_nmutot, current_r, E, &U);
    }

    Trace.plotU("matrix_smul_td", 1);
    const td_nonzero = @abs(trace_t * trace_d) > threshold_mul;

    if (td_nonzero) {
        Trace.plotU("matrix_smul_td_nonzero", 1);
        Trace.plotU("matrix_esmul_semul_add", 1);
        if (q_is_zero) {
            basis.esmulSemulSelfAddProductKnownNonzeroInto(next_t, basis.max_nmutot, basis.max_gauss, E, current_t);
        } else {
            basis.esmulSemulAddProductKnownNonzeroInto(next_t, basis.max_nmutot, basis.max_gauss, E, D, current_t);
        }
    } else {
        Trace.plotU("matrix_esmul_semul", 1);
        if (q_is_zero) {
            basis.esmulSemulSelfInto(next_t, basis.max_nmutot, E, current_t);
        } else {
            basis.esmulSemulInto(next_t, basis.max_nmutot, E, D, current_t);
        }
    }
}

fn maxLayerPhaseCoefficientIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |*layer| {
        max_index = @max(max_index, layer.phase.maxIndex());
    }
    return max_index;
}

// hot path:
//   when: LABOS workspace precomputes per-layer phase coefficient limits
//   work: scans phase coefficient arrays and records the highest active coefficient per layer
//   data: layer phase coefficient arrays and phase-max-index output
//   follow: calcRTlayersIntoWithBasis Fourier-term skip decisions
pub fn fillLayerPhaseMaxIndices(
    layer_phase_max_indices: []usize,
    layers: []const common.LayerInput,
) void {
    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    for (layers, layer_phase_max_indices[0..layers.len]) |*layer, *max_index| {
        max_index.* = layer.phase.maxIndex();
    }
}

// hot path:
//   when: LABOS workspace precomputes effective scattering suffixes by layer
//   work: scans phase coefficients in reverse order and writes suffix maxima
//   data: layer phase coefficient arrays, phase max indexes, suffix output array
//   follow: calcRTlayersIntoWithBasis effective-scattering lookup
pub fn fillLayerEffectiveScatteringSuffixes(
    suffixes: []f64,
    layers: []const common.LayerInput,
    layer_phase_max_indices: []const usize,
    phase_stride: usize,
) void {
    std.debug.assert(layer_phase_max_indices.len >= layers.len);
    std.debug.assert(phase_stride > 0 and phase_stride <= basis.max_phase_coef);
    std.debug.assert(suffixes.len >= layers.len * phase_stride);
    for (layers, layer_phase_max_indices[0..layers.len], 0..) |*layer, max_phase_index, layer_idx| {
        const layer_suffixes = suffixes[layer_idx * phase_stride ..][0..phase_stride];
        @memset(layer_suffixes, 0.0);
        var suffix: f64 = 0.0;
        var reverse_index = max_phase_index + 1;
        while (reverse_index > 0) {
            reverse_index -= 1;
            const beta_eff = @abs(layer.phase.coefficient(reverse_index)) * phase_odd_reciprocal[reverse_index];
            suffix = @max(suffix, beta_eff);
            if (reverse_index < phase_stride) layer_suffixes[reverse_index] = suffix;
        }
    }
}

// hot path:
//   when: for each layer inside each LABOS Fourier term
//   work: builds phase matrices, effective scattering suffixes, exponentials, single scatter, and doubled RT layers
//   data: layer optical properties, phase basis, RT layer outputs, doubling workspace
//   follow: labos.rt_layer trace zones and fixed 12x10 versus dynamic doubling branches
pub fn calcRTlayersIntoWithBasis(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const basis.Geometry,
    controls: common.RadiativeTransferControls,
    plm_basis: *const basis.FourierPlmBasis,
    layer_phase_max_indices: ?[]const usize,
    layer_effective_scattering_suffixes: ?[]const f64,
    layer_effective_scattering_suffix_stride: usize,
    phase_row_cache: ?[]basis.PhaseKernelRow,
    phase_row_valid: ?[]bool,
    rt_active: ?[]bool,
) void {
    const nlayer = layers.len;
    rt[0] = zeroLayerRt(geo.nmutot);
    if (rt_active) |active| active[0] = false;
    if (phase_row_valid) |valid| @memset(valid, false);

    for (0..nlayer) |layer_idx| {
        Trace.plotU("layer_visits", 1);
        const rt_idx = layer_idx + 1;
        const layer = &layers[layer_idx];
        if (i_fourier >= basis.max_phase_coef) {
            Trace.plotU("layer_skipped_fourier_out_of_range", 1);
            if (rt_active) |active| active[rt_idx] = false;
            rt[rt_idx] = zeroLayerRt(geo.nmutot);
            continue;
        }

        const phase = layer.phase;
        const max_phase_index = if (layer_phase_max_indices) |indices|
            indices[layer_idx]
        else
            phase.maxIndex();
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
            break :z basis.fillZplusZminFromWeightedPhaseLimited(
                i_fourier,
                phase.aerosol_weight,
                phase.cloud_weight,
                phase.rayleigh2_weight,
                phase.aerosol_phase_coefficients,
                phase.cloud_phase_coefficients,
                max_phase_index,
                geo,
                plm_basis,
            );
        };
        Trace.plotU("phase_matrix_builds", 1);
        if (phase_row_cache) |cache| {
            cachePhaseKernelViewRow(cache, rt_idx, &z, geo.viewIdx());
            if (phase_row_valid) |valid| valid[rt_idx] = true;
        }
        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;

        const max_beta_eff = max_beta_eff: {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.effective_scattering");
            defer zone.end();
            if (layer_effective_scattering_suffixes) |suffixes| {
                std.debug.assert(layer_effective_scattering_suffix_stride > i_fourier);
                std.debug.assert(suffixes.len >= layers.len * layer_effective_scattering_suffix_stride);
                break :max_beta_eff suffixes[layer_idx * layer_effective_scattering_suffix_stride + i_fourier];
            }
            var suffix: f64 = 0.0;
            var scanned_terms: usize = 0;
            var nonzero_terms: usize = 0;
            for (i_fourier..max_phase_index + 1) |ic| {
                scanned_terms += 1;
                const phase_coefficient = phase.coefficient(ic);
                if (phase_coefficient != 0.0) nonzero_terms += 1;
                const beta_eff = @abs(phase_coefficient) * phase_odd_reciprocal[ic];
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
        const needs_renormalized_phase =
            use_doubling and i_fourier == 0 and controls.renorm_phase_function;

        var E = basis.Vec.zero(geo.nmutot);
        {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.initial_exponential");
            defer zone.end();
            for (0..geo.nmutot) |imu| {
                E.data[imu] = math.exp(-b_start / @max(geo.u[imu], 1.0e-12));
            }
        }
        Trace.plotU("initial_exp_evals", @intCast(geo.nmutot));

        if (needs_renormalized_phase) {
            {
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.phase_renormalization");
                defer zone.end();
                renormalizeZeroFourierPhaseKernel(geo, &z.Zplus, &z.Zmin);
            }
            Trace.plotU("phase_renormalizations", 1);
        }

        const layer_rt = &rt[rt_idx];
        {
            const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.single_scatter");
            defer zone.end();
            fillSingleScatterR(&layer_rt.R, a, &E, &z.Zmin, geo);
            fillSingleScatterT(&layer_rt.T, a, b_start, &E, &z.Zplus, geo);
        }
        Trace.plotU("single_scatter_r", 1);
        Trace.plotU("single_scatter_t", 1);

        if (use_doubling) {
            Trace.plotU("doubled_layers", 1);
            {
                const zone = Trace.deepStaticZone(@src(), "labos.rt_layer.doubling");
                defer zone.end();
                doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.performance_thresholds.threshold_mul, &layer_rt.R, &layer_rt.T, &E);
            }
        }

        if (rt_active) |active| active[rt_idx] = a != 0.0;
    }
}

fn cachePhaseKernelViewRow(
    phase_row_cache: []basis.PhaseKernelRow,
    rt_idx: usize,
    z: *const basis.PhaseKernel,
    row_index: usize,
) void {
    const n = z.Zplus.n;
    const row_offset = row_index * n;
    var row = basis.PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = n,
    };
    for (0..n) |col| {
        row.zplus[col] = z.Zplus.data[row_offset + col];
        row.zmin[col] = z.Zmin.data[row_offset + col];
    }
    phase_row_cache[rt_idx] = row;
}

// hot path:
//   when: tangent transport derivatives are requested for LABOS layers
//   work: builds derivative RT layers alongside the base layer matrix path
//   data: base layer inputs, derivative layer inputs, tangent RT outputs, phase basis
//   follow: calcRTlayersIntoWithBasis and derivative workspace consumers
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
            0,
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
            0,
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
        0,
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
) [attenuation.max_levels]LayerRT {
    var rt: [attenuation.max_levels]LayerRT = undefined;
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
