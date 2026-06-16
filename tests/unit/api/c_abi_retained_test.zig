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

test "warm optimal-estimation cache rejects one-state request" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);

    try prepareDefault(ctx);

    const state_ids = [_]u8{0};
    try std.testing.expectEqual(
        @intFromEnum(c_api.ZdsStatus.failure),
        c_api.zds_warm_o2a_optimal_estimation(ctx, state_ids[0..].ptr, state_ids.len),
    );
    try std.testing.expectEqualStrings(
        "invalid optimal-estimation state vector",
        std.mem.span(c_api.zds_last_error(ctx)),
    );
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

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
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
    try std.testing.expectEqual(@as(usize, 2), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count);
    try std.testing.expectEqual(@as(u8, 0), result.converged);
    try std.testing.expectEqual(@as(u8, 0), result.state_ids.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.state_ids.?[1]);
    try std.testing.expectApproxEqRel(0.3218022557145076, result.state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(841.0563427719196, result.state.?[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(0.3, result.initial_state.?[0], 0.0);
    try std.testing.expectApproxEqAbs(850.0, result.initial_state.?[1], 0.0);
    try std.testing.expectApproxEqRel(5.0327224966474805e-5, result.posterior_covariance.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(0.005484945752473451, result.posterior_covariance.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(0.005484945752473451, result.posterior_covariance.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(98.14024630925327, result.posterior_covariance.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(313.7498523160241, result.averaging_kernel.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(-0.017296055445342524, result.averaging_kernel.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(-172.96055445340608, result.averaging_kernel.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(5.864488802889277, result.averaging_kernel.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3218022557145076, result.history_state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(841.0563427719196, result.history_state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(17581.186238836166, result.history_chi2.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(17580.338814954608, result.history_chi2_reflectance.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(0.8474238815580228, result.history_chi2_state_vector.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(5.379307392874958, result.history_state_vector_convergence.?[0], 1.0e-12);
    try std.testing.expectEqual(@as(u8, 0), result.history_snr_normal.?[0]);
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

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var states = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
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
    try std.testing.expectEqual(@as(usize, 2), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count);
    try std.testing.expectApproxEqAbs(0.1, result.initial_state.?[0], 0.0);
    try std.testing.expectApproxEqAbs(850.0, result.initial_state.?[1], 0.0);
    try std.testing.expectApproxEqRel(0.36656240097651505, result.state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(847.531818925324, result.state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(3.212187341505087e-7, result.posterior_covariance.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(0.0015179266918172764, result.posterior_covariance.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(0.0015179266918172764, result.posterior_covariance.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(72.29518736871741, result.posterior_covariance.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(0.9999678781265839, result.averaging_kernel.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(-1.5179266918172786e-5, result.averaging_kernel.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(-0.15179266918767098, result.averaging_kernel.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(0.2770481263128252, result.averaging_kernel.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(0.36656240097651505, result.history_state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(847.531818925324, result.history_state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(265603.46505356533, result.history_chi2.?[0], 1.0e-12);
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

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
    const initial = [_]f64{ 0.08, 850.0, 0.09, 850.0 };
    const prior = [_]f64{ 0.10, 850.0, 0.10, 850.0 };
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
    try std.testing.expectEqual(@as(usize, 2), result.state_count);
    try std.testing.expectEqual(@as(usize, 1), result.history_capacity);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 1), result.iteration_count.?[1]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[1]);
    try std.testing.expectApproxEqRel(0.3815807881577048, result.state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(848.0765436795413, result.state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3735949222795868, result.state.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(847.8074099290603, result.state.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(result.state.?[0], result.history_state.?[0], 0.0);
    try std.testing.expectApproxEqRel(result.state.?[1], result.history_state.?[1], 0.0);
    try std.testing.expectApproxEqRel(result.state.?[2], result.history_state.?[2], 0.0);
    try std.testing.expectApproxEqRel(result.state.?[3], result.history_state.?[3], 0.0);
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

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    var fast_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
    var correction_state_template = [_]c_api.ZdsOptimalEstimationStateSpec{
        aerosolOpticalDepthSpec(),
        aerosolPressureSpec(&altitude_km, &pressure_hpa),
    };
    const initial = [_]f64{ 0.08, 850.0, 0.09, 850.0 };
    const prior = [_]f64{ 0.10, 850.0, 0.10, 850.0 };
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
    try std.testing.expectEqual(@as(usize, 2), result.state_count);
    try std.testing.expectEqual(@as(usize, 2), result.history_capacity);
    try std.testing.expectEqual(@as(usize, 2), result.iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 2), result.iteration_count.?[1]);
    try std.testing.expectEqual(@as(usize, 1), result.fast_stage_iteration_count.?[0]);
    try std.testing.expectEqual(@as(usize, 1), result.full_correction_iteration_count.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[0]);
    try std.testing.expectEqual(@as(u8, 1), result.status.?[1]);
    try std.testing.expectApproxEqRel(0.3212508722823766, result.state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(829.2142546099802, result.state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3210901563847662, result.state.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(829.6743599634119, result.state.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3815807881577048, result.history_state.?[0], 1.0e-12);
    try std.testing.expectApproxEqRel(848.0765436795413, result.history_state.?[1], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3212508722823766, result.history_state.?[2], 1.0e-12);
    try std.testing.expectApproxEqRel(829.2142546099802, result.history_state.?[3], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3735949222795868, result.history_state.?[4], 1.0e-12);
    try std.testing.expectApproxEqRel(847.8074099290603, result.history_state.?[5], 1.0e-12);
    try std.testing.expectApproxEqRel(0.3210901563847662, result.history_state.?[6], 1.0e-12);
    try std.testing.expectApproxEqRel(829.6743599634119, result.history_state.?[7], 1.0e-12);
    try std.testing.expectEqualStrings("", std.mem.span(c_api.zds_last_error(fast_ctx)));
}

test "optimal-estimation request rejects removed surface-albedo state lane" {
    const ctx = c_api.zds_context_create() orelse return error.OutOfMemory;
    defer c_api.zds_context_destroy(ctx);
    try prepareDefault(ctx);

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
    try prepareDefault(ctx);

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

fn expectDefaultProductSpectrum(spectrum: c_api.ZdsSpectrum) !void {
    try std.testing.expectEqual(@as(usize, 701), spectrum.len);
    try expectProductRow(spectrum, 0, 755.0, 17800959849043.055, 480585461471192.25, 0.23273015591193758);
    try expectProductRow(spectrum, 350, 765.5, 9257524836591.932, 475479621402183.7, 0.12233278024112049);
    try expectProductRow(spectrum, 700, 776.0, 17690866913508.75, 475983979180662.75, 0.23352675704246348);
}

fn expectProductRow(
    spectrum: c_api.ZdsSpectrum,
    index: usize,
    wavelength_nm: f64,
    radiance: f64,
    irradiance: f64,
    reflectance: f64,
) !void {
    try std.testing.expectApproxEqAbs(wavelength_nm, spectrum.wavelength_nm[index], 0.0);
    try std.testing.expectApproxEqRel(radiance, spectrum.radiance[index], 1.0e-13);
    try std.testing.expectApproxEqRel(irradiance, spectrum.irradiance[index], 1.0e-13);
    try std.testing.expectApproxEqAbs(reflectance, spectrum.reflectance[index], 1.0e-15);
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
