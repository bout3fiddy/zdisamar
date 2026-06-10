const std = @import("std");
const response_support = @import("response.zig");
const types = @import("types.zig");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const AdaptiveReferenceGrid = @import("../../../input/Instrument.zig").AdaptiveReferenceGrid;
const InstrumentModel = @import("../../../input/Instrument.zig").Instrument;
const Scene = @import("../../../input/Scene.zig").Scene;
const Allocator = std.mem.Allocator;

// adaptive_plan.zig ------------------------------------------------------------------------------------------- |
// Builds adaptive high-resolution instrument kernels by turning support windows into weighted Gauss samples.    |
//                                                                                                               |
// called by                                                                                                     |
//   integration.zig calls the public builders for adaptive kernels, DISAMAR-style realized kernels, and         |
//   reusable interval caches. wavelength_sampling.zig reaches this file through integration.zig when product    |
//   simulation can retain one interval plan across many nominal wavelengths. input/o2a_reference/run.zig calls  |
//   buildAdaptiveSupportWavelengths only to expose the realized support lattice for validation output.          |
//                                                                                                               |
// contains                                                                                                      |
//   AdaptiveKernelSupportWindow is the global/local support bounds. AdaptiveIntervalPlan is the fixed-capacity  |
//   interval-end table plus per-interval Gauss division count. The public builders share the same internal      |
//   path: support bounds -> interval ends -> Gauss samples -> response weights -> normalized kernel.            |
//                                                                                                               |
// main paths                                                                                                    |
//   buildAdaptiveIntegrationKernel -> support window -> interval plan -> samples -> normalized kernel           |
//   prepareAdaptiveKernelCache in integration.zig can retain that interval plan for all nominal wavelengths     |
//   buildDisamarRealizedKernel uses the same sample/finalize path but a regular DISAMAR-style interval grid     |
//   buildAdaptiveSupportWavelengths emits the realized support lattice for validation/reporting only            |
//                                                                                                               |
// interval model                                                                                                |
//   global_start_nm/global_end_nm is the scene grid expanded by response support. interval_end_nm stores only   |
//   each end boundary; the start is global_start_nm or the previous end. Strong O2 line centers can split the   |
//   FWHM-sized intervals, and narrow intervals receive more Gauss divisions.                                    |
//   Strong-line collection scans wide SpectroscopyLine rows during setup. It reads strength at [24..31] and     |
//   center at [8..15]; the result is the compact boundary list reused by cached plans and per-wavelength        |
//   sample emission.                                                                                            |
//                                                                                                               |
// hot path                                                                                                      |
//   Wavelength sampling reuses a caller-owned IntegrationKernel and, when possible, a cached 20 KiB             |
//   AdaptiveIntervalPlan. Per nominal wavelength this file only emits candidate wavelengths, evaluates scalar   |
//   response weights, sorts/merges nearby samples, and normalizes the active prefix.                            |
//                                                                                                               |
// math                                                                                                          |
//   lambda_j = interval_start + interval_width * Gauss node                                                     |
//   raw_w_j  = response(lambda_j - lambda_i) * interval_width * Gauss weight                                    |
//   delta_j  = lambda_j - lambda_i                                                                              |
//                                                                                                               |
// memory                                                                                                        |
//   AdaptiveIntervalPlan is fixed-capacity stack/caller storage sized to max_integration_sample_count. The      |
//   only owned allocation here is buildAdaptiveSupportWavelengths, which returns validation support rows.       |
// ------------------------------------------------------------------------------------------------------------- |

// AdaptiveKernelSupportWindow -------------------------------------------------------------------------------   |
// Global and local wavelength support bounds for adaptive integration.                                          |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 32 B (0.031 KiB), align: 8 B                                                                            |
//                                                                                                               |
// memory                                                                                                        |
// [ 0.. 7] global_start_nm : f64                                                                                |
// [ 8..15] global_end_nm   : f64                                                                                |
// [16..23] window_start_nm : f64                                                                                |
// [24..31] window_end_nm   : f64                                                                                |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// footprint: per instance = 32 B; stack value during adaptive support selection                                 |
pub const AdaptiveKernelSupportWindow = struct {
    global_start_nm: f64,
    global_end_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
};
// ------------------------------------------------------------------------------------------------------------  |

