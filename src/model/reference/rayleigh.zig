//! Purpose:
//!   Provide dry-air Rayleigh scattering and depolarization helpers.
//!
//! Physics:
//!   Computes refractive index, King factors, depolarization, and molecular cross section for air.
//!
//! Vendor:
//!   `Rayleigh scattering`
//!
//! Design:
//!   Constants stay local so the scattering model remains self-contained and easy to validate.
//!
//! Invariants:
//!   Wavelengths are clamped to positive values before the refractive and scattering formulas are evaluated.
//!
//! Validation:
//!   Tests compare O2A-scale expectations and monotonic wavelength trends.

const std = @import("std");

const fraction_n2 = 78.084;
const fraction_o2 = 20.946;
const fraction_ar = 0.934;
const fraction_co2 = 0.036;
const reference_number_density_cm3 = 2.5468993e19;

/// Purpose:
///   Compute the nitrogen King factor at a wavelength.
fn kingFactorN2(wavelength_nm: f64) f64 {
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    return 1.034 + 3.17e-4 * sigma_um_inv * sigma_um_inv;
}

/// Purpose:
///   Compute the oxygen King factor at a wavelength.
fn kingFactorO2(wavelength_nm: f64) f64 {
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    const sigma_sq = sigma_um_inv * sigma_um_inv;
    return 1.096 + 1.385e-3 * sigma_sq + 1.448e-4 * sigma_sq * sigma_sq;
}

/// Purpose:
///   Compute the weighted King factor for dry air.
fn kingFactorAir(wavelength_nm: f64) f64 {
    const weighted_sum =
        fraction_n2 * kingFactorN2(wavelength_nm) +
        fraction_o2 * kingFactorO2(wavelength_nm) +
        fraction_ar * 1.0 +
        fraction_co2 * 1.15;
    return weighted_sum / (fraction_n2 + fraction_o2 + fraction_ar + fraction_co2);
}

/// Purpose:
///   Compute the refractive index of dry air at a wavelength.
///
/// Physics:
///   Uses a standard wavelength-dependent refractivity approximation.
pub fn refractiveIndexDryAir(wavelength_nm: f64) f64 {
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    const sigma_sq = sigma_um_inv * sigma_um_inv;
    const refractivity =
        8060.51 +
        2480990.0 / (132.274 - sigma_sq) +
        17455.7 / (39.32957 - sigma_sq);
    return 1.0 + refractivity * 1.0e-8;
}

/// Purpose:
///   Compute the depolarization factor of dry air.
pub fn depolarizationFactorAir(wavelength_nm: f64) f64 {
    const king_factor_air = kingFactorAir(wavelength_nm);
    return 6.0 * (king_factor_air - 1.0) / (3.0 + 7.0 * king_factor_air);
}

/// Purpose:
///   Compute the Rayleigh scattering cross section of dry air.
///
/// Physics:
///   Returns the scattering cross section in cm^2.
///
/// Units:
///   `wavelength_nm` is in nanometers and the output is in cm^2.
pub fn crossSectionCm2(wavelength_nm: f64) f64 {
    const safe_wavelength_nm = @max(wavelength_nm, 1.0);
    const refractive_index = refractiveIndexDryAir(safe_wavelength_nm);
    const numerator = 24.0 * std.math.pi * std.math.pi * std.math.pi;
    const wavelength_cm = safe_wavelength_nm * 1.0e-7;
    var cross_section =
        numerator /
        std.math.pow(f64, wavelength_cm, 4.0) /
        (reference_number_density_cm3 * reference_number_density_cm3);
    cross_section *=
        std.math.pow(f64, refractive_index * refractive_index - 1.0, 2.0) /
        std.math.pow(f64, refractive_index * refractive_index + 2.0, 2.0);
    return cross_section * kingFactorAir(safe_wavelength_nm);
}

test "rayleigh cross section and depolarization match dry-air O2A-scale expectations" {
    try std.testing.expectApproxEqAbs(@as(f64, 0.02771347468938541), depolarizationFactorAir(760.0), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.213452195882859e-27), crossSectionCm2(760.0), 1.0e-39);
    try std.testing.expect(crossSectionCm2(405.0) > crossSectionCm2(760.0));
    try std.testing.expect(depolarizationFactorAir(405.0) > depolarizationFactorAir(760.0));
}
