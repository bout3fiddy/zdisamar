const std = @import("std");

const c_api = @import("c_api");
const o2a_json = @import("o2a_json.zig");

test "optimal-estimation C ABI result rows keep ctypes layout" {
    try std.testing.expect(c_api.links_libc);
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(c_api.ZdsOptimalEstimationStateSpec));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(c_api.ZdsOptimalEstimationControls));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationRequest));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(c_api.ZdsOptimalEstimationResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationBatchRequest));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationBatchResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationFastmodeBatchResult));
}

test "C ABI radiance-Jacobian scale uses transport solar cosine floor" {
    try std.testing.expectApproxEqAbs(0.5, c_api.solarMu0FromZenithDegrees(60.0), 1.0e-15);
    try std.testing.expectApproxEqAbs(0.05, c_api.solarMu0FromZenithDegrees(90.0), 1.0e-15);
}

test "C ABI rejects null context and input rows with stable errors" {
    try std.testing.expectEqualStrings("null context", std.mem.span(c_api.zds_last_error(null)));
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_prepare_o2a_json(null, null, 0),
    );

    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    try expectFailure(ctx, c_api.zds_prepare_o2a_json(ctx, null, 1), "null input JSON");

    const empty = "";
    try expectFailure(ctx, c_api.zds_prepare_o2a_json(ctx, empty.ptr, empty.len), "empty input JSON");

    var spectrum: c_api.ZdsSpectrum = .{ .len = 123 };
    try expectFailure(ctx, c_api.zds_run_spectrum(ctx, &spectrum), "not prepared");
    try std.testing.expectEqual(@as(usize, 123), spectrum.len);
    try expectFailure(ctx, c_api.zds_run_spectrum(ctx, null), "null spectrum output");
}

test "C ABI JSON prepare byte fuzz corpus leaves context unprepared" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    const corpus = [_][]const u8{
        "{",
        "[{}]",
        "{\"metadata\":{\"id\":\"x\"},\"plan\":{\"derivative_mode\":NaN}}",
        "{\"metadata\":{\"id\":\"x\"},\"rtm_controls\":{\"zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz\":true}}",
        "{\"metadata\":{\"id\":\"x\\uD800\"},\"plan\":{\"derivative_mode\":\"none\"}}",
        "\xff\xfe{\"scene_id\":\"x\"}",
    };
    for (corpus) |payload| {
        try std.testing.expectEqual(
            @intFromEnum(c_api.ZdsStatus.failure),
            c_api.zds_prepare_o2a_json(ctx, payload.ptr, payload.len),
        );
        try std.testing.expect(std.mem.span(c_api.zds_last_error(ctx)).len != 0);

        var spectrum: c_api.ZdsSpectrum = .{ .len = 99 };
        try expectFailure(ctx, c_api.zds_run_spectrum(ctx, &spectrum), "not prepared");
        try std.testing.expectEqual(@as(usize, 99), spectrum.len);
    }
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
    try expectTinyProductRows(spectrum);
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "C ABI spectrum free clears row view and tolerates repeated free" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(ctx, &spectrum),
    );
    try std.testing.expect(spectrum.result_handle != null);

    c_api.zds_spectrum_free(ctx, &spectrum);
    try expectSpectrumClosed(spectrum);

    c_api.zds_spectrum_free(ctx, &spectrum);
    try expectSpectrumClosed(spectrum);
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

test "optimal-estimation C ABI rejects null request and output pointers" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    var single = c_api.ZdsOptimalEstimationResult{ .state_count = 99 };
    try expectFailure(
        ctx,
        c_api.zds_run_o2a_optimal_estimation(ctx, null, &single),
        "null optimal-estimation request",
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationResult{}, single);
    try expectFailure(
        ctx,
        c_api.zds_run_o2a_optimal_estimation(ctx, null, null),
        "null optimal-estimation result",
    );

    var batch = c_api.ZdsOptimalEstimationBatchResult{ .run_count = 99 };
    try expectFailure(
        ctx,
        c_api.zds_run_o2a_optimal_estimation_batch(ctx, null, &batch),
        "null optimal-estimation batch request",
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationBatchResult{}, batch);
    try expectFailure(
        ctx,
        c_api.zds_run_o2a_optimal_estimation_batch(ctx, null, null),
        "null optimal-estimation batch result",
    );
}

test "optimal-estimation request rejects removed surface-albedo state lane" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
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
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        pressureStateWithoutProfile(),
    };
    var request = singleRequest(&wavelength_nm, &reflectance, &variance, &states);
    var result: c_api.ZdsOptimalEstimationResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_run_o2a_optimal_estimation(ctx, &request, &result),
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationResult{}, result);
    try std.testing.expectEqualStrings("missing pressure profile altitude", std.mem.span(c_api.zds_last_error(ctx)));
}

test "optimal-estimation batch rejects unsupported worker counts" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
    const initial = [_]f64{ 0.1, 850.0 };
    const prior = [_]f64{ 0.1, 850.0 };
    var request = batchRequest(&wavelength_nm, &reflectance, &variance, &state_template, &initial, &prior);
    request.batch_worker_count = 2;
    var result: c_api.ZdsOptimalEstimationBatchResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_run_o2a_optimal_estimation_batch(ctx, &request, &result),
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationBatchResult{}, result);
    try std.testing.expectEqualStrings(
        "invalid optimal-estimation batch_worker_count",
        std.mem.span(c_api.zds_last_error(ctx)),
    );
}

