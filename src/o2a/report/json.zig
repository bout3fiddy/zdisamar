//! Purpose:
//!   Provide reusable O2A forward profiling helpers for the CLI wrapper and
//!   focused validation tests.
//!
//! Design:
//!   Keeps report aggregation and artifact writing separate from the CLI
//!   parser so tests can exercise the profiling workflow directly.

const builtin = @import("builtin");
const std = @import("std");
const o2a_parity = @import("../data/vendor_parity_yaml.zig");

const MeasurementSpace = @import("../../kernels/transport/measurement.zig");

pub const output_dir_default = "out/analysis/o2a/profile";
pub const summary_name = "summary.json";
pub const spectrum_name = "generated_spectrum.csv";

pub const CliConfig = struct {
    output_dir: []u8,
    repeat_count: u32 = 1,
    write_spectrum: bool = false,
    preset: Preset = .full,
};

pub const Preset = enum {
    quick,
    full,
    plot_bundle,
};

const PhaseStats = struct {
    mean_ns: f64,
    min_ns: u64,
    max_ns: u64,
};

const PreparationStats = struct {
    input_loading_ns: PhaseStats,
    scene_assembly_ns: PhaseStats,
    optics_preparation_ns: PhaseStats,
    plan_preparation_ns: PhaseStats,
    total_ns: PhaseStats,
};

const ForwardStats = struct {
    radiance_integration_ns: PhaseStats,
    radiance_postprocess_ns: PhaseStats,
    irradiance_integration_ns: PhaseStats,
    irradiance_postprocess_ns: PhaseStats,
    reduction_ns: PhaseStats,
    total_ns: PhaseStats,
};

const RunRecord = struct {
    run_index: u32,
    sample_count: u32,
    preparation: o2a_parity.VendorO2APreparationProfile,
    forward: MeasurementSpace.ForwardProfile,
    total_prepare_ns: u64,
    total_forward_ns: u64,
    total_end_to_end_ns: u64,
};

pub const ExecutionOverrides = o2a_parity.ExecutionOverrides;

pub const SummaryReport = struct {
    optimize_mode: []const u8,
    repeat_count: u32,
    sample_count: u32,
    summary_path: []const u8,
    spectrum_path: ?[]const u8 = null,
    runs: []const RunRecord,
    preparation: PreparationStats,
    forward: ForwardStats,
    total_prepare_ns: PhaseStats,
    total_forward_ns: PhaseStats,
    total_end_to_end_ns: PhaseStats,
};

const StatsAccumulator = struct {
    count: usize = 0,
    sum_ns: u128 = 0,
    min_ns: u64 = std.math.maxInt(u64),
    max_ns: u64 = 0,

    fn add(self: *StatsAccumulator, value_ns: u64) void {
        self.count += 1;
        self.sum_ns += value_ns;
        self.min_ns = @min(self.min_ns, value_ns);
        self.max_ns = @max(self.max_ns, value_ns);
    }

    fn finalize(self: StatsAccumulator) PhaseStats {
        if (self.count == 0) {
            return .{
                .mean_ns = 0.0,
                .min_ns = 0,
                .max_ns = 0,
            };
        }
        return .{
            .mean_ns = @as(f64, @floatFromInt(self.sum_ns)) / @as(f64, @floatFromInt(self.count)),
            .min_ns = self.min_ns,
            .max_ns = self.max_ns,
        };
    }
};

const ReportAccumulator = struct {
    prep_input_loading: StatsAccumulator = .{},
    prep_scene_assembly: StatsAccumulator = .{},
    prep_optics: StatsAccumulator = .{},
    prep_plan: StatsAccumulator = .{},
    prep_total: StatsAccumulator = .{},
    forward_radiance_integration: StatsAccumulator = .{},
    forward_radiance_postprocess: StatsAccumulator = .{},
    forward_irradiance_integration: StatsAccumulator = .{},
    forward_irradiance_postprocess: StatsAccumulator = .{},
    forward_reduction: StatsAccumulator = .{},
    forward_total: StatsAccumulator = .{},
    end_to_end_total: StatsAccumulator = .{},

    fn addRun(self: *ReportAccumulator, run: RunRecord) void {
        self.prep_input_loading.add(run.preparation.input_loading_ns);
        self.prep_scene_assembly.add(run.preparation.scene_assembly_ns);
        self.prep_optics.add(run.preparation.optics_preparation_ns);
        self.prep_plan.add(run.preparation.plan_preparation_ns);
        self.prep_total.add(run.total_prepare_ns);
        self.forward_radiance_integration.add(run.forward.radiance_integration_ns);
        self.forward_radiance_postprocess.add(run.forward.radiance_postprocess_ns);
        self.forward_irradiance_integration.add(run.forward.irradiance_integration_ns);
        self.forward_irradiance_postprocess.add(run.forward.irradiance_postprocess_ns);
        self.forward_reduction.add(run.forward.reduction_ns);
        self.forward_total.add(run.total_forward_ns);
        self.end_to_end_total.add(run.total_end_to_end_ns);
    }

    fn preparationStats(self: ReportAccumulator) PreparationStats {
        return .{
            .input_loading_ns = self.prep_input_loading.finalize(),
            .scene_assembly_ns = self.prep_scene_assembly.finalize(),
            .optics_preparation_ns = self.prep_optics.finalize(),
            .plan_preparation_ns = self.prep_plan.finalize(),
            .total_ns = self.prep_total.finalize(),
        };
    }

    fn forwardStats(self: ReportAccumulator) ForwardStats {
        return .{
            .radiance_integration_ns = self.forward_radiance_integration.finalize(),
            .radiance_postprocess_ns = self.forward_radiance_postprocess.finalize(),
            .irradiance_integration_ns = self.forward_irradiance_integration.finalize(),
            .irradiance_postprocess_ns = self.forward_irradiance_postprocess.finalize(),
            .reduction_ns = self.forward_reduction.finalize(),
            .total_ns = self.forward_total.finalize(),
        };
    }
};

