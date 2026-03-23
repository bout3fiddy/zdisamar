//! Purpose:
//!   Map retrieval state-vector parameters onto canonical scene fields and
//!   build solver-space seed states.
//!
//! Physics:
//!   This module defines how typed retrieval parameters become scene-state
//!   updates and how existing scene values seed the solver when priors are
//!   absent.
//!
//! Vendor:
//!   State-vector layout and scene-update mapping stages.
//!
//! Design:
//!   Keep the typed accessor list separate from the scene mutation logic so
//!   the solver can resolve a stable state order before any values are
//!   clamped or transformed.
//!
//! Invariants:
//!   State-vector length must stay within the fixed accessor capacity and any
//!   scene generated from a solver state must preserve the measured-channel
//!   configuration.
//!
//! Validation:
//!   Retrieval state-access tests cover measured-channel preservation and
//!   canonical target mapping.

const std = @import("std");
const common = @import("contracts.zig");
const Scene = @import("../../model/Scene.zig").Scene;
const StateParameter = @import("../../model/Scene.zig").StateParameter;
const StateTarget = @import("../../model/Scene.zig").StateTarget;
const Allocator = std.mem.Allocator;

pub const MaxStateParameters: usize = 32;

pub const StateAccessor = struct {
    target: StateTarget,
};

pub const ResolvedStateLayout = struct {
    count: usize = 0,
    accessors: [MaxStateParameters]StateAccessor = undefined,

    /// Purpose:
    ///   Return the accessor for a state-vector position.
    pub fn at(self: ResolvedStateLayout, index: usize) StateAccessor {
        std.debug.assert(index < self.count);
        return self.accessors[index];
    }
};

/// Purpose:
///   Resolve the canonical accessors for the retrieval state vector.
pub fn resolveStateLayout(problem: common.RetrievalProblem) common.Error!ResolvedStateLayout {
    const state_count = try validateStateCount(problem);
    var layout: ResolvedStateLayout = .{ .count = state_count };

    for (0..state_count) |index| {
        layout.accessors[index] = resolveStateAccessor(problem, index);
    }
    return layout;
}

/// Purpose:
///   Seed a solver state from the current scene values and priors.
pub fn seedState(allocator: Allocator, problem: common.RetrievalProblem) common.Error![]f64 {
    const layout = try resolveStateLayout(problem);
    return seedStateWithLayout(allocator, problem, layout);
}

