const std = @import("std");

const telemetry = @import("../instrumentation/telemetry.zig");
const controls = @import("../transport/controls.zig");
const jacobian_states = @import("../transport/jacobian_states.zig");
const radiance_results = @import("radiance_results.zig");

pub const Error = error{
    ShapeMismatch,
    InvalidSolarCosine,
    KernelShapeMismatch,
};

// instrument_average.zig ------------------------------------------------------------------------------------ |
// Product-grid radiance, irradiance, and reflectance assembly helpers.                                        |
//                                                                                                             |
// provenance                                                                                                  |
//   `assembleReflectance` ports the old final conversion from main:                                           |
//   `src/forward_model/instrument_grid/grid_calculation/simulate.zig` `assembleReflectance`.                  |
//                                                                                                             |
// boundary                                                                                                    |
//   Earlier spectrum steps gather calibrated radiance and irradiance on the public product grid. This file    |
//   performs the shared final conversion and summary accounting. It does not own wavelength planning, solar   |
//   lookup, convolution, or calibration tables.                                                               |
// ------------------------------------------------------------------------------------------------------------|

// reflectance_denominator_floor ----------------------------------------------------------------------------- |
// Minimum denominator for top-of-atmosphere reflectance conversion.                                           |
//                                                                                                             |
// provenance                                                                                                  |
//   Old `simulate.zig` clamps `irradiance * mu0` to `1e-9` before dividing radiance by the solar denominator. |
//   Telemetry still records how often raw denominators cross that guard.                                      |
pub const reflectance_denominator_floor: f64 = 1.0e-9;
// ------------------------------------------------------------------------------------------------------------|

// default_slit_kernel --------------------------------------------------------------------------------------- |
// Legacy five-tap response used when no integrated instrument sampling route has already averaged a channel.  |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/implementations/instrument/integration.zig` `slitKernelForScene` when       |
//   `response.fwhm_nm <= 0.0`. `applySlitConvolution` normalizes the row before use.                          |
pub const default_slit_kernel = [5]f64{ 1.0, 4.0, 6.0, 4.0, 1.0 };
// ------------------------------------------------------------------------------------------------------------|

