const std = @import("std");
const internal = @import("internal");
const o2a_scene = @import("support/o2a_scene.zig");

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
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalState"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalStateScalar"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalPressureLayerPlacement"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalPressureAltitudeProfile"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalResult"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalBatchResult"));
    try std.testing.expect(@hasDecl(zdisamar, "RetrievalFastmodeBatchResult"));
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

test "public root surface keeps route-only spectrum knobs internal" {
    const zdisamar = internal.public;

    // Source: canonical evidence fixtures owned by this repository.
    // Canonical expected values owned by this repository.
    // integrated irradiance rows. `python-reference-case-native.json` exposes no calibration, slit-kernel,
    // radiance-integration, or irradiance-integration override keys, so the root call keeps those six
    // `runForwardSpectrum` arguments as fixed route constants rather than public scene fields.
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

    const scene = o2a_scene.reference();
    const Scene = @TypeOf(scene);
    const Observation = @TypeOf(scene.observation);
    try std.testing.expect(!@hasField(Scene, "radiance_calibration"));
    try std.testing.expect(!@hasField(Scene, "irradiance_calibration"));
    try std.testing.expect(!@hasField(Scene, "radiance_slit_kernel"));
    try std.testing.expect(!@hasField(Scene, "irradiance_slit_kernel"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_radiance_sampling"));
    try std.testing.expect(!@hasField(Observation, "uses_integrated_irradiance_sampling"));
}
