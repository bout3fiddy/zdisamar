const std = @import("std");

const c_api = @import("c_api");

test "optimal-estimation C ABI result rows keep ctypes layout" {
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(c_api.ZdsOptimalEstimationStateSpec));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(c_api.ZdsOptimalEstimationControls));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationRequest));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(c_api.ZdsOptimalEstimationResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationBatchRequest));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationBatchResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationFastmodeBatchResult));
}

test "tiny JSON C ABI spectrum returns two product rows" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(ctx, &spectrum),
    );
    defer c_api.zds_spectrum_free(ctx, &spectrum);

    try std.testing.expectEqual(@as(usize, 2), spectrum.len);
    for (
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.radiance[0..spectrum.len],
        spectrum.irradiance[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
    ) |wavelength_nm, radiance, irradiance, reflectance| {
        try std.testing.expect(std.math.isFinite(wavelength_nm));
        try std.testing.expect(std.math.isFinite(radiance));
        try std.testing.expect(std.math.isFinite(irradiance));
        try std.testing.expect(std.math.isFinite(reflectance));
    }
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "optimal-estimation free hooks clear borrowed result rows" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    var single = c_api.ZdsOptimalEstimationResult{
        .state_count = 2,
        .iteration_count = 3,
        .converged = 1,
        .result_handle = null,
    };
    c_api.zds_optimal_estimation_result_free(ctx, &single);
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationResult{}, single);

    var batch = c_api.ZdsOptimalEstimationBatchResult{
        .run_count = 4,
        .state_count = 2,
        .history_capacity = 10,
        .result_handle = null,
    };
    c_api.zds_optimal_estimation_batch_result_free(ctx, &batch);
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationBatchResult{}, batch);

    var fastmode = c_api.ZdsOptimalEstimationFastmodeBatchResult{
        .run_count = 4,
        .state_count = 2,
        .history_capacity = 11,
        .result_handle = null,
    };
    c_api.zds_optimal_estimation_fastmode_batch_result_free(ctx, &fastmode);
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationFastmodeBatchResult{}, fastmode);
}

test "optimal-estimation request rejects removed surface-albedo state lane" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    states[0].state_id = 2;
    var request = singleRequest(&wavelength_nm, &reflectance, &variance, &states);
    var result: c_api.ZdsOptimalEstimationResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_run_o2a_optimal_estimation(ctx, &request, &result),
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationResult{}, result);
    try std.testing.expectEqualStrings("UnsupportedState", std.mem.span(c_api.zds_last_error(ctx)));
}

test "optimal-estimation pressure state requires profile rows" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{pressureStateWithoutProfile()};
    var request = singleRequest(&wavelength_nm, &reflectance, &variance, &states);
    var result: c_api.ZdsOptimalEstimationResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_run_o2a_optimal_estimation(ctx, &request, &result),
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationResult{}, result);
    try std.testing.expectEqualStrings("missing pressure profile altitude", std.mem.span(c_api.zds_last_error(ctx)));
}

fn prepareTinyJson(ctx: *c_api.Context) !void {
    const allocator = std.testing.allocator;
    var json_len: usize = 0;
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_default_o2a_input_json(ctx, null, 0, &json_len),
    );

    const rendered = try allocator.alloc(u8, json_len + 1);
    defer allocator.free(rendered);
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_default_o2a_input_json(ctx, rendered.ptr, rendered.len, &json_len),
    );

    const sparse_count = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered[0..json_len],
        "\"sample_count\":701",
        "\"sample_count\":2",
    );
    defer allocator.free(sparse_count);
    const sparse_axis = try std.mem.replaceOwned(
        u8,
        allocator,
        sparse_count,
        "\"measured_wavelengths_nm\":[]",
        "\"measured_wavelengths_nm\":[755.0,776.0]",
    );
    defer allocator.free(sparse_axis);

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_prepare_o2a_json(ctx, sparse_axis.ptr, sparse_axis.len),
    );
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

fn aerosolOpticalDepthSpec() c_api.ZdsOptimalEstimationStateSpec {
    return .{
        .state_id = 0,
        .has_lower = 1,
        .has_upper = 1,
        .initial = 0.1,
        .prior = 0.1,
        .variance = 0.01,
        .lower = 0.0,
        .upper = 1.0,
    };
}

fn pressureStateWithoutProfile() c_api.ZdsOptimalEstimationStateSpec {
    return .{
        .state_id = 1,
        .has_lower = 1,
        .has_upper = 1,
        .interval_index_1based = 1,
        .initial = 850.0,
        .prior = 850.0,
        .variance = 100.0,
        .lower = 600.0,
        .upper = 1000.0,
        .thickness_hpa = 10.0,
    };
}

fn singleRequest(
    wavelength_nm: []const f64,
    reflectance: []const f64,
    variance: []const f64,
    states: []const c_api.ZdsOptimalEstimationStateSpec,
) c_api.ZdsOptimalEstimationRequest {
    return .{
        .sample_count = wavelength_nm.len,
        .wavelength_nm = wavelength_nm.ptr,
        .reflectance = reflectance.ptr,
        .variance = variance.ptr,
        .state_count = states.len,
        .states = states.ptr,
    };
}
