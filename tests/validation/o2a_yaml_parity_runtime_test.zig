const std = @import("std");
const validation_support = @import("disamar_reference_support").disamar_reference;
const parity_config = validation_support.config;
const parity_cli = validation_support.cli;
const o2a_parity = validation_support.yaml;

const BaselineAnchor = struct {
    version: u32,
    scenario: []const u8,
    upstream_config: []const u8,
    reference_path: []const u8,
    zero_tolerance_abs: f64,
    trend_tolerances: o2a_parity.TrendTolerances,
    guidance: struct {
        allowed_to_fail: bool,
        summary: []const u8,
        expect_improvement_when_touched: []const []const u8,
    },
    baseline: o2a_parity.ComparisonMetrics,
};

fn exampleConfigPath() []const u8 {
    return "data/examples/vendor_o2a_parity.yaml";
}

fn loadBaselineAnchor(allocator: std.mem.Allocator) !std.json.Parsed(BaselineAnchor) {
    const raw = try std.fs.cwd().readFileAlloc(
        allocator,
        "validation/o2a_vendor_forward_reflectance_baseline.json",
        64 * 1024,
    );
    defer allocator.free(raw);
    return std.json.parseFromSlice(BaselineAnchor, allocator, raw, .{ .ignore_unknown_fields = false });
}

test "yaml parity example resolves key DISAMAR mapping controls" {
    var loaded = try parity_config.loadResolvedCaseFromFile(std.testing.allocator, exampleConfigPath());
    defer loaded.deinit();

    try std.testing.expectEqualStrings("disamar_standard", loaded.resolved.plan.model_family);
    try std.testing.expectEqualStrings(
        "data/climatologies/vendor_config_o2a_profile.csv",
        loaded.resolved.inputs.atmosphere_profile.path,
    );
    try std.testing.expectEqual(@as(f64, 755.0), loaded.resolved.spectral_grid.start_nm);
    try std.testing.expectEqual(@as(f64, 776.0), loaded.resolved.spectral_grid.end_nm);
    try std.testing.expectEqual(@as(u32, 21), loaded.resolved.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(f64, 0.38), loaded.resolved.observation.instrument_line_fwhm_nm);
    try std.testing.expectEqual(@as(f64, 60.0), loaded.resolved.geometry.solar_zenith_deg);
    try std.testing.expectEqual(@as(f64, 30.0), loaded.resolved.geometry.viewing_zenith_deg);
    try std.testing.expectEqual(@as(f64, 120.0), loaded.resolved.geometry.relative_azimuth_deg);
    try std.testing.expectEqual(@as(u32, 2), loaded.resolved.fit_interval_index_1based);
    try std.testing.expectEqual(@as(usize, 3), loaded.resolved.intervals.len);
    try std.testing.expectEqual(@as(u32, 2), loaded.resolved.aerosol.placement.interval_index_1based);
    try std.testing.expectEqual(@as(?f64, 1.0), loaded.resolved.o2.line_mixing_factor);
    try std.testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, loaded.resolved.o2.isotopes_sim);
    try std.testing.expectEqual(@as(?f64, 3.0e-5), loaded.resolved.o2.threshold_line_sim);
    try std.testing.expectEqual(@as(?f64, 200.0), loaded.resolved.o2.cutoff_sim_cm1);
    try std.testing.expect(loaded.resolved.o2o2.enabled);
    try std.testing.expectEqual(@as(u16, 20), loaded.resolved.rtm_controls.n_streams);
    try std.testing.expect(loaded.resolved.rtm_controls.integrate_source_function);
    try std.testing.expect(loaded.resolved.rtm_controls.renorm_phase_function);
}

test "yaml parity runtime resolves symmetric DISAMAR HR integration for both channels" {
    var loaded = try parity_config.loadResolvedCaseFromFile(std.testing.allocator, exampleConfigPath());
    defer loaded.deinit();

    var parity_case = try o2a_parity.prepareResolvedVendorO2ACase(std.testing.allocator, &loaded.resolved);
    defer parity_case.deinit(std.testing.allocator);

    const radiance = parity_case.scene.observation_model.resolvedChannelControls(.radiance).response;
    const irradiance = parity_case.scene.observation_model.resolvedChannelControls(.irradiance).response;

    try std.testing.expect(radiance.explicit);
    try std.testing.expect(irradiance.explicit);
    try std.testing.expectEqual(.disamar_hr_grid, radiance.integration_mode);
    try std.testing.expectEqual(.disamar_hr_grid, irradiance.integration_mode);
    try std.testing.expectApproxEqAbs(@as(f64, 0.01), radiance.high_resolution_step_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.14), radiance.high_resolution_half_span_nm, 1.0e-12);
    try std.testing.expectEqual(radiance.slit_index, irradiance.slit_index);
    try std.testing.expectEqual(radiance.builtin_line_shape, irradiance.builtin_line_shape);
    try std.testing.expectApproxEqAbs(radiance.fwhm_nm, irradiance.fwhm_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(radiance.high_resolution_step_nm, irradiance.high_resolution_step_nm, 1.0e-12);
    try std.testing.expectApproxEqAbs(radiance.high_resolution_half_span_nm, irradiance.high_resolution_half_span_nm, 1.0e-12);
    try std.testing.expectEqual(
        @as(usize, 47),
        parity_case.prepared.spectroscopy_profile_altitudes_km.len,
    );
}

test "yaml parity output computes vendor comparison metrics on the executable config" {
    var loaded = try parity_config.loadResolvedCaseFromFile(std.testing.allocator, exampleConfigPath());
    defer loaded.deinit();

    var baseline = try loadBaselineAnchor(std.testing.allocator);
    defer baseline.deinit();

    var yaml_case = try o2a_parity.runResolvedVendorO2AReflectanceCase(std.testing.allocator, &loaded.resolved);
    defer yaml_case.deinit(std.testing.allocator);

    const current = o2a_parity.computeComparisonMetrics(
        &yaml_case.product,
        yaml_case.reference,
        baseline.value.zero_tolerance_abs,
    );
    try std.testing.expectEqual(@as(u32, 701), current.sample_count);
    try std.testing.expect(!current.exact_match_within_zero_tolerance);
    try std.testing.expect(current.mean_abs_difference > 0.0);
    try std.testing.expect(current.correlation > 0.95);
}

test "yaml cli validate and resolve commands succeed" {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(std.testing.allocator);
    var validate_writer = output.writer(std.testing.allocator);

    try parity_cli.mainWithArgs(
        std.testing.allocator,
        &.{ "zdisamar", "config", "validate", exampleConfigPath() },
        &validate_writer,
    );
    try std.testing.expect(std.mem.indexOf(u8, output.items, "validated") != null);

    output.clearRetainingCapacity();
    var resolve_writer = output.writer(std.testing.allocator);
    try parity_cli.mainWithArgs(
        std.testing.allocator,
        &.{ "zdisamar", "config", "resolve", exampleConfigPath() },
        &resolve_writer,
    );
    try std.testing.expect(std.mem.indexOf(u8, output.items, "\"scene_id\": \"o2a_vendor_parity_yaml\"") != null);
}

test "yaml cli run command writes configured outputs" {
    var null_writer = std.io.null_writer;
    try parity_cli.mainWithArgs(
        std.testing.allocator,
        &.{ "zdisamar", "run", exampleConfigPath() },
        &null_writer,
    );

    try std.fs.cwd().access("out/analysis/o2a/yaml_run/summary.json", .{});
    try std.fs.cwd().access("out/analysis/o2a/yaml_run/generated_spectrum.csv", .{});
}
