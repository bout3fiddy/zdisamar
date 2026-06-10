const std = @import("std");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// integration.zig ------------------------------------------------------------------------------------------- |
// Converts one scene/channel/nominal wavelength into the instrument-response samples used by product          |
// wavelength planning. This is the router between observation-model controls and the fixed IntegrationKernel  |
// row: it decides which response model is active, writes offsets relative to the nominal wavelength,          |
// normalizes weights, and tells later code whether legacy slit convolution must be skipped.                   |
//                                                                                                             |
// called by                                                                                                   |
//   wavelength_sampling.zig builds retained radiance and irradiance integration rows for every output sample  |
//   simulate.zig asks usesIntegratedInstrumentSampling before deciding whether to run five-tap convolution    |
//   output/instrument_response.zig expands the same kernels into diagnostic support rows                      |
//   input/o2a_reference/run.zig samples endpoint kernels for DISAMAR parity support bounds                    |
//                                                                                                             |
// inputs                                                                                                      |
//   Scene supplies observation-model sampling mode, channel response controls, line-shape tables, and         |
//   fallback FWHM metadata. PreparedOpticalState is optional because DISAMAR high-resolution grids can be     |
//   realized either from prepared strong-line intervals or from scene-only operational controls.              |
//                                                                                                             |
// output row                                                                                                  |
//   IntegrationKernel is caller-owned 32 KiB scratch from types.zig. Only the active prefix                   |
//   offsets_nm[0..sample_count] and weights[0..sample_count] is meaningful after this file returns.           |
//   Disabled kernels are still a valid direct-sample contract: offset 0, weight 1, enabled=false.             |
//                                                                                                             |
// main path                                                                                                   |
//   integrationForWavelengthWithAdaptiveCacheChecked chooses exactly one route, in this order:                |
//     direct sample when the channel is native/synthetic and has no broadening metadata                       |
//     measured line-shape table keyed by nominal wavelength                                                   |
//     explicit caller-provided line-shape kernel                                                              |
//     DISAMAR-style high-resolution grid with strong-line intervals when prepared data exists                 |
//     explicit high-resolution lattice from operational-band controls                                         |
//     adaptive strong-line-aware Gauss integration                                                            |
//     legacy five-point response-weighted fallback                                                            |
//                                                                                                             |
// module split                                                                                                |
//   response.zig owns scalar response weights and identity/reset helpers. adaptive_plan.zig owns interval     |
//   construction, Gauss sample emission, strong-line splitting, and validation support grids. This file keeps |
//   the public route order, normalization boundary, and double-convolution guard in one place.                |
//                                                                                                             |
// contract                                                                                                    |
//   IntegrationKernel offsets are relative to nominal_wavelength_nm and weights are normalized before return. |
//   kernel.enabled means wavelength sampling already integrated the response. Disabled kernels still mean one |
//   direct sample at offset 0 with weight 1. usesIntegratedInstrumentSampling keeps measured/operational      |
//   channels from applying the line shape twice in the later slit-convolution stage.                          |
//                                                                                                             |
// hot path                                                                                                    |
//   Wavelength-plan workers call this twice per nominal row, once for radiance and once for irradiance. The   |
//   caller supplies the 32 KiB IntegrationKernel scratch. Adaptive caches keep the 20 KiB interval plan out   |
//   of repeated per-wavelength planning when the response can share strong-line boundaries.                   |
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