// AdaptiveIntervalPlan --------------------------------------------------------------------------------------   |
// Fixed-capacity interval ends and division counts for adaptive instrument sampling.                            |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 20504 B (20.023 KiB), align: 8 B                                                                        |
//                                                                                                               |
// memory                                                                                                        |
// [    0..    7] count           : usize                                                                        |
// [    8..   15] global_start_nm : f64                                                                          |
// [   16..   23] global_end_nm   : f64                                                                          |
// [   24..16407] interval_end_nm : [2048]f64                                                                    |
// [16408..20503] division_counts : [2048]u16                                                                    |
//                                                                                                               |
// encoded fields                                                                                                |
//   interval starts derive from global_start_nm and the previous interval_end_nm entry.                         |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// cache span: 321 cache lines at 64 B per line                                                                  |
// footprint: per instance = 20504 B; caller-owned plan or adaptive cache field                                  |
pub const AdaptiveIntervalPlan = struct {
    count: usize = 0,
    global_start_nm: f64 = 0.0,
    global_end_nm: f64 = 0.0,
    interval_end_nm: [types.max_integration_sample_count]f64 = undefined,
    division_counts: [types.max_integration_sample_count]u16 = undefined,

    pub inline fn reset(self: *AdaptiveIntervalPlan, global_start_nm: f64, global_end_nm: f64) void {
        self.count = 0;
        self.global_start_nm = global_start_nm;
        self.global_end_nm = global_end_nm;
    }

    pub inline fn append(self: *AdaptiveIntervalPlan, interval_end_nm: f64, division_count: usize) bool {
        if (self.count >= types.max_integration_sample_count) return false;
        if (division_count > std.math.maxInt(u16)) return false;
        self.interval_end_nm[self.count] = interval_end_nm;
        self.division_counts[self.count] = @intCast(division_count);
        self.count += 1;
        return true;
    }

    pub inline fn setDivisionCount(self: *AdaptiveIntervalPlan, index: usize, division_count: usize) bool {
        if (index >= self.count) return false;
        if (division_count > std.math.maxInt(u16)) return false;
        self.division_counts[index] = @intCast(division_count);
        return true;
    }

    pub inline fn intervalStartNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        return if (index == 0) self.global_start_nm else self.interval_end_nm[index - 1];
    }

    pub inline fn intervalEndNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        return self.interval_end_nm[index];
    }

    pub inline fn intervalWidthNm(self: *const AdaptiveIntervalPlan, index: usize) f64 {
        return self.intervalEndNm(index) - self.intervalStartNm(index);
    }

    pub inline fn divisionCount(self: *const AdaptiveIntervalPlan, index: usize) usize {
        return @intCast(self.division_counts[index]);
    }
};
// ------------------------------------------------------------------------------------------------------------  |

// AdaptiveSupportRange --------------------------------------------------------------------------------------   |
// Half-open strong-line support index range inside a line-list center array.                                    |
//                                                                                                               |
// layout(64-bit)                                                                                                |
// size: 16 B (0.016 KiB), align: 8 B                                                                            |
//                                                                                                               |
// memory                                                                                                        |
// [ 0.. 7] start_index : usize                                                                                  |
// [ 8..15] end_index   : usize                                                                                  |
//                                                                                                               |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                        |
// footprint: per instance = 16 B; stack value during adaptive interval selection                                |
const AdaptiveSupportRange = struct {
    start_index: usize,
    end_index: usize,
};
// ------------------------------------------------------------------------------------------------------------  |

