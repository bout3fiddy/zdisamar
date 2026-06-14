const std = @import("std");

const c_api = @import("c_api");
const o2a_json = @import("o2a_json.zig");

test "optimal-estimation C ABI result rows keep ctypes layout" {
    try std.testing.expectEqual(@as(usize, 80), @sizeOf(c_api.ZdsOptimalEstimationStateSpec));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(c_api.ZdsOptimalEstimationControls));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationRequest));
    try std.testing.expectEqual(@as(usize, 120), @sizeOf(c_api.ZdsOptimalEstimationResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationBatchRequest));
    try std.testing.expectEqual(@as(usize, 72), @sizeOf(c_api.ZdsOptimalEstimationBatchResult));
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(c_api.ZdsOptimalEstimationFastmodeBatchResult));
}

test "warm optimal-estimation cache accepts the two retained Jacobian states" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    try prepareDefault(ctx);

    const state_ids = [_]u8{ 0, 1 };
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_warm_o2a_optimal_estimation(ctx, state_ids[0..].ptr, state_ids.len),
    );
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "warm optimal-estimation cache rejects removed surface-albedo state lane" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    try prepareDefault(ctx);

    const removed_surface_albedo_id = [_]u8{2};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_warm_o2a_optimal_estimation(
            ctx,
            removed_surface_albedo_id[0..].ptr,
            removed_surface_albedo_id.len,
        ),
    );
    try std.testing.expectEqualStrings("UnsupportedJacobianState", std.mem.span(c_api.zds_last_error(ctx)));
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

test "single-run optimal-estimation returns result handle for full-grid measurement" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareDefault(ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(ctx, &spectrum),
    );
    defer c_api.zds_spectrum_free(ctx, &spectrum);
    try expectDefaultProductSpectrum(spectrum);

    const variance = try std.testing.allocator.alloc(f64, spectrum.len);
    defer std.testing.allocator.free(variance);
    @memset(variance, 1.0e-6);

    var states = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    states[0].initial = 0.3;
    states[0].prior = 0.3;
    var request = singleRequest(
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
        variance,
        &states,
    );
    request.controls.max_iterations = 1;
    var result: c_api.ZdsOptimalEstimationResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_o2a_optimal_estimation(ctx, &request, &result),
    );
    defer c_api.zds_optimal_estimation_result_free(ctx, &result);

    try std.testing.expect(result.result_handle != null);
    try std.testing.expectEqual(@as(usize, 1), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count);
    try std.testing.expectEqual(@as(u8, 1), result.converged);
    try std.testing.expectEqual(@as(u8, 0), result.state_ids.?[0]);
    try std.testing.expectApproxEqAbs(0.3, result.state.?[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(0.3, result.initial_state.?[0], 0.0);
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "correction optimal-estimation returns one-step result handle" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareDefault(ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(ctx, &spectrum),
    );
    defer c_api.zds_spectrum_free(ctx, &spectrum);
    try expectDefaultProductSpectrum(spectrum);

    const variance = try std.testing.allocator.alloc(f64, spectrum.len);
    defer std.testing.allocator.free(variance);
    @memset(variance, 1.0e-6);

    var states = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    var request = singleRequest(
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
        variance,
        &states,
    );
    request.controls.max_iterations = 5;
    var result: c_api.ZdsOptimalEstimationResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_o2a_optimal_estimation_correction(ctx, &request, &result),
    );
    defer c_api.zds_optimal_estimation_result_free(ctx, &result);

    try std.testing.expect(result.result_handle != null);
    try std.testing.expectEqual(@as(usize, 1), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count);
    try std.testing.expectApproxEqAbs(0.1, result.initial_state.?[0], 0.0);
    try std.testing.expect(std.math.isFinite(result.state.?[0]));
    try std.testing.expect(std.math.isFinite(result.history_state.?[0]));
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "batch optimal-estimation returns run-major result handle" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareDefault(ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(ctx, &spectrum),
    );
    defer c_api.zds_spectrum_free(ctx, &spectrum);
    try expectDefaultProductSpectrum(spectrum);

    const variance = try std.testing.allocator.alloc(f64, spectrum.len);
    defer std.testing.allocator.free(variance);
    @memset(variance, 1.0e-6);

    var state_template = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    const initial = [_]f64{ 0.08, 0.09 };
    const prior = [_]f64{ 0.10, 0.10 };
    var request = batchRequest(
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
        variance,
        &state_template,
        &initial,
        &prior,
    );
    request.controls.max_iterations = 1;
    var result: c_api.ZdsOptimalEstimationBatchResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_o2a_optimal_estimation_batch(ctx, &request, &result),
    );
    defer c_api.zds_optimal_estimation_batch_result_free(ctx, &result);

    try std.testing.expect(result.result_handle != null);
    try std.testing.expectEqual(@as(usize, 2), result.run_count);
    try std.testing.expectEqual(@as(usize, 1), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.history_capacity);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count.?[1]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[1]);
    try std.testing.expect(std.math.isFinite(result.state.?[0]));
    try std.testing.expect(std.math.isFinite(result.state.?[1]));
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(ctx)));
}

