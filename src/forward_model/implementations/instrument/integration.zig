const std = @import("std");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

pub const IntegrationKernel = types.IntegrationKernel;
pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;
pub const Error = error{
    InstrumentKernelRealizationFailed,
};

// layout(64-bit):
//   size: 20512 B, align: 8 B
//   field storage: plan=20504 B, ready=1 B; padding: 7 B (56 bits)
//   unused bits: 56 padding + 7 bool-storage slack = 63 bits
//   cache span: 321 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 20512 B (20.0 KiB); total = per instance * live instance count
pub const AdaptiveKernelCache = struct {
    ready: bool = false,
    plan: adaptive_plan.AdaptiveIntervalPlan = .{},
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

// hot path:
//   when: wavelength sampling builds radiance/irradiance integration kernels per nominal wavelength
//   work: chooses table, fixed line-shape, adaptive, or default integration samples
//   data: channel response controls, adaptive cache, offsets/weights kernel storage
//   follow: adaptive_plan builders and response_support.spectralResponseWeight
//   math: kernel approximates integral y(lambda_i) = sum_j w_ij y(lambda_i + delta_ij), with sum_j w_ij = 1
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
        response_support.writeIdentityKernel(kernel, false);
        return;
    }

    if (response.instrument_line_shape_table.nominal_count > 0) {
        kernel.sample_count = response.instrument_line_shape_table.writeNormalizedKernelForNominal(
            nominal_wavelength_nm,
            kernel.offsets_nm[0..],
            kernel.weights[0..],
        );
        if (kernel.sample_count == 0) {
            response_support.writeIdentityKernel(kernel, true);
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
            response_support.writeIdentityKernel(kernel, true);
            return;
        }
        kernel.enabled = true;
        return;
    }

    switch (response.integration_mode) {
        .disamar_hr_grid => {
            const wrote_kernel = writeDisamarHighResolutionKernel(
                scene,
                prepared,
                response,
                nominal_wavelength_nm,
                channel,
                cached_adaptive_kernel,
                kernel,
            );
            if (wrote_kernel) return;

            return Error.InstrumentKernelRealizationFailed;
        },

        .explicit_hr_grid => {
            const wrote_kernel = writeExplicitGridKernel(response, kernel);
            if (wrote_kernel) return;

            return Error.InstrumentKernelRealizationFailed;
        },

        .adaptive => {
            if (prepared) |prepared_state| {
                const wrote_kernel = adaptiveIntegrationFromPrepared(
                    scene,
                    prepared_state,
                    response,
                    nominal_wavelength_nm,
                    channel,
                    cached_adaptive_kernel,
                    kernel,
                );
                if (wrote_kernel) return;
            }

            return Error.InstrumentKernelRealizationFailed;
        },

        .default_kernel => {},
    }

    switch (scene.observation_model.sampling) {
        .operational, .measured_channels => {
            response_support.writeIdentityKernel(kernel, false);
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

        // math: fallback raw w_j = response(delta_j), normalized so sum_j w_j = 1.
        kernel.weights[index] = response_support.spectralResponseWeight(response, offset_nm);
        total_weight += kernel.weights[index];
    }
    for (0..default_integration_sample_count) |index| kernel.weights[index] /= total_weight;
    kernel.enabled = true;
    kernel.sample_count = default_integration_sample_count;
}

fn writeDisamarHighResolutionKernel(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    channel: SpectralChannel,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) bool {
    if (prepared) |prepared_state| {
        return adaptiveIntegrationFromPrepared(
            scene,
            prepared_state,
            response,
            nominal_wavelength_nm,
            channel,
            cached_adaptive_kernel,
            kernel,
        );
    }

    return adaptive_plan.buildDisamarRealizedKernel(
        scene,
        response,
        nominal_wavelength_nm,
        channel == .irradiance,
        kernel,
    );
}

