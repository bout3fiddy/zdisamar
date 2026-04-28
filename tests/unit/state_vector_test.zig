const std = @import("std");
const internal = @import("internal");

const state_vector = internal.state_vector;
const StateVector = state_vector.StateVector;
const Parameter = state_vector.Parameter;
const Target = state_vector.Target;
const errors = internal.core.errors;

test "state vector accepts canonical parameter descriptors" {
    const vector: StateVector = .{
        .parameters = &[_]Parameter{
            .{
                .name = "surface_albedo",
                .target = .surface_albedo,
                .transform = .logit,
                .prior = .{ .enabled = true, .mean = 0.04, .sigma = 0.02 },
                .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 },
            },
            .{
                .name = "aerosol_tau",
                .target = .aerosol_optical_depth_550_nm,
                .transform = .log,
                .prior = .{ .enabled = true, .mean = 0.10, .sigma = 0.10 },
                .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 5.0 },
            },
        },
    };

    try vector.validate();
    try std.testing.expectEqual(@as(u32, 2), vector.count());
}

test "state targets parse canonical labels and reject unknown labels" {
    try std.testing.expectEqual(Target.surface_albedo, try Target.parse("scene.surface.albedo"));
    try std.testing.expectEqualStrings(
        "scene.aerosols.plume.layer_center_km",
        Target.aerosol_layer_center_km.label(),
    );
    try std.testing.expectError(errors.Error.InvalidRequest, Target.parse("scene.unknown.target"));
}

test "state vector rejects parsed-but-unwired retrieval targets" {
    const unsupported_targets = [_]Target{
        .absorber_column_amount,
        .temperature_shift,
        .cloud_top_pressure,
    };
    for (unsupported_targets) |target| {
        const vector: StateVector = .{
            .parameters = &[_]Parameter{
                .{
                    .name = "unsupported_target",
                    .target = target,
                    .prior = .{ .enabled = true, .mean = 1.0, .sigma = 0.1 },
                },
            },
        };

        try std.testing.expectError(errors.Error.InvalidRequest, vector.validate());
    }
}
