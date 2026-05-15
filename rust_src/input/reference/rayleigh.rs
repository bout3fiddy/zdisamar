const FRACTION_N2: f64 = 78.084;
const FRACTION_O2: f64 = 20.946;
const FRACTION_AR: f64 = 0.934;
const FRACTION_CO2: f64 = 0.036;
const REFERENCE_NUMBER_DENSITY_CM3: f64 = 2.5468993e19;

fn king_factor_n2(wavelength_nm: f64) -> f64 {
    let sigma_um_inv = 1000.0 / wavelength_nm.max(1.0);
    1.034 + 3.17e-4 * sigma_um_inv * sigma_um_inv
}

fn king_factor_o2(wavelength_nm: f64) -> f64 {
    let sigma_um_inv = 1000.0 / wavelength_nm.max(1.0);
    let sigma_sq = sigma_um_inv * sigma_um_inv;
    1.096 + 1.385e-3 * sigma_sq + 1.448e-4 * sigma_sq * sigma_sq
}

fn king_factor_air(wavelength_nm: f64) -> f64 {
    let weighted_sum = FRACTION_N2 * king_factor_n2(wavelength_nm)
        + FRACTION_O2 * king_factor_o2(wavelength_nm)
        + FRACTION_AR
        + FRACTION_CO2 * 1.15;
    weighted_sum / (FRACTION_N2 + FRACTION_O2 + FRACTION_AR + FRACTION_CO2)
}

pub fn refractive_index_dry_air(wavelength_nm: f64) -> f64 {
    let sigma_um_inv = 1000.0 / wavelength_nm.max(1.0);
    let sigma_sq = sigma_um_inv * sigma_um_inv;
    let refractivity = 8060.51 + 2480990.0 / (132.274 - sigma_sq) + 17455.7 / (39.32957 - sigma_sq);
    1.0 + refractivity * 1.0e-8
}

pub fn depolarization_factor_air(wavelength_nm: f64) -> f64 {
    let king_factor_air = king_factor_air(wavelength_nm);
    6.0 * (king_factor_air - 1.0) / (3.0 + 7.0 * king_factor_air)
}

pub fn cross_section_cm2(wavelength_nm: f64) -> f64 {
    let safe_wavelength_nm = wavelength_nm.max(1.0);
    let refractive_index = refractive_index_dry_air(safe_wavelength_nm);
    let numerator = 24.0 * std::f64::consts::PI.powi(3);
    let wavelength_cm = safe_wavelength_nm * 1.0e-7;
    let mut cross_section = numerator
        / wavelength_cm.powi(4)
        / (REFERENCE_NUMBER_DENSITY_CM3 * REFERENCE_NUMBER_DENSITY_CM3);
    cross_section *= (refractive_index * refractive_index - 1.0).powi(2)
        / (refractive_index * refractive_index + 2.0).powi(2);
    cross_section * king_factor_air(safe_wavelength_nm)
}

pub fn scattering_optical_depth_for_column(wavelength_nm: f64, air_column_density_cm2: f64) -> f64 {
    cross_section_cm2(wavelength_nm) * air_column_density_cm2.max(0.0)
}
