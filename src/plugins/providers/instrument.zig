//! Purpose:
//!   Provide builtin instrument-response behavior for the registry-selected
//!   observation model.
//!
//! Physics:
//!   This file maps scene metadata into calibration, integration, and slit
//!   kernel behavior used by the forward instrument response.
//!
//! Vendor:
//!   `instrument`
//!
//! Design:
//!   Keep the provider self-contained: select the response profile from the
//!   scene, then build the integration kernel or slit kernel the caller needs.
//!
//! Invariants:
//!   Sample kernels must remain normalized, and measured-channel sampling must
//!   not fall back to legacy post-convolution behavior.
//!
//! Validation:
//!   Covered by the instrument provider unit tests in this file.
const std = @import("std");
const ReferenceData = @import("../../model/ReferenceData.zig");
const calibration = @import("../../kernels/spectra/calibration.zig");
const PreparedOpticalState = @import("../../kernels/optics/preparation.zig").PreparedOpticalState;
const AdaptiveReferenceGrid = @import("../../model/Instrument.zig").AdaptiveReferenceGrid;
const BuiltinLineShapeKind = @import("../../model/Instrument.zig").BuiltinLineShapeKind;
const InstrumentModel = @import("../../model/Instrument.zig").Instrument;
const SpectralChannel = @import("../../model/Instrument.zig").SpectralChannel;
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;
const Scene = @import("../../model/Scene.zig").Scene;

/// Default number of samples used by the fallback integration kernel.
pub const default_integration_sample_count: usize = 5;
/// Maximum number of samples accepted by the integration kernel buffers.
pub const max_integration_sample_count: usize = max_line_shape_samples;

/// Integration kernel sampled around a nominal wavelength.
pub const IntegrationKernel = struct {
    enabled: bool,
    sample_count: usize,
    offsets_nm: [max_integration_sample_count]f64,
    weights: [max_integration_sample_count]f64,
};

/// Builtin instrument-response provider contract.
pub const Provider = struct {
    id: []const u8,
    calibrationForScene: *const fn (scene: *const Scene, channel: SpectralChannel) calibration.Calibration,
    usesIntegratedSampling: *const fn (scene: *const Scene, channel: SpectralChannel) bool,
    integrationForWavelength: *const fn (scene: *const Scene, prepared: ?*const PreparedOpticalState, channel: SpectralChannel, nominal_wavelength_nm: f64, kernel: *IntegrationKernel) void,
    slitKernelForScene: *const fn (scene: *const Scene, channel: SpectralChannel) [5]f64,
};

/// Resolve a builtin instrument response provider by identifier.
pub fn resolve(provider_id: []const u8) ?Provider {
    if (std.mem.eql(u8, provider_id, "builtin.generic_response")) {
        return genericProvider(provider_id);
    }
    return null;
}

fn genericProvider(provider_id: []const u8) Provider {
    return .{
        .id = provider_id,
        .calibrationForScene = calibrationForScene,
        .usesIntegratedSampling = usesIntegratedInstrumentSampling,
        .integrationForWavelength = integrationForWavelength,
        .slitKernelForScene = slitKernelForScene,
    };
}

fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) calibration.Calibration {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    return .{
        .gain = controls.multiplicative_offset,
        .offset = controls.additive_offset,
        .wavelength_shift_nm = controls.wavelength_shift_nm,
        .stray_light = controls.stray_light,
    };
}

fn usesIntegratedInstrumentSampling(scene: *const Scene, channel: SpectralChannel) bool {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // DECISION:
    //   Integrated sampling is driven by the observation model first; explicit
    //   line-shape metadata also forces integration so the legacy convolution
    //   path does not silently handle modern measured channels.
    const mode_requires_native_integration = switch (scene.observation_model.sampling) {
        .operational, .measured_channels => true,
        .native, .synthetic => false,
    };
    return mode_requires_native_integration or
        response.fwhm_nm > 0.0 or
        response.instrument_line_shape.sample_count > 0 or
        response.instrument_line_shape_table.nominal_count > 0;
}

