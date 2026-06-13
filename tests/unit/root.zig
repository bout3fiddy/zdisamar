const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

test {
    _ = @import("input/o2_case_test.zig");
    _ = @import("input/hitran_partition_tables_test.zig");
    _ = @import("assets/readers_test.zig");
    _ = @import("common/units_test.zig");
    _ = @import("common/memory_test.zig");
    _ = @import("common/worker_partition_test.zig");
    _ = @import("common/math/gauss_legendre_test.zig");
    _ = @import("common/math/spline_test.zig");
    _ = @import("setup/o2_run_tables_test.zig");
    _ = @import("setup/phase_table_test.zig");
    _ = @import("cache/forward_worker_pool_test.zig");
    _ = @import("cache/o2_session_memory_test.zig");
    _ = @import("cache/profile_line_memory_test.zig");
    _ = @import("cache/radiance_memory_test.zig");
    _ = @import("cache/solar_irradiance_memory_test.zig");
    _ = @import("cache/spectrum_memory_test.zig");
    _ = @import("cache/transport_worker_memory_test.zig");
    _ = @import("optics/curved_sun_path_test.zig");
    _ = @import("optics/layer_depths_test.zig");
    _ = @import("optics/source_levels_test.zig");
    _ = @import("transport/attenuation_test.zig");
    _ = @import("transport/controls_test.zig");
    _ = @import("transport/gauss_angles_test.zig");
    _ = @import("transport/jacobian_states_test.zig");
    _ = @import("transport/layer_reflect_transmit_test.zig");
    _ = @import("transport/matrix_12x10_test.zig");
    _ = @import("transport/phase_basis_test.zig");
    _ = @import("transport/phase_timing_test.zig");
    _ = @import("transport/reflectance_test.zig");
    _ = @import("transport/rows_test.zig");
    _ = @import("transport/scattering_orders_test.zig");
    _ = @import("transport/solve_test.zig");
    _ = @import("spectrum/instrument_average_test.zig");
    _ = @import("spectrum/radiance_results_test.zig");
    _ = @import("spectrum/radiance_wavelengths_test.zig");
    _ = @import("spectrum/sampling_table_test.zig");
    _ = @import("spectrum/solar_lookup_test.zig");
    _ = @import("spectrum/spectrum_run_test.zig");
    _ = @import("output/atmospheric_budget_test.zig");
    _ = @import("output/instrument_response_test.zig");
    _ = @import("output/o2_line_contributions_test.zig");
    _ = @import("output/o2_o2_cia_test.zig");
    _ = @import("validation/o2a_band_metrics_test.zig");
    _ = @import("instrumentation/facades_test.zig");
}

