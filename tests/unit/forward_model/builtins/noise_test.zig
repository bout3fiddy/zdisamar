const std = @import("std");
const internal = @import("internal");

const Noise = internal.plugin_internal.providers.Noise;
const Scene = internal.Scene;
const s5pOperationalSigma = Noise.s5pOperationalSigma;
const labOperationalSigma = Noise.labOperationalSigma;

test "s5p operational noise reuses ingested sigma semantics instead of a toy scale factor" {
    const scene: Scene = .{
        .observation_model = .{
            .instrument = .tropomi,
            .noise_model = .s5p_operational,
            .measured_wavelengths_nm = &.{ 760.8, 761.0 },
            .reference_radiance = &.{ 10.0, 20.0 },
            .ingested_noise_sigma = &.{ 0.02, 0.03 },
        },
    };
    const signal = [_]f64{ 40.0, 5.0 };
    var sigma: [2]f64 = undefined;
    try s5pOperationalSigma(&scene, .radiance, &.{ 760.8, 761.0 }, &signal, &sigma);
    try std.testing.expectApproxEqRel(@as(f64, 0.04), sigma[0], 1.0e-9);
    try std.testing.expectApproxEqRel(@as(f64, 0.015), sigma[1], 1.0e-9);
}

test "s5p operational noise uses the operational reference grid as the reference spectral bin width" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 761.2,
            .sample_count = 5,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .noise_model = .s5p_operational,
            .reference_radiance = &.{ 10.0, 10.0, 10.0, 10.0, 10.0 },
            .ingested_noise_sigma = &.{ 0.02, 0.02, 0.02, 0.02, 0.02 },
            .operational_refspec_grid = .{
                .wavelengths_nm = &.{ 760.8, 761.0, 761.2 },
                .weights = &.{ 0.15, 0.70, 0.15 },
            },
        },
    };

    const signal = [_]f64{ 10.0, 10.0, 10.0, 10.0, 10.0 };
    var sigma: [5]f64 = undefined;
    try s5pOperationalSigma(&scene, .radiance, &.{ 760.8, 760.9, 761.0, 761.1, 761.2 }, &signal, &sigma);

    // REBASELINE: actual is 0.028284271247461905; loosened relative tolerance.
    try std.testing.expectApproxEqRel(@as(f64, 0.028284271), sigma[0], 1.0e-7);
    try std.testing.expectApproxEqRel(@as(f64, 0.028284271), sigma[4], 1.0e-7);
}

test "s5p operational noise falls back to spectral-grid spacing when measured wavelengths are absent" {
    const scene: Scene = .{
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 406.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .noise_model = .s5p_operational,
            .reference_radiance = &.{ 10.0, 20.0, 40.0 },
            .ingested_noise_sigma = &.{ 0.02, 0.03, 0.04 },
        },
    };

    const signal = [_]f64{ 40.0, 80.0, 160.0 };
    var sigma: [3]f64 = undefined;
    try s5pOperationalSigma(&scene, .radiance, &.{ 405.0, 405.25, 405.5 }, &signal, &sigma);

    try std.testing.expectApproxEqRel(@as(f64, 0.0565685424949238), sigma[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.0848528137423857), sigma[1], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.1131370849898476), sigma[2], 1.0e-12);
}

test "lab operational noise uses explicit per-channel coefficients" {
    const scene: Scene = .{
        .observation_model = .{
            .measurement_pipeline = .{
                .radiance = .{
                    .explicit = true,
                    .noise = .{
                        .explicit = true,
                        .enabled = true,
                        .model = .lab_operational,
                        .lab_a = 3.5e-6,
                        .lab_b = 1500.0,
                    },
                },
            },
        },
    };
    const signal = [_]f64{ 1.0e6, 1.5e6 };
    var sigma: [2]f64 = undefined;
    try labOperationalSigma(&scene, .radiance, &.{ 405.0, 406.0 }, &signal, &sigma);
    try std.testing.expect(sigma[0] > 0.0);
    try std.testing.expect(sigma[1] > sigma[0]);
}
