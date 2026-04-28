const std = @import("std");
const internal = @import("internal");

const rayleigh = internal.reference.rayleigh;
const depolarizationFactorAir = rayleigh.depolarizationFactorAir;
const crossSectionCm2 = rayleigh.crossSectionCm2;

test "rayleigh cross section and depolarization match dry-air O2A-scale expectations" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.02771347468938541), depolarizationFactorAir(760.0), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.213452195882859e-27), crossSectionCm2(760.0), 1.0e-39);
    try std.testing.expect(crossSectionCm2(405.0) > crossSectionCm2(760.0));
    try std.testing.expect(depolarizationFactorAir(405.0) > depolarizationFactorAir(760.0));
}