pub fn buildAdaptiveIntegrationKernel(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
    kernel: *types.IntegrationKernel,
) bool {
    // buildAdaptiveIntegrationKernel ------------------------------------------------------------------------   |
    // Builds one adaptive instrument kernel from support intervals and Gauss samples.                           |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Integrated instrument sampling calls this for one nominal wavelength. It constructs the interval        |
    //   plan, emits candidate samples, and finalizes normalized weights.                                        |
    //                                                                                                           |
    // math                                                                                                      |
    //   integral response(lambda - lambda_i) * y(lambda) dlambda by Gauss samples                               |
    // -------------------------------------------------------------------------------------------------------   |

    const adaptive = scene.observation_model.adaptive_reference_grid;
    if (!adaptive.enabled()) return false;
    if (response.fwhm_nm <= 0.0) return false;

    const has_single_line_list = if (prepared.spectroscopy_lines) |line_list|
        line_list.lines.len != 0
    else
        false;
    if (!has_single_line_list and prepared.line_absorbers.len == 0) return false;

    const support_window = adaptiveKernelSupportWindow(scene, response, nominal_wavelength_nm);
    if (support_window.window_end_nm <= support_window.window_start_nm) return false;

    var plan: AdaptiveIntervalPlan = .{};
    if (!buildAdaptiveIntervalPlan(scene, prepared, response, &plan)) return false;

    var sample_count: usize = 0;
    if (!appendAdaptiveSamplesFromPlan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        apply_disamar_midpoint_bias,
        &kernel.offsets_nm,
        &kernel.weights,
        &sample_count,
    )) return false;

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        kernel.offsets_nm[0..sample_count],
        kernel.weights[0..sample_count],
    );
}

pub fn buildAdaptiveSupportWavelengths(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
) !?[]f64 {
    // buildAdaptiveSupportWavelengths ------------------------------------------------------------------------- |
    // Builds the sorted adaptive support grid used by DISAMAR-style high-resolution instrument integration.     |
    //                                                                                                           |
    // math                                                                                                      |
    //   wavelength = interval_start + interval_width * Gauss node on [0, 1]                                     |
    //                                                                                                           |
    //   support wavelengths closer than 1e-9 nm are merged because they describe the same realized node.        |
    // --------------------------------------------------------------------------------------------------------  |

    const adaptive = scene.observation_model.adaptive_reference_grid;
    if (!adaptive.enabled()) return null;
    if (response.fwhm_nm <= 0.0) return null;

    const has_single_line_list = if (prepared.spectroscopy_lines) |line_list|
        line_list.lines.len != 0
    else
        false;
    if (!has_single_line_list and prepared.line_absorbers.len == 0) return null;

    var plan: AdaptiveIntervalPlan = .{};
    if (!buildAdaptiveIntervalPlan(scene, prepared, response, &plan)) return null;

    var support = std.ArrayList(f64).empty;
    errdefer support.deinit(allocator);
    var gauss_nodes_01: [types.max_integration_sample_count]f64 = undefined;
    var gauss_weights_01: [types.max_integration_sample_count]f64 = undefined;

    for (0..plan.count) |interval_index| {
        const order = plan.divisionCount(interval_index);
        if (order == 0) continue;
        fillAdaptiveUnitGauss(response, order, gauss_nodes_01[0..order], gauss_weights_01[0..order]) catch return null;

        const interval_start_nm = plan.intervalStartNm(interval_index);
        const interval_width_nm = plan.intervalWidthNm(interval_index);
        for (0..order) |gauss_index| {
            const wavelength_nm = interval_start_nm + interval_width_nm * gauss_nodes_01[gauss_index];
            if (!std.math.isFinite(wavelength_nm)) continue;
            try support.append(allocator, wavelength_nm);
        }
    }
    if (support.items.len == 0) return null;

    std.sort.block(f64, support.items, {}, lessThanF64);

    var merged_count: usize = 0;
    for (support.items) |wavelength_nm| {
        if (merged_count != 0 and @abs(support.items[merged_count - 1] - wavelength_nm) <= 1.0e-9) continue;
        support.items[merged_count] = wavelength_nm;
        merged_count += 1;
    }
    support.shrinkRetainingCapacity(merged_count);
    return try support.toOwnedSlice(allocator);
}