fn integrationForWavelength(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: *IntegrationKernel,
) void {
    resetKernel(kernel);
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    if (!usesIntegratedInstrumentSampling(scene, channel)) {
        kernel.sample_count = 1;
        return;
    }

    if (response.instrument_line_shape_table.nominal_count > 0) {
        kernel.sample_count = response.instrument_line_shape_table.writeNormalizedKernelForNominal(
            nominal_wavelength_nm,
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        // PARITY:
        //   Strong-line table kernels bypass the legacy slit convolution when
        //   the table can provide a normalized kernel directly.
        kernel.enabled = true;
        return;
    }

    if (response.instrument_line_shape.sample_count > 0) {
        kernel.sample_count = response.instrument_line_shape.writeNormalizedKernel(
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        kernel.enabled = true;
        return;
    }

    if (prepared) |prepared_state| {
        if (buildAdaptiveIntegrationKernel(scene, prepared_state, response, nominal_wavelength_nm, kernel)) {
            return;
        }
    }

    if (response.high_resolution_step_nm > 0.0 and response.high_resolution_half_span_nm > 0.0) {
        const step_nm = response.high_resolution_step_nm;
        const half_span_nm = response.high_resolution_half_span_nm;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            kernel.offsets_nm[sample_count] = offset_nm;
            kernel.weights[sample_count] = spectralResponseWeight(response, offset_nm);
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += kernel.weights[index];
        if (total_weight <= 0.0) {
            resetKernel(kernel);
            kernel.offsets_nm[0] = 0.0;
            kernel.weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| kernel.weights[index] /= total_weight;
        }
        // PARITY:
        //   High-resolution measurement kernels are normalized in place rather
        //   than routed through the legacy slit-convolution stage.
        kernel.enabled = true;
        kernel.sample_count = sample_count;
        return;
    }

    switch (scene.observation_model.sampling) {
        .operational, .measured_channels => {
            kernel.sample_count = 1;
            return;
        },
        .native, .synthetic => {},
    }

    const default_half_span_nm = defaultKernelHalfSpanNm(response.fwhm_nm);
    const offsets_nm: [default_integration_sample_count]f64 = .{
        -default_half_span_nm,
        -0.5 * default_half_span_nm,
        0.0,
        0.5 * default_half_span_nm,
        default_half_span_nm,
    };

    var total_weight: f64 = 0.0;
    for (offsets_nm, 0..) |offset_nm, index| {
        kernel.offsets_nm[index] = offset_nm;
        kernel.weights[index] = spectralResponseWeight(response, offset_nm);
        total_weight += kernel.weights[index];
    }
    for (0..default_integration_sample_count) |index| kernel.weights[index] /= total_weight;
    kernel.enabled = true;
    kernel.sample_count = default_integration_sample_count;
}

/// Purpose:
///   Build an adaptive integration kernel from prepared spectroscopy data.
///
/// Physics:
///   The adaptive kernel refines sampling around strong spectral lines so the
///   instrument response can capture line-centre structure.
///
/// Vendor:
///   `instrument::buildAdaptiveIntegrationKernel`
///
/// Inputs:
///   `prepared` carries prepared spectroscopy lines and absorber data.
///
/// Outputs:
///   Returns true when an adaptive kernel could be built.
///
/// Units:
///   Wavelengths are in nanometers.
///
/// Assumptions:
///   The adaptive reference grid is enabled and the line FWHM is positive.
///
/// Decisions:
///   The adaptive path short-circuits the legacy fixed-kernel path when the
///   prepared state can provide a better sampled response.
///
/// Validation:
///   Covered by the adaptive strong-line unit test in this file.
fn buildAdaptiveIntegrationKernel(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    kernel: *IntegrationKernel,
) bool {
    const adaptive = scene.observation_model.adaptive_reference_grid;
    if (!adaptive.enabled()) return false;
    if (response.fwhm_nm <= 0.0) return false;

    const has_single_line_list = if (prepared.spectroscopy_lines) |line_list|
        line_list.lines.len != 0
    else
        false;
    if (!has_single_line_list and prepared.line_absorbers.len == 0) return false;

    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    const half_span_nm = if (response.high_resolution_half_span_nm > 0.0)
        response.high_resolution_half_span_nm
    else
        defaultKernelHalfSpanNm(fwhm_nm);
    const window_start_nm = nominal_wavelength_nm - half_span_nm;
    const window_end_nm = nominal_wavelength_nm + half_span_nm;

    var sample_wavelengths_nm: [max_integration_sample_count]f64 = undefined;
    var sample_raw_weights: [max_integration_sample_count]f64 = undefined;
    var sample_count: usize = 0;

    if (!addUniformAdaptiveSamples(
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
        response,
        nominal_wavelength_nm,
        window_start_nm,
        window_end_nm,
        adaptive.points_per_fwhm,
    )) return false;

    if (prepared.spectroscopy_lines) |line_list| {
        if (!addAdaptiveStrongLineSamplesFromList(
            adaptive,
            line_list,
            response,
            nominal_wavelength_nm,
            window_start_nm,
            window_end_nm,
            &sample_wavelengths_nm,
            &sample_raw_weights,
            &sample_count,
        )) return false;
    }
    if (prepared.line_absorbers.len != 0) {
        for (prepared.line_absorbers) |line_absorber| {
            if (!addAdaptiveStrongLineSamplesFromList(
                adaptive,
                line_absorber.line_list,
                response,
                nominal_wavelength_nm,
                window_start_nm,
                window_end_nm,
                &sample_wavelengths_nm,
                &sample_raw_weights,
                &sample_count,
            )) return false;
        }
    }

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    );
}

fn addAdaptiveStrongLineSamplesFromList(
    adaptive: AdaptiveReferenceGrid,
    line_list: ReferenceData.SpectroscopyLineList,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
) bool {
    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    const threshold_strength = line_list.runtime_controls.thresholdStrength(line_list.lines) orelse return true;
    var previous_center_nm: ?f64 = null;
    for (line_list.lines) |line| {
        if (line.line_strength_cm2_per_molecule < threshold_strength) continue;
        if (line.center_wavelength_nm < window_start_nm or line.center_wavelength_nm > window_end_nm) continue;
        if (previous_center_nm) |previous| {
            if (@abs(line.center_wavelength_nm - previous) <= 1.0e-9) continue;
        }
        previous_center_nm = line.center_wavelength_nm;

        const strong_half_span_nm = 0.5 * fwhm_nm;
        const strong_start_nm = @max(window_start_nm, line.center_wavelength_nm - strong_half_span_nm);
        const strong_end_nm = @min(window_end_nm, line.center_wavelength_nm + strong_half_span_nm);
        // UNITS:
        //   `refinement_count` tracks how many wavelength intervals are used to
        //   cover the strong-line window in nanometers.
        const refinement_count = strongDivisionCount(adaptive, strong_end_nm - strong_start_nm, fwhm_nm);
        if (!addStrongAdaptiveSamples(
            sample_wavelengths_nm,
            sample_raw_weights,
            sample_count,
            response,
            nominal_wavelength_nm,
            line.center_wavelength_nm,
            strong_start_nm,
            strong_end_nm,
            refinement_count,
        )) return false;
    }
    return true;
}

fn addUniformAdaptiveSamples(
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
    points_per_fwhm: u16,
) bool {
    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    const safe_points_per_fwhm: usize = @max(@as(usize, points_per_fwhm), 1);
    // UNITS:
    //   The integration step is derived from FWHM in nanometers and the grid
    //   points-per-FWHM control.
    const step_nm = fwhm_nm / @as(f64, @floatFromInt(safe_points_per_fwhm));
    var interval_start_nm = window_start_nm;
    while (interval_start_nm < window_end_nm - 1.0e-12) {
        const interval_end_nm = @min(interval_start_nm + step_nm, window_end_nm);
        if (!appendAdaptiveSample(
            sample_wavelengths_nm,
            sample_raw_weights,
            sample_count,
            0.5 * (interval_start_nm + interval_end_nm),
            spectralResponseWeight(response, 0.5 * (interval_start_nm + interval_end_nm) - nominal_wavelength_nm) * (interval_end_nm - interval_start_nm),
        )) return false;
        interval_start_nm = interval_end_nm;
    }
    return true;
}

fn addStrongAdaptiveSamples(
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    strong_center_nm: f64,
    strong_start_nm: f64,
    strong_end_nm: f64,
    refinement_count: usize,
) bool {
    if (refinement_count == 0) return true;
    const strong_width_nm = @max(strong_end_nm - strong_start_nm, 1.0e-9);
    if (!appendAdaptiveSample(
        sample_wavelengths_nm,
        sample_raw_weights,
        sample_count,
        strong_center_nm,
        spectralResponseWeight(response, strong_center_nm - nominal_wavelength_nm) *
            (strong_width_nm / @as(f64, @floatFromInt(refinement_count))),
    )) return false;

    if (refinement_count == 1) return true;
    const interval_count = refinement_count - 1;
    const step_nm = strong_width_nm / @as(f64, @floatFromInt(interval_count));
    var interval_start_nm = strong_start_nm;
    while (interval_start_nm < strong_end_nm - 1.0e-12) {
        const interval_end_nm = @min(interval_start_nm + step_nm, strong_end_nm);
        if (!appendAdaptiveSample(
            sample_wavelengths_nm,
            sample_raw_weights,
            sample_count,
            0.5 * (interval_start_nm + interval_end_nm),
            spectralResponseWeight(response, 0.5 * (interval_start_nm + interval_end_nm) - nominal_wavelength_nm) * (interval_end_nm - interval_start_nm),
        )) return false;
        interval_start_nm = interval_end_nm;
    }
    return true;
}

fn strongDivisionCount(adaptive: AdaptiveReferenceGrid, span_nm: f64, fwhm_nm: f64) usize {
    const min_divisions = @as(usize, adaptive.strong_line_min_divisions);
    const max_divisions = @as(usize, adaptive.strong_line_max_divisions);
    const scaled = @as(usize, @intFromFloat(std.math.round(
        (@max(span_nm, 1.0e-9) / @max(fwhm_nm, 1.0e-9)) * @as(f64, @floatFromInt(min_divisions)),
    )));
    // DECISION:
    //   Clamp the division count into the configured min/max range so very
    //   narrow or very broad strong-line windows still produce bounded work.
    return std.math.clamp(@max(scaled, min_divisions), min_divisions, max_divisions);
}

fn appendAdaptiveSample(
    sample_wavelengths_nm: *[max_integration_sample_count]f64,
    sample_raw_weights: *[max_integration_sample_count]f64,
    sample_count: *usize,
    wavelength_nm: f64,
    raw_weight: f64,
) bool {
    if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(raw_weight) or raw_weight <= 0.0) return true;
    if (sample_count.* >= max_integration_sample_count) return false;
    sample_wavelengths_nm[sample_count.*] = wavelength_nm;
    sample_raw_weights[sample_count.*] = raw_weight;
    sample_count.* += 1;
    return true;
}

