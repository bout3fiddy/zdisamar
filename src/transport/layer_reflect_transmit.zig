const std = @import("std");

const controls = @import("controls.zig");
const gauss_angles = @import("gauss_angles.zig");
const matrix12 = @import("matrix_12x10.zig");
const phase_timing = @import("phase_timing.zig");
const rows = @import("rows.zig");
const Perturbation = @import("../instrumentation/sensitivity.zig");
const Telemetry = @import("../instrumentation/telemetry.zig");
const Trace = @import("../instrumentation/trace.zig");

const math = std.math;

// layer_reflect_transmit.zig ---------------------------------------------------------------------------------|
// Single-layer LABOS reflection/transmission matrix fills and layer-doubling support math.                    |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/layers.zig` `fillSingleScatterR`,                  |
//   `fillSingleScatterR12`, `fillSingleScatterT`, `fillSingleScatterT12`, `classifyLayerDoubling`,            |
//   `doDouble`, `doDouble12x10`, `doDouble12x10Step`, `gaussTrace`, and `squareAttenuation`.                  |
//                                                                                                             |
// math                                                                                                        |
//   R[i,j] = omega * Zmin[i,j]  * (1 - E[i] * E[j]) * dmu_plus[i,j]                                           |
//   T[i,j] = omega * Zplus[i,j] * EET[i,j]             * dmu_min[i,j]                                         |
//                                                                                                             |
//   EET[i,j] = tau_start * E[i]     when mu_i ~= mu_j                                                         |
//            = E[i] - E[j]          otherwise                                                                 |
//   trace_gg = sum over Gaussian k of M[k,k]                                                                  |
//   E <- E * E after each layer-doubling step                                                                 |
//                                                                                                             |
// memory                                                                                                      |
//   The functions write caller-owned Mat rows and allocate no storage. Fixed stream_count=12 keeps the old    |
//   constant-bound loop shape used by the O2 A LABOS route.                                                   |
// ------------------------------------------------------------------------------------------------------------|

