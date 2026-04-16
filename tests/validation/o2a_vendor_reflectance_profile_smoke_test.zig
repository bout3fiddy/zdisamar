const std = @import("std");
const builtin = @import("builtin");
const zdisamar = @import("zdisamar");
const o2a_parity = zdisamar.parity;
const o2a_profile_support = zdisamar.profile;

const ProfileStats = struct {
    mean_ns: f64,
    min_ns: u64,
    max_ns: u64,
};

const ParsedForwardProfile = struct {
    radiance_integration_ns: u64,
    radiance_postprocess_ns: u64,
    irradiance_integration_ns: u64,
    irradiance_postprocess_ns: u64,
    reduction_ns: u64,
};

const ParsedProfileRun = struct {
    run_index: u32,
    sample_count: u32,
    preparation: o2a_parity.VendorO2APreparationProfile,
    forward: ParsedForwardProfile,
    total_prepare_ns: u64,
    total_forward_ns: u64,
    total_end_to_end_ns: u64,
};

const ParsedPreparationStats = struct {
    input_loading_ns: ProfileStats,
    scene_assembly_ns: ProfileStats,
    optics_preparation_ns: ProfileStats,
    plan_preparation_ns: ProfileStats,
    total_ns: ProfileStats,
};

const ParsedForwardStats = struct {
    radiance_integration_ns: ProfileStats,
    radiance_postprocess_ns: ProfileStats,
    irradiance_integration_ns: ProfileStats,
    irradiance_postprocess_ns: ProfileStats,
    reduction_ns: ProfileStats,
    total_ns: ProfileStats,
};

const ParsedProfileSummary = struct {
    optimize_mode: []const u8,
    repeat_count: u32,
    sample_count: u32,
    summary_path: []const u8,
    spectrum_path: ?[]const u8 = null,
    runs: []const ParsedProfileRun,
    preparation: ParsedPreparationStats,
    forward: ParsedForwardStats,
    total_prepare_ns: ProfileStats,
    total_forward_ns: ProfileStats,
    total_end_to_end_ns: ProfileStats,
};

fn profiledTestOverrides() o2a_profile_support.ExecutionOverrides {
    return .{
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 761.5,
            .sample_count = 24,
        },
        .adaptive_points_per_fwhm = 20,
        .adaptive_strong_line_min_divisions = 8,
        .adaptive_strong_line_max_divisions = 40,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    };
}

fn expectApproxEqSlices(expected: []const f64, actual: []const f64, tolerance: f64) !void {
    try std.testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |expected_value, actual_value| {
        try std.testing.expectApproxEqAbs(expected_value, actual_value, tolerance);
    }
}

test "profiled and non-profiled O2A forward paths remain identical" {
    const overrides = profiledTestOverrides();

    var unprofiled = try o2a_parity.runDefaultReflectanceCase(
        std.testing.allocator,
        overrides,
    );
    defer unprofiled.deinit(std.testing.allocator);

    var profiled = try o2a_parity.runDefaultProfileCase(
        std.testing.allocator,
        overrides,
    );
    defer profiled.deinit(std.testing.allocator);

    try std.testing.expectEqual(
        unprofiled.product.summary.sample_count,
        profiled.reflectance_case.product.summary.sample_count,
    );
    try std.testing.expectApproxEqAbs(
        unprofiled.product.summary.mean_radiance,
        profiled.reflectance_case.product.summary.mean_radiance,
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        unprofiled.product.summary.mean_irradiance,
        profiled.reflectance_case.product.summary.mean_irradiance,
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        unprofiled.product.summary.mean_reflectance,
        profiled.reflectance_case.product.summary.mean_reflectance,
        0.0,
    );
    try expectApproxEqSlices(
        unprofiled.product.wavelengths,
        profiled.reflectance_case.product.wavelengths,
        0.0,
    );
    try expectApproxEqSlices(
        unprofiled.product.radiance,
        profiled.reflectance_case.product.radiance,
        0.0,
    );
    try expectApproxEqSlices(
        unprofiled.product.irradiance,
        profiled.reflectance_case.product.irradiance,
        0.0,
    );
    try expectApproxEqSlices(
        unprofiled.product.reflectance,
        profiled.reflectance_case.product.reflectance,
        0.0,
    );
    try std.testing.expect(profiled.preparation_profile.totalNs() > 0);
    try std.testing.expect(profiled.forward_profile.totalNs() > 0);
}

test "o2a forward profile workflow writes a valid summary report" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const output_dir = try std.fmt.allocPrint(
        std.testing.allocator,
        ".zig-cache/tmp/{s}/o2a-forward-profile",
        .{tmp.sub_path[0..]},
    );
    defer std.testing.allocator.free(output_dir);

    try o2a_profile_support.runProfileWorkflowWithExecutionOverrides(
        std.testing.allocator,
        .{
            .output_dir = output_dir,
            .repeat_count = 1,
            .write_spectrum = true,
        },
        profiledTestOverrides(),
    );

    const summary_path = try std.fmt.allocPrint(
        std.testing.allocator,
        "{s}/{s}",
        .{ output_dir, o2a_profile_support.summary_name },
    );
    defer std.testing.allocator.free(summary_path);
    const raw = try std.fs.cwd().readFileAlloc(std.testing.allocator, summary_path, 1024 * 1024);
    defer std.testing.allocator.free(raw);

    const parsed = try std.json.parseFromSlice(
        ParsedProfileSummary,
        std.testing.allocator,
        raw,
        .{ .ignore_unknown_fields = false },
    );
    defer parsed.deinit();

    try std.testing.expectEqualStrings(@tagName(builtin.mode), parsed.value.optimize_mode);
    try std.testing.expectEqual(@as(u32, 1), parsed.value.repeat_count);
    try std.testing.expect(parsed.value.sample_count > 0);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.runs.len);
    try std.testing.expectEqual(parsed.value.sample_count, parsed.value.runs[0].sample_count);
    try std.testing.expect(parsed.value.preparation.total_ns.mean_ns >= 0.0);
    try std.testing.expect(parsed.value.forward.total_ns.mean_ns >= 0.0);
    try std.testing.expect(parsed.value.total_prepare_ns.max_ns >= parsed.value.total_prepare_ns.min_ns);
    try std.testing.expect(parsed.value.total_forward_ns.max_ns >= parsed.value.total_forward_ns.min_ns);
    try std.testing.expect(parsed.value.total_end_to_end_ns.max_ns >= parsed.value.total_end_to_end_ns.min_ns);
    try std.testing.expect(parsed.value.runs[0].total_prepare_ns > 0);
    try std.testing.expect(parsed.value.runs[0].total_forward_ns > 0);
    try std.testing.expect(parsed.value.runs[0].total_end_to_end_ns >= parsed.value.runs[0].total_forward_ns);
    try std.testing.expect(parsed.value.spectrum_path != null);
    try std.fs.cwd().access(parsed.value.summary_path, .{});
    try std.fs.cwd().access(parsed.value.spectrum_path.?, .{});
}