fn finalizeAdaptiveKernel(
    kernel: *IntegrationKernel,
    nominal_wavelength_nm: f64,
    sample_wavelengths_nm: []f64,
    sample_raw_weights: []f64,
) bool {
    if (sample_wavelengths_nm.len == 0 or sample_wavelengths_nm.len != sample_raw_weights.len) return false;

    insertionSortSamples(sample_wavelengths_nm, sample_raw_weights);

    var merged_count: usize = 0;
    for (sample_wavelengths_nm, sample_raw_weights) |wavelength_nm, raw_weight| {
        if (merged_count != 0 and @abs(sample_wavelengths_nm[merged_count - 1] - wavelength_nm) <= 1.0e-9) {
            sample_raw_weights[merged_count - 1] += raw_weight;
            continue;
        }
        sample_wavelengths_nm[merged_count] = wavelength_nm;
        sample_raw_weights[merged_count] = raw_weight;
        merged_count += 1;
    }
    if (merged_count == 0) return false;

    var total_weight: f64 = 0.0;
    for (sample_raw_weights[0..merged_count]) |raw_weight| total_weight += raw_weight;
    if (!std.math.isFinite(total_weight) or total_weight <= 0.0) return false;

    resetKernel(kernel);
    kernel.enabled = true;
    kernel.sample_count = merged_count;
    for (0..merged_count) |index| {
        kernel.offsets_nm[index] = sample_wavelengths_nm[index] - nominal_wavelength_nm;
        kernel.weights[index] = sample_raw_weights[index] / total_weight;
    }
    return true;
}