// LayerDoublingDecision --------------------------------------------------------------------------------------|
// Small return row for the layer-doubling branch chosen from optical depth and effective scattering depth.    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_optical_depth : f64                                                                          |
// [ 8..15] doubling_count      : usize                                                                        |
// [16..16] uses_doubling       : bool                                                                         |
// [17..23] trailing padding     : 7 B                                                                         |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// footprint: per instance = 24 B (0.023 KiB); stack return value                                              |
pub const LayerDoublingDecision = struct {
    start_optical_depth: f64,
    doubling_count: usize,
    uses_doubling: bool,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn classifyLayerDoubling(
    scattering: controls.ScatteringMode,
    threshold_doubl: f64,
    optical_depth: f64,
    effective_scattering_coefficient: f64,
    effective_scattering_depth: f64,
) LayerDoublingDecision {
    // classifyLayerDoubling --------------------------------------------------------------------------------- |
    // Choose whether a layer needs doubling and how thin the starting layer should be.                        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `classifyLayerDoubling`.                                                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   effective_scattering_depth = effective_scattering_coefficient * optical_depth                         |
    //   start_optical_depth = optical_depth / 2^doubling_count                                                |
    // --------------------------------------------------------------------------------------------------------|

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: layer doubling threshold                                                                      |
    // Skip layer doubling when the scaled scattering thickness is below threshold_doubl.                      |
    // --------------------------------------------------------------------------------------------------------|
    // Doubling is the expensive multiple-scattering correction inside one layer. For weakly scattering        |
    // layers, this branch keeps the single-scatter layer and avoids repeated matrix squaring. The cost is     |
    // that very small intra-layer multiple-scattering feedback is not added.                                  |
    //                                                                                                         |
    // threshold_doubl is 0.1 by generic default and 1.0e-6 in the O2 A rtm_config. Lower values double more   |
    // layers.                                                                                                 |
    if (scattering != .multiple or !(effective_scattering_depth > threshold_doubl)) {
        return .{
            .start_optical_depth = optical_depth,
            .doubling_count = 0,
            .uses_doubling = false,
        };
    }
    // end tradeoff: layer doubling threshold -----------------------------------------------------------------|

    const ratio = effective_scattering_depth / threshold_doubl;
    const exponent = math.ilogb(ratio);

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: maximum doubling depth                                                                        |
    // Cap the number of layer splits at 60 so extreme inputs cannot create an unbounded doubling chain.       |
    // --------------------------------------------------------------------------------------------------------|
    // Each extra split halves the starting optical depth and adds another matrix-squaring step. The hard cap  |
    // is 60 splits. It is far beyond normal LABOS layers, but still matters as a hard stop for pathological   |
    // inputs. If an extreme layer still fails threshold_doubl after 60 splits, the solver uses the best       |
    // capped split count that bounds setup time while still refining the starting layer.                      |
    var count_i32: i32 = if (exponent >= 60) 60 else @max(1, exponent + 1);
    var count: usize = @intCast(count_i32);
    var start = math.ldexp(optical_depth, -count_i32);

    // Try one fewer split while the previous starting layer is still below the threshold.
    while (count > 1) {
        const previous_count_i32 = count_i32 - 1;
        const previous_start = math.ldexp(optical_depth, -previous_count_i32);
        if (effective_scattering_coefficient * previous_start >= threshold_doubl) break;
        count_i32 = previous_count_i32;
        count -= 1;
        start = previous_start;
    }

    // Add splits until the starting layer is safely below the threshold.
    while (count < 60 and effective_scattering_coefficient * start >= threshold_doubl) {
        start *= 0.5;
        count += 1;
    }
    // end tradeoff: maximum doubling depth -------------------------------------------------------------------|

    return .{
        .start_optical_depth = start,
        .doubling_count = count,
        .uses_doubling = true,
    };
}

pub fn fillSingleScatterReflection(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    attenuation: *const rows.Vec,
    zmin: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterReflection ----------------------------------------------------------------------------|
    // Fill one homogeneous layer reflection matrix.                                                           |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and fixed stream_count=12 dispatch follow old `layers.zig` `fillSingleScatterR`.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   R[i,j] = omega * Zmin[i,j] * (1 - E[i] * E[j]) * dmu_plus[i,j]                                        |
    // --------------------------------------------------------------------------------------------------------|

    const n = geometry.stream_count;
    if (n == rows.max_stream_count) {
        return fillSingleScatterReflection12(out, single_scatter_albedo, attenuation, zmin, geometry);
    }

    out.* = rows.Mat.zero(n);

    for (0..n) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        for (0..n) |i| {
            const direct_pair = attenuation.data[i] * ej;
            const phase_term = single_scatter_albedo * zmin.data[idx];
            out.data[idx] = phase_term * (1.0 - direct_pair) * geometry.dmu_plus[idx];
            idx += n;
        }
    }
}

pub fn fillSingleScatterTransmission(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    optical_depth_start: f64,
    attenuation: *const rows.Vec,
    zplus: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterTransmission --------------------------------------------------------------------------|
    // Fill one homogeneous layer transmission matrix.                                                         |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and fixed stream_count=12 dispatch follow old `layers.zig` `fillSingleScatterT`.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   T[i,j] = omega * Zplus[i,j] * EET[i,j] * dmu_min[i,j]                                                 |
    //   EET[i,j] = tau_start * E[i] when geometry.dmu_same[i,j], otherwise E[i] - E[j]                        |
    // --------------------------------------------------------------------------------------------------------|

    const n = geometry.stream_count;
    if (n == rows.max_stream_count) {
        return fillSingleScatterTransmission12(
            out,
            single_scatter_albedo,
            optical_depth_start,
            attenuation,
            zplus,
            geometry,
        );
    }

    out.* = rows.Mat.zero(n);

    for (0..n) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        for (0..n) |i| {
            const integrated_attenuation = if (geometry.dmu_same[idx])
                optical_depth_start * attenuation.data[i]
            else
                attenuation.data[i] - ej;

            const phase_term = single_scatter_albedo * zplus.data[idx];
            out.data[idx] = phase_term * integrated_attenuation * geometry.dmu_min[idx];
            idx += n;
        }
    }
}