pub fn buildDisamarRealizedKernel(
    scene: *const Scene,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    apply_disamar_midpoint_bias: bool,
    kernel: *types.IntegrationKernel,
) bool {
    if (response.fwhm_nm <= 0.0) return false;

    const support_window = adaptiveKernelSupportWindow(scene, response, nominal_wavelength_nm);
    if (support_window.window_end_nm <= support_window.window_start_nm) return false;

    const division_count = disamarIntervalDivisionCount(scene.observation_model.adaptive_reference_grid, response);
    if (division_count == 0) return false;

    var plan: AdaptiveIntervalPlan = .{};
    if (!buildDisamarIntervalPlan(
        support_window.global_start_nm,
        support_window.global_end_nm,
        @max(response.fwhm_nm, 1.0e-4),
        division_count,
        &plan,
    )) return false;

    var sample_count: usize = 0;
    if (!appendAdaptiveSamplesFromPlan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        apply_disamar_midpoint_bias,
        &kernel.offsets_nm,
        &kernel.weights,
        &sample_count,
    )) return false;

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        kernel.offsets_nm[0..sample_count],
        kernel.weights[0..sample_count],
    );
}

pub fn adaptiveKernelSupportWindow(
    scene: *const Scene,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
) AdaptiveKernelSupportWindow {
    // adaptiveKernelSupportWindow ----------------------------------------------------------------------------- |
    // Computes the global adaptive support span and the per-nominal wavelength window.                          |
    //                                                                                                           |
    // math                                                                                                      |
    //   global span = spectral grid expanded by 2 * FWHM on each side                                           |
    //   window span = nominal wavelength +/- configured half span                                               |
    // --------------------------------------------------------------------------------------------------------  |

    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    const half_span_nm = if (response.high_resolution_half_span_nm > 0.0)
        response.high_resolution_half_span_nm
    else
        response_support.defaultKernelHalfSpanNm(fwhm_nm);

    const global_start_nm = scene.spectral_grid.start_nm - (2.0 * fwhm_nm);
    const global_end_nm = scene.spectral_grid.end_nm + (2.0 * fwhm_nm);
    return .{
        .global_start_nm = global_start_nm,
        .global_end_nm = global_end_nm,
        .window_start_nm = @max(global_start_nm, nominal_wavelength_nm - half_span_nm),
        .window_end_nm = @min(global_end_nm, nominal_wavelength_nm + half_span_nm),
    };
}

pub fn buildAdaptiveIntervalPlan(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    plan: *AdaptiveIntervalPlan,
) bool {
    // buildAdaptiveIntervalPlan -----------------------------------------------------------------------------   |
    // Partitions the global support window around strong-line centers and assigns division counts.              |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Adaptive sampling prepares this plan once when a channel response can reuse support intervals.          |
    //                                                                                                           |
    // math                                                                                                      |
    //   interval boundaries advance by FWHM unless a strong-line center creates the next boundary first         |
    // -------------------------------------------------------------------------------------------------------   |

    const adaptive = scene.observation_model.adaptive_reference_grid;
    const support_window = adaptiveKernelSupportWindow(scene, response, scene.spectral_grid.start_nm);
    const fwhm_nm = @max(response.fwhm_nm, 1.0e-4);

    var strong_centers_nm: [types.max_integration_sample_count]f64 = undefined;
    var strong_center_count: usize = 0;
    if (!collectAdaptiveStrongLineCenters(
        prepared,
        support_window.global_start_nm,
        support_window.global_end_nm,
        &strong_centers_nm,
        &strong_center_count,
    )) return false;

    plan.reset(support_window.global_start_nm, support_window.global_end_nm);
    var current_nm = support_window.global_start_nm;
    var strong_index: usize = 0;
    while (strong_index < strong_center_count and
        strong_centers_nm[strong_index] <= current_nm + 1.0e-12) : (strong_index += 1)
    {}

    while (plan.count < types.max_integration_sample_count) {
        var next_nm = current_nm + fwhm_nm;

        if (strong_index < strong_center_count and strong_centers_nm[strong_index] < next_nm - 1.0e-12) {
            next_nm = strong_centers_nm[strong_index];
            strong_index += 1;
        }

        if (next_nm <= current_nm + 1.0e-12) {
            next_nm = current_nm + fwhm_nm;
        }

        if (!plan.append(next_nm, 1)) return false;
        current_nm = next_nm;

        while (strong_index < strong_center_count and
            strong_centers_nm[strong_index] <= current_nm + 1.0e-12) : (strong_index += 1)
        {}

        if (current_nm > support_window.global_end_nm) break;
    }

    if (plan.count == 0 or current_nm <= support_window.global_end_nm) return false;

    const max_interval_nm = maxAdaptiveIntervalWidth(plan);
    for (0..plan.count) |interval_index| {
        const division_count = adaptiveIntervalDivisionCount(
            adaptive,
            plan.intervalWidthNm(interval_index),
            max_interval_nm,
            strong_center_count != 0,
        );
        if (!plan.setDivisionCount(interval_index, division_count)) return false;
    }
    return true;
}

