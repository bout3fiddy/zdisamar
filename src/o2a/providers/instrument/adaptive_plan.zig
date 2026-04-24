const std = @import("std");
const response_support = @import("response.zig");
const types = @import("types.zig");
const gauss_legendre = @import("../../../kernels/quadrature/gauss_legendre.zig");
const PreparedOpticalState = @import("../../../kernels/optics/preparation.zig").PreparedOpticalState;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const AdaptiveReferenceGrid = @import("../../../model/Instrument.zig").AdaptiveReferenceGrid;
const InstrumentModel = @import("../../../model/Instrument.zig").Instrument;
const Scene = @import("../../../model/Scene.zig").Scene;
const Allocator = std.mem.Allocator;

pub const AdaptiveKernelSupportWindow = struct {
    global_start_nm: f64,
    global_end_nm: f64,
    window_start_nm: f64,
    window_end_nm: f64,
};

pub const AdaptiveTraceIntervalKind = enum {
    uniform,
    strong_refinement,
};

pub const AdaptiveIntervalDescriptor = struct {
    kind: AdaptiveTraceIntervalKind,
    source_center_wavelength_nm: ?f64 = null,
    interval_start_nm: f64,
    interval_end_nm: f64,
    division_count: usize,
};

pub const AdaptiveIntervalPlan = struct {
    count: usize = 0,
    intervals: [types.max_integration_sample_count]AdaptiveIntervalDescriptor = undefined,
};

const AdaptiveSupportRange = struct {
    start_index: usize,
    end_index: usize,
};

pub fn buildAdaptiveIntegrationKernel(
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    kernel: *types.IntegrationKernel,
) bool {
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

    var sample_wavelengths_nm: [types.max_integration_sample_count]f64 = undefined;
    var sample_raw_weights: [types.max_integration_sample_count]f64 = undefined;
    var sample_count: usize = 0;
    if (!appendAdaptiveSamplesFromPlan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
        null,
    )) return false;

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    );
}