test "optimal-estimation batch rejects state-count overflow before slicing run rows" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareTinyJson(ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    var state_template = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    const initial = [_]f64{0.1};
    const prior = [_]f64{0.1};
    var request = batchRequest(&wavelength_nm, &reflectance, &variance, &state_template, &initial, &prior);
    request.run_count = std.math.maxInt(usize);
    request.state_count = 2;
    var result: c_api.ZdsOptimalEstimationBatchResult = .{};

    try expectFailure(
        ctx,
        c_api.zds_run_o2a_optimal_estimation_batch(ctx, &request, &result),
        "optimal-estimation batch is too large",
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationBatchResult{}, result);
}

test "fastmode optimal-estimation batch rejects mismatched state ordering" {
    const fast_ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(fast_ctx);
    const correction_ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(correction_ctx);
    try prepareTinyJson(fast_ctx);
    try prepareTinyJson(correction_ctx);

    const wavelength_nm = [_]f64{ 758.0, 760.0 };
    const reflectance = [_]f64{ 0.12, 0.13 };
    const variance = [_]f64{ 1.0e-4, 1.0e-4 };
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var fast_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
    var correction_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
        aerosolOpticalDepthSpec(),
    };
    const initial = [_]f64{ 0.1, 850.0 };
    const prior = [_]f64{ 0.1, 850.0 };
    var fast_request = batchRequest(
        &wavelength_nm,
        &reflectance,
        &variance,
        &fast_state_template,
        &initial,
        &prior,
    );
    var correction_request = batchRequest(
        &wavelength_nm,
        &reflectance,
        &variance,
        &correction_state_template,
        &initial,
        &prior,
    );
    var result: c_api.ZdsOptimalEstimationFastmodeBatchResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_run_o2a_fastmode_optimal_estimation_batch(
            fast_ctx,
            correction_ctx,
            &fast_request,
            &correction_request,
            &result,
        ),
    );
    try std.testing.expectEqual(c_api.ZdsOptimalEstimationFastmodeBatchResult{}, result);
    try std.testing.expectEqualStrings("invalid state order", std.mem.span(c_api.zds_last_error(fast_ctx)));
}

fn expectFailure(ctx: *c_api.Context, status: c_int, expected_error: []const u8) !void {
    try std.testing.expectEqual(@intFromEnum(c_api.ZdsStatus.failure), status);
    try std.testing.expectEqualStrings(expected_error, std.mem.span(c_api.zds_last_error(ctx)));
}

fn expectTinyProductRows(spectrum: c_api.ZdsSpectrum) !void {
    const expected_wavelength_nm = [_]f64{ 755.0, 776.0 };
    const expected_radiance = [_]f64{ 17800959849043.055, 17690866913508.75 };
    const expected_irradiance = [_]f64{ 480585461471192.25, 475983979180662.75 };
    const expected_reflectance = [_]f64{ 0.23273015591193758, 0.23352675704246348 };

    for (0..spectrum.len) |index| {
        try std.testing.expectApproxEqAbs(expected_wavelength_nm[index], spectrum.wavelength_nm[index], 0.0);
        try std.testing.expectApproxEqRel(expected_radiance[index], spectrum.radiance[index], 1.0e-13);
        try std.testing.expectApproxEqRel(expected_irradiance[index], spectrum.irradiance[index], 1.0e-13);
        try std.testing.expectApproxEqAbs(expected_reflectance[index], spectrum.reflectance[index], 1.0e-15);
    }
}

fn expectSpectrumClosed(spectrum: c_api.ZdsSpectrum) !void {
    try std.testing.expectEqual(@as(usize, 0), spectrum.len);
    try std.testing.expectEqual(@as(?[*]const f64, null), spectrum.jacobian);
    try std.testing.expectEqual(@as(usize, 0), spectrum.jacobian_state_count);
    try std.testing.expectEqual(@as(?*anyopaque, null), spectrum.result_handle);
}

fn prepareTinyJson(ctx: *c_api.Context) !void {
    const allocator = std.testing.allocator;
    const rendered = try o2a_json.nativeJson(allocator);
    defer allocator.free(rendered);
    const sparse_count = try std.mem.replaceOwned(
        u8,
        allocator,
        rendered,
        "\"sample_count\": 701",
        "\"sample_count\": 2",
    );
    defer allocator.free(sparse_count);
    const sparse_axis = try std.mem.replaceOwned(
        u8,
        allocator,
        sparse_count,
        "\"measured_wavelengths_nm\": []",
        "\"measured_wavelengths_nm\": [755.0, 776.0]",
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

fn aerosolPressureSpec(
    altitude_km: []const f64,
    pressure_hpa: []const f64,
) c_api.ZdsOptimalEstimationStateSpec {
    return .{
        .state_id = 1,
        .has_lower = 1,
        .has_upper = 1,
        .interval_index_1based = 2,
        .initial = 850.0,
        .prior = 850.0,
        .variance = 100.0,
        .lower = 600.0,
        .upper = 1000.0,
        .thickness_hpa = 10.0,
        .pressure_profile_count = altitude_km.len,
        .pressure_profile_altitude_km = altitude_km.ptr,
        .pressure_profile_pressure_hpa = pressure_hpa.ptr,
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

fn batchRequest(
    wavelength_nm: []const f64,
    reflectance: []const f64,
    variance: []const f64,
    state_template: []const c_api.ZdsOptimalEstimationStateSpec,
    initial: []const f64,
    prior: []const f64,
) c_api.ZdsOptimalEstimationBatchRequest {
    return .{
        .sample_count = wavelength_nm.len,
        .wavelength_nm = wavelength_nm.ptr,
        .reflectance = reflectance.ptr,
        .variance = variance.ptr,
        .state_count = state_template.len,
        .state_template = state_template.ptr,
        .run_count = initial.len / state_template.len,
        .initial = initial.ptr,
        .prior = prior.ptr,
        .batch_worker_count = 1,
    };
}
