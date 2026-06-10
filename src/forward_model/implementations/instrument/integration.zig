const std = @import("std");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// integration.zig ------------------------------------------------------------------------------------------- |
// Builds instrument-response integration kernels for one Scene channel at one nominal wavelength. This is the |
// route boundary between observation-model controls and product wavelength sampling: it chooses the response  |
// model, writes relative wavelength offsets, normalizes weights, and marks whether later slit convolution is  |
// allowed to run.                                                                                             |
//                                                                                                             |
// called by                                                                                                   |
//   wavelength_sampling.zig calls this twice per output wavelength: radiance then irradiance. It compacts the |
//   active kernel prefix into retained plan rows or side arrays.                                              |
//   simulate.zig asks usesIntegratedInstrumentSampling before applying legacy five-tap slit convolution, so   |
//   measured/operational channels do not integrate the same line shape twice.                                 |
//   output/instrument_response.zig expands the same kernels into diagnostic rows exposed through the API.     |
//   input/o2a_reference/run.zig samples start/end kernels to compute DISAMAR parity support bounds.           |
//                                                                                                             |
// inputs                                                                                                      |
//   Scene supplies sampling mode, per-channel response controls, line-shape tables, high-resolution grid      |
//   controls, adaptive controls, and fallback FWHM metadata. PreparedOpticalState is optional because DISAMAR |
//   high-resolution grids can be realized from prepared strong-line intervals when available, or from         |
//   scene-only operational controls when only reference support is being built.                               |
//                                                                                                             |
// kernel shape                                                                                                |
//   IntegrationKernel is a caller-owned 32 KiB builder row from types.zig. offsets_nm and weights are         |
//   parallel [2048]f64 arrays; only [0..sample_count] is meaningful after this file returns. enabled=false    |
//   means direct sampling at the nominal wavelength; enabled=true means the product row is already integrated |
//   over response weights and later slit convolution must not repeat that work.                               |
//   wavelength_sampling.zig compacts this temporary row into disabled, inline-five-sample, or side-array      |
//   storage. spectral_eval.zig then reads only the compact WavelengthSampling view during radiance and        |
//   irradiance gather; it does not call back into this file from the per-forward-sample RTM path.             |
//                                                                                                             |
// route order                                                                                                 |
//   integrationForWavelengthWithAdaptiveCacheChecked chooses one route and stops:                             |
//     1. identity direct sample when no integrated response is configured                                     |
//     2. measured line-shape table keyed by nominal wavelength                                                |
//     3. explicit caller-provided line-shape kernel                                                           |
//     4. DISAMAR high-resolution grid, using prepared strong-line intervals when available                    |
//     5. explicit high-resolution lattice from operational-band controls                                      |
//     6. adaptive strong-line-aware Gauss integration                                                         |
//     7. legacy five-point response-weighted fallback for native/synthetic channels with FWHM only            |
//                                                                                                             |
// module split                                                                                                |
//   response.zig owns scalar response weights and identity/reset helpers. adaptive_plan.zig owns interval     |
//   construction, Gauss sample emission, strong-line splitting, and validation support grids. This file keeps |
//   the public route order, normalization boundary, and double-convolution guard in one place.                |
//                                                                                                             |
// weight contract                                                                                             |
//   IntegrationKernel offsets are relative to nominal_wavelength_nm and weights are normalized before return. |
//   Table, explicit, DISAMAR, adaptive, and fallback kernels all use the same compact row contract, so later  |
//   code never needs to know which route produced the samples.                                                |
//   Checked entry points return InstrumentKernelRealizationFailed when an explicitly requested route cannot   |
//   produce a finite non-empty kernel. High-resolution and adaptive controls fail here instead of silently    |
//   falling through to the legacy five-tap fallback.                                                          |
//                                                                                                             |
// hot path                                                                                                    |
//   Wavelength-plan workers call this inside the output-sample loop. The 32 KiB IntegrationKernel is reused   |
//   by pointer so workers only rewrite the active prefix. AdaptiveKernelCache stores one 20 KiB interval plan |
//   per channel, keeping strong-line boundary planning out of repeated per-wavelength kernel construction.    |
//                                                                                                             |
// math names                                                                                                  |
//   lambda_i : nominal output wavelength                                                                      |
//   delta_j  : kernel.offsets_nm[j]                                                                           |
//   weight_j : kernel.weights[j]                                                                              |
//   y_i      = sum_j weight_j * y(lambda_i + delta_j)                                                         |
// ----------------------------------------------------------------------------------------------------------- |

pub const IntegrationKernel = types.IntegrationKernel;
pub const default_integration_sample_count = types.default_integration_sample_count;
pub const max_integration_sample_count = types.max_integration_sample_count;
pub const Error = error{
    InstrumentKernelRealizationFailed,
};

// AdaptiveKernelCache --------------------------------------------------------------------------------------- |
// Cached adaptive interval plan for one nominal wavelength route.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 20512 B (20.031 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..20503] plan    : AdaptiveIntervalPlan                                                               |
// [20504..20504] ready   : bool                                                                               |
// [20505..20511] padding : 7 B                                                                                |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 321 cache lines at 64 B per line                                                                |
// footprint: per instance = 20512 B; caller-owned cache row                                                   |
pub const AdaptiveKernelCache = struct {
    ready: bool = false,
    plan: adaptive_plan.AdaptiveIntervalPlan = .{},
};
// ------------------------------------------------------------------------------------------------------------|

