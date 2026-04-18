const std = @import("std");
const adaptive_plan = @import("adaptive_plan.zig");
const response_support = @import("response.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../../kernels/optics/preparation.zig").PreparedOpticalState;
const Scene = @import("../../../model/Scene.zig").Scene;
const SpectralChannel = @import("../../../model/Instrument.zig").SpectralChannel;
const Allocator = std.mem.Allocator;

pub const AdaptiveTraceIntervalKind = adaptive_plan.AdaptiveTraceIntervalKind;

pub const AdaptiveTraceInterval = struct {
    kind: AdaptiveTraceIntervalKind,
    nominal_wavelength_nm: f64,
    source_center_wavelength_nm: ?f64 = null,
    interval_start_nm: f64,
    interval_end_nm: f64,
    division_count: usize,
};

pub const AdaptiveKernelTrace = struct {
    kernel: types.IntegrationKernel,
    intervals: []AdaptiveTraceInterval,

    pub fn deinit(self: *AdaptiveKernelTrace, allocator: Allocator) void {
        allocator.free(self.intervals);
        self.* = undefined;
    }
};

pub fn traceAdaptiveIntegrationKernel(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
) !?AdaptiveKernelTrace {
    const response = scene.observation_model.resolvedChannelControls(channel).response;
    const adaptive = scene.observation_model.adaptive_reference_grid;
    if (!adaptive.enabled()) return null;
    if (response.fwhm_nm <= 0.0) return null;

    const has_single_line_list = if (prepared.spectroscopy_lines) |line_list|
        line_list.lines.len != 0
    else
        false;
    if (!has_single_line_list and prepared.line_absorbers.len == 0) return null;

    const support_window = adaptive_plan.adaptiveKernelSupportWindow(scene, response, nominal_wavelength_nm);
    if (support_window.window_end_nm <= support_window.window_start_nm) return null;

    var plan: adaptive_plan.AdaptiveIntervalPlan = .{};
    if (!adaptive_plan.buildAdaptiveIntervalPlan(scene, prepared, response, &plan)) return null;

    var selected_intervals = [_]bool{false} ** types.max_integration_sample_count;
    var sample_wavelengths_nm: [types.max_integration_sample_count]f64 = undefined;
    var sample_raw_weights: [types.max_integration_sample_count]f64 = undefined;
    var sample_count: usize = 0;
    if (!adaptive_plan.appendAdaptiveSamplesFromPlan(
        &plan,
        response,
        nominal_wavelength_nm,
        support_window.global_start_nm,
        support_window.global_end_nm,
        &sample_wavelengths_nm,
        &sample_raw_weights,
        &sample_count,
        selected_intervals[0..plan.count],
    )) return null;

    var intervals = std.ArrayList(AdaptiveTraceInterval).empty;
    errdefer intervals.deinit(allocator);
    for (plan.intervals[0..plan.count], 0..) |interval, interval_index| {
        if (!selected_intervals[interval_index]) continue;
        try intervals.append(allocator, .{
            .kind = interval.kind,
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .source_center_wavelength_nm = interval.source_center_wavelength_nm,
            .interval_start_nm = interval.interval_start_nm,
            .interval_end_nm = interval.interval_end_nm,
            .division_count = interval.division_count,
        });
    }

    var kernel: types.IntegrationKernel = undefined;
    response_support.resetKernel(&kernel);
    if (!adaptive_plan.finalizeAdaptiveKernel(
        &kernel,
        nominal_wavelength_nm,
        sample_wavelengths_nm[0..sample_count],
        sample_raw_weights[0..sample_count],
    )) {
        intervals.deinit(allocator);
        return null;
    }
    return .{
        .kernel = kernel,
        .intervals = try intervals.toOwnedSlice(allocator),
    };
}

test "adaptive interval construction follows vendor FWHM stepping and strong-line boundaries" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = @import("../../../model/ReferenceData.zig").SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(@import("../../../model/ReferenceData.zig").SpectroscopyLine, &.{
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 759.55, .line_strength_cm2_per_molecule = 2.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.20, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
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
            .start_nm = 760.1,
            .end_nm = 761.3,
            .sample_count = 61,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.4,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 5,
                .strong_line_min_divisions = 4,
                .strong_line_max_divisions = 8,
            },
        },
    };

    const trace = try traceAdaptiveIntegrationKernel(
        std.testing.allocator,
        &scene,
        &prepared,
        .radiance,
        760.5,
    ) orelse return error.ExpectedAdaptiveTrace;
    defer {
        var owned = trace;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expect(trace.intervals.len >= 2);
    try std.testing.expectEqual(AdaptiveTraceIntervalKind.strong_refinement, trace.intervals[0].kind);
    try std.testing.expectApproxEqAbs(@as(f64, 759.3), trace.intervals[0].interval_start_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 759.55), trace.intervals[0].interval_end_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 759.55), trace.intervals[0].source_center_wavelength_nm.?, 1.0e-12);
    try std.testing.expectEqual(@as(usize, 5), trace.intervals[0].division_count);
    try std.testing.expectApproxEqAbs(@as(f64, 759.55), trace.intervals[1].interval_start_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 759.95), trace.intervals[1].interval_end_nm, 1.0e-12);
}

test "adaptive support keeps vendor tail samples and boundary interval at the band edge" {
    var prepared = std.mem.zeroInit(PreparedOpticalState, .{
        .layers = &.{},
        .continuum_points = &.{},
        .spectroscopy_lines = @import("../../../model/ReferenceData.zig").SpectroscopyLineList{
            .lines = try std.testing.allocator.dupe(@import("../../../model/ReferenceData.zig").SpectroscopyLine, &.{
                .{ .gas_index = 7, .isotope_number = 1, .center_wavelength_nm = 760.52, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.001, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.0, .line_mixing_coefficient = 0.0 },
            }),
        },
    });
    defer if (prepared.spectroscopy_lines) |*line_list| line_list.deinit(std.testing.allocator);

    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 765.0,
            .sample_count = 101,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .high_resolution_half_span_nm = 1.14,
            .adaptive_reference_grid = .{
                .points_per_fwhm = 40,
                .strong_line_min_divisions = 40,
                .strong_line_max_divisions = 40,
            },
        },
    };

    const trace = try traceAdaptiveIntegrationKernel(
        std.testing.allocator,
        &scene,
        &prepared,
        .radiance,
        755.0,
    ) orelse return error.ExpectedAdaptiveTrace;
    defer {
        var owned = trace;
        owned.deinit(std.testing.allocator);
    }

    try std.testing.expectEqual(@as(usize, 6), trace.intervals.len);
    try std.testing.expectEqual(@as(usize, 201), trace.kernel.sample_count);
    try std.testing.expectApproxEqAbs(@as(f64, -0.759665164845), trace.kernel.offsets_nm[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.1403348351549), trace.kernel.offsets_nm[trace.kernel.sample_count - 1], 1.0e-12);
    try std.testing.expectEqual(@as(f64, 0.0), trace.kernel.weights[trace.kernel.sample_count - 1]);
    try std.testing.expectApproxEqAbs(@as(f64, 756.14), trace.intervals[5].interval_start_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 756.52), trace.intervals[5].interval_end_nm, 1.0e-12);
}