/// Run the stock O2A vendor-parity profile workflow.
pub fn runProfileWorkflow(
    allocator: std.mem.Allocator,
    config: CliConfig,
) !void {
    try runProfileWorkflowWithExecutionOverrides(
        allocator,
        config,
        executionOverridesForPreset(config.preset),
    );
}

fn executionOverridesForPreset(preset: Preset) ExecutionOverrides {
    return switch (preset) {
        .quick => .{
            .spectral_grid = .{
                .start_nm = 755.0,
                .end_nm = 776.0,
                .sample_count = 5,
            },
            .adaptive_points_per_fwhm = 4,
            .adaptive_strong_line_min_divisions = 2,
            .adaptive_strong_line_max_divisions = 6,
            .line_mixing_factor = 1.0,
            .isotopes_sim = &.{ 1, 2, 3 },
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
        .full, .plot_bundle => .{
            .spectral_grid = .{
                .start_nm = 755.0,
                .end_nm = 776.0,
                .sample_count = 701,
            },
            .adaptive_points_per_fwhm = 20,
            .adaptive_strong_line_min_divisions = 8,
            .adaptive_strong_line_max_divisions = 40,
            .line_mixing_factor = 1.0,
            .isotopes_sim = &.{ 1, 2, 3 },
            .threshold_line_sim = 3.0e-5,
            .cutoff_sim_cm1 = 200.0,
        },
    };
}

/// Run the O2A forward profiler with explicit YAML-case overrides.
pub fn runProfileWorkflowWithExecutionOverrides(
    allocator: std.mem.Allocator,
    config: CliConfig,
    execution_overrides: ExecutionOverrides,
) !void {
    if (config.repeat_count == 0) return error.InvalidRepeatCount;

    try std.fs.cwd().makePath(config.output_dir);

    const summary_path = try std.fs.path.join(allocator, &.{ config.output_dir, summary_name });
    defer allocator.free(summary_path);
    const spectrum_path = if (config.write_spectrum)
        try std.fs.path.join(allocator, &.{ config.output_dir, spectrum_name })
    else
        null;
    defer if (spectrum_path) |path| allocator.free(path);

    const runs = try allocator.alloc(RunRecord, config.repeat_count);
    defer allocator.free(runs);

    var sample_count: u32 = 0;
    var accumulator: ReportAccumulator = .{};
    for (0..config.repeat_count) |run_index| {
        var total_timer = std.time.Timer.start() catch unreachable;
        var profile_case = try o2a_parity.runDefaultProfileCase(
            allocator,
            execution_overrides,
        );
        defer profile_case.deinit(allocator);

        const run_sample_count = profile_case.reflectance_case.product.summary.sample_count;
        if (run_index == 0) {
            sample_count = run_sample_count;
        } else if (sample_count != run_sample_count) {
            return error.ProfileSampleCountMismatch;
        }

        if (config.write_spectrum and run_index + 1 == config.repeat_count) {
            try writeGeneratedSpectrumCsv(
                spectrum_path.?,
                &profile_case.reflectance_case.product,
            );
        }

        runs[run_index] = .{
            .run_index = @intCast(run_index + 1),
            .sample_count = run_sample_count,
            .preparation = profile_case.preparation_profile,
            .forward = profile_case.forward_profile,
            .total_prepare_ns = profile_case.preparation_profile.totalNs(),
            .total_forward_ns = profile_case.forward_profile.totalNs(),
            .total_end_to_end_ns = total_timer.read(),
        };
        accumulator.addRun(runs[run_index]);
    }

    const report: SummaryReport = .{
        .optimize_mode = optimizeModeLabel(),
        .repeat_count = config.repeat_count,
        .sample_count = sample_count,
        .summary_path = summary_path,
        .spectrum_path = spectrum_path,
        .runs = runs,
        .preparation = accumulator.preparationStats(),
        .forward = accumulator.forwardStats(),
        .total_prepare_ns = accumulator.prep_total.finalize(),
        .total_forward_ns = accumulator.forward_total.finalize(),
        .total_end_to_end_ns = accumulator.end_to_end_total.finalize(),
    };
    try writeSummaryReport(summary_path, report);
}

fn optimizeModeLabel() []const u8 {
    return @tagName(builtin.mode);
}

pub fn writeSummaryReport(
    summary_path: []const u8,
    report: SummaryReport,
) !void {
    var file = try std.fs.cwd().createFile(summary_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    try std.json.Stringify.value(report, .{ .whitespace = .indent_2 }, &writer.interface);
    try writer.interface.flush();
}

fn writeGeneratedSpectrumCsv(
    output_path: []const u8,
    product: *const MeasurementSpace.MeasurementSpaceProduct,
) !void {
    var file = try std.fs.cwd().createFile(output_path, .{ .truncate = true });
    defer file.close();

    var writer = file.writer(&.{});
    defer writer.interface.flush() catch {};
    try writer.interface.writeAll(
        "wavelength_nm,irradiance,radiance,reflectance\n",
    );

    for (product.wavelengths, product.irradiance, product.radiance, product.reflectance) |wavelength_nm, irradiance, radiance, reflectance| {
        try writer.interface.print(
            "{d:.8},{e:.12},{e:.12},{e:.12}\n",
            .{ wavelength_nm, irradiance, radiance, reflectance },
        );
    }
}