fn insertionSortSamples(sample_wavelengths_nm: []f64, sample_raw_weights: []f64) void {
    if (sample_wavelengths_nm.len != sample_raw_weights.len) return;
    for (1..sample_wavelengths_nm.len) |index| {
        var cursor = index;
        while (cursor > 0 and sample_wavelengths_nm[cursor] < sample_wavelengths_nm[cursor - 1]) : (cursor -= 1) {
            std.mem.swap(f64, &sample_wavelengths_nm[cursor], &sample_wavelengths_nm[cursor - 1]);
            std.mem.swap(f64, &sample_raw_weights[cursor], &sample_raw_weights[cursor - 1]);
        }
    }
}

fn resetKernel(kernel: *IntegrationKernel) void {
    kernel.enabled = false;
    kernel.sample_count = 0;
    @memset(kernel.offsets_nm[0..], 0.0);
    @memset(kernel.weights[0..], 0.0);
}

fn slitKernelForScene(scene: *const Scene, channel: SpectralChannel) [5]f64 {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // PARITY:
    //   The default slit kernel remains a five-point symmetric kernel so the
    //   legacy convolution shape stays recognizable when explicit line-shape
    //   metadata is absent.
    if (response.fwhm_nm <= 0.0) {
        return .{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    }

    const sample_spacing_nm = if (scene.spectral_grid.sample_count <= 1)
        1.0
    else
        (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    var kernel: [5]f64 = undefined;
    var sum: f64 = 0.0;
    for (0..kernel.len) |index| {
        const offset_samples = @as(f64, @floatFromInt(@as(i32, @intCast(index)) - 2));
        const offset_nm = offset_samples * sample_spacing_nm;
        const value = spectralResponseWeight(response, offset_nm);
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}

fn defaultKernelHalfSpanNm(fwhm_nm: f64) f64 {
    // UNITS:
    //   Half-span is expressed in nanometers and clamped to keep the fallback
    //   kernel away from degenerate widths.
    return @max(3.0 * @max(fwhm_nm, 1.0e-4), 1.0e-4);
}

fn spectralResponseWeight(response: InstrumentModel.SpectralResponse, offset_nm: f64) f64 {
    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    return switch (response.slit_index) {
        .gaussian_modulated => {
            const sigma_nm = fwhm_nm / 2.354820045;
            const gaussian = @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
            const phase_rad = std.math.degreesToRadians(response.phase_deg);
            const modulation = 1.0 + response.amplitude * std.math.pow(f64, @sin(response.scale * offset_nm / fwhm_nm + phase_rad), 2.0);
            return @max(gaussian * modulation, 0.0);
        },
        .flat_top_n4 => flatTopN4Weight(fwhm_nm, offset_nm),
        .triple_flat_top_n4 => flatTopN4Weight(fwhm_nm, offset_nm) +
            flatTopN4Weight(fwhm_nm, offset_nm - 0.1) +
            flatTopN4Weight(fwhm_nm, offset_nm + 0.1),
        .table => builtinLineShapeWeight(response.builtin_line_shape, fwhm_nm, offset_nm),
    };
}

fn builtinLineShapeWeight(shape: BuiltinLineShapeKind, fwhm_nm: f64, offset_nm: f64) f64 {
    const safe_fwhm_nm = @max(fwhm_nm, 1.0e-4);
    return switch (shape) {
        .gaussian => {
            const sigma_nm = safe_fwhm_nm / 2.354820045;
            return @exp(-0.5 * std.math.pow(f64, offset_nm / sigma_nm, 2.0));
        },
        .flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm),
        .triple_flat_top_n4 => flatTopN4Weight(safe_fwhm_nm, offset_nm) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm - 0.1) +
            flatTopN4Weight(safe_fwhm_nm, offset_nm + 0.1),
    };
}

fn flatTopN4Weight(fwhm_nm: f64, offset_nm: f64) f64 {
    // UNITS:
    //   The width parameter is in nanometers and controls the normalized
    //   flat-top shape used by the builtin response.
    const w_nm = fwhm_nm / 1.681793;
    return std.math.pow(f64, 2.0, -2.0 * std.math.pow(f64, offset_nm / @max(w_nm, 1.0e-6), 4.0));
}

test "high-resolution integration retains the full symmetric sampling span" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 771.0,
            .sample_count = 1301,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 0.40,
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, null, .radiance, 760.5, &kernel);
    try std.testing.expect(kernel.enabled);
    try std.testing.expectEqual(@as(usize, 81), kernel.sample_count);
    try std.testing.expectApproxEqAbs(@as(f64, -0.40), kernel.offsets_nm[0], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), kernel.offsets_nm[kernel.sample_count - 1], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), kernel.offsets_nm[kernel.sample_count / 2], 1e-12);
    try std.testing.expectApproxEqAbs(kernel.weights[0], kernel.weights[kernel.sample_count - 1], 1e-12);
}