test "fastmode optimal-estimation batch returns per-stage metadata" {
    const fast_ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(fast_ctx);
    const correction_ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(correction_ctx);
    try prepareDefault(fast_ctx);
    try prepareDefault(correction_ctx);

    var spectrum: c_api.ZdsSpectrum = .{};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_spectrum(fast_ctx, &spectrum),
    );
    defer c_api.zds_spectrum_free(fast_ctx, &spectrum);
    try expectDefaultProductSpectrum(spectrum);

    const variance = try std.testing.allocator.alloc(f64, spectrum.len);
    defer std.testing.allocator.free(variance);
    @memset(variance, 1.0e-6);

    var fast_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    var correction_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{aerosolOpticalDepthSpec()};
    const initial = [_]f64{ 0.08, 0.09 };
    const prior = [_]f64{ 0.10, 0.10 };
    var fast_request = batchRequest(
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
        variance,
        &fast_state_template,
        &initial,
        &prior,
    );
    fast_request.controls.max_iterations = 1;

    var correction_request = batchRequest(
        spectrum.wavelength_nm[0..spectrum.len],
        spectrum.reflectance[0..spectrum.len],
        variance,
        &correction_state_template,
        &initial,
        &prior,
    );
    correction_request.controls.max_iterations = 1;
    var result: c_api.ZdsOptimalEstimationFastmodeBatchResult = .{};

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_run_o2a_fastmode_optimal_estimation_batch(
            fast_ctx,
            correction_ctx,
            &fast_request,
            &correction_request,
            &result,
        ),
    );
    defer c_api.zds_optimal_estimation_fastmode_batch_result_free(fast_ctx, &result);

    try std.testing.expect(result.result_handle != null);
    try std.testing.expectEqual(@as(usize, 2), result.run_count);
    try std.testing.expectEqual(@as(usize, 1), result.state_count);
    try std.testing.expectEqual(@as(usize, 2), result.history_capacity);
    try std.testing.expectEqual(@as(usize, 2), result.iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 2), result.iteration_count.?[1]);
    try std.testing.expectEqual(@as(usize, 1), result.fast_stage_iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 1), result.full_correction_iteration_count.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[1]);
    try std.testing.expect(std.math.isFinite(result.state.?[0]));
    try std.testing.expect(std.math.isFinite(result.state.?[1]));
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(fast_ctx)));
}

test "optimal-estimation request rejects removed surface-albedo state lane" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareDefault(ctx);

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
    try prepareDefault(ctx);

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

fn prepareDefault(ctx: *c_api.Context) !void {
    const allocator = std.testing.allocator;
    const rendered = try o2a_json.nativeJson(allocator);
    defer allocator.free(rendered);

    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.ok),
        c_api.zds_prepare_o2a_json(ctx, rendered.ptr, rendered.len),
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

fn expectDefaultProductSpectrum(spectrum: c_api.ZdsSpectrum) !void {
    try std.testing.expectEqual(@as(usize, 701), spectrum.len);
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