pub fn gaussianBlockTrace(n: usize, n_gauss: usize, matrix: *const rows.Mat) f64 {
    // gaussianBlockTrace ------------------------------------------------------------------------------------ |
    // Sum the diagonal of the Gaussian block used by LABOS layer-doubling threshold gates.                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `gaussTrace`.                                                                  |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 uses literal row-major diagonal indexes: k*12 + k = 13*k.                        |
    // Generic stream counts use k*n + k.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    if (n == rows.max_stream_count and n_gauss == rows.max_gauss) {
        var trace = matrix.data[0];
        trace += matrix.data[13];
        trace += matrix.data[26];
        trace += matrix.data[39];
        trace += matrix.data[52];
        trace += matrix.data[65];
        trace += matrix.data[78];
        trace += matrix.data[91];
        trace += matrix.data[104];
        trace += matrix.data[117];
        return trace;
    }

    var trace: f64 = 0.0;
    for (0..n_gauss) |k| trace += matrix.data[k * n + k];

    return trace;
}

pub inline fn squareAttenuation(n: usize, attenuation: *rows.Vec) void {
    // squareAttenuation ------------------------------------------------------------------------------------- |
    // One doubling step turns half-layer attenuation into full-layer attenuation: E <- E * E.                 |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `squareAttenuation`.                                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (n == rows.max_stream_count) return squareAttenuation12(attenuation);

    for (0..n) |direction_index| {
        const e = attenuation.data[direction_index];
        attenuation.data[direction_index] = e * e;
    }
}

pub fn doubleLayer(
    doubling_count: usize,
    n: usize,
    n_gauss: usize,
    thresholds: controls.PerformanceThresholds,
    reflection: *rows.Mat,
    transmission: *rows.Mat,
    attenuation: *rows.Vec,
    fourier_index: usize,
    layer_index: usize,
    phase_max_index: usize,
    trace_phase_timing: ?phase_timing.Active,
) void {
    // doubleLayer --------------------------------------------------------------------------------------------|
    // Dynamic-shape LABOS layer doubling for one layer and Fourier term.                                      |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `doDouble`, with a fixed 12x10 dispatch for the O2 A route.                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   Q = inverse(I - R*R) - I                                                                              |
    //   D = T + Q*E + Q*T, or D = T when Q is skipped                                                         |
    //   U = R*E + R*D, or U = R*E when the R-D product is skipped                                             |
    //   R = R + E*U + T*U, or R = R + E*U when the T-U product is skipped                                     |
    //   T = E*D + T*E + T*D, or T = E*D + T*E when the T-D product is skipped                                 |
    //   E <- E*E after each doubling step                                                                     |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Uses two caller-stack scratch matrices for next R/T plus one temporary D per step. No heap storage    |
    //   enters the per-layer transport loop.                                                                  |
    // --------------------------------------------------------------------------------------------------------|

    if (n == rows.max_stream_count and n_gauss == rows.max_gauss) {
        return doubleLayer12x10(
            doubling_count,
            thresholds,
            reflection,
            transmission,
            attenuation,
            fourier_index,
            layer_index,
            phase_max_index,
            trace_phase_timing,
        );
    }

    const threshold_mul = thresholds.threshold_mul;
    var r_storage: rows.Mat = undefined;
    var t_storage: rows.Mat = undefined;
    var current_r = reflection;
    var current_t = transmission;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..doubling_count) |doubling_step_index| {
        Trace.plotU("doubling_steps", 1);

        const trace_r = gaussianBlockTrace(n, n_gauss, current_r);
        const trace_t = gaussianBlockTrace(n, n_gauss, current_t);
        const coord = Perturbation.Coord{
            .layer_index = @intCast(layer_index),
            .fourier_index = @intCast(fourier_index),
            .order_index = @intCast(doubling_step_index),
        };
        const q_is_zero = Perturbation.decision(.qseries_skip, coord, @abs(trace_r * trace_r) <= threshold_mul);

        Telemetry.labosDoublingStep(
            fourier_index,
            layer_index,
            phase_max_index,
            doubling_step_index,
            trace_r,
            trace_t,
            threshold_mul,
            q_is_zero,
        );

        doubleLayerStep(
            n,
            n_gauss,
            threshold_mul,
            current_r,
            current_t,
            attenuation,
            next_r,
            next_t,
            trace_r,
            trace_t,
            q_is_zero,
            fourier_index,
            layer_index,
            phase_max_index,
            doubling_step_index,
        );

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        Trace.plotU("doubling_square_evals", @intCast(n));
        squareAttenuation(n, attenuation);
    }

    if (final_in_scratch) {
        reflection.* = current_r.*;
        transmission.* = current_t.*;
    }
}

