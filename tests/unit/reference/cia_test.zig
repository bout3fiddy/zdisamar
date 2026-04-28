const std = @import("std");
const internal = @import("internal");

const cia = internal.reference.cia;
const cross_sections = internal.reference.cross_sections;
const spline = internal.common.math.interpolation.spline;
const CollisionInducedAbsorptionPoint = cia.CollisionInducedAbsorptionPoint;
const CollisionInducedAbsorptionTable = cia.CollisionInducedAbsorptionTable;
const effectiveSigmaAtSamples = cia.effectiveSigmaAtSamples;

test "cia helpers project sigma onto the same differential fit space" {
    const table: CollisionInducedAbsorptionTable = .{
        .scale_factor_cm5_per_molecule2 = 1.0,
        .points = &[_]CollisionInducedAbsorptionPoint{
            .{ .wavelength_nm = 759.0, .a0 = 1.0, .a1 = 0.0, .a2 = 0.0 },
            .{ .wavelength_nm = 762.0, .a0 = 2.0, .a1 = 0.0, .a2 = 0.0 },
        },
    };
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const weights = [_]f64{ 1.0, 1.0, 1.0, 1.0 };
    const sigma = try effectiveSigmaAtSamples(std.testing.allocator, table, &wavelengths, 273.15, &weights, 1);
    defer std.testing.allocator.free(sigma);

    try std.testing.expectApproxEqAbs(@as(f64, 0.0), cross_sections.weightedMeanSamples(sigma, &weights), 1.0e-9);
}

test "cia coefficient interpolation follows vendor endpoint-secant spline" {
    const points = [_]CollisionInducedAbsorptionPoint{
        .{ .wavelength_nm = 760.0, .a0 = 4.90, .a1 = 0.10, .a2 = 0.01 },
        .{ .wavelength_nm = 760.5, .a0 = 4.90, .a1 = 0.12, .a2 = 0.02 },
        .{ .wavelength_nm = 761.0, .a0 = 4.91, .a1 = 0.14, .a2 = 0.03 },
        .{ .wavelength_nm = 761.5, .a0 = 4.91, .a1 = 0.16, .a2 = 0.04 },
        .{ .wavelength_nm = 762.0, .a0 = 4.93, .a1 = 0.18, .a2 = 0.05 },
    };
    const table: CollisionInducedAbsorptionTable = .{
        .scale_factor_cm5_per_molecule2 = 1.0,
        .points = &points,
    };

    const target_nm = 761.25;
    const coefficients = table.interpolateCoefficients(target_nm);
    const wavelengths = [_]f64{ 760.0, 760.5, 761.0, 761.5, 762.0 };
    const a0 = [_]f64{ 4.90, 4.90, 4.91, 4.91, 4.93 };
    const expected_a0 = try spline.sampleEndpointSecant(&wavelengths, &a0, target_nm);

    try std.testing.expectApproxEqAbs(expected_a0, coefficients.a0, 1.0e-15);
}
