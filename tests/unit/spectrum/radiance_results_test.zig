const std = @import("std");

const internal = @import("internal");

const controls = internal.rtm.controls;
const jacobian_states = internal.rtm.jacobian_states;
const radiance_results = internal.spectrum.radiance_results;
const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const sampling_table = internal.spectrum.sampling_table;
const solve = internal.rtm.solve;

test "scaleReflectanceToRadiance applies solar radiance scale and active Jacobian lanes" {
    const mask = jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa);
    const reflectance = solve.ReflectanceResult{
        .reflectance = 0.42,
        .jacobian = .{ 0.1, 0.2 },
    };
    const solar_cosine = 0.5;
    const solar_irradiance = 12.0;

    const actual = radiance_results.scaleReflectanceToRadiance(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = mask,
        },
        reflectance,
        solar_cosine,
        solar_irradiance,
    );

    const scale = solar_cosine * solar_irradiance / std.math.pi;
    try std.testing.expectApproxEqAbs(0.42 * scale, actual.radiance, 1.0e-15);
    try std.testing.expectApproxEqAbs(0.0, actual.jacobian[0], 0.0);
    try std.testing.expectApproxEqAbs(0.2 * scale, actual.jacobian[1], 1.0e-15);
}

test "scaleReflectanceToRadiance zeros Jacobian when derivative mode is off" {
    const actual = radiance_results.scaleReflectanceToRadiance(
        .{
            .derivative_mode = .none,
            .derivative_state_mask = jacobian_states.all_states_mask,
        },
        .{
            .reflectance = 0.25,
            .jacobian = .{ 1.0, 2.0 },
        },
        0.5,
        8.0,
    );

    try std.testing.expectApproxEqAbs(0.25 * 0.5 * 8.0 / std.math.pi, actual.radiance, 1.0e-15);
    try std.testing.expectEqual(jacobian_states.zero(), actual.jacobian);
}

test "integratePrefetchedRadianceAtNominal returns direct prefetched row" {
    var radiance = [_]f64{ 1.25, 2.5 };
    var jacobian = [_]jacobian_states.Vector{ .{ 0.1, 0.2 }, .{ 0.4, 0.5 } };
    const sample_indices = [_]u32{1};
    const actual = try radiance_results.integratePrefetchedRadianceAtNominal(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = jacobian_states.all_states_mask,
        },
        .{ .radiance = radiance[0..], .jacobian = jacobian[0..] },
        .{ .start = 0 },
        sample_indices[0..],
        &sampling_table.IntegrationKernelRef.disabled(),
        .{},
    );

    try std.testing.expectApproxEqAbs(2.5, actual.radiance, 0.0);
    try std.testing.expectApproxEqAbs(0.4, actual.jacobian[0], 0.0);
    try std.testing.expectApproxEqAbs(0.5, actual.jacobian[1], 0.0);
}

test "integratePrefetchedRadianceAtNominal weights radiance and active Jacobian lanes" {
    var radiance = [_]f64{ 10.0, 20.0, 40.0 };
    var jacobian = [_]jacobian_states.Vector{ .{ 1.0, 100.0 }, .{ 2.0, 200.0 }, .{ 4.0, 400.0 } };
    const sample_indices = [_]u32{ 2, 0, 1 };
    const weights = [_]f64{ 0.25, 0.5, 0.25 };
    const offsets = [_]f64{ -0.01, 0.0, 0.01 };
    const integration = sampling_table.IntegrationKernelRef{
        .side_start = 0,
        .sample_count = 3,
        .encoding = .side_samples,
    };
    const mask = jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa);

    const actual = try radiance_results.integratePrefetchedRadianceAtNominal(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = mask,
        },
        .{ .radiance = radiance[0..], .jacobian = jacobian[0..] },
        .{ .start = 0 },
        sample_indices[0..],
        &integration,
        .{
            .offsets_nm = offsets[0..],
            .weights = weights[0..],
        },
    );

    try std.testing.expectApproxEqAbs(20.0, actual.radiance, 0.0);
    try std.testing.expectApproxEqAbs(0.0, actual.jacobian[0], 0.0);
    try std.testing.expectApproxEqAbs(200.0, actual.jacobian[1], 0.0);
}

test "integratePrefetchedRadianceAtNominal omits Jacobian when derivative mode is off" {
    var radiance = [_]f64{ 1.0, 3.0 };
    const sample_indices = [_]u32{ 0, 1 };
    const weights = [_]f64{ 0.25, 0.75 };
    const offsets = [_]f64{ 0.0, 0.01 };
    const integration = sampling_table.IntegrationKernelRef{
        .side_start = 0,
        .sample_count = 2,
        .encoding = .side_samples,
    };
    const actual = try radiance_results.integratePrefetchedRadianceAtNominal(
        controls.SolveConfig{
            .derivative_mode = .none,
            .derivative_state_mask = jacobian_states.all_states_mask,
        },
        .{ .radiance = radiance[0..] },
        .{ .start = 0 },
        sample_indices[0..],
        &integration,
        .{
            .offsets_nm = offsets[0..],
            .weights = weights[0..],
        },
    );

    try std.testing.expectApproxEqAbs(2.5, actual.radiance, 0.0);
    try std.testing.expectEqual(jacobian_states.zero(), actual.jacobian);
}

test "integratePrefetchedRadianceAtNominal rejects mismatched sample indexes" {
    var radiance = [_]f64{1.0};
    const sample_indices = [_]u32{0};
    const integration = sampling_table.IntegrationKernelRef{
        .sample_count = 2,
        .encoding = .inline_samples,
    };

    try std.testing.expectError(
        error.ShapeMismatch,
        radiance_results.integratePrefetchedRadianceAtNominal(
            .{},
            .{ .radiance = radiance[0..] },
            radiance_wavelengths.RadianceSampleIndexRef{ .start = 0 },
            sample_indices[0..],
            &integration,
            .{},
        ),
    );
}

test "integratePrefetchedRadianceAtNominal rejects missing Jacobian storage when active" {
    var radiance = [_]f64{1.0};
    const sample_indices = [_]u32{0};

    try std.testing.expectError(
        error.ShapeMismatch,
        radiance_results.integratePrefetchedRadianceAtNominal(
            .{
                .derivative_mode = .semi_analytical,
                .derivative_state_mask = jacobian_states.all_states_mask,
            },
            .{ .radiance = radiance[0..] },
            radiance_wavelengths.RadianceSampleIndexRef{ .start = 0 },
            sample_indices[0..],
            &sampling_table.IntegrationKernelRef.disabled(),
            .{},
        ),
    );
}