fn doubleLayer12x10(
    doubling_count: usize,
    thresholds: controls.PerformanceThresholds,
    reflection: *rows.Mat,
    transmission: *rows.Mat,
    attenuation: *rows.Vec,
    fourier_index: usize,
    layer_index: usize,
    phase_max_index: usize,
    trace_phase_timing: ?phase_timing.Active,
) void {
    // doubleLayer12x10 ---------------------------------------------------------------------------------------|
    // Fixed 12x10 layer doubling for the O2 A LABOS route.                                                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `doDouble12x10`.                                                               |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Uses two stack scratch matrices and pointer swaps. The fixed kernels write caller-owned storage and   |
    //   keep constant loop bounds visible to the optimizer.                                                   |
    // --------------------------------------------------------------------------------------------------------|

    var r_storage: rows.Mat = undefined;
    var t_storage: rows.Mat = undefined;
    var current_r = reflection;
    var current_t = transmission;
    var next_r = &r_storage;
    var next_t = &t_storage;
    var final_in_scratch = false;

    for (0..doubling_count) |doubling_step_index| {
        Trace.plotU("doubling_steps", 1);
        phase_timing.count(trace_phase_timing, "fixed_doubling_steps", 1);

        doubleLayer12x10Step(
            thresholds,
            current_r,
            current_t,
            attenuation,
            next_r,
            next_t,
            fourier_index,
            layer_index,
            phase_max_index,
            doubling_step_index,
            trace_phase_timing,
        );

        const previous_r = current_r;
        const previous_t = current_t;
        current_r = next_r;
        current_t = next_t;
        next_r = previous_r;
        next_t = previous_t;
        final_in_scratch = !final_in_scratch;

        Trace.plotU("doubling_square_evals", rows.max_stream_count);
        squareAttenuation12(attenuation);
    }

    if (final_in_scratch) {
        reflection.* = current_r.*;
        transmission.* = current_t.*;
    }
}

