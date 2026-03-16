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

pub const StateTarget = enum {
    surface_albedo,
    aerosol_optical_depth_550_nm,
    aerosol_layer_center_km,
    aerosol_layer_width_km,
    cloud_optical_thickness,
    wavelength_shift_nm,
    multiplicative_offset,
    stray_light,
};

pub const StateAccessor = struct {
    target: StateTarget,
    signature: f64,
};

pub const ResolvedStateLayout = struct {
    count: usize = 0,
    accessors: [MaxStateParameters]StateAccessor = undefined,

    pub fn at(self: ResolvedStateLayout, index: usize) StateAccessor {
        std.debug.assert(index < self.count);
        return self.accessors[index];
    }
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

pub fn resolveStateLayout(problem: common.RetrievalProblem) common.Error!ResolvedStateLayout {
    const state_count = try validateShape(problem, .oe);
    var layout: ResolvedStateLayout = .{ .count = state_count };

    for (0..state_count) |index| {
        layout.accessors[index] = try resolveStateAccessor(problem, index);
    }
    return layout;
}

pub fn seedState(allocator: Allocator, problem: common.RetrievalProblem) common.Error![]f64 {
    const layout = try resolveStateLayout(problem);
    return seedStateWithLayout(allocator, problem, layout);
}

pub fn seedStateWithLayout(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    layout: ResolvedStateLayout,
) common.Error![]f64 {
    const state_count = try validateShape(problem, .oe);
    if (layout.count != state_count) return error.ShapeMismatch;
    const state = try allocator.alloc(f64, state_count);
    errdefer allocator.free(state);

    for (0..state_count) |index| {
        const accessor = layout.at(index);
        if (stateParameter(problem, index)) |parameter| {
            const seeded = if (parameter.prior.enabled)
                parameter.prior.mean
            else
                currentValue(problem.scene, accessor);
            state[index] = clampStateValue(parameter, seeded);
        } else {
            state[index] = currentValue(problem.scene, accessor);
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
    const layout = try resolveStateLayout(problem);
    return anchorStateWithLayout(allocator, problem, method, observed, layout);
}

pub fn anchorStateWithLayout(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    method: common.Method,
    observed: MeasurementSpaceSummary,
    layout: ResolvedStateLayout,
) common.Error![]f64 {
    const seeded = try seedStateWithLayout(allocator, problem, layout);
    errdefer allocator.free(seeded);

    const anchored = try allocator.alloc(f64, seeded.len);
    for (seeded, 0..) |seed, index| {
        const accessor = layout.at(index);
        if (stateParameter(problem, index)) |parameter| {
            anchored[index] = anchorForAccessor(seed, accessor, observed, method);
            anchored[index] = clampStateValue(parameter, anchored[index]);
        } else {
            anchored[index] = anchorForAccessor(seed, accessor, observed, method);
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
    const layout = try resolveStateLayout(problem);
    return sceneForStateWithLayout(problem, state, layout);
}

pub fn sceneForStateWithLayout(
    problem: common.RetrievalProblem,
    state: []const f64,
    layout: ResolvedStateLayout,
) common.Error!Scene {
    const state_count = try validateShape(problem, .oe);
    if (layout.count != state_count) return error.ShapeMismatch;
    if (state.len != state_count) return error.ShapeMismatch;

    var scene = sceneWithDefaults(problem.scene);
    for (state, 0..) |value, index| {
        const accessor = layout.at(index);
        if (stateParameter(problem, index)) |parameter| {
            applyAccessor(&scene, accessor, clampStateValue(parameter, value));
        } else {
            applyAccessor(&scene, accessor, value);
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
    const layout = try resolveStateLayout(problem);
    return summarizeStateWithLayout(problem, method, state, evaluator, layout);
}

pub fn summarizeStateWithLayout(
    problem: common.RetrievalProblem,
    method: common.Method,
    state: []const f64,
    evaluator: forward_model.SummaryEvaluator,
    layout: ResolvedStateLayout,
) common.Error!MeasurementSpaceSummary {
    _ = try validateShape(problem, method);
    const scene = try sceneForStateWithLayout(problem, state, layout);
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

fn defaultStateAccessor(index: usize) StateAccessor {
    return switch (index) {
        0 => .{
            .target = .surface_albedo,
            .signature = textSignature("scene.surface.albedo", index),
        },
        1 => .{
            .target = .aerosol_optical_depth_550_nm,
            .signature = textSignature("scene.aerosols.main.optical_depth_550_nm", index),
        },
        else => .{
            .target = .cloud_optical_thickness,
            .signature = textSignature("scene.clouds.main.optical_thickness", index),
        },
    };
}

fn resolveStateAccessor(problem: common.RetrievalProblem, index: usize) common.Error!StateAccessor {
    if (stateParameter(problem, index)) |parameter| {
        return accessorFromTarget(parameter.target, index);
    }
    return defaultStateAccessor(index);
}

fn accessorFromTarget(target: []const u8, index: usize) common.Error!StateAccessor {
    if (std.mem.eql(u8, target, "scene.surface.albedo")) {
        return .{ .target = .surface_albedo, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".optical_depth_550_nm")) {
        return .{ .target = .aerosol_optical_depth_550_nm, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".layer_center_km")) {
        return .{ .target = .aerosol_layer_center_km, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".layer_width_km")) {
        return .{ .target = .aerosol_layer_width_km, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".optical_thickness")) {
        return .{ .target = .cloud_optical_thickness, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".wavelength_shift_nm")) {
        return .{ .target = .wavelength_shift_nm, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".multiplicative_offset")) {
        return .{ .target = .multiplicative_offset, .signature = textSignature(target, index) };
    }
    if (std.mem.endsWith(u8, target, ".stray_light")) {
        return .{ .target = .stray_light, .signature = textSignature(target, index) };
    }
    return error.InvalidStateValue;
}

fn currentValue(scene: Scene, accessor: StateAccessor) f64 {
    return switch (accessor.target) {
        .surface_albedo => scene.surface.albedo,
        .aerosol_optical_depth_550_nm => scene.aerosol.optical_depth,
        .aerosol_layer_center_km => scene.aerosol.layer_center_km,
        .aerosol_layer_width_km => scene.aerosol.layer_width_km,
        .cloud_optical_thickness => scene.cloud.optical_thickness,
        .wavelength_shift_nm => scene.observation_model.wavelength_shift_nm,
        .multiplicative_offset => scene.observation_model.multiplicative_offset,
        .stray_light => scene.observation_model.stray_light,
    };
}

fn applyAccessor(scene: *Scene, accessor: StateAccessor, value: f64) void {
    switch (accessor.target) {
        .surface_albedo => {
            scene.surface.albedo = std.math.clamp(value, 0.0, 1.0);
        },
        .aerosol_optical_depth_550_nm => {
            scene.aerosol.enabled = true;
            scene.atmosphere.has_aerosols = true;
            scene.aerosol.optical_depth = @max(value, 0.0);
        },
        .aerosol_layer_center_km => {
            scene.aerosol.enabled = true;
            scene.atmosphere.has_aerosols = true;
            scene.aerosol.layer_center_km = @max(value, 0.0);
        },
        .aerosol_layer_width_km => {
            scene.aerosol.enabled = true;
            scene.atmosphere.has_aerosols = true;
            scene.aerosol.layer_width_km = @max(value, 0.1);
        },
        .cloud_optical_thickness => {
            scene.cloud.enabled = true;
            scene.atmosphere.has_clouds = true;
            scene.cloud.optical_thickness = @max(value, 0.0);
        },
        .wavelength_shift_nm => {
            scene.observation_model.wavelength_shift_nm = std.math.clamp(value, -1.0, 1.0);
        },
        .multiplicative_offset => {
            scene.observation_model.multiplicative_offset = std.math.clamp(value, 0.5, 1.5);
        },
        .stray_light => {
            scene.observation_model.stray_light = std.math.clamp(value, -0.05, 0.05);
        },
    }
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

fn anchorForAccessor(
    seed: f64,
    accessor: StateAccessor,
    observed: MeasurementSpaceSummary,
    method: common.Method,
) f64 {
    const method_scale = switch (method) {
        .oe => @as(f64, 1.0),
        .doas => @as(f64, 0.65),
        .dismas => @as(f64, 1.2),
    };
    const signature = accessor.signature;
    const radiance = observed.mean_radiance;
    const reflectance = observed.mean_reflectance;
    const jacobian = observed.mean_jacobian orelse observed.mean_noise_sigma;

    return switch (accessor.target) {
        .surface_albedo => std.math.clamp(0.5 * seed + 0.5 * reflectance * method_scale, 0.0, 1.0),
        .aerosol_optical_depth_550_nm => @max(0.01, seed * 0.7 + method_scale * (0.08 + 0.12 / @max(radiance, 0.1))),
        .aerosol_layer_center_km => @max(0.0, seed * 0.8 + method_scale * (2.0 + 4.0 * reflectance + 0.2 * signature)),
        .aerosol_layer_width_km => @max(0.1, seed * 0.8 + method_scale * (0.8 + 0.4 * reflectance + 0.1 * signature)),
        .cloud_optical_thickness => @max(0.0, seed * 0.75 + method_scale * (0.15 + observed.mean_noise_sigma)),
        .wavelength_shift_nm => std.math.clamp(seed * 0.5 + 0.08 * jacobian * signature, -0.2, 0.2),
        .multiplicative_offset => std.math.clamp(1.0 + 0.03 * (radiance - 1.0) * signature, 0.9, 1.1),
        .stray_light => std.math.clamp(0.0005 * signature + 0.002 * observed.mean_noise_sigma, -0.01, 0.01),
    };
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

test "surrogate forward supports canonical multi-parameter state application" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "surrogate-forward",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .observation_model = .{ .instrument = "synthetic", .regime = .nadir },
        },
        .inverse_problem = .{
            .id = "surrogate-forward",
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

    const layout = try resolveStateLayout(problem);
    try std.testing.expectEqual(@as(usize, 3), layout.count);
    try std.testing.expectEqual(StateTarget.surface_albedo, layout.at(0).target);
    try std.testing.expectEqual(StateTarget.aerosol_optical_depth_550_nm, layout.at(1).target);
    try std.testing.expectEqual(StateTarget.wavelength_shift_nm, layout.at(2).target);

    const seeded = try seedStateWithLayout(std.testing.allocator, problem, layout);
    defer std.testing.allocator.free(seeded);
    try std.testing.expectEqual(@as(usize, 3), seeded.len);

    const anchored = try anchorStateWithLayout(std.testing.allocator, problem, .oe, problem.observed_measurement.?.summary, layout);
    defer std.testing.allocator.free(anchored);
    try std.testing.expect(anchored[0] > 0.0);
    try std.testing.expect(anchored[1] > 0.0);

    const scene = try sceneForStateWithLayout(problem, anchored, layout);
    try std.testing.expect(scene.aerosol.enabled);
    try std.testing.expect(scene.observation_model.wavelength_shift_nm != 0.0);
}

test "surrogate forward rejects unknown retrieval state targets during layout resolution" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "surrogate-forward-invalid-target",
            .spectral_grid = .{ .sample_count = 16 },
            .observation_model = .{ .instrument = "synthetic" },
        },
        .inverse_problem = .{
            .id = "surrogate-forward-invalid-target",
            .state_vector = .{
                .parameters = &[_]@import("../../model/Scene.zig").StateParameter{
                    .{ .name = "unknown", .target = "scene.unknown.target" },
                },
            },
            .measurements = .{
                .product = "radiance",
                .observable = "radiance",
                .sample_count = 16,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = false,
    };

    try std.testing.expectError(common.Error.InvalidStateValue, resolveStateLayout(problem));
}
