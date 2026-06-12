const std = @import("std");

// rayleigh.zig ---------------------------------------------------------------------------------------------- |
// Dry-air Rayleigh scattering helpers for gas-scattering optical-depth and phase-coefficient paths.           |
//                                                                                                             |
// provenance                                                                                                  |
//   Ported from main:`src/input/reference/rayleigh.zig`. Constants and formulas stay byte-for-byte in value   |
//   space because WP3 optical-depth parity reads Rayleigh scattering directly from atmospheric-budget rows.   |
//                                                                                                             |
// math                                                                                                        |
//   sigma_um_inv = 1000 / max(wavelength_nm, 1)                                                               |
//   depol        = 6 * (King_air - 1) / (3 + 7 * King_air)                                                    |
//   sigma_R      = 24*pi^3 / (lambda_cm^4 * N_s^2)                                                            |
//                  * ((n^2 - 1) / (n^2 + 2))^2 * King_air                                                     |
// ------------------------------------------------------------------------------------------------------------|

const fraction_n2 = 78.084;
const fraction_o2 = 20.946;
const fraction_ar = 0.934;
const fraction_co2 = 0.036;
const reference_number_density_cm3 = 2.5468993e19;

fn kingFactorN2(wavelength_nm: f64) f64 {
    // kingFactorN2 ------------------------------------------------------------------------------------------ |
    // Return the Bates wavelength-dependent King factor for nitrogen.                                         |
    // ------------------------------------------------------------------------------------------------------- |
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    return 1.034 + 3.17e-4 * sigma_um_inv * sigma_um_inv;
}

fn kingFactorO2(wavelength_nm: f64) f64 {
    // kingFactorO2 ------------------------------------------------------------------------------------------ |
    // Return the Bates wavelength-dependent King factor for oxygen.                                           |
    // ------------------------------------------------------------------------------------------------------- |
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    const sigma_sq = sigma_um_inv * sigma_um_inv;
    return 1.096 + 1.385e-3 * sigma_sq + 1.448e-4 * sigma_sq * sigma_sq;
}

fn kingFactorAir(wavelength_nm: f64) f64 {
    // kingFactorAir ----------------------------------------------------------------------------------------- |
    // Return the dry-air mixture King factor using the old reference gas fractions.                           |
    // ------------------------------------------------------------------------------------------------------- |
    const weighted_sum =
        fraction_n2 * kingFactorN2(wavelength_nm) +
        fraction_o2 * kingFactorO2(wavelength_nm) +
        fraction_ar * 1.0 +
        fraction_co2 * 1.15;
    return weighted_sum / (fraction_n2 + fraction_o2 + fraction_ar + fraction_co2);
}

pub fn refractiveIndexDryAir(wavelength_nm: f64) f64 {
    // refractiveIndexDryAir --------------------------------------------------------------------------------- |
    // Evaluate the old dry-air refractive-index fit at one wavelength.                                        |
    // ------------------------------------------------------------------------------------------------------- |
    const sigma_um_inv = 1000.0 / @max(wavelength_nm, 1.0);
    const sigma_sq = sigma_um_inv * sigma_um_inv;
    const refractivity =
        8060.51 +
        2480990.0 / (132.274 - sigma_sq) +
        17455.7 / (39.32957 - sigma_sq);
    return 1.0 + refractivity * 1.0e-8;
}

pub fn depolarizationFactorAir(wavelength_nm: f64) f64 {
    // depolarizationFactorAir ------------------------------------------------------------------------------- |
    // Convert the dry-air King factor to the wavelength-dependent depolarization factor.                      |
    // ------------------------------------------------------------------------------------------------------- |
    const king_factor_air = kingFactorAir(wavelength_nm);
    return 6.0 * (king_factor_air - 1.0) / (3.0 + 7.0 * king_factor_air);
}

pub fn phaseCoefficient2(wavelength_nm: f64) f64 {
    // phaseCoefficient2 ------------------------------------------------------------------------------------- |
    // Convert wavelength-dependent dry-air depolarization into the Rayleigh l=2 phase coefficient consumed    |
    // by LABOS source and non-integrated scattering paths.                                                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`src/forward_model/radiative_transfer/labos/phase_function.zig`                            |
    //   `get_ph2_rayleigh`.                                                                                   |
    //                                                                                                         |
    // math                                                                                                    |
    //   eps = 45 * depol / (6 - 7 * depol)                                                                    |
    //   phase2 = (45 + eps) / (90 + 20 * eps)                                                                 |
    // --------------------------------------------------------------------------------------------------------|
    const depolarization = depolarizationFactorAir(wavelength_nm);
    const eps = 45.0 * depolarization / (6.0 - 7.0 * depolarization);
    return (45.0 + eps) / (90.0 + 20.0 * eps);
}

pub fn crossSectionCm2(wavelength_nm: f64) f64 {
    // crossSectionCm2 ----------------------------------------------------------------------------------------|
    // Evaluate dry-air Rayleigh cross section for one wavelength.                                             |
    //                                                                                                         |
    // hot path                                                                                                |
    //   Support-row optics callers precompute this once per wavelength before streaming rows.                 |
    // --------------------------------------------------------------------------------------------------------|
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
