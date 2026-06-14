const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

test {
    _ = @import("input/scene_test.zig");
    _ = @import("input/hitran_partition_tables_test.zig");
    _ = @import("assets/readers_test.zig");
    _ = @import("common/units_test.zig");
    _ = @import("common/memory_test.zig");
    _ = @import("common/worker_partition_test.zig");
    _ = @import("common/math/gauss_legendre_test.zig");
    _ = @import("common/math/spline_test.zig");
    _ = @import("setup/run_tables_test.zig");
    _ = @import("setup/phase_table_test.zig");
    _ = @import("cache/forward_worker_pool_test.zig");
    _ = @import("cache/session_memory_test.zig");
    _ = @import("cache/profile_line_memory_test.zig");
    _ = @import("cache/radiance_memory_test.zig");
    _ = @import("cache/solar_irradiance_memory_test.zig");
    _ = @import("cache/spectrum_memory_test.zig");
    _ = @import("cache/transport_worker_memory_test.zig");
    _ = @import("optics/curved_sun_path_test.zig");
    _ = @import("optics/layer_depths_test.zig");
    _ = @import("optics/source_levels_test.zig");
    _ = @import("rtm/attenuation_test.zig");
    _ = @import("rtm/controls_test.zig");
    _ = @import("rtm/gauss_angles_test.zig");
    _ = @import("rtm/jacobian_states_test.zig");
    _ = @import("rtm/layer_reflect_transmit_test.zig");
    _ = @import("rtm/matrix_12x10_test.zig");
    _ = @import("rtm/phase_basis_test.zig");
    _ = @import("instrumentation/cost_timing_test.zig");
    _ = @import("rtm/reflectance_test.zig");
    _ = @import("rtm/rows_test.zig");
    _ = @import("rtm/scattering_orders_test.zig");
    _ = @import("rtm/solve_test.zig");
    _ = @import("spectrum/instrument_average_test.zig");
    _ = @import("spectrum/radiance_results_test.zig");
    _ = @import("spectrum/radiance_wavelengths_test.zig");
    _ = @import("spectrum/sampling_table_test.zig");
    _ = @import("spectrum/solar_lookup_test.zig");
    _ = @import("spectrum/spectrum_run_test.zig");
    _ = @import("output/atmospheric_budget_test.zig");
    _ = @import("output/instrument_response_test.zig");
    _ = @import("output/line_contributions_test.zig");
    _ = @import("output/cia_diagnostics_test.zig");
    _ = @import("retrieval/root_test.zig");
    _ = @import("validation/band_metrics_test.zig");
    _ = @import("instrumentation/facades_test.zig");
}

test "public root exposes setup session and spectrum surface" {
    const zdisamar = internal.public;

    try std.testing.expect(@hasDecl(zdisamar, "Scene"));
    try std.testing.expect(@hasDecl(zdisamar, "RunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "ProfileLineValues"));
    try std.testing.expect(@hasDecl(zdisamar, "SessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "AtmosphericBudget"));
    try std.testing.expect(@hasDecl(zdisamar, "AtmosphericBudgetRow"));
    try std.testing.expect(@hasDecl(zdisamar, "InstrumentResponse"));
    try std.testing.expect(@hasDecl(zdisamar, "InstrumentResponseRow"));
    try std.testing.expect(@hasDecl(zdisamar, "LineContributions"));
    try std.testing.expect(@hasDecl(zdisamar, "LineContributionRow"));
    try std.testing.expect(@hasDecl(zdisamar, "CiaDiagnostics"));
    try std.testing.expect(@hasDecl(zdisamar, "CiaRow"));
    try std.testing.expect(@hasDecl(zdisamar, "Spectrum"));
    try std.testing.expect(@hasDecl(zdisamar, "SpectrumRunResult"));
    try std.testing.expect(@hasDecl(zdisamar, "optimal_estimation"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalStateSpec"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalPressureAltitudeProfile"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalResult"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalBatchResult"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalFastmodeBatchResult"));
    try std.testing.expect(@hasDecl(zdisamar, "defaultScene"));
    try std.testing.expect(@hasDecl(zdisamar, "prepare"));
    try std.testing.expect(@hasDecl(zdisamar, "initSessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "warmSessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "runForwardWithSessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "runForward"));
    try std.testing.expect(@hasDecl(zdisamar, "buildRunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "buildProfileLineValues"));
    try std.testing.expect(@hasDecl(zdisamar, "buildAtmosphericBudget"));
    try std.testing.expect(@hasDecl(zdisamar, "buildInstrumentResponse"));
    try std.testing.expect(@hasDecl(zdisamar, "buildLineContributions"));
    try std.testing.expect(@hasDecl(zdisamar, "buildCiaDiagnostics"));

    try std.testing.expect(!@hasDecl(zdisamar, "Case"));
    try std.testing.expect(!@hasDecl(zdisamar, "PreparedOpticalState"));
    try std.testing.expect(!@hasDecl(zdisamar, "Context"));
    try std.testing.expect(!@hasDecl(zdisamar, "zds_context_create"));
}

test "public O2 A root surface keeps route-only spectrum knobs internal" {
    const zdisamar = internal.public;

    // Source: canonical O2 A evidence fixtures owned by this repository.
    // Canonical expected values owned by this repository.
    // integrated irradiance rows. `python-reference-case-native.json` exposes no calibration, slit-kernel,
    // radiance-integration, or irradiance-integration override keys, so the root call keeps those six
    // `runForwardSpectrum` arguments as fixed route constants rather than public case fields.
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceRunTables"));
    try std.testing.expect(!@hasDecl(zdisamar, "deinitReferenceRunTables"));
    try std.testing.expect(!@hasDecl(zdisamar, "deinitRunTables"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceProfileLineValues"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceSpectrumSamplingTable"));
    try std.testing.expect(!@hasDecl(zdisamar, "parseReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "parseReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "renderDefaultReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "renderDefaultReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "ParsedReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "ParsedReferenceSceneJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "runReferenceSpectrumSingleWorker"));
    try std.testing.expect(!@hasDecl(zdisamar, "runReferenceSpectrum"));
    try std.testing.expect(!@hasDecl(zdisamar, "runForwardSpectrum"));

    const scene = zdisamar.defaultScene();
    const Scene = @TypeOf(scene);
    const Observation = @TypeOf(scene.observation);
    try std.testing.expect(!@hasField(Scene, "radiance_calibration"));
    try std.testing.expect(!@hasField(Scene, "irradiance_calibration"));
    try std.testing.expect(!@hasField(Scene, "radiance_slit_kernel"));
    try std.testing.expect(!@hasField(Scene, "irradiance_slit_kernel"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_radiance_sampling"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_irradiance_sampling"));
}

test "runForwardWithSessionMemory reuses profile-line rows across repeated scene runs" {
    if (builtin.mode == .Debug) return error.SkipZigTest;
    if (!std.process.hasEnvVarConstant("ZDISAMAR_RUN_ROOT_SESSION_PARITY")) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const zdisamar = internal.public;

    var scene = zdisamar.defaultScene();
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
        .derivative_state_mask = 0,
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