pub fn appendAdaptiveSamplesFromPlan(
    plan: *const AdaptiveIntervalPlan,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    global_start_nm: f64,
    global_end_nm: f64,
    apply_disamar_midpoint_bias: bool,
    sample_wavelengths_nm: *[types.max_integration_sample_count]f64,
    sample_raw_weights: *[types.max_integration_sample_count]f64,
    sample_count: *usize,
) bool {
    // appendAdaptiveSamplesFromPlan -------------------------------------------------------------------------   |
    // Emits candidate Gauss samples for one nominal wavelength from an adaptive interval plan.                  |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Visits interval Gauss nodes, computes response weights, sorts candidates, and selects support range     |
    //   before final kernel normalization.                                                                      |
    //                                                                                                           |
    // math                                                                                                      |
    //   raw_w = response(lambda - lambda_i) * interval_width * gauss_weight                                     |
    // -------------------------------------------------------------------------------------------------------   |

    const support_half_span_nm = response_support.adaptiveKernelHalfSpanNm(response);
    const safe_fwhm_nm = @max(response.fwhm_nm, 1.0e-4);
    const generation_start_nm = @max(
        global_start_nm,
        nominal_wavelength_nm - support_half_span_nm - safe_fwhm_nm,
    );
    const generation_end_nm = @min(
        global_end_nm,
        nominal_wavelength_nm + support_half_span_nm + safe_fwhm_nm,
    );

    var candidate_count: usize = 0;

    sample_count.* = 0;

    var gauss_nodes_01: [types.max_integration_sample_count]f64 = undefined;
    var gauss_weights_01: [types.max_integration_sample_count]f64 = undefined;

    for (0..plan.count) |interval_index| {
        const interval_start_nm = plan.intervalStartNm(interval_index);
        const interval_end_nm = plan.intervalEndNm(interval_index);
        if (interval_end_nm < generation_start_nm - 1.0e-12) continue;
        if (interval_start_nm > generation_end_nm + 1.0e-12) continue;
        const order = plan.divisionCount(interval_index);
        if (order == 0) continue;
        fillAdaptiveUnitGauss(response, order, gauss_nodes_01[0..order], gauss_weights_01[0..order]) catch return false;

        const interval_width_nm = interval_end_nm - interval_start_nm;
        for (0..order) |gauss_index| {
            const wavelength_nm = realizedIntervalWavelengthNm(
                response,
                interval_start_nm,
                interval_width_nm,
                gauss_nodes_01[gauss_index],
                order,
                gauss_index,
                apply_disamar_midpoint_bias,
            );
            if (!appendAdaptiveSample(
                sample_wavelengths_nm,
                sample_raw_weights,
                &candidate_count,
                wavelength_nm,
                response_support.spectralResponseWeight(response, wavelength_nm - nominal_wavelength_nm) *
                    (interval_width_nm * gauss_weights_01[gauss_index]),
            )) return false;
        }
    }
    if (candidate_count == 0) return false;

    insertionSortSamples(
        sample_wavelengths_nm[0..candidate_count],
        sample_raw_weights[0..candidate_count],
    );

    const support_range = selectVendorSupportRange(
        sample_wavelengths_nm[0..candidate_count],
        nominal_wavelength_nm,
        support_half_span_nm,
    );
    var selected_count: usize = 0;
    for (support_range.start_index..support_range.end_index + 1) |candidate_index| {
        sample_wavelengths_nm[selected_count] = sample_wavelengths_nm[candidate_index];
        sample_raw_weights[selected_count] = sample_raw_weights[candidate_index];
        selected_count += 1;
    }
    sample_count.* = selected_count;
    return sample_count.* != 0;
}