// Calibration ------------------------------------------------------------------------------------------------|
// Four scalar channel corrections used after radiance or irradiance sampling.                                 |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/instrument_grid/spectral_math/calibration.zig` `Calibration`.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] gain               : f64                                                                           |
// [ 8..15] offset             : f64                                                                           |
// [16..23] wavelength_shift_nm: f64                                                                           |
// [24..31] stray_light        : f64                                                                           |
pub const Calibration = struct {
    gain: f64 = 1.0,
    offset: f64 = 0.0,
    wavelength_shift_nm: f64 = 0.0,
    stray_light: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

// ReflectanceAssemblySummary -------------------------------------------------------------------------------- |
// Per-spectrum summary from radiance/irradiance-to-reflectance conversion.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] radiance_sum           : f64                                                                       |
// [ 8..15] irradiance_sum         : f64                                                                       |
// [16..23] reflectance_sum        : f64                                                                       |
// [24..31] min_denominator        : f64                                                                       |
// [32..39] max_reflectance        : f64                                                                       |
// [40..63] jacobian_sum          : [3]f64                                                                     |
//          |----- [40..47] jacobian_sum[0]                                                                    |
//          |----- [48..55] jacobian_sum[1]                                                                    |
//          |----- [56..63] jacobian_sum[2]                                                                    |
// [64..71] sample_count           : usize                                                                     |
// [72..79] denominator_clamp_count: usize                                                                     |
pub const ReflectanceAssemblySummary = struct {
    radiance_sum: f64 = 0.0,
    irradiance_sum: f64 = 0.0,
    reflectance_sum: f64 = 0.0,
    min_denominator: f64 = 0.0,
    max_reflectance: f64 = 0.0,
    jacobian_sum: jacobian_states.Vector = jacobian_states.zero(),
    sample_count: usize = 0,
    denominator_clamp_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn applySignal(calibration: Calibration, signal: []const f64, output: []f64) Error!void {
    // applySignal ------------------------------------------------------------------------------------------- |
    // Apply gain, offset, and stray-light mixing to one sampled channel.                                      |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/forward_model/instrument_grid/spectral_math/calibration.zig` `applySignal`.           |
    //                                                                                                         |
    // math                                                                                                    |
    //   mean     = sum(signal) / N                                                                            |
    //   mixed_i  = signal_i + stray_light * (mean - signal_i)                                                 |
    //   output_i = gain * mixed_i + offset                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    if (signal.len != output.len) return error.ShapeMismatch;
    if (signal.len == 0) return;

    const mean_signal = mean(signal);
    for (signal, output) |sample, *slot| {
        const stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        slot.* = calibration.gain * stray_mixed + calibration.offset;
    }
}

pub fn applySignalDerivative(calibration: Calibration, signal: []const f64, output: []f64) Error!void {
    // applySignalDerivative --------------------------------------------------------------------------------- |
    // Apply the linear channel calibration terms to one derivative column.                                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/forward_model/instrument_grid/spectral_math/calibration.zig`                          |
    //   `applySignalDerivative`.                                                                              |
    //                                                                                                         |
    // math                                                                                                    |
    //   mean_dx      = sum(dsignal_i/dx) / N                                                                  |
    //   doutput_i/dx = gain * (dsignal_i/dx + stray_light * (mean_dx - dsignal_i/dx))                         |
    //                                                                                                         |
    // branch reason                                                                                           |
    //   The additive offset drops out because d(offset)/dx = 0.                                               |
    // --------------------------------------------------------------------------------------------------------|
    if (signal.len != output.len) return error.ShapeMismatch;
    if (signal.len == 0) return;

    const mean_signal = mean(signal);
    for (signal, output) |sample, *slot| {
        const stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        slot.* = calibration.gain * stray_mixed;
    }
}

pub fn applySlitConvolution(signal: []const f64, kernel: []const f64, output: []f64) Error!void {
    // applySlitConvolution ---------------------------------------------------------------------------------- |
    // Apply the legacy slit convolution used when instrument integration has not already averaged a channel.  |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/forward_model/instrument_grid/spectral_math/convolution.zig` `apply`.                 |
    //                                                                                                         |
    // math                                                                                                    |
    //                   sum_j signal[i + j - half_width] * kernel_j                                           |
    //   output_i = --------------------------------------------------                                         |
    //                         sum_j kernel_j over valid samples                                               |
    //                                                                                                         |
    // boundary rows                                                                                           |
    //   Edge samples clip the kernel to valid signal rows and normalize by the clipped kernel sum, preserving |
    //   constant input at spectrum boundaries.                                                                |
    // --------------------------------------------------------------------------------------------------------|
    if (signal.len != output.len or kernel.len == 0) return error.KernelShapeMismatch;

    const half_width = kernel.len / 2;
    const right_width = kernel.len - half_width - 1;
    const interior_begin = @min(half_width, signal.len);
    const interior_end = if (signal.len > right_width) signal.len - right_width else 0;
    const full_norm = kernelSum(kernel);

    var index: usize = 0;
    while (index < interior_begin) : (index += 1) {
        output[index] = convolvedBoundarySample(signal, kernel, half_width, index);
    }
    if (interior_end > interior_begin) {
        while (index < interior_end) : (index += 1) {
            output[index] = convolvedFullKernelSample(signal[index - half_width ..], kernel, full_norm);
        }
    }
    while (index < output.len) : (index += 1) {
        output[index] = convolvedBoundarySample(signal, kernel, half_width, index);
    }
}

pub fn postprocessSignal(
    uses_integrated_sampling: bool,
    calibration: Calibration,
    slit_kernel: []const f64,
    raw_signal: []const f64,
    out_signal: []f64,
) Error!void {
    // postprocessSignal ------------------------------------------------------------------------------------- |
    // Apply the old product-channel order: optional slit convolution, then scalar channel calibration.        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports the scalar radiance and irradiance postprocess sections from main:                              |
    //   `src/forward_model/instrument_grid/grid_calculation/simulate.zig` `fillRadianceSamples` and           |
    //   `fillIrradianceSamples`.                                                                              |
    //                                                                                                         |
    // shape                                                                                                   |
    //   Integrated sampling already applied the instrument response, so this route skips slit convolution.    |
    // --------------------------------------------------------------------------------------------------------|
    if (raw_signal.len != out_signal.len) return error.ShapeMismatch;

    const needs_slit_convolution = !uses_integrated_sampling;
    const storage_overlaps = slicesOverlap(f64, raw_signal, out_signal);
    if (needs_slit_convolution and storage_overlaps) return error.ShapeMismatch;

    if (uses_integrated_sampling) {
        @memcpy(out_signal, raw_signal);
    } else {
        try applySlitConvolution(raw_signal, slit_kernel, out_signal);
    }
    try applySignal(calibration, out_signal, out_signal);
}

pub fn postprocessRadianceResults(
    solve_config: controls.SolveConfig,
    uses_integrated_sampling: bool,
    calibration: Calibration,
    slit_kernel: []const f64,
    raw_rows: []const radiance_results.RadianceResult,
    out_rows: []radiance_results.RadianceResult,
) Error!void {
    // postprocessRadianceResults ---------------------------------------------------------------------------- |
    // Apply product-grid radiance postprocess while carrying active row-vector Jacobian lanes.                |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports the old `simulate.zig` order: radiance convolution/calibration first, then each active          |
    //   Jacobian column gets the same convolution guard and derivative calibration.                           |
    //                                                                                                         |
    // math                                                                                                    |
    //   L_out        = channel_calibration(convolution_or_identity(L_raw))                                    |
    //   dL_out/dx    = derivative_calibration(convolution_or_identity(dL_raw/dx))                             |
    //                                                                                                         |
    // memory                                                                                                  |
    //   raw_rows and out_rows may alias only when integrated sampling is true. Non-integrated convolution     |
    //   reads neighboring raw rows while writing output rows, so overlapping storage is rejected.             |
    // --------------------------------------------------------------------------------------------------------|
    const shape_matches = raw_rows.len == out_rows.len;
    if (!shape_matches) return error.ShapeMismatch;

    const needs_slit_convolution = !uses_integrated_sampling;
    if (needs_slit_convolution and slit_kernel.len == 0) return error.KernelShapeMismatch;

    const storage_overlaps = slicesOverlap(
        radiance_results.RadianceResult,
        raw_rows,
        out_rows,
    );
    if (needs_slit_convolution and storage_overlaps) {
        return error.ShapeMismatch;
    }

    for (raw_rows, out_rows, 0..) |raw_row, *out_row, index| {
        const radiance = choose_radiance: {
            if (uses_integrated_sampling) break :choose_radiance raw_row.radiance;
            break :choose_radiance convolvedRadianceRow(raw_rows, slit_kernel, index);
        };
        out_row.* = .{
            .radiance = radiance,
            .jacobian = jacobian_states.zero(),
        };
    }
    applyRadianceCalibration(calibration, out_rows);

    const active_state_count = jacobian_states.activeStateCount(solve_config.derivative_state_mask);
    const wants_jacobian = solve_config.derivative_mode != .none and active_state_count != 0;
    if (!wants_jacobian) return;

    for (0..jacobian_states.state_count) |state_index| {
        const state: jacobian_states.State = @enumFromInt(state_index);
        if (!jacobian_states.includes(solve_config.derivative_state_mask, state)) continue;

        for (raw_rows, out_rows, 0..) |raw_row, *out_row, index| {
            out_row.jacobian[state_index] = choose_jacobian: {
                if (uses_integrated_sampling) break :choose_jacobian raw_row.jacobian[state_index];
                break :choose_jacobian convolvedJacobianRow(raw_rows, slit_kernel, state_index, index);
            };
        }
        applyJacobianCalibration(calibration, out_rows, state_index);
    }
}

pub fn assembleReflectance(
    solar_cosine: f64,
    radiance: []const f64,
    irradiance: []const f64,
    out_reflectance: []f64,
) Error!ReflectanceAssemblySummary {
    // assembleReflectance ----------------------------------------------------------------------------------- |
    // Convert calibrated radiance and irradiance into top-of-atmosphere reflectance for each output sample.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   rho_i = pi * L_i / max(E0_i * mu0, 1e-9)                                                              |
    //                                                                                                         |
    // relation to forward scaling                                                                             |
    //   The forward radiance prefetch uses L = rho * mu0 * E0 / pi. This step inverts that convention after   |
    //   instrument sampling has produced calibrated radiance and irradiance on the product grid.              |
    //                                                                                                         |
    // numerical guard                                                                                         |
    //   The `1e-9` floor prevents Inf/NaN reflectance when irradiance is near zero. Telemetry reports how     |
    //   often the raw denominator crossed the guard.                                                          |
    // --------------------------------------------------------------------------------------------------------|
    if (radiance.len != irradiance.len or radiance.len != out_reflectance.len) return error.ShapeMismatch;
    if (!std.math.isFinite(solar_cosine)) return error.InvalidSolarCosine;

    var min_denominator: f64 = 0.0;
    var max_reflectance: f64 = 0.0;
    if (radiance.len != 0) {
        min_denominator = std.math.inf(f64);
        max_reflectance = -std.math.inf(f64);
    }

    var summary = ReflectanceAssemblySummary{
        .sample_count = radiance.len,
        .min_denominator = min_denominator,
        .max_reflectance = max_reflectance,
    };

    for (radiance, irradiance, out_reflectance) |radiance_value, irradiance_value, *reflectance| {
        const denominator_raw = irradiance_value * solar_cosine;
        const denominator = @max(denominator_raw, reflectance_denominator_floor);
        reflectance.* = (radiance_value * std.math.pi) / denominator;

        if (denominator_raw <= reflectance_denominator_floor) summary.denominator_clamp_count += 1;
        summary.min_denominator = @min(summary.min_denominator, denominator_raw);
        summary.max_reflectance = @max(summary.max_reflectance, reflectance.*);
        summary.radiance_sum += radiance_value;
        summary.irradiance_sum += irradiance_value;
        summary.reflectance_sum += reflectance.*;
    }

    // instrumentation: calculation telemetry: reflectance assembly -----------------------------------------  |
    // captures: denominator clamps and final reflectance extrema                                              |
    // why: preserves old simulate.reflectanceAssembly telemetry for numerical guard analysis.                 |
    telemetry.reflectanceAssembly(
        summary.sample_count,
        summary.denominator_clamp_count,
        summary.min_denominator,
        summary.max_reflectance,
    );
    // end instrumentation: calculation telemetry: reflectance assembly -------------------------------------  |

    return summary;
}

pub fn assembleReflectanceResults(
    solve_config: controls.SolveConfig,
    solar_cosine: f64,
    radiance: []const radiance_results.RadianceResult,
    irradiance: []const f64,
    out_reflectance: []f64,
    out_jacobian: []jacobian_states.Vector,
) Error!ReflectanceAssemblySummary {
    // assembleReflectanceResults ---------------------------------------------------------------------------- |
    // Convert calibrated radiance rows into reflectance rows and carry active RTM Jacobian lanes with them.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   rho_i      = pi * L_i / max(E0_i * mu0, 1e-9)                                                         |
    //   d rho_i/dx = pi * dL_i/dx / max(E0_i * mu0, 1e-9) for active RTM states                               |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Old `spectral_forward.zig` converts LABOS reflectance derivatives into radiance units by multiplying  |
    //   by `mu0 * E0 / pi`. Old `simulate.zig` inverts that scale for reflectance after product-grid          |
    //   averaging. The Jacobian states here do not perturb solar irradiance or geometry, so no extra          |
    //   product-rule term is present.                                                                         |
    //                                                                                                         |
    // shape                                                                                                   |
    //   Requested Jacobians require a full output vector per sample. Inactive lanes are written as zero so    |
    //   callers never read stale derivative values from reused buffers.                                       |
    // --------------------------------------------------------------------------------------------------------|
    if (radiance.len != irradiance.len or radiance.len != out_reflectance.len) return error.ShapeMismatch;
    if (!std.math.isFinite(solar_cosine)) return error.InvalidSolarCosine;

    const active_state_count = jacobian_states.activeStateCount(solve_config.derivative_state_mask);
    const wants_jacobian = solve_config.derivative_mode != .none and active_state_count != 0;
    if (wants_jacobian and out_jacobian.len != radiance.len) return error.ShapeMismatch;
    if (!wants_jacobian and out_jacobian.len != 0 and out_jacobian.len != radiance.len) {
        return error.ShapeMismatch;
    }

    var summary = initialSummary(radiance.len);
    for (radiance, irradiance, out_reflectance, 0..) |radiance_row, irradiance_value, *reflectance, index| {
        const denominator_raw = irradiance_value * solar_cosine;
        const denominator = @max(denominator_raw, reflectance_denominator_floor);
        const scale = std.math.pi / denominator;
        reflectance.* = radiance_row.radiance * scale;

        var row_jacobian = jacobian_states.zero();
        if (wants_jacobian) {
            row_jacobian = jacobian_states.scaleMasked(
                radiance_row.jacobian,
                scale,
                solve_config.derivative_state_mask,
            );
            out_jacobian[index] = row_jacobian;
            for (0..jacobian_states.state_count) |state_index| {
                summary.jacobian_sum[state_index] += row_jacobian[state_index];
            }
        } else if (out_jacobian.len != 0) {
            out_jacobian[index] = row_jacobian;
        }

        addReflectanceSample(&summary, radiance_row.radiance, irradiance_value, reflectance.*, denominator_raw);
    }

    emitReflectanceTelemetry(summary);
    return summary;
}

fn initialSummary(sample_count: usize) ReflectanceAssemblySummary {
    // initialSummary ---------------------------------------------------------------------------------------- |
    // Start reflectance summary extrema in the same empty-spectrum shape as the old route.                    |
    // --------------------------------------------------------------------------------------------------------|
    var min_denominator: f64 = 0.0;
    var max_reflectance: f64 = 0.0;
    if (sample_count != 0) {
        min_denominator = std.math.inf(f64);
        max_reflectance = -std.math.inf(f64);
    }

    return .{
        .sample_count = sample_count,
        .min_denominator = min_denominator,
        .max_reflectance = max_reflectance,
    };
}

fn addReflectanceSample(
    summary: *ReflectanceAssemblySummary,
    radiance: f64,
    irradiance: f64,
    reflectance: f64,
    denominator_raw: f64,
) void {
    // addReflectanceSample ---------------------------------------------------------------------------------- |
    // Add one product-grid row to scalar reflectance summary fields.                                          |
    // --------------------------------------------------------------------------------------------------------|
    if (denominator_raw <= reflectance_denominator_floor) summary.denominator_clamp_count += 1;
    summary.min_denominator = @min(summary.min_denominator, denominator_raw);
    summary.max_reflectance = @max(summary.max_reflectance, reflectance);
    summary.radiance_sum += radiance;
    summary.irradiance_sum += irradiance;
    summary.reflectance_sum += reflectance;
}

fn emitReflectanceTelemetry(summary: ReflectanceAssemblySummary) void {
    // emitReflectanceTelemetry ------------------------------------------------------------------------------ |
    // Preserve old reflectance-assembly telemetry after either scalar or Jacobian-aware assembly.             |
    // --------------------------------------------------------------------------------------------------------|

    // instrumentation: calculation telemetry: reflectance assembly -----------------------------------------  |
    // captures: denominator clamps and final reflectance extrema                                              |
    // why: preserves old simulate.reflectanceAssembly telemetry for numerical guard analysis.                 |
    telemetry.reflectanceAssembly(
        summary.sample_count,
        summary.denominator_clamp_count,
        summary.min_denominator,
        summary.max_reflectance,
    );
    // end instrumentation: calculation telemetry: reflectance assembly -------------------------------------  |

}

fn mean(values: []const f64) f64 {
    // mean -------------------------------------------------------------------------------------------------- |
    // Return the arithmetic mean of a non-empty scalar row.                                                   |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (values) |value| total += value;
    return total / @as(f64, @floatFromInt(values.len));
}

fn kernelSum(kernel: []const f64) f64 {
    // kernelSum --------------------------------------------------------------------------------------------- |
    // Sum kernel weights once so interior convolution rows can reuse the same normalization.                  |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (kernel) |weight| total += weight;
    return total;
}

fn convolvedBoundarySample(signal: []const f64, kernel: []const f64, half_width: usize, index: usize) f64 {
    // convolvedBoundarySample ------------------------------------------------------------------------------- |
    // Compute one edge sample with clipped-kernel normalization.                                              |
    // --------------------------------------------------------------------------------------------------------|
    const kernel_start = if (index < half_width) half_width - index else 0;
    const kernel_end = @min(kernel.len, signal.len + half_width - index);

    var acc: f64 = 0.0;
    var norm: f64 = 0.0;
    for (kernel_start..kernel_end) |kernel_index| {
        const signal_index = index + kernel_index - half_width;
        const weight = kernel[kernel_index];
        acc += signal[signal_index] * weight;
        norm += weight;
    }

    return if (norm == 0.0) 0.0 else acc / norm;
}

fn convolvedFullKernelSample(signal_window: []const f64, kernel: []const f64, norm: f64) f64 {
    // convolvedFullKernelSample ----------------------------------------------------------------------------- |
    // Compute one dense interior sample with the full kernel normalization.                                   |
    // --------------------------------------------------------------------------------------------------------|
    if (norm == 0.0) return 0.0;
    const Vec2 = @Vector(2, f64);
    var vector_sum: Vec2 = @splat(0.0);
    var kernel_index: usize = 0;
    while (kernel_index + 2 <= kernel.len) : (kernel_index += 2) {
        vector_sum = @mulAdd(
            Vec2,
            loadPair(signal_window, kernel_index),
            loadPair(kernel, kernel_index),
            vector_sum,
        );
    }

    var acc: f64 = @reduce(.Add, vector_sum);
    while (kernel_index < kernel.len) : (kernel_index += 1) {
        acc += signal_window[kernel_index] * kernel[kernel_index];
    }
    return acc / norm;
}

inline fn loadPair(values: []const f64, index: usize) @Vector(2, f64) {
    // loadPair ---------------------------------------------------------------------------------------------- |
    // Read two adjacent f64 values without requiring vector-aligned slice storage.                            |
    // --------------------------------------------------------------------------------------------------------|
    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&values[index]);
    return pair.*;
}

fn convolvedRadianceRow(
    rows: []const radiance_results.RadianceResult,
    kernel: []const f64,
    index: usize,
) f64 {
    // convolvedRadianceRow ---------------------------------------------------------------------------------- |
    // Compute one slit-convolved radiance value from row-vector storage.                                      |
    // --------------------------------------------------------------------------------------------------------|
    return convolvedRow(rows, kernel, index, .radiance, 0);
}

fn convolvedJacobianRow(
    rows: []const radiance_results.RadianceResult,
    kernel: []const f64,
    state_index: usize,
    index: usize,
) f64 {
    // convolvedJacobianRow ---------------------------------------------------------------------------------- |
    // Compute one slit-convolved derivative value from row-vector storage.                                    |
    // --------------------------------------------------------------------------------------------------------|
    return convolvedRow(rows, kernel, index, .jacobian, state_index);
}

const RowValue = enum {
    radiance,
    jacobian,
};

fn convolvedRow(
    rows: []const radiance_results.RadianceResult,
    kernel: []const f64,
    index: usize,
    value: RowValue,
    state_index: usize,
) f64 {
    // convolvedRow ------------------------------------------------------------------------------------------ |
    // Shared clipped-kernel convolution over row-vector radiance or one derivative lane.                      |
    // --------------------------------------------------------------------------------------------------------|
    const half_width = kernel.len / 2;
    const kernel_start = if (index < half_width) half_width - index else 0;
    const kernel_end = @min(kernel.len, rows.len + half_width - index);

    var acc: f64 = 0.0;
    var norm: f64 = 0.0;
    for (kernel_start..kernel_end) |kernel_index| {
        const row_index = index + kernel_index - half_width;
        const weight = kernel[kernel_index];
        const sample = switch (value) {
            .radiance => rows[row_index].radiance,
            .jacobian => rows[row_index].jacobian[state_index],
        };
        acc += sample * weight;
        norm += weight;
    }

    return if (norm == 0.0) 0.0 else acc / norm;
}

fn applyRadianceCalibration(calibration: Calibration, rows: []radiance_results.RadianceResult) void {
    // applyRadianceCalibration ------------------------------------------------------------------------------ |
    // Apply scalar channel calibration to the radiance field in row-vector storage.                           |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return;

    var total: f64 = 0.0;
    for (rows) |row| total += row.radiance;
    const mean_signal = total / @as(f64, @floatFromInt(rows.len));

    for (rows) |*row| {
        const stray_mixed = row.radiance + calibration.stray_light * (mean_signal - row.radiance);
        row.radiance = calibration.gain * stray_mixed + calibration.offset;
    }
}

fn applyJacobianCalibration(
    calibration: Calibration,
    rows: []radiance_results.RadianceResult,
    state_index: usize,
) void {
    // applyJacobianCalibration ------------------------------------------------------------------------------ |
    // Apply derivative channel calibration to one Jacobian lane in row-vector storage.                        |
    // --------------------------------------------------------------------------------------------------------|
    if (rows.len == 0) return;

    var total: f64 = 0.0;
    for (rows) |row| total += row.jacobian[state_index];
    const mean_signal = total / @as(f64, @floatFromInt(rows.len));

    for (rows) |*row| {
        const value = row.jacobian[state_index];
        const stray_mixed = value + calibration.stray_light * (mean_signal - value);
        row.jacobian[state_index] = calibration.gain * stray_mixed;
    }
}

fn slicesOverlap(
    comptime T: type,
    left: []const T,
    right: []const T,
) bool {
    // slicesOverlap ----------------------------------------------------------------------------------------- |
    // Detect storage overlap for non-integrated convolution guards.                                           |
    // --------------------------------------------------------------------------------------------------------|
    if (left.len == 0 or right.len == 0) return false;

    const item_size = @sizeOf(T);
    const left_start = @intFromPtr(left.ptr);
    const left_end = left_start + left.len * item_size;
    const right_start = @intFromPtr(right.ptr);
    const right_end = right_start + right.len * item_size;

    return left_start < right_end and right_start < left_end;
}

comptime {
    std.debug.assert(@sizeOf(Calibration) == 32);
    std.debug.assert(@sizeOf(ReflectanceAssemblySummary) == 80);
}