fn writeExplicitGridKernel(
    response: InstrumentModel.SpectralResponse,
    kernel: *IntegrationKernel,
) bool {
    if (response.high_resolution_step_nm <= 0.0 or response.high_resolution_half_span_nm <= 0.0) {
        return false;
    }

    const step_nm = response.high_resolution_step_nm;
    const half_span_nm = response.high_resolution_half_span_nm;
    var sample_count: usize = 0;
    var offset_nm = -half_span_nm;
    while (offset_nm <= half_span_nm + (step_nm * 0.5) and
        sample_count < max_integration_sample_count) : (offset_nm += step_nm)
    {
        kernel.offsets_nm[sample_count] = offset_nm;

        // math: raw w(delta) = response(delta); normalized below as w_j / sum_k w_k.
        const response_weight = response_support.spectralResponseWeight(response, offset_nm);
        kernel.weights[sample_count] = response_weight;
        sample_count += 1;
    }
    if (sample_count == 0) return false;

    var total_weight: f64 = 0.0;
    for (0..sample_count) |index| total_weight += kernel.weights[index];
    if (!std.math.isFinite(total_weight) or total_weight <= 0.0) return false;

    for (0..sample_count) |index| kernel.weights[index] /= total_weight;

    // High-resolution measurement routines are normalized in place rather
    // than routed through the legacy slit-convolution stage.
    kernel.enabled = true;
    kernel.sample_count = sample_count;
    return true;
}

fn adaptiveIntegrationFromPrepared(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    channel: SpectralChannel,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) bool {
    if (cached_adaptive_kernel) |cache| {
        if (buildAdaptiveIntegrationKernelFromCache(
            response,
            nominal_wavelength_nm,
            cache,
            channel == .irradiance,
            kernel,
        )) {
            return true;
        }
    }
    return adaptive_plan.buildAdaptiveIntegrationKernel(
        scene,
        prepared,
        response,
        nominal_wavelength_nm,
        channel == .irradiance,
        kernel,
    );
}

// hot path:
//   when: wavelength sampling can reuse adaptive instrument grids across nominal wavelengths
//   work: prepares strong-line-aware support data for adaptive kernel construction
//   data: scene response controls, prepared spectroscopy state, adaptive cache storage
//   follow: adaptive_plan interval construction
pub fn prepareAdaptiveKernelCache(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    cache: *AdaptiveKernelCache,
) bool {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    cache.* = .{};
    if (!adaptive_plan.buildAdaptiveIntervalPlan(scene, prepared, response, &cache.plan)) {
        return false;
    }
    cache.ready = true;
    return true;
}

fn buildAdaptiveIntegrationKernelFromCache(
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    cache: *const AdaptiveKernelCache,
    apply_disamar_midpoint_bias: bool,
    kernel: *types.IntegrationKernel,
) bool {
    if (!cache.ready) return false;

    var sample_count: usize = 0;
    // math: cached plan reuses interval boundaries; nominal lambda only shifts response weights and final offsets.
    if (!adaptive_plan.appendAdaptiveSamplesFromPlan(
        &cache.plan,
        response,
        nominal_wavelength_nm,
        cache.plan.global_start_nm,
        cache.plan.global_end_nm,
        apply_disamar_midpoint_bias,
        &kernel.offsets_nm,
        &kernel.weights,
        &sample_count,
    )) return false;

    return adaptive_plan.finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        kernel.offsets_nm[0..sample_count],
        kernel.weights[0..sample_count],
    );
}

pub fn slitKernelForScene(scene: *const Scene, channel: SpectralChannel) [5]f64 {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    // PARITY:
    //   The default slit routine remains a five-point symmetric routine so the
    //   legacy convolution shape stays recognizable when explicit line-shape
    //   metadata is absent.
    if (response.fwhm_nm <= 0.0) {
        // math: default convolution kernel is [1,4,6,4,1] before convolution.apply normalizes by its sum.
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
        // math: raw slit weight k_j = response((j - 2) * sample_spacing_nm), then k_j /= sum(k).
        const value = response_support.spectralResponseWeight(response, offset_nm);
        kernel[index] = value;
        sum += value;
    }
    for (&kernel) |*value| value.* /= sum;
    return kernel;
}