test "flat-top line shape spreads weight more broadly than gaussian for the same FWHM" {
    const gaussian_scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 771.0,
            .sample_count = 1301,
        },
        .observation_model = .{
            .instrument = .{ .custom = "compare" },
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .gaussian,
            .high_resolution_step_nm = 0.19,
            .high_resolution_half_span_nm = 1.14,
        },
    };
    const flat_top_scene: Scene = .{
        .spectral_grid = gaussian_scene.spectral_grid,
        .observation_model = .{
            .instrument = .{ .custom = "compare" },
            .sampling = .native,
            .noise_model = .none,
            .instrument_line_fwhm_nm = 0.38,
            .builtin_line_shape = .flat_top_n4,
            .high_resolution_step_nm = 0.19,
            .high_resolution_half_span_nm = 1.14,
        },
    };

    var gaussian_kernel: IntegrationKernel = undefined;
    integrationForWavelength(&gaussian_scene, null, .radiance, 760.5, &gaussian_kernel);
    var flat_top_kernel: IntegrationKernel = undefined;
    integrationForWavelength(&flat_top_scene, null, .radiance, 760.5, &flat_top_kernel);

    try std.testing.expectEqual(gaussian_kernel.sample_count, flat_top_kernel.sample_count);
    try std.testing.expect(flat_top_kernel.weights[flat_top_kernel.sample_count / 2] < gaussian_kernel.weights[gaussian_kernel.sample_count / 2]);
    try std.testing.expect(flat_top_kernel.weights[0] > gaussian_kernel.weights[0]);
}

