const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");
const o2a_scene = @import("support/o2a_scene.zig");

test "runForwardWithSessionMemory reuses profile-line rows across repeated scene runs" {
    if (builtin.mode == .Debug) return error.SkipZigTest;
    if (!std.process.hasEnvVarConstant("ZDISAMAR_RUN_ROOT_SESSION_PARITY")) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const zdisamar = internal.public;

    var scene = o2a_scene.reference();
    scene.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 760.0,
        .sample_count = 2,
    };

    var prepared = try zdisamar.prepare(allocator, scene);
    defer prepared.deinit(allocator);
    var session = zdisamar.initSessionMemory(allocator);
    defer session.deinit(allocator);

    const solve_config = zdisamar.SolveConfig{
        .derivative_mode = .none,
        .wants_jacobian = false,
        .controls = .{
            .scattering = .none,
            .n_streams = @intCast(scene.rtm.stream_count),
            .integrate_source_function = false,
        },
    };

    var first = try zdisamar.runForwardWithSessionMemory(
        allocator,
        &session,
        &prepared,
        solve_config,
    );
    defer first.deinit(allocator);
    const support_profile_sigma_ptr = session.profile_lines.support_profile_total_sigma_cm2_per_molecule.ptr;
    const dense_radiance_ptr = session.radiance.radiance.ptr;
    const dense_radiance_stamp = session.radiance.result_stamp;
    try std.testing.expect(dense_radiance_stamp.value != 0);
    try std.testing.expectEqual(@as(usize, 0), session.profile_lines.profile_node_count);
    try std.testing.expectEqual(@as(usize, 0), session.profile_lines.values.len);
    try std.testing.expect(session.profile_lines.support_profile_total_sigma_cm2_per_molecule.len != 0);

    var second = try zdisamar.runForwardWithSessionMemory(
        allocator,
        &session,
        &prepared,
        solve_config,
    );
    defer second.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), first.spectrum.sampleCount());
    try std.testing.expectEqual(first.spectrum.sampleCount(), second.spectrum.sampleCount());
    try std.testing.expectEqual(@as(usize, 0), session.profile_lines.values.len);
    try std.testing.expect(
        session.profile_lines.support_profile_total_sigma_cm2_per_molecule.ptr == support_profile_sigma_ptr,
    );
    try std.testing.expect(session.radiance.radiance.ptr == dense_radiance_ptr);
    try std.testing.expect(session.radiance.result_stamp.eql(dense_radiance_stamp));

    for (
        first.spectrum.wavelength_nm,
        first.spectrum.radiance,
        first.spectrum.irradiance,
        first.spectrum.reflectance,
        second.spectrum.radiance,
        second.spectrum.irradiance,
        second.spectrum.reflectance,
    ) |
        wavelength_nm,
        first_radiance,
        first_irradiance,
        first_reflectance,
        second_radiance,
        second_irradiance,
        second_reflectance,
    | {
        try std.testing.expect(std.math.isFinite(wavelength_nm));
        try std.testing.expect(std.math.isFinite(first_radiance));
        try std.testing.expect(std.math.isFinite(first_irradiance));
        try std.testing.expect(std.math.isFinite(first_reflectance));
        try std.testing.expectApproxEqAbs(first_radiance, second_radiance, 0.0);
        try std.testing.expectApproxEqAbs(first_irradiance, second_irradiance, 0.0);
        try std.testing.expectApproxEqAbs(first_reflectance, second_reflectance, 0.0);
    }
}
