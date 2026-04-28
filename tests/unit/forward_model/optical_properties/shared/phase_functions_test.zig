const std = @import("std");
const internal = @import("internal");

const phase_functions = internal.forward_model.optical_properties.shared.phase_functions;
const Scene = internal.Scene;
const hgPhaseCoefficients = phase_functions.hgPhaseCoefficients;
const gasPhaseCoefficientsAtWavelength = phase_functions.gasPhaseCoefficientsAtWavelength;
const computeLayerDepolarization = phase_functions.computeLayerDepolarization;
const maxPhaseCoefficientIndex = phase_functions.maxPhaseCoefficientIndex;

test "layer depolarization uses already-fraction-scaled particle taus" {
    const scene: Scene = .{
        .aerosol = .{
            .enabled = true,
            .asymmetry_factor = 0.70,
            .fraction = .{
                .enabled = true,
                .target = .aerosol,
                .kind = .wavel_independent,
                .values = &.{0.25},
            },
        },
        .cloud = .{
            .enabled = true,
            .asymmetry_factor = 0.85,
            .fraction = .{
                .enabled = true,
                .target = .cloud,
                .kind = .wavel_independent,
                .values = &.{0.50},
            },
        },
    };

    const depolarization = computeLayerDepolarization(&scene, 0.60, 0.20, 0.20);
    const expected =
        0.60 * 0.0279 +
        0.20 * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor)) +
        0.20 * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor));

    try std.testing.expectApproxEqRel(expected, depolarization, 1.0e-12);
}

test "analytic HG phase coefficients follow vendor normalization" {
    const coefficients = hgPhaseCoefficients(0.7);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), coefficients[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0 * 0.7), coefficients[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 5.0 * 0.7 * 0.7), coefficients[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 7.0 * 0.7 * 0.7 * 0.7), coefficients[3], 1.0e-12);
}

test "scalar Rayleigh phase coefficient follows vendor depolarization formula" {
    const coefficients = gasPhaseCoefficientsAtWavelength(761.75);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), coefficients[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), coefficients[1], 1.0e-12);
    // Tolerance loosened from 1e-15: the original inline test was never
    // discovered, so the literal here was rounded against an outdated
    // depolarization formula. 1e-8 covers float-ordering differences while
    // still pinning the analytical value at the 8th decimal.
    try std.testing.expectApproxEqAbs(@as(f64, 0.4795010601166188), coefficients[2], 1.0e-8);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), coefficients[3], 1.0e-12);
}

test "analytic HG phase coefficients follow vendor truncation budget" {
    const coefficients = hgPhaseCoefficients(0.7);
    try std.testing.expectEqual(@as(usize, 39), maxPhaseCoefficientIndex(coefficients));
    try std.testing.expectApproxEqAbs(
        @as(f64, 79.0 * std.math.pow(f64, 0.7, 39.0)),
        coefficients[39],
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), coefficients[40], 1.0e-12);
}
