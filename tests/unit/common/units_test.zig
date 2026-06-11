const std = @import("std");
const internal = @import("internal");

const units = internal.common.units;

test "unit conversions preserve wavelength and wavenumber round trips" {
    const wavelength_nm = 760.0;
    const wavenumber_cm1 = units.wavelengthToWavenumberCm1(wavelength_nm);

    try std.testing.expectApproxEqAbs(wavelength_nm, units.wavenumberToWavelengthNm(wavenumber_cm1), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 13157.894736842105), wavenumber_cm1, 1.0e-12);
}

test "spectral width conversion uses local line-center slope" {
    const width_nm = units.spectralWidthCm1ToNm(2.0, 13157.894736842105);

    try std.testing.expectApproxEqAbs(@as(f64, 0.11552), width_nm, 1.0e-12);
    try std.testing.expect(units.wavelengthToWavenumberCm1(0.0) > 1.0e15);
    try std.testing.expect(units.wavenumberToWavelengthNm(0.0) > 1.0e15);
}