fn doubleLayerStep(
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    current_r: *const rows.Mat,
    current_t: *const rows.Mat,
    attenuation: *const rows.Vec,
    next_r: *rows.Mat,
    next_t: *rows.Mat,
    trace_r: f64,
    trace_t: f64,
    q_is_zero: bool,
    fourier_index: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
) void {
    // doubleLayerStep ----------------------------------------------------------------------------------------|
    // One generic layer-doubling step using the old trace-threshold branch sequence.                          |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports the body of old `layers.zig` `doDouble`.                                                        |
    //                                                                                                         |
    // math                                                                                                    |
    //   The q-series gate decides D. The downstream R-D, T-U, and T-D gates then choose between retained      |
    //   Gaussian products and diagonal-scale updates for U, R, and T.                                         |
    // --------------------------------------------------------------------------------------------------------|

    var d_storage: rows.Mat = undefined;
    const D = choose_doubling_d: {
        if (q_is_zero) {
            Trace.plotU("doubling_qseries_skipped", 1);
            break :choose_doubling_d current_t;
        }

        Trace.plotU("doubling_qseries_nonzero", 1);
        Trace.plotU("matrix_qseries", 1);
        Trace.plotU("matrix_smul_q_product", 1);
        Trace.plotU("matrix_smul_add_semul3", 1);

        var Q: rows.Mat = undefined;
        matrix12.qseriesKnownNonzeroProductInto(&Q, n, n_gauss, current_r, current_r);
        matrix12.smulAddSemul3KnownRightTraceInto(
            &d_storage,
            n,
            n_gauss,
            threshold_mul,
            &Q,
            attenuation,
            current_t,
            trace_t,
        );
        break :choose_doubling_d &d_storage;
    };

    const trace_d = if (q_is_zero) trace_t else gaussianBlockTrace(n, n_gauss, D);
    Trace.plotU("matrix_smul_rd", 1);

    const downstream_coord = Perturbation.Coord{
        .layer_index = @intCast(layer_index),
        .fourier_index = @intCast(fourier_index),
        .order_index = @intCast(doubling_step_index),
        .branch = if (q_is_zero) 1 else 0,
    };
    const rd_nonzero = Perturbation.decision(
        .qseries_rd_product,
        downstream_coord,
        @abs(trace_r * trace_d) > threshold_mul,
    );

    var U: rows.Mat = undefined;
    if (rd_nonzero) {
        Trace.plotU("matrix_smul_rd_nonzero", 1);
        Trace.plotU("matrix_semul_add", 1);
        matrix12.semulAddProductKnownNonzeroInto(&U, n, n_gauss, current_r, attenuation, D);
    } else {
        Trace.plotU("matrix_semul", 1);
        matrix12.semulInto(&U, n, current_r, attenuation);
    }

    const trace_u = gaussianBlockTrace(n, n_gauss, &U);
    Trace.plotU("matrix_smul_tu", 1);

    const tu_nonzero = Perturbation.decision(
        .qseries_tu_product,
        downstream_coord,
        @abs(trace_t * trace_u) > threshold_mul,
    );
    if (tu_nonzero) {
        Trace.plotU("matrix_smul_tu_nonzero", 1);
        Trace.plotU("matrix_mat_add_esmul3", 1);
        matrix12.matAddEsmul3ProductKnownNonzeroInto(next_r, n, n_gauss, current_r, attenuation, &U, current_t);
    } else {
        Trace.plotU("matrix_mat_add_esmul", 1);
        matrix12.matAddEsmulInto(next_r, n, current_r, attenuation, &U);
    }

    Trace.plotU("matrix_smul_td", 1);

    const td_nonzero = Perturbation.decision(
        .qseries_td_product,
        downstream_coord,
        @abs(trace_t * trace_d) > threshold_mul,
    );
    Telemetry.labosDoublingDownstreamGates(
        fourier_index,
        layer_index,
        phase_max_index,
        doubling_step_index,
        q_is_zero,
        trace_r,
        trace_t,
        trace_d,
        trace_u,
        threshold_mul,
        rd_nonzero,
        tu_nonzero,
        td_nonzero,
    );

    if (q_is_zero) {
        if (td_nonzero) {
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            matrix12.esmulSemulSelfAddProductKnownNonzeroInto(next_t, n, n_gauss, attenuation, current_t);
        } else {
            Trace.plotU("matrix_esmul_semul", 1);
            matrix12.esmulSemulSelfInto(next_t, n, attenuation, current_t);
        }
    } else {
        if (td_nonzero) {
            Trace.plotU("matrix_smul_td_nonzero", 1);
            Trace.plotU("matrix_esmul_semul_add", 1);
            matrix12.esmulSemulAddProductKnownNonzeroInto(next_t, n, n_gauss, attenuation, D, current_t);
        } else {
            Trace.plotU("matrix_esmul_semul", 1);
            matrix12.esmulSemulInto(next_t, n, attenuation, D, current_t);
        }
    }
}