pub fn usesIntegratedInstrumentSampling(scene: *const Scene, channel: SpectralChannel) bool {
    // usesIntegratedInstrumentSampling -----------------------------------------------------------------------|
    // Return whether this channel's product samples already include instrument-response integration.          |
    //                                                                                                         |
    // call sites                                                                                              |
    //   simulate.zig uses this as the double-convolution guard before applying legacy slit convolution.       |
    //   The answer is channel-specific because radiance and irradiance can carry different response controls. |
    // --------------------------------------------------------------------------------------------------------|

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
    // integrationForWavelengthChecked ------------------------------------------------------------------------|
    // Public no-cache entry point for callers that need one realized kernel and cannot retain adaptive state. |
    // It delegates to the cached route with null cache so all response modes use the same route order.        |
    // --------------------------------------------------------------------------------------------------------|

    try integrationForWavelengthWithAdaptiveCacheChecked(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        null,
        kernel,
    );
}

pub fn integrationForWavelengthWithAdaptiveCacheChecked(
    scene: *const Scene,
    prepared: ?*const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
    cached_adaptive_kernel: ?*const AdaptiveKernelCache,
    kernel: *IntegrationKernel,
) Error!void {
    // integrationForWavelengthWithAdaptiveCacheChecked ------------------------------------------------------ |
    // Builds radiance/irradiance integration offsets and weights for one nominal wavelength.                  |
    //                                                                                                         |
    // route order                                                                                             |
    //   1. identity direct sample when no integrated response is configured                                   |
    //   2. measured line-shape table keyed by nominal wavelength                                              |
    //   3. explicit fixed line-shape kernel                                                                   |
    //   4. DISAMAR high-resolution grid from prepared state or scene-only controls                            |
    //   5. explicit high-resolution lattice                                                                   |
    //   6. adaptive strong-line-aware Gauss integration                                                       |
    //   7. five-tap fallback for native/synthetic channels with only FWHM metadata                            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Wavelength-plan workers call this once for radiance and once for irradiance per nominal sample. The   |
    //   caller reuses the large IntegrationKernel scratch; this function only writes the active prefix and    |
    //   never allocates. Adaptive caches, when provided, move interval planning out of this repeated route.   |
    //                                                                                                         |
    // math                                                                                                    |
    //   lambda_i : nominal output wavelength                                                                  |
    //   delta_j  : kernel.offsets_nm[j]                                                                       |
    //   weight_j : kernel.weights[j]                                                                          |
    //   y_i      = sum_j weight_j * y(lambda_i + delta_j), with sum_j weight_j = 1                            |
    // ------------------------------------------------------------------------------------------------------- |

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
    // writeDisamarHighResolutionKernel -----------------------------------------------------------------------|
    // Realize the DISAMAR-style high-resolution response route. Prepared state wins because it can split      |
    // around strong-line intervals; scene-only operational controls are the fallback used while building      |
    // reference support before a full PreparedOpticalState exists.                                            |
    // --------------------------------------------------------------------------------------------------------|

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
    // writeExplicitGridKernel --------------------------------------------------------------------------------|
    // Emit a uniform high-resolution lattice from response controls and normalize response weights in place.  |
    // Returns false when the requested step/span cannot produce a finite non-empty kernel.                    |
    // --------------------------------------------------------------------------------------------------------|

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
    // adaptiveIntegrationFromPrepared ------------------------------------------------------------------------|
    // Build a strong-line-aware adaptive kernel from PreparedOpticalState, using a retained interval plan     |
    // when wavelength_sampling.zig prepared one for this channel. The fallback computes the plan and samples  |
    // in one call for callers that do not carry AdaptiveKernelCache.                                          |
    // --------------------------------------------------------------------------------------------------------|

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

pub fn prepareAdaptiveKernelCache(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    cache: *AdaptiveKernelCache,
) bool {
    // prepareAdaptiveKernelCache ---------------------------------------------------------------------------- |
    // Prepares the strong-line-aware interval plan shared by all nominal wavelengths in one product run.      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Wavelength sampling calls this when adaptive instrument grids can reuse an interval plan. The cache   |
    //   stores the 20 KiB plan so per-wavelength kernel construction only emits samples and weights.          |
    //                                                                                                         |
    // boundary                                                                                                |
    //   The cache is valid only for the same Scene, PreparedOpticalState, channel, and response controls used |
    //   to build the wavelength plan. Product storage keys enforce that boundary before this cache is reused. |
    // ------------------------------------------------------------------------------------------------------- |

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
    // buildAdaptiveIntegrationKernelFromCache ----------------------------------------------------------------|
    // Reuse cached interval boundaries and emit the nominal-wavelength-specific offsets/weights. The cache    |
    // stores geometry; this function still applies the current response weights and final normalization.      |
    // --------------------------------------------------------------------------------------------------------|

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
    // slitKernelForScene -------------------------------------------------------------------------------------|
    // Build the legacy five-tap convolution kernel used only when integrated sampling did not already realize |
    // the instrument response. This keeps native/synthetic FWHM-only scenes compatible with the older         |
    // convolution path while measured/operational routes use IntegrationKernel rows instead.                  |
    // --------------------------------------------------------------------------------------------------------|

    const response = scene.observation_model.resolvedChannelControls(channel).response;

    // PARITY:
    //   The default slit routine remains a five-point symmetric routine so the
    //   legacy convolution shape stays recognizable when explicit line-shape
    //   metadata is absent.
    if (response.fwhm_nm <= 0.0) {

        // math: default convolution kernel is [1,4,6,4,1] before convolution.apply normalizes by its sum.
        return .{ 1.0, 4.0, 6.0, 4.0, 1.0 };
    }

    const sample_span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const sample_spacing_nm = if (scene.spectral_grid.sample_count <= 1)
        1.0
    else
        sample_span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
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