/// Purpose:
///   Materialize the full DISAMAR-style adaptive HR wavelength support without
///   narrowing it to one measured-channel slit window.
///
/// Vendor:
///   `DISAMARModule::setupHRWavelengthGrid`
///
/// Decisions:
///   Integration kernels select a per-nominal support subset from this same
///   interval plan. Weak-line cutoff parity needs the global index space,
///   because `HITRANModule::CalculatAbsXsec` compares cutoff endpoints against
///   indices on the complete high-resolution grid.
pub fn buildAdaptiveSupportWavelengths(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    response: InstrumentModel.SpectralResponse,
) !?[]f64 {
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

    for (plan.intervals[0..plan.count]) |interval| {
        const order = interval.division_count;
        if (order == 0) continue;
        fillAdaptiveUnitGauss(response, order, gauss_nodes_01[0..order], gauss_weights_01[0..order]) catch return null;

        const interval_width_nm = interval.interval_end_nm - interval.interval_start_nm;
        for (0..order) |gauss_index| {
            // PARITY: `DISAMARModule::setupHRWavelengthGrid` consumes
            // Gauss division points already scaled to [0, 1], then applies
            // `sw + dw * x0`.
            const wavelength_nm = interval.interval_start_nm + interval_width_nm * gauss_nodes_01[gauss_index];
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

    var sample_wavelengths_nm: [types.max_integration_sample_count]f64 = undefined;
    var sample_raw_weights: [types.max_integration_sample_count]f64 = undefined;
    var sample_count: usize = 0;
    if (!appendAdaptiveSamplesFromPlan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
        null,
    )) return false;

    return finalizeAdaptiveKernel(
        kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    );
}

pub fn adaptiveKernelSupportWindow(
    scene: *const Scene,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
) AdaptiveKernelSupportWindow {
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

    plan.count = 0;
    var current_nm = support_window.global_start_nm;
    var strong_index: usize = 0;
    while (strong_index < strong_center_count and strong_centers_nm[strong_index] <= current_nm + 1.0e-12) : (strong_index += 1) {}

    while (plan.count < types.max_integration_sample_count) {
        var next_nm = current_nm + fwhm_nm;
        var source_center_nm: ?f64 = null;
        if (strong_index < strong_center_count and strong_centers_nm[strong_index] < next_nm - 1.0e-12) {
            next_nm = strong_centers_nm[strong_index];
            source_center_nm = strong_centers_nm[strong_index];
            strong_index += 1;
        }
        if (next_nm <= current_nm + 1.0e-12) {
            next_nm = current_nm + fwhm_nm;
        }
        plan.intervals[plan.count] = .{
            .kind = if (source_center_nm != null) .strong_refinement else .uniform,
            .source_center_wavelength_nm = source_center_nm,
            .interval_start_nm = current_nm,
            .interval_end_nm = next_nm,
            .division_count = 1,
        };
        plan.count += 1;
        current_nm = next_nm;
        while (strong_index < strong_center_count and strong_centers_nm[strong_index] <= current_nm + 1.0e-12) : (strong_index += 1) {}
        if (current_nm > support_window.global_end_nm) break;
    }

    if (plan.count == 0 or current_nm <= support_window.global_end_nm) return false;

    const max_interval_nm = maxAdaptiveIntervalWidth(plan.intervals[0..plan.count]);
    for (plan.intervals[0..plan.count]) |*interval| {
        interval.division_count = adaptiveIntervalDivisionCount(
            adaptive,
            interval.interval_end_nm - interval.interval_start_nm,
            max_interval_nm,
            strong_center_count != 0,
        );
    }
    return true;
}

pub fn appendAdaptiveSamplesFromPlan(
    plan: *const AdaptiveIntervalPlan,
    response: InstrumentModel.SpectralResponse,
    nominal_wavelength_nm: f64,
    global_start_nm: f64,
    global_end_nm: f64,
    sample_wavelengths_nm: *[types.max_integration_sample_count]f64,
    sample_raw_weights: *[types.max_integration_sample_count]f64,
    sample_count: *usize,
    selected_intervals: ?[]bool,
) bool {
    const support_half_span_nm = response_support.adaptiveKernelHalfSpanNm(response);
    const generation_start_nm = @max(global_start_nm, nominal_wavelength_nm - support_half_span_nm - @max(response.fwhm_nm, 1.0e-4));
    const generation_end_nm = @min(global_end_nm, nominal_wavelength_nm + support_half_span_nm + @max(response.fwhm_nm, 1.0e-4));

    var candidate_wavelengths_nm: [types.max_integration_sample_count]f64 = undefined;
    var candidate_raw_weights: [types.max_integration_sample_count]f64 = undefined;
    var candidate_interval_indices: [types.max_integration_sample_count]usize = undefined;
    var candidate_count: usize = 0;

    sample_count.* = 0;
    if (selected_intervals) |selected| @memset(selected, false);

    var gauss_nodes_01: [types.max_integration_sample_count]f64 = undefined;
    var gauss_weights_01: [types.max_integration_sample_count]f64 = undefined;

    for (plan.intervals[0..plan.count], 0..) |interval, interval_index| {
        if (interval.interval_end_nm < generation_start_nm - 1.0e-12) continue;
        if (interval.interval_start_nm > generation_end_nm + 1.0e-12) continue;
        const order = interval.division_count;
        if (order == 0) continue;
        fillAdaptiveUnitGauss(response, order, gauss_nodes_01[0..order], gauss_weights_01[0..order]) catch return false;

        const interval_width_nm = interval.interval_end_nm - interval.interval_start_nm;
        for (0..order) |gauss_index| {
            // PARITY: preserve DISAMAR's Gauss division-point contract:
            // nodes and weights are first scaled to [0, 1], then interval
            // width is applied.
            const wavelength_nm = interval.interval_start_nm + interval_width_nm * gauss_nodes_01[gauss_index];
            if (!appendAdaptiveCandidateSample(
                &candidate_wavelengths_nm,
                &candidate_raw_weights,
                &candidate_interval_indices,
                &candidate_count,
                wavelength_nm,
                response_support.spectralResponseWeight(response, wavelength_nm - nominal_wavelength_nm) *
                    (interval_width_nm * gauss_weights_01[gauss_index]),
                interval_index,
            )) return false;
        }
    }
    if (candidate_count == 0) return false;

    insertionSortSamplesWithIntervalIndices(
        candidate_wavelengths_nm[0..candidate_count],
        candidate_raw_weights[0..candidate_count],
        candidate_interval_indices[0..candidate_count],
    );

    const support_range = selectVendorSupportRange(
        candidate_wavelengths_nm[0..candidate_count],
        nominal_wavelength_nm,
        support_half_span_nm,
    );
    var selected_count: usize = 0;
    for (support_range.start_index..support_range.end_index + 1) |candidate_index| {
        if (!appendAdaptiveSample(
            sample_wavelengths_nm,
            sample_raw_weights,
            &selected_count,
            candidate_wavelengths_nm[candidate_index],
            candidate_raw_weights[candidate_index],
        )) return false;
        if (selected_intervals) |selected| selected[candidate_interval_indices[candidate_index]] = true;
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
    const threshold_strength = line_list.runtime_controls.thresholdStrength(line_list.lines) orelse return true;
    for (line_list.lines) |line| {
        if (line.line_strength_cm2_per_molecule < threshold_strength) continue;
        if (line.center_wavelength_nm < global_start_nm or line.center_wavelength_nm > global_end_nm) continue;
        if (center_count.* >= types.max_integration_sample_count) return false;
        centers_nm[center_count.*] = line.center_wavelength_nm;
        center_count.* += 1;
    }
    return true;
}

fn maxAdaptiveIntervalWidth(intervals: []const AdaptiveIntervalDescriptor) f64 {
    if (intervals.len == 0) return 1.0;
    var max_width_nm: f64 = 0.0;
    if (intervals.len > 2) {
        for (intervals[1 .. intervals.len - 1]) |interval| {
            max_width_nm = @max(max_width_nm, interval.interval_end_nm - interval.interval_start_nm);
        }
    }
    if (max_width_nm <= 0.0) {
        for (intervals) |interval| {
            max_width_nm = @max(max_width_nm, interval.interval_end_nm - interval.interval_start_nm);
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
    if (order == 0 or nodes_01.len < order or weights_01.len < order) return error.InvalidOrder;
    if (response.integration_mode == .disamar_hr_grid) {
        // PARITY:
        //   DISAMAR `mathTools::GaussDivPoints` uses a QL eigensolve and
        //   returns nodes/weights already scaled to [0, 1]. The tiny
        //   last-bit differences from the generic Newton rule are visible in
        //   steep O2A solar support samples.
        return gauss_legendre.fillDisamarDivPoints01(@intCast(order), nodes_01[0..order], weights_01[0..order]);
    }

    try gauss_legendre.fillNodesAndWeights(@intCast(order), nodes_01[0..order], weights_01[0..order]);
    for (0..order) |index| {
        nodes_01[index] = (nodes_01[index] + 1.0) * 0.5;
        weights_01[index] *= 0.5;
    }
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

    plan.count = 0;
    var current_nm = global_start_nm;
    while (current_nm < global_end_nm - 1.0e-12 and plan.count < types.max_integration_sample_count) {
        const next_nm = @min(current_nm + interval_width_nm, global_end_nm);
        plan.intervals[plan.count] = .{
            .kind = .uniform,
            .interval_start_nm = current_nm,
            .interval_end_nm = next_nm,
            .division_count = division_count,
        };
        plan.count += 1;
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

fn appendAdaptiveCandidateSample(
    candidate_wavelengths_nm: *[types.max_integration_sample_count]f64,
    candidate_raw_weights: *[types.max_integration_sample_count]f64,
    candidate_interval_indices: *[types.max_integration_sample_count]usize,
    candidate_count: *usize,
    wavelength_nm: f64,
    raw_weight: f64,
    interval_index: usize,
) bool {
    if (!std.math.isFinite(wavelength_nm) or !std.math.isFinite(raw_weight) or raw_weight < 0.0) return true;
    if (candidate_count.* >= types.max_integration_sample_count) return false;
    candidate_wavelengths_nm[candidate_count.*] = wavelength_nm;
    candidate_raw_weights[candidate_count.*] = raw_weight;
    candidate_interval_indices[candidate_count.*] = interval_index;
    candidate_count.* += 1;
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

fn insertionSortSamplesWithIntervalIndices(
    sample_wavelengths_nm: []f64,
    sample_raw_weights: []f64,
    sample_interval_indices: []usize,
) void {
    if (sample_wavelengths_nm.len != sample_raw_weights.len or
        sample_wavelengths_nm.len != sample_interval_indices.len) return;
    for (1..sample_wavelengths_nm.len) |index| {
        var cursor = index;
        while (cursor > 0 and sample_wavelengths_nm[cursor] < sample_wavelengths_nm[cursor - 1]) : (cursor -= 1) {
            std.mem.swap(f64, &sample_wavelengths_nm[cursor], &sample_wavelengths_nm[cursor - 1]);
            std.mem.swap(f64, &sample_raw_weights[cursor], &sample_raw_weights[cursor - 1]);
            std.mem.swap(usize, &sample_interval_indices[cursor], &sample_interval_indices[cursor - 1]);
        }
    }
}