inline fn doubleLayer12x10Step(
    thresholds: controls.PerformanceThresholds,
    current_r: *const rows.Mat,
    current_t: *const rows.Mat,
    attenuation: *const rows.Vec,
    next_r: *rows.Mat,
    next_t: *rows.Mat,
    fourier_index: usize,
    layer_index: usize,
    phase_max_index: usize,
    doubling_step_index: usize,
    trace_phase_timing: ?phase_timing.Active,
) void {
    // doubleLayer12x10Step -----------------------------------------------------------------------------------|
    // One fixed 12x10 doubling step with old LABOS gate order and phase-timing buckets.                       |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `doDouble12x10Step`.                                                           |
    //                                                                                                         |
    // math                                                                                                    |
    //   Uses the same Q/D/U/R/T equations as doubleLayerStep, with fixed matrix helper kernels for each       |
    //   retained or skipped product branch.                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    const threshold_mul = thresholds.threshold_mul;
    const trace_r = gaussianBlockTrace(rows.max_stream_count, rows.max_gauss, current_r);
    const trace_t = gaussianBlockTrace(rows.max_stream_count, rows.max_gauss, current_t);
    const coord = Perturbation.Coord{
        .layer_index = @intCast(layer_index),
        .fourier_index = @intCast(fourier_index),
        .order_index = @intCast(doubling_step_index),
    };
    const q_is_zero = Perturbation.decision(.qseries_skip, coord, @abs(trace_r * trace_r) <= threshold_mul);

    Telemetry.labosDoublingStep(
        fourier_index,
        layer_index,
        phase_max_index,
        doubling_step_index,
        trace_r,
        trace_t,
        threshold_mul,
        q_is_zero,
    );

    var d_storage: rows.Mat = undefined;
    const D = choose_fixed_doubling_d: {
        if (q_is_zero) {
            Trace.plotU("doubling_qseries_skipped", 1);
            phase_timing.count(trace_phase_timing, "fixed_qseries_skipped", 1);
            break :choose_fixed_doubling_d current_t;
        }

        Trace.plotU("doubling_qseries_nonzero", 1);
        Trace.plotU("matrix_qseries", 1);
        Trace.plotU("matrix_smul_q_product", 1);
        Trace.plotU("matrix_smul_add_semul3", 1);
        phase_timing.count(trace_phase_timing, "fixed_qseries_retained", 1);

        var Q: rows.Mat = undefined;
        const trace_start = phase_timing.start(trace_phase_timing);
        defer phase_timing.finish(trace_phase_timing, trace_start, "fixed_qseries_work");

        matrix12.qseriesKnownNonzeroProductInto(&Q, rows.max_stream_count, rows.max_gauss, current_r, current_r);
        matrix12.smulAddSemul3KnownRightTraceInto(
            &d_storage,
            rows.max_stream_count,
            rows.max_gauss,
            threshold_mul,
            &Q,
            attenuation,
            current_t,
            trace_t,
        );
        break :choose_fixed_doubling_d &d_storage;
    };

    const trace_d = if (q_is_zero) trace_t else gaussianBlockTrace(rows.max_stream_count, rows.max_gauss, D);
    const downstream_coord = Perturbation.Coord{
        .layer_index = @intCast(layer_index),
        .fourier_index = @intCast(fourier_index),
        .order_index = @intCast(doubling_step_index),
        .branch = if (q_is_zero) 1 else 0,
    };

    Trace.plotU("matrix_smul_rd", 1);
    const rd_nonzero = Perturbation.decision(
        .qseries_rd_product,
        downstream_coord,
        @abs(trace_r * trace_d) > threshold_mul,
    );

    var U: rows.Mat = undefined;
    {
        const trace_start = phase_timing.start(trace_phase_timing);
        defer phase_timing.finish(trace_phase_timing, trace_start, "fixed_rd_update");

        if (rd_nonzero) {
            Trace.plotU("matrix_smul_rd_nonzero", 1);
            Trace.plotU("matrix_semul_add", 1);
            phase_timing.count(trace_phase_timing, "fixed_rd_retained", 1);
            matrix12.semulAddProductKnownNonzeroInto(
                &U,
                rows.max_stream_count,
                rows.max_gauss,
                current_r,
                attenuation,
                D,
            );
        } else {
            Trace.plotU("matrix_semul", 1);
            phase_timing.count(trace_phase_timing, "fixed_rd_skipped", 1);
            matrix12.semulInto(&U, rows.max_stream_count, current_r, attenuation);
        }
    }

    const trace_u = gaussianBlockTrace(rows.max_stream_count, rows.max_gauss, &U);
    Trace.plotU("matrix_smul_tu", 1);
    const tu_nonzero = Perturbation.decision(
        .qseries_tu_product,
        downstream_coord,
        @abs(trace_t * trace_u) > threshold_mul,
    );

    {
        const trace_start = phase_timing.start(trace_phase_timing);
        defer phase_timing.finish(trace_phase_timing, trace_start, "fixed_tu_update");

        if (tu_nonzero) {
            Trace.plotU("matrix_smul_tu_nonzero", 1);
            Trace.plotU("matrix_mat_add_esmul3", 1);
            phase_timing.count(trace_phase_timing, "fixed_tu_retained", 1);
            matrix12.matAddEsmul3ProductKnownNonzeroInto(
                next_r,
                rows.max_stream_count,
                rows.max_gauss,
                current_r,
                attenuation,
                &U,
                current_t,
            );
        } else {
            Trace.plotU("matrix_mat_add_esmul", 1);
            phase_timing.count(trace_phase_timing, "fixed_tu_skipped", 1);
            matrix12.matAddEsmulInto(next_r, rows.max_stream_count, current_r, attenuation, &U);
        }
    }

    Trace.plotU("matrix_smul_td", 1);
    const td_nonzero = Perturbation.decision(
        .qseries_td_product,
        downstream_coord,
        @abs(trace_t * trace_d) > threshold_mul,
    );
    Telemetry.labosDoublingDownstreamGates(
        fourier_index,
        layer_index,
        phase_max_index,
        doubling_step_index,
        q_is_zero,
        trace_r,
        trace_t,
        trace_d,
        trace_u,
        threshold_mul,
        rd_nonzero,
        tu_nonzero,
        td_nonzero,
    );

    {
        const trace_start = phase_timing.start(trace_phase_timing);
        defer phase_timing.finish(trace_phase_timing, trace_start, "fixed_td_update");

        if (q_is_zero) {
            if (td_nonzero) {
                Trace.plotU("matrix_smul_td_nonzero", 1);
                Trace.plotU("matrix_esmul_semul_add", 1);
                phase_timing.count(trace_phase_timing, "fixed_td_retained", 1);
                matrix12.esmulSemulSelfAddProductKnownNonzeroInto(
                    next_t,
                    rows.max_stream_count,
                    rows.max_gauss,
                    attenuation,
                    current_t,
                );
            } else {
                Trace.plotU("matrix_esmul_semul", 1);
                phase_timing.count(trace_phase_timing, "fixed_td_skipped", 1);
                matrix12.esmulSemulSelfInto(next_t, rows.max_stream_count, attenuation, current_t);
            }
        } else {
            if (td_nonzero) {
                Trace.plotU("matrix_smul_td_nonzero", 1);
                Trace.plotU("matrix_esmul_semul_add", 1);
                phase_timing.count(trace_phase_timing, "fixed_td_retained", 1);
                matrix12.esmulSemulAddProductKnownNonzeroInto(
                    next_t,
                    rows.max_stream_count,
                    rows.max_gauss,
                    attenuation,
                    D,
                    current_t,
                );
            } else {
                Trace.plotU("matrix_esmul_semul", 1);
                phase_timing.count(trace_phase_timing, "fixed_td_skipped", 1);
                matrix12.esmulSemulInto(next_t, rows.max_stream_count, attenuation, D, current_t);
            }
        }
    }
}