pub fn finalizeAdaptiveKernel(
    kernel: *types.IntegrationKernel,
    nominal_wavelength_nm: f64,
    sample_wavelengths_nm: []f64,
    sample_raw_weights: []f64,
) bool {
    // finalizeAdaptiveKernel --------------------------------------------------------------------------------   |
    // Sorts, merges duplicate wavelengths, normalizes weights, and writes kernel offsets.                       |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Adaptive and DISAMAR-realized candidate samples become the IntegrationKernel consumed by spectral       |
    //   evaluation loops.                                                                                       |
    //                                                                                                           |
    // math                                                                                                      |
    //   delta_j = lambda_j - lambda_i                                                                           |
    //   w_j = raw_w_j / sum_k raw_w_k after duplicate wavelengths are merged                                    |
    // -------------------------------------------------------------------------------------------------------   |

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

    response_support.resetKernel(kernel);
    kernel.enabled = true;
    kernel.sample_count = merged_count;
    for (0..merged_count) |index| {
        kernel.offsets_nm[index] = sample_wavelengths_nm[index] - nominal_wavelength_nm;
        kernel.weights[index] = sample_raw_weights[index] / total_weight;
    }
    return true;
}

fn collectAdaptiveStrongLineCenters(
    prepared: *const PreparedOpticalState,
    global_start_nm: f64,
    global_end_nm: f64,
    centers_nm: *[types.max_integration_sample_count]f64,
    center_count: *usize,
) bool {
    // collectAdaptiveStrongLineCenters ----------------------------------------------------------------------   |
    // Collects, sorts, and deduplicates strong-line centers from all active line lists.                         |
    //                                                                                                           |
    // hot path                                                                                                  |
    //   Adaptive interval planning uses these centers as line-aware support boundaries.                         |
    // -------------------------------------------------------------------------------------------------------   |

    center_count.* = 0;
    if (prepared.spectroscopy_lines) |line_list| {
        if (!collectAdaptiveStrongLineCentersFromList(
            line_list,
            global_start_nm,
            global_end_nm,
            centers_nm,
            center_count,
        )) return false;
    }
    for (prepared.line_absorbers) |line_absorber| {
        if (!collectAdaptiveStrongLineCentersFromList(
            line_absorber.line_list,
            global_start_nm,
            global_end_nm,
            centers_nm,
            center_count,
        )) return false;
    }

    if (center_count.* == 0) return true;

    std.sort.block(f64, centers_nm[0..center_count.*], {}, lessThanF64);

    var merged_count: usize = 1;
    for (1..center_count.*) |index| {
        if (@abs(centers_nm[index] - centers_nm[merged_count - 1]) <= 1.0e-9) continue;

        centers_nm[merged_count] = centers_nm[index];
        merged_count += 1;
    }

    center_count.* = merged_count;
    return true;
}

fn collectAdaptiveStrongLineCentersFromList(
    line_list: ReferenceData.SpectroscopyLineList,
    global_start_nm: f64,
    global_end_nm: f64,
    centers_nm: *[types.max_integration_sample_count]f64,
    center_count: *usize,
) bool {
    // collectAdaptiveStrongLineCentersFromList --------------------------------------------------------------   |
    // Append strong line centers that should split the adaptive instrument intervals.                           |
    //                                                                                                           |
    // call path                                                                                                 |
    //   collectAdaptiveStrongLineCenters calls this for the base line list and each prepared line absorber.     |
    //   buildAdaptiveIntervalPlan sorts and merges the collected centers before assigning Gauss divisions.      |
    //                                                                                                           |
    // memory                                                                                                    |
    //   SpectroscopyLine is a 104 B setup row. This scan reads line_strength_cm2_per_molecule at [24..31]       |
    //   and center_wavelength_nm at [8..15] by pointer. It writes only the compact centers_nm prefix used to    |
    //   split intervals; no line data is retained here.                                                         |
    //                                                                                                           |
    // math                                                                                                      |
    //   keep line when strength >= thresholdStrength(lines) and center is inside the global support window      |
    // --------------------------------------------------------------------------------------------------------- |

    const threshold_strength = line_list.runtime_controls.thresholdStrength(line_list.lines) orelse return true;

    for (line_list.lines) |*line| {
        if (line.line_strength_cm2_per_molecule < threshold_strength) continue;
        if (line.center_wavelength_nm < global_start_nm or line.center_wavelength_nm > global_end_nm) continue;
        if (center_count.* >= types.max_integration_sample_count) return false;
        centers_nm[center_count.*] = line.center_wavelength_nm;
        center_count.* += 1;
    }
    return true;
}