test "public root exposes setup session and spectrum surface" {
    const zdisamar = internal.public;

    try std.testing.expect(@hasDecl(zdisamar, "O2Case"));
    try std.testing.expect(@hasDecl(zdisamar, "O2RunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "ProfileLineValues"));
    try std.testing.expect(@hasDecl(zdisamar, "O2SessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "AtmosphericBudget"));
    try std.testing.expect(@hasDecl(zdisamar, "AtmosphericBudgetRow"));
    try std.testing.expect(@hasDecl(zdisamar, "InstrumentResponse"));
    try std.testing.expect(@hasDecl(zdisamar, "InstrumentResponseRow"));
    try std.testing.expect(@hasDecl(zdisamar, "O2LineContributions"));
    try std.testing.expect(@hasDecl(zdisamar, "O2LineContributionRow"));
    try std.testing.expect(@hasDecl(zdisamar, "O2O2CIADiagnostics"));
    try std.testing.expect(@hasDecl(zdisamar, "O2O2CIARow"));
    try std.testing.expect(@hasDecl(zdisamar, "O2Spectrum"));
    try std.testing.expect(@hasDecl(zdisamar, "O2SpectrumRunResult"));
    try std.testing.expect(@hasDecl(zdisamar, "defaultO2Case"));
    try std.testing.expect(@hasDecl(zdisamar, "prepareO2A"));
    try std.testing.expect(@hasDecl(zdisamar, "initO2SessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "warmO2ASessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "runO2AWithSessionMemory"));
    try std.testing.expect(@hasDecl(zdisamar, "runO2A"));
    try std.testing.expect(@hasDecl(zdisamar, "buildO2RunTables"));
    try std.testing.expect(@hasDecl(zdisamar, "buildO2ProfileLineValues"));
    try std.testing.expect(@hasDecl(zdisamar, "buildAtmosphericBudget"));
    try std.testing.expect(@hasDecl(zdisamar, "buildInstrumentResponse"));
    try std.testing.expect(@hasDecl(zdisamar, "buildO2LineContributions"));
    try std.testing.expect(@hasDecl(zdisamar, "buildO2O2CIADiagnostics"));

    try std.testing.expect(!@hasDecl(zdisamar, "Scene"));
    try std.testing.expect(!@hasDecl(zdisamar, "PreparedOpticalState"));
    try std.testing.expect(!@hasDecl(zdisamar, "ProductStorage"));
    try std.testing.expect(!@hasDecl(zdisamar, "Context"));
    try std.testing.expect(!@hasDecl(zdisamar, "zds_context_create"));
}

test "public O2 A root surface keeps route-only spectrum knobs internal" {
    const zdisamar = internal.public;

    // Source: WP1 evidence under scratch/refactor/2026-06-11-explicit-dataflow-refactor/evidence/.
    // `baseline-main-56605387/internal-dump-baseline.json` pins 701 integrated radiance rows and 701
    // integrated irradiance rows. `python-reference-case-native.json` exposes no calibration, slit-kernel,
    // radiance-integration, or irradiance-integration override keys, so the root call keeps those six
    // `runO2ASpectrum` arguments as fixed route constants rather than public case fields.
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceO2RunTables"));
    try std.testing.expect(!@hasDecl(zdisamar, "deinitReferenceO2RunTables"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceProfileLineValues"));
    try std.testing.expect(!@hasDecl(zdisamar, "buildReferenceSpectrumSamplingTable"));
    try std.testing.expect(!@hasDecl(zdisamar, "parseReferenceCaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "parseReferenceO2CaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "renderDefaultReferenceCaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "renderDefaultReferenceO2CaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "ParsedReferenceCaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "ParsedReferenceO2CaseJson"));
    try std.testing.expect(!@hasDecl(zdisamar, "runReferenceSpectrumSingleWorker"));
    try std.testing.expect(!@hasDecl(zdisamar, "runReferenceSpectrum"));
    try std.testing.expect(!@hasDecl(zdisamar, "runO2ASpectrum"));

    const case = zdisamar.defaultO2Case();
    const Case = @TypeOf(case);
    const Observation = @TypeOf(case.observation);
    try std.testing.expect(!@hasField(Case, "radiance_calibration"));
    try std.testing.expect(!@hasField(Case, "irradiance_calibration"));
    try std.testing.expect(!@hasField(Case, "radiance_slit_kernel"));
    try std.testing.expect(!@hasField(Case, "irradiance_slit_kernel"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_radiance_sampling"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_irradiance_sampling"));
}

test "runO2AWithSessionMemory reuses profile-line rows across repeated case runs" {
    if (builtin.mode == .Debug) return error.SkipZigTest;
    if (!std.process.hasEnvVarConstant("ZDISAMAR_RUN_ROOT_SESSION_PARITY")) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const zdisamar = internal.public;
    const jacobian_states = internal.transport.jacobian_states;

    var case = zdisamar.defaultO2Case();
    case.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 760.0,
        .sample_count = 2,
    };

    var prepared = try zdisamar.prepareO2A(allocator, case);
    defer prepared.deinit(allocator);
    var session = zdisamar.initO2SessionMemory(allocator);
    defer session.deinit(allocator);

    const solve_config = zdisamar.SolveConfig{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.surface_albedo),
        .controls = .{
            .scattering = .none,
            .n_streams = @intCast(case.rtm.stream_count),
            .integrate_source_function = false,
        },
    };

    var first = try zdisamar.runO2AWithSessionMemory(
        allocator,
        &session,
        &prepared,
        solve_config,
    );
    defer first.deinit(allocator);
    const profile_values_ptr = session.profile_lines.values.ptr;
    const support_profile_values_ptr = session.profile_lines.support_profile_values.ptr;

    var second = try zdisamar.runO2AWithSessionMemory(
        allocator,
        &session,
        &prepared,
        solve_config,
    );
    defer second.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), first.spectrum.sampleCount());
    try std.testing.expectEqual(first.spectrum.sampleCount(), second.spectrum.sampleCount());
    try std.testing.expect(session.profile_lines.values.ptr == profile_values_ptr);
    try std.testing.expect(session.profile_lines.support_profile_values.ptr == support_profile_values_ptr);

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