/// Purpose:
///   Seed a solver state using a pre-resolved layout.
pub fn seedStateWithLayout(
    allocator: Allocator,
    problem: common.RetrievalProblem,
    layout: ResolvedStateLayout,
) common.Error![]f64 {
    const state_count = try validateStateCount(problem);
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

/// Purpose:
///   Rebuild a scene from a solver-state vector.
pub fn sceneForState(problem: common.RetrievalProblem, state: []const f64) common.Error!Scene {
    const layout = try resolveStateLayout(problem);
    return sceneForStateWithLayout(problem, state, layout);
}

/// Purpose:
///   Rebuild a scene from a solver-state vector and resolved layout.
pub fn sceneForStateWithLayout(
    problem: common.RetrievalProblem,
    state: []const f64,
    layout: ResolvedStateLayout,
) common.Error!Scene {
    const state_count = try validateStateCount(problem);
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

fn validateStateCount(problem: common.RetrievalProblem) common.Error!usize {
    const state_count: usize = @intCast(problem.inverse_problem.state_vector.count());
    if (state_count == 0 or state_count > MaxStateParameters) return error.ShapeMismatch;
    return state_count;
}

fn stateParameter(problem: common.RetrievalProblem, index: usize) ?StateParameter {
    if (problem.inverse_problem.state_vector.parameters.len == 0) return null;
    return problem.inverse_problem.state_vector.parameters[index];
}

fn defaultStateAccessor(index: usize) StateAccessor {
    // DECISION:
    //   Preserve the legacy default ordering only for unconfigured state
    //   vectors; typed parameters take precedence whenever present.
    return switch (index) {
        0 => .{ .target = .surface_albedo },
        1 => .{ .target = .aerosol_optical_depth_550_nm },
        else => .{ .target = .cloud_optical_thickness },
    };
}

fn resolveStateAccessor(problem: common.RetrievalProblem, index: usize) StateAccessor {
    if (stateParameter(problem, index)) |parameter| {
        return .{ .target = parameter.target };
    }
    return defaultStateAccessor(index);
}

fn currentValue(scene: Scene, accessor: StateAccessor) f64 {
    return switch (accessor.target) {
        .unset => unreachable,
        .surface_albedo => scene.surface.albedo,
        .aerosol_optical_depth_550_nm => scene.aerosol.optical_depth,
        .aerosol_layer_center_km => scene.aerosol.layer_center_km,
        .aerosol_layer_width_km => scene.aerosol.layer_width_km,
        .cloud_optical_thickness => scene.cloud.optical_thickness,
        .wavelength_shift_nm => scene.observation_model.wavelength_shift_nm,
        .multiplicative_offset => scene.observation_model.multiplicative_offset,
        .stray_light => scene.observation_model.stray_light,
        // ISSUE:
        //   Some vendor targets still fall back to placeholder scene fields
        //   until the retrieval-parity work package wires the full mapping.
        .cloud_top_pressure => scene.cloud.top_altitude_km,
        .absorber_column_amount => 0.0,
        .temperature_shift => 0.0,
    };
}

fn applyAccessor(scene: *Scene, accessor: StateAccessor, value: f64) void {
    switch (accessor.target) {
        .unset => unreachable,
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
        // ISSUE:
        //   Some vendor targets still fall back to placeholder scene fields
        //   until the retrieval-parity work package wires the full mapping.
        .cloud_top_pressure => {
            scene.cloud.enabled = true;
            scene.atmosphere.has_clouds = true;
            scene.cloud.top_altitude_km = @max(value, 0.0);
        },
        .absorber_column_amount => {},
        .temperature_shift => {},
    }
}

fn sceneWithDefaults(base: Scene) Scene {
    var scene = base;
    if (scene.id.len == 0) scene.id = "retrieval-synthetic";
    if (scene.spectral_grid.sample_count < 8 and scene.observation_model.measured_wavelengths_nm.len == 0) {
        scene.spectral_grid.sample_count = 8;
    }
    if (scene.spectral_grid.end_nm <= scene.spectral_grid.start_nm) {
        scene.spectral_grid.start_nm = 405.0;
        scene.spectral_grid.end_nm = 465.0;
    }
    if (scene.atmosphere.layer_count == 0) scene.atmosphere.layer_count = 24;
    if (scene.observation_model.instrument == .unset) scene.observation_model.instrument = .{ .custom = "retrieval-synthetic" };
    if (scene.observation_model.multiplicative_offset <= 0.0) scene.observation_model.multiplicative_offset = 1.0;
    return scene;
}

fn clampStateValue(parameter: StateParameter, value: f64) f64 {
    if (!parameter.bounds.enabled) return value;
    return std.math.clamp(value, parameter.bounds.min, parameter.bounds.max);
}

test "state access preserves explicit measured-channel axes" {
    const measured_wavelengths = [_]f64{ 405.0, 406.0 };
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "",
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 406.0,
                .sample_count = 2,
            },
            .observation_model = .{
                .instrument = .tropomi,
                .sampling = .measured_channels,
                .measured_wavelengths_nm = &measured_wavelengths,
            },
        },
        .inverse_problem = .{
            .id = "state-access",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 2,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    const state = try seedState(std.testing.allocator, problem);
    defer std.testing.allocator.free(state);
    const scene = try sceneForState(problem, state);

    try std.testing.expectEqual(@as(u32, 2), scene.spectral_grid.sample_count);
    try std.testing.expectEqual(@as(usize, 2), scene.observation_model.measured_wavelengths_nm.len);
    try scene.validate();
}

test "state access applies canonical typed targets without string heuristics" {
    const problem: common.RetrievalProblem = .{
        .scene = .{
            .id = "state-access-scene",
            .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .observation_model = .{ .instrument = .synthetic, .regime = .nadir },
        },
        .inverse_problem = .{
            .id = "state-access-inverse",
            .state_vector = .{
                .parameters = &[_]StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .prior = .{ .enabled = true, .mean = 0.08, .sigma = 0.02 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.05 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.02 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 32,
            },
        },
        .derivative_mode = .semi_analytical,
        .jacobians_requested = true,
    };

    const layout = try resolveStateLayout(problem);
    try std.testing.expectEqual(@as(usize, 3), layout.count);
    try std.testing.expectEqual(StateTarget.surface_albedo, layout.at(0).target);
    try std.testing.expectEqual(StateTarget.aerosol_optical_depth_550_nm, layout.at(1).target);
    try std.testing.expectEqual(StateTarget.wavelength_shift_nm, layout.at(2).target);

    const seeded = try seedStateWithLayout(std.testing.allocator, problem, layout);
    defer std.testing.allocator.free(seeded);

    const scene = try sceneForStateWithLayout(problem, &.{ 0.12, 0.09, 0.01 }, layout);
    try std.testing.expect(scene.aerosol.enabled);
    try std.testing.expect(scene.observation_model.wavelength_shift_nm != 0.0);
}