fn fillSingleScatterReflection12(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    attenuation: *const rows.Vec,
    zmin: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterReflection12 --------------------------------------------------------------------------|
    // Fixed 12x12 reflection fill.                                                                            |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = rows.Mat{ .data = undefined, .n = rows.max_stream_count };

    inline for (0..rows.max_stream_count) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        inline for (0..rows.max_stream_count) |i| {
            const direct_pair = attenuation.data[i] * ej;
            const phase_term = single_scatter_albedo * zmin.data[idx];
            out.data[idx] = phase_term * (1.0 - direct_pair) * geometry.dmu_plus[idx];
            idx += rows.max_stream_count;
        }
    }
}

inline fn squareAttenuation12(attenuation: *rows.Vec) void {
    // squareAttenuation12 ----------------------------------------------------------------------------------- |
    // Fixed 12-direction attenuation square for the LABOS O2 A rtm_config.                                    |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..rows.max_stream_count) |direction_index| {
        const e = attenuation.data[direction_index];
        attenuation.data[direction_index] = e * e;
    }
}

fn fillSingleScatterTransmission12(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    optical_depth_start: f64,
    attenuation: *const rows.Vec,
    zplus: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterTransmission12 ------------------------------------------------------------------------|
    // Fixed 12x12 transmission fill.                                                                          |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = rows.Mat{ .data = undefined, .n = rows.max_stream_count };

    inline for (0..rows.max_stream_count) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        inline for (0..rows.max_stream_count) |i| {
            const integrated_attenuation = if (geometry.dmu_same[idx])
                optical_depth_start * attenuation.data[i]
            else
                attenuation.data[i] - ej;

            const phase_term = single_scatter_albedo * zplus.data[idx];
            out.data[idx] = phase_term * integrated_attenuation * geometry.dmu_min[idx];
            idx += rows.max_stream_count;
        }
    }
}
