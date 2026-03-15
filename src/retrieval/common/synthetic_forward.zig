const std = @import("std");
const common = @import("contracts.zig");
const forward_model = @import("forward_model.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const ExecutionMode = @import("../../kernels/transport/common.zig").ExecutionMode;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;

pub const MaxSamples: usize = 256;

pub const FeatureVector = struct {
    values: [3]f64 = .{ 0.0, 0.0, 0.0 },
    len: usize,
};

pub fn requiredStateCount(method: common.Method) usize {
    return switch (method) {
        .oe => 2,
        .doas => 1,
        .dismas => 3,
    };
}

pub fn validateShape(problem: common.RetrievalProblem, method: common.Method) common.Error!usize {
    const state_count: usize = @intCast(problem.inverse_problem.state_vector.value_count);
    const sample_count: usize = @intCast(problem.inverse_problem.measurements.sample_count);
    if (state_count != requiredStateCount(method) or sample_count == 0 or sample_count > MaxSamples) {
        return error.ShapeMismatch;
    }
    return state_count;
}

pub fn seedState(method: common.Method, out: []f64) void {
    switch (method) {
        .oe => {
            out[0] = 0.18;
            out[1] = 0.08;
        },
        .doas => {
            out[0] = 0.10;
        },
        .dismas => {
            out[0] = 0.16;
            out[1] = 0.06;
            out[2] = 0.04;
        },
    }
}

pub fn targetState(problem: common.RetrievalProblem, method: common.Method, out: []f64) void {
    const spectral_scale = @as(f64, @floatFromInt(problem.inverse_problem.measurements.sample_count)) / 200.0;
    switch (method) {
        .oe => {
            out[0] = 0.28 + 0.02 * spectral_scale;
            out[1] = 0.12 + 0.01 * spectral_scale;
        },
        .doas => {
            out[0] = 0.18 + 0.03 * spectral_scale;
        },
        .dismas => {
            out[0] = 0.24 + 0.02 * spectral_scale;
            out[1] = 0.11 + 0.01 * spectral_scale;
            out[2] = 0.09 + 0.01 * spectral_scale;
        },
    }
}

pub fn summarizeState(
    problem: common.RetrievalProblem,
    method: common.Method,
    state: []const f64,
    evaluator: forward_model.SummaryEvaluator,
) common.Error!MeasurementSpaceSummary {
    _ = try validateShape(problem, method);

    const scene = sceneForState(problem.scene, state);
    _ = executionMode(problem, method);
    return evaluator.evaluate(evaluator.context, scene) catch |err| switch (err) {
        error.OutOfMemory => common.Error.OutOfMemory,
        error.InvalidRequest => common.Error.InvalidRequest,
        else => common.Error.InvalidRequest,
    };
}

pub fn featureVector(
    summary: MeasurementSpaceSummary,
    method: common.Method,
) FeatureVector {
    return switch (method) {
        .oe => .{
            .values = .{
                summary.mean_radiance,
                summary.mean_reflectance,
                0.0,
            },
            .len = 2,
        },
        .doas => .{
            .values = .{
                std.math.log(
                    f64,
                    std.math.e,
                    @max(summary.mean_irradiance / @max(summary.mean_radiance, 1e-9), 1e-9),
                ),
                summary.mean_noise_sigma,
                0.0,
            },
            .len = 2,
        },
        .dismas => .{
            .values = .{
                summary.mean_radiance,
                summary.mean_reflectance,
                summary.mean_noise_sigma + @abs(summary.mean_jacobian orelse 0.0),
            },
            .len = 3,
        },
    };
}

pub fn residualNorm(lhs: FeatureVector, rhs: FeatureVector) f64 {
    var total: f64 = 0.0;
    const len = @min(lhs.len, rhs.len);
    for (0..len) |index| {
        const delta = lhs.values[index] - rhs.values[index];
        total += delta * delta;
    }
    return std.math.sqrt(total);
}

fn sceneForState(base: Scene, state: []const f64) Scene {
    var scene = base;
    if (scene.id.len == 0) scene.id = "retrieval-synthetic";
    if (scene.spectral_grid.sample_count < 8) scene.spectral_grid.sample_count = 8;
    if (scene.spectral_grid.end_nm <= scene.spectral_grid.start_nm) {
        scene.spectral_grid.start_nm = 405.0;
        scene.spectral_grid.end_nm = 465.0;
    }
    if (scene.atmosphere.layer_count == 0) scene.atmosphere.layer_count = 24;
    if (scene.observation_model.instrument.len == 0) scene.observation_model.instrument = "retrieval-synthetic";
    if (scene.observation_model.sampling.len == 0) scene.observation_model.sampling = "operational";

    scene.surface.albedo = std.math.clamp(0.04 + 0.60 * state[0], 0.01, 0.95);

    if (state.len > 1) {
        scene.aerosol.enabled = true;
        scene.aerosol.optical_depth = std.math.clamp(0.02 + 0.70 * @abs(state[1]), 0.0, 2.5);
        scene.atmosphere.has_aerosols = true;
    } else {
        scene.aerosol.enabled = false;
        scene.aerosol.optical_depth = 0.0;
        scene.atmosphere.has_aerosols = false;
    }

    if (state.len > 2) {
        scene.cloud.enabled = true;
        scene.cloud.optical_thickness = std.math.clamp(0.05 + 1.10 * @abs(state[2]), 0.0, 8.0);
        scene.atmosphere.has_clouds = true;
    } else {
        scene.cloud.enabled = false;
        scene.cloud.optical_thickness = 0.0;
        scene.atmosphere.has_clouds = false;
    }

    return scene;
}

fn executionMode(problem: common.RetrievalProblem, method: common.Method) ExecutionMode {
    return switch (method) {
        .dismas => .polarized,
        .oe, .doas => switch (problem.scene.observation_model.regime) {
            .nadir => .scalar,
            .limb, .occultation => .polarized,
        },
    };
}

test "synthetic forward summary exposes method-shaped feature vectors" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "synthetic-forward",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 32 },
            .observation_model = .{ .instrument = "synthetic", .regime = .nadir },
        },
        .inverse_problem = .{
            .id = "synthetic-forward",
            .state_vector = .{
                .parameter_names = &[_][]const u8{ "a", "b" },
                .value_count = 2,
            },
            .measurements = .{
                .product = "radiance",
                .sample_count = 32,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    const evaluator: forward_model.SummaryEvaluator = .{
        .context = undefined,
        .evaluate = struct {
            fn evaluate(_: *const anyopaque, scene: Scene) anyerror!MeasurementSpaceSummary {
                _ = scene;
                return .{
                    .sample_count = 32,
                    .wavelength_start_nm = 405.0,
                    .wavelength_end_nm = 465.0,
                    .mean_radiance = 1.0,
                    .mean_irradiance = 2.0,
                    .mean_reflectance = 0.5,
                    .mean_noise_sigma = 0.1,
                    .mean_jacobian = 0.05,
                };
            }
        }.evaluate,
    };
    const summary = try summarizeState(problem, .oe, &[_]f64{ 0.2, 0.1 }, evaluator);
    const features = featureVector(summary, .oe);
    try std.testing.expect(features.len == 2);
    try std.testing.expect(features.values[0] > 0.0);
    try std.testing.expect(features.values[1] > 0.0);
}