fn maxAdaptiveIntervalWidth(plan: *const AdaptiveIntervalPlan) f64 {
    if (plan.count == 0) return 1.0;

    var max_width_nm: f64 = 0.0;
    if (plan.count > 2) {
        const inner_end = plan.count - 1;
        for (1..inner_end) |interval_index| {
            max_width_nm = @max(max_width_nm, plan.intervalWidthNm(interval_index));
        }
    }

    if (max_width_nm <= 0.0) {
        for (0..plan.count) |interval_index| {
            max_width_nm = @max(max_width_nm, plan.intervalWidthNm(interval_index));
        }
    }

    return @max(max_width_nm, 1.0e-9);
}

fn adaptiveIntervalDivisionCount(
    adaptive: AdaptiveReferenceGrid,
    interval_width_nm: f64,
    max_interval_nm: f64,
    has_strong_lines: bool,
) usize {
    if (!has_strong_lines) return @max(@as(usize, adaptive.points_per_fwhm), 1);
    const min_divisions = @max(@as(usize, adaptive.strong_line_min_divisions), 1);
    const max_divisions = @max(@as(usize, adaptive.strong_line_max_divisions), min_divisions);
    const scaled = @as(usize, @intFromFloat(std.math.round(
        @as(f64, @floatFromInt(max_divisions)) * (@max(interval_width_nm, 1.0e-9) / @max(max_interval_nm, 1.0e-9)),
    )));

    return std.math.clamp(@max(scaled, min_divisions), min_divisions, max_divisions);
}

fn fillAdaptiveUnitGauss(
    response: InstrumentModel.SpectralResponse,
    order: usize,
    nodes_01: []f64,
    weights_01: []f64,
) error{InvalidOrder}!void {
    // fillAdaptiveUnitGauss ----------------------------------------------------------------------------------- |
    // Fills Gauss nodes and weights on [0, 1]. The DISAMAR mode uses its realized division-point rule because   |
    // last-bit node differences are visible in steep O2 A solar high-resolution samples.                        |
    //                                                                                                           |
    // math                                                                                                      |
    //   generic nodes: x' = (x + 1) / 2, w' = w / 2                                                             |
    // --------------------------------------------------------------------------------------------------------  |

    if (order == 0 or nodes_01.len < order or weights_01.len < order) return error.InvalidOrder;
    if (response.integration_mode == .disamar_hr_grid) {
        return gauss_legendre.fillDisamarDivPoints01(@intCast(order), nodes_01[0..order], weights_01[0..order]);
    }

    try gauss_legendre.fillNodesAndWeights(@intCast(order), nodes_01[0..order], weights_01[0..order]);
    for (0..order) |index| {
        nodes_01[index] = (nodes_01[index] + 1.0) * 0.5;
        weights_01[index] *= 0.5;
    }
}

