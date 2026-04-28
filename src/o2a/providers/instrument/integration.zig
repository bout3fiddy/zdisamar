const std = @import("std");
const adaptive_cache = @import("adaptive_cache.zig");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../../kernels/optics/preparation.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../model/Instrument.zig").Instrument;
const Scene = @import("../../../model/Scene.zig").Scene;
const SpectralChannel = @import("../../../model/Instrument.zig").SpectralChannel;

pub const IntegrationKernel = types.IntegrationKernel;
pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;
pub const AdaptiveKernelCache = adaptive_cache.AdaptiveKernelCache;
pub const Error = error{
    DisamarKernelRealizationFailed,
};

pub fn usesIntegratedInstrumentSampling(scene: *const Scene, channel: SpectralChannel) bool {
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

pub fn integrationForWavelength(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: *IntegrationKernel,
) void {
    integrationForWavelengthChecked(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        kernel,
    ) catch {
        response_support.resetKernel(kernel);
        kernel.sample_count = 1;
    };
}

pub fn integrationForWavelengthChecked(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    kernel: *IntegrationKernel,
) Error!void {
    try integrationForWavelengthWithAdaptiveCacheChecked(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        null,
        kernel,
    );
}

pub fn integrationForWavelengthWithAdaptiveCache(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) void {
    integrationForWavelengthWithAdaptiveCacheChecked(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        cached_adaptive_kernel,
        kernel,
    ) catch {
        response_support.resetKernel(kernel);
        kernel.sample_count = 1;
    };
}

pub fn integrationForWavelengthWithAdaptiveCacheChecked(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) Error!void {
    response_support.resetKernel(kernel);
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
            response_support.resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        // PARITY:
        //   Strong-line table routines bypass the legacy slit convolution when
        //   the table can provide a normalized routine directly.
        kernel.enabled = true;
        return;
    }

    if (response.instrument_line_shape.sample_count > 0) {
        kernel.sample_count = response.instrument_line_shape.writeNormalizedKernel(
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            response_support.resetKernel(kernel);
            kernel.enabled = true;
            kernel.sample_count = 1;
            kernel.weights[0] = 1.0;
            return;
        }
        kernel.enabled = true;
        return;
    }

    if (response.integration_mode == .disamar_hr_grid) {
        if (prepared) |prepared_state| {
            if (cached_adaptive_kernel) |cache| {
                if (adaptive_cache.buildAdaptiveIntegrationKernelFromCache(
                    response,
                    nominal_wavelength_nm,
                    cache,
                    kernel,
                )) {
                    return;
                }
            }
            if (adaptive_plan.buildAdaptiveIntegrationKernel(
                scene,
                prepared_state,
                response,
                nominal_wavelength_nm,
                kernel,
            )) {
                return;
            }
        } else if (adaptive_plan.buildDisamarRealizedKernel(
            scene,
            response,
            nominal_wavelength_nm,
            kernel,
        )) {
            return;
        }
        return Error.DisamarKernelRealizationFailed;
    }

    const prefer_explicit_hr_grid = switch (response.integration_mode) {
        .auto, .explicit_hr_grid => true,
        .adaptive => false,
        .disamar_hr_grid => false,
    };
    const prefer_adaptive_grid = response.integration_mode == .adaptive;

    if (prefer_explicit_hr_grid and response.high_resolution_step_nm > 0.0 and response.high_resolution_half_span_nm > 0.0) {
        const step_nm = response.high_resolution_step_nm;
        const half_span_nm = response.high_resolution_half_span_nm;
        var sample_count: usize = 0;
        var offset_nm = -half_span_nm;
        while (offset_nm <= half_span_nm + (step_nm * 0.5) and sample_count < max_integration_sample_count) : (offset_nm += step_nm) {
            kernel.offsets_nm[sample_count] = offset_nm;
            const response_weight = response_support.spectralResponseWeight(response, offset_nm);
            kernel.weights[sample_count] = response_weight;
            sample_count += 1;
        }
        if (sample_count == 0) sample_count = 1;
        var total_weight: f64 = 0.0;
        for (0..sample_count) |index| total_weight += kernel.weights[index];
        if (total_weight <= 0.0) {
            response_support.resetKernel(kernel);
            kernel.offsets_nm[0] = 0.0;
            kernel.weights[0] = 1.0;
            sample_count = 1;
        } else {
            for (0..sample_count) |index| kernel.weights[index] /= total_weight;
        }
        // PARITY:
        //   High-resolution measurement routines are normalized in place rather
        //   than routed through the legacy slit-convolution stage.
        kernel.enabled = true;
        kernel.sample_count = sample_count;
        return;
    }

    if (prepared) |prepared_state| {
        if (cached_adaptive_kernel) |cache| {
            if (adaptive_cache.buildAdaptiveIntegrationKernelFromCache(
                response,
                nominal_wavelength_nm,
                cache,
                kernel,
            )) {
                return;
            }
        }
        if (prefer_adaptive_grid or response.high_resolution_step_nm == 0.0 or response.high_resolution_half_span_nm == 0.0) {
            if (adaptive_plan.buildAdaptiveIntegrationKernel(
                scene,
                prepared_state,
                response,
                nominal_wavelength_nm,
                kernel,
            )) {
                return;
            }
        }
    }

    switch (scene.observation_model.sampling) {
        .operational, .measured_channels => {
            kernel.sample_count = 1;
            return;
        },
        .native, .synthetic => {},
    }

    const default_half_span_nm = response_support.defaultKernelHalfSpanNm(response.fwhm_nm);
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
        kernel.weights[index] = response_support.spectralResponseWeight(response, offset_nm);
        total_weight += kernel.weights[index];
    }
    for (0..default_integration_sample_count) |index| kernel.weights[index] /= total_weight;
    kernel.enabled = true;
    kernel.sample_count = default_integration_sample_count;
}

pub fn prepareAdaptiveKernelCache(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    cache: *AdaptiveKernelCache,
) bool {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    return adaptive_cache.prepareAdaptiveKernelCache(scene, prepared, response, cache);
}

pub fn slitKernelForScene(scene: *const Scene, channel: SpectralChannel) [5]f64 {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // PARITY:
    //   The default slit routine remains a five-point symmetric routine so the
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
        const value = response_support.spectralResponseWeight(response, offset_nm);
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}