test "measured-channel sampling bypasses legacy post-convolution even without explicit slit metadata" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .{ .custom = "measured" },
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .measured_wavelengths_nm = &.{ 760.81, 761.03, 761.19 },
            .ingested_noise_sigma = &.{ 0.02, 0.02, 0.02 },
        },
    };

    try std.testing.expect(usesIntegratedInstrumentSampling(&scene, .radiance));

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, null, .radiance, 761.03, &kernel);
    try std.testing.expectEqual(@as(usize, 1), kernel.sample_count);
    try std.testing.expect(!kernel.enabled);
}

test "adaptive strong-line sampling injects refined centers from prepared spectroscopy" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = ReferenceData.SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.52, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 761.10, .line_strength_cm2_per_molecule = 2.0e-21, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            }),
            .runtime_controls = .{
                .gas_index = 7,
                .threshold_line_scale = 0.5,
            },
        },
    });
    defer if (prepared.spectroscopy_lines) |*line_list| line_list.deinit(std.testing.allocator);

    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 759.0,
            .end_nm = 762.0,
            .sample_count = 121,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.4,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 3,
                .strong_line_min_divisions = 5,
                .strong_line_max_divisions = 9,
            },
        },
    };

    var kernel: IntegrationKernel = undefined;
    integrationForWavelength(&scene, &prepared, .radiance, 760.5, &kernel);
    try std.testing.expect(kernel.enabled);
    try std.testing.expect(kernel.sample_count > 18);

    var found_strong_center = false;
    for (kernel.offsets_nm[0..kernel.sample_count]) |offset_nm| {
        if (@abs(offset_nm - 0.02) <= 1.0e-6) {
            found_strong_center = true;
            break;
        }
    }
    try std.testing.expect(found_strong_center);
}
