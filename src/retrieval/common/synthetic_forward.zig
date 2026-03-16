const std = @import("std");
const common = @import("contracts.zig");
const forward_model = @import("forward_model.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const StateParameter = @import("../../model/Scene.zig").StateParameter;
const ExecutionMode = @import("../../kernels/transport/common.zig").ExecutionMode;
const MeasurementSpaceSummary = @import("../../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const Allocator = std.mem.Allocator;

pub const MaxSamples: usize = 4096;
pub const MaxStateParameters: usize = 32;

pub const FeatureVector = struct {
    values: [3]f64 = .{ 0.0, 0.0, 0.0 },
    len: usize,
};

pub fn validateShape(problem: common.RetrievalProblem, method: common.Method) common.Error!usize {
    _ = method;
    const state_count: usize = @intCast(problem.inverse_problem.state_vector.count());
    const sample_count: usize = @intCast(problem.inverse_problem.measurements.sample_count);
    if (state_count == 0 or state_count > MaxStateParameters or sample_count == 0 or sample_count > MaxSamples) {
        return error.ShapeMismatch;
    }
    return state_count;
}

pub fn seedState(allocator: Allocator, problem: common.RetrievalProblem) common.Error![]f64 {
    const state_count = try validateShape(problem, .oe);
    const state = try allocator.alloc(f64, state_count);
    errdefer allocator.free(state);

    for (0..state_count) |index| {
        if (stateParameter(problem, index)) |parameter| {
            const seeded = if (parameter.prior.enabled)
                parameter.prior.mean
            else
                try currentValue(problem.scene, parameter.target, index);
            state[index] = clampStateValue(parameter, seeded);
        } else {
            state[index] = try currentValue(problem.scene, defaultStateTarget(index), index);
        }
    }

    return state;
}

pub fn anchorState(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    method: common.Method,
    observed: MeasurementSpaceSummary,
) common.Error![]f64 {
    const seeded = try seedState(allocator, problem);
    errdefer allocator.free(seeded);

    const anchored = try allocator.alloc(f64, seeded.len);
    for (seeded, 0..) |seed, index| {
        if (stateParameter(problem, index)) |parameter| {
            anchored[index] = anchorForParameter(seed, parameter.target, observed, index, method);
            anchored[index] = clampStateValue(parameter, anchored[index]);
        } else {
            anchored[index] = anchorForParameter(seed, defaultStateTarget(index), observed, index, method);
        }
    }
    allocator.free(seeded);
    return anchored;
}

pub fn observedSummary(
    problem: common.RetrievalProblem,
    evaluator: forward_model.SummaryEvaluator,
) common.Error!MeasurementSpaceSummary {
    if (problem.observed_measurement) |observed| return observed.summary;

    return evaluator.evaluate(evaluator.context, sceneWithDefaults(problem.scene)) catch |err| switch (err) {
        error.OutOfMemory => common.Error.OutOfMemory,
        error.InvalidRequest => common.Error.InvalidRequest,
        else => common.Error.InvalidRequest,
    };
}

pub fn sceneForState(problem: common.RetrievalProblem, state: []const f64) common.Error!Scene {
    const state_count = try validateShape(problem, .oe);
    if (state.len != state_count) return error.ShapeMismatch;

    var scene = sceneWithDefaults(problem.scene);
    for (state, 0..) |value, index| {
        if (stateParameter(problem, index)) |parameter| {
            try applyTarget(&scene, parameter.target, clampStateValue(parameter, value), index);
        } else {
            try applyTarget(&scene, defaultStateTarget(index), value, index);
        }
    }
    return scene;
}

pub fn summarizeState(
    problem: common.RetrievalProblem,
    method: common.Method,
    state: []const f64,
    evaluator: forward_model.SummaryEvaluator,
) common.Error!MeasurementSpaceSummary {
    _ = try validateShape(problem, method);
    const scene = try sceneForState(problem, state);
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

fn stateParameter(problem: common.RetrievalProblem, index: usize) ?@TypeOf(problem.inverse_problem.state_vector.parameters[0]) {
    if (problem.inverse_problem.state_vector.parameters.len == 0) return null;
    return problem.inverse_problem.state_vector.parameters[index];
}

fn defaultStateTarget(index: usize) []const u8 {
    return switch (index) {
        0 => "scene.surface.albedo",
        1 => "scene.aerosols.main.optical_depth_550_nm",
        else => "scene.clouds.main.optical_thickness",
    };
}

fn currentValue(scene: Scene, target: []const u8, index: usize) common.Error!f64 {
    _ = index;
    if (std.mem.eql(u8, target, "scene.surface.albedo")) {
        return scene.surface.albedo;
    }
    if (std.mem.endsWith(u8, target, ".optical_depth_550_nm")) {
        return scene.aerosol.optical_depth;
    }
    if (std.mem.endsWith(u8, target, ".layer_center_km")) {
        return scene.aerosol.layer_center_km;
    }
    if (std.mem.endsWith(u8, target, ".layer_width_km")) {
        return scene.aerosol.layer_width_km;
    }
    if (std.mem.endsWith(u8, target, ".optical_thickness")) {
        return scene.cloud.optical_thickness;
    }
    if (std.mem.endsWith(u8, target, ".wavelength_shift_nm")) {
        return scene.observation_model.wavelength_shift_nm;
    }
    if (std.mem.endsWith(u8, target, ".multiplicative_offset")) {
        return scene.observation_model.multiplicative_offset;
    }
    if (std.mem.endsWith(u8, target, ".stray_light")) {
        return scene.observation_model.stray_light;
    }
    return error.InvalidStateValue;
}

fn applyTarget(scene: *Scene, target: []const u8, value: f64, index: usize) common.Error!void {
    _ = index;
    if (std.mem.eql(u8, target, "scene.surface.albedo")) {
        scene.surface.albedo = std.math.clamp(value, 0.0, 1.0);
        return;
    }
    if (std.mem.endsWith(u8, target, ".optical_depth_550_nm")) {
        scene.aerosol.enabled = true;
        scene.atmosphere.has_aerosols = true;
        scene.aerosol.optical_depth = @max(value, 0.0);
        return;
    }
    if (std.mem.endsWith(u8, target, ".layer_center_km")) {
        scene.aerosol.enabled = true;
        scene.atmosphere.has_aerosols = true;
        scene.aerosol.layer_center_km = @max(value, 0.0);
        return;
    }
    if (std.mem.endsWith(u8, target, ".layer_width_km")) {
        scene.aerosol.enabled = true;
        scene.atmosphere.has_aerosols = true;
        scene.aerosol.layer_width_km = @max(value, 0.1);
        return;
    }
    if (std.mem.endsWith(u8, target, ".optical_thickness")) {
        scene.cloud.enabled = true;
        scene.atmosphere.has_clouds = true;
        scene.cloud.optical_thickness = @max(value, 0.0);
        return;
    }
    if (std.mem.endsWith(u8, target, ".wavelength_shift_nm")) {
        scene.observation_model.wavelength_shift_nm = std.math.clamp(value, -1.0, 1.0);
        return;
    }
    if (std.mem.endsWith(u8, target, ".multiplicative_offset")) {
        scene.observation_model.multiplicative_offset = std.math.clamp(value, 0.5, 1.5);
        return;
    }
    if (std.mem.endsWith(u8, target, ".stray_light")) {
        scene.observation_model.stray_light = std.math.clamp(value, -0.05, 0.05);
        return;
    }
    return error.InvalidStateValue;
}

fn sceneWithDefaults(base: Scene) Scene {
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
    if (scene.observation_model.multiplicative_offset <= 0.0) scene.observation_model.multiplicative_offset = 1.0;
    return scene;
}

fn clampStateValue(parameter: StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

fn anchorForParameter(
    seed: f64,
    target: []const u8,
    observed: MeasurementSpaceSummary,
    index: usize,
    method: common.Method,
) f64 {
    const method_scale = switch (method) {
        .oe => @as(f64, 1.0),
        .doas => @as(f64, 0.65),
        .dismas => @as(f64, 1.2),
    };
    const signature = textSignature(target, index);
    const radiance = observed.mean_radiance;
    const reflectance = observed.mean_reflectance;
    const jacobian = observed.mean_jacobian orelse observed.mean_noise_sigma;

    if (std.mem.eql(u8, target, "scene.surface.albedo")) {
        return std.math.clamp(0.5 * seed + 0.5 * reflectance * method_scale, 0.0, 1.0);
    }
    if (std.mem.endsWith(u8, target, ".optical_depth_550_nm")) {
        return @max(0.01, seed * 0.7 + method_scale * (0.08 + 0.12 / @max(radiance, 0.1)));
    }
    if (std.mem.endsWith(u8, target, ".layer_center_km")) {
        return @max(0.0, seed * 0.8 + method_scale * (2.0 + 4.0 * reflectance + 0.2 * signature));
    }
    if (std.mem.endsWith(u8, target, ".layer_width_km")) {
        return @max(0.1, seed * 0.8 + method_scale * (0.8 + 0.4 * reflectance + 0.1 * signature));
    }
    if (std.mem.endsWith(u8, target, ".optical_thickness")) {
        return @max(0.0, seed * 0.75 + method_scale * (0.15 + observed.mean_noise_sigma));
    }
    if (std.mem.endsWith(u8, target, ".wavelength_shift_nm")) {
        return std.math.clamp(seed * 0.5 + 0.08 * jacobian * signature, -0.2, 0.2);
    }
    if (std.mem.endsWith(u8, target, ".multiplicative_offset")) {
        return std.math.clamp(1.0 + 0.03 * (radiance - 1.0) * signature, 0.9, 1.1);
    }
    if (std.mem.endsWith(u8, target, ".stray_light")) {
        return std.math.clamp(0.0005 * signature + 0.002 * observed.mean_noise_sigma, -0.01, 0.01);
    }

    return seed + 0.05 * signature * method_scale;
}

fn textSignature(text: []const u8, index: usize) f64 {
    var hash: u64 = @intCast(index + 1);
    for (text) |byte| {
        hash = hash *% 1099511628211 +% byte;
    }
    const centered = @as(f64, @floatFromInt(hash % 2000)) / 1000.0 - 1.0;
    return if (centered == 0.0) 0.25 else centered;
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

test "synthetic forward supports canonical multi-parameter state application" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "synthetic-forward",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .observation_model = .{ .instrument = "synthetic", .regime = .nadir },
        },
        .inverse_problem = .{
            .id = "synthetic-forward",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "surface_albedo", .target = "scene.surface.albedo", .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 } },
                    .{ .name = "aerosol_tau", .target = "scene.aerosols.plume.optical_depth_550_nm", .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 } },
                    .{ .name = "wavelength_shift", .target = "scene.measurement_model.calibration.wavelength_shift_nm", .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.02 } },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 32,
                .source = .{ .kind = .stage_product, .name = "truth_radiance" },
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth_radiance",
            .observable = "radiance",
            .product_name = "radiance",
            .sample_count = 32,
            .summary = .{
                .sample_count = 32,
                .wavelength_start_nm = 405.0,
                .wavelength_end_nm = 465.0,
                .mean_radiance = 1.1,
                .mean_irradiance = 2.0,
                .mean_reflectance = 0.55,
                .mean_noise_sigma = 0.08,
                .mean_jacobian = 0.06,
            },
        },
    };

    const seeded = try seedState(std.testing.allocator, problem);
    defer std.testing.allocator.free(seeded);
    try std.testing.expectEqual(@as(usize, 3), seeded.len);

    const anchored = try anchorState(std.testing.allocator, problem, .oe, problem.observed_measurement.?.summary);
    defer std.testing.allocator.free(anchored);
    try std.testing.expect(anchored[0] > 0.0);
    try std.testing.expect(anchored[1] > 0.0);

    const scene = try sceneForState(problem, anchored);
    try std.testing.expect(scene.aerosol.enabled);
    try std.testing.expect(scene.observation_model.wavelength_shift_nm != 0.0);
}