fn realizedIntervalWavelengthNm(
    response: InstrumentModel.SpectralResponse,
    interval_start_nm: f64,
    interval_width_nm: f64,
    node_01: f64,
    order: usize,
    gauss_index: usize,
    apply_disamar_midpoint_bias: bool,
) f64 {
    // realizedIntervalWavelengthNm ---------------------------------------------------------------------------- |
    // Realizes one interval-local node as an absolute wavelength. The optional midpoint bias preserves the      |
    // DISAMAR value when an exact center sample lands on a steep O2 A solar line.                               |
    //                                                                                                           |
    // math                                                                                                      |
    //   wavelength = interval_start + interval_width * node_01                                                  |
    //   DISAMAR midpoint bias = nextAfter(wavelength, -inf)                                                     |
    // --------------------------------------------------------------------------------------------------------  |

    const wavelength_nm = interval_start_nm + interval_width_nm * node_01;
    if (!apply_disamar_midpoint_bias or response.integration_mode != .disamar_hr_grid) return wavelength_nm;
    if (order % 2 == 0 or gauss_index != order / 2 or node_01 != 0.5) return wavelength_nm;

    return std.math.nextAfter(f64, wavelength_nm, -std.math.inf(f64));
}

fn disamarIntervalDivisionCount(
    adaptive: AdaptiveReferenceGrid,
    response: InstrumentModel.SpectralResponse,
) usize {
    if (adaptive.points_per_fwhm > 0) return adaptive.points_per_fwhm;
    if (response.high_resolution_step_nm > 0.0 and response.fwhm_nm > 0.0) {
        return @max(
            @as(usize, @intFromFloat(std.math.round(response.fwhm_nm / response.high_resolution_step_nm))),
            1,
        );
    }
    return 1;
}

fn buildDisamarIntervalPlan(
    global_start_nm: f64,
    global_end_nm: f64,
    interval_width_nm: f64,
    division_count: usize,
    plan: *AdaptiveIntervalPlan,
) bool {
    if (global_end_nm <= global_start_nm or interval_width_nm <= 0.0 or division_count == 0) return false;

    plan.reset(global_start_nm, global_end_nm);
    var current_nm = global_start_nm;
    while (current_nm < global_end_nm - 1.0e-12 and plan.count < types.max_integration_sample_count) {
        const next_nm = @min(current_nm + interval_width_nm, global_end_nm);
        if (!plan.append(next_nm, division_count)) return false;
        current_nm = next_nm;
    }
    return plan.count != 0 and current_nm >= global_end_nm - 1.0e-12;
}

fn lessThanF64(_: void, lhs: f64, rhs: f64) bool {
    return lhs < rhs;
}

fn appendAdaptiveSample(
    sample_wavelengths_nm: *[types.max_integration_sample_count]f64,
    sample_raw_weights: *[types.max_integration_sample_count]f64,
    sample_count: *usize,
    wavelength_nm: f64,
    raw_weight: f64,
) bool {
    if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(raw_weight) or raw_weight < 0.0) return true;
    if (sample_count.* >= types.max_integration_sample_count) return false;

    sample_wavelengths_nm[sample_count.*] = wavelength_nm;
    sample_raw_weights[sample_count.*] = raw_weight;
    sample_count.* += 1;

    return true;
}

fn selectVendorSupportRange(
    sample_wavelengths_nm: []const f64,
    nominal_wavelength_nm: f64,
    support_half_span_nm: f64,
) AdaptiveSupportRange {
    std.debug.assert(sample_wavelengths_nm.len != 0);

    var closest_index: usize = 0;
    var closest_distance_nm = @abs(sample_wavelengths_nm[0] - nominal_wavelength_nm);
    for (sample_wavelengths_nm[1..], 1..) |wavelength_nm, index| {
        const distance_nm = @abs(wavelength_nm - nominal_wavelength_nm);
        if (distance_nm < closest_distance_nm) {
            closest_distance_nm = distance_nm;
            closest_index = index;
        }
    }

    var start_index: usize = 0;
    var left_index = closest_index;
    while (left_index > 0) {
        left_index -= 1;
        if (@abs(nominal_wavelength_nm - sample_wavelengths_nm[left_index]) > support_half_span_nm) {
            start_index = left_index;
            break;
        }
    }

    var end_index = sample_wavelengths_nm.len - 1;
    var right_index = closest_index;
    while (right_index + 1 < sample_wavelengths_nm.len) {
        right_index += 1;
        if (@abs(sample_wavelengths_nm[right_index] - nominal_wavelength_nm) > support_half_span_nm) {
            end_index = right_index;
            break;
        }
    }

    return .{
        .start_index = start_index,
        .end_index = end_index,
    };
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
