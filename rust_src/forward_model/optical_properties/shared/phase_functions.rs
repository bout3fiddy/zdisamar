use crate::input::{reference::rayleigh, scene::Scene};

pub const COMPACT_PHASE_COEFFICIENT_COUNT: usize = 4;
pub const VENDOR_HG_MAX_PHASE_INDEX: usize = 150;
pub const VENDOR_HG_TRUNCATION_THRESHOLD: f64 = 1.0e-8;
pub const PHASE_COEFFICIENT_COUNT: usize = VENDOR_HG_MAX_PHASE_INDEX + 1;

pub type PhaseCoefficients = [f64; PHASE_COEFFICIENT_COUNT];

pub fn zero_phase_coefficients() -> PhaseCoefficients {
    let mut coefficients = [0.0; PHASE_COEFFICIENT_COUNT];
    coefficients[0] = 1.0;
    coefficients
}

pub fn phase_coefficients_from_compact(
    compact_coefficients: [f64; COMPACT_PHASE_COEFFICIENT_COUNT],
) -> PhaseCoefficients {
    let mut coefficients = zero_phase_coefficients();
    coefficients[..COMPACT_PHASE_COEFFICIENT_COUNT].copy_from_slice(&compact_coefficients);
    coefficients[0] = 1.0;
    coefficients
}

pub fn max_phase_coefficient_index(phase_coefficients: &PhaseCoefficients) -> usize {
    for index in (1..PHASE_COEFFICIENT_COUNT).rev() {
        if phase_coefficients[index].abs() > 1.0e-12 {
            return index;
        }
    }
    0
}

pub fn gas_phase_coefficients() -> PhaseCoefficients {
    gas_phase_coefficients_at_wavelength(760.0)
}

pub fn gas_phase_coefficients_at_wavelength(wavelength_nm: f64) -> PhaseCoefficients {
    gas_phase_coefficients_from_rayleigh2(rayleigh_phase_coefficient2_at_wavelength(wavelength_nm))
}

pub fn gas_phase_coefficients_from_rayleigh2(rayleigh_coef2: f64) -> PhaseCoefficients {
    let mut coefficients = zero_phase_coefficients();
    coefficients[2] = rayleigh_coef2;
    coefficients
}

pub fn rayleigh_phase_coefficient2_at_wavelength(wavelength_nm: f64) -> f64 {
    let depolarization = rayleigh::depolarization_factor_air(wavelength_nm);
    let eps = 45.0 * depolarization / (6.0 - 7.0 * depolarization);
    (45.0 + eps) / (90.0 + 20.0 * eps)
}

pub fn compute_single_scatter_albedo(scene: &Scene, wavelength_nm: f64) -> f64 {
    let gas_ssa = 0.92;
    let aerosol_ssa = if scene.atmosphere.has_aerosols {
        scene.aerosol.single_scatter_albedo
    } else {
        gas_ssa
    };
    let cloud_ssa = if scene.atmosphere.has_clouds {
        scene.cloud.single_scatter_albedo
    } else {
        gas_ssa
    };
    let aerosol_fraction = if scene.aerosol.fraction.enabled {
        scene.aerosol.fraction.value_at_wavelength(wavelength_nm)
    } else {
        1.0
    };
    let cloud_fraction = if scene.cloud.fraction.enabled {
        scene.cloud.fraction.value_at_wavelength(wavelength_nm)
    } else {
        1.0
    };
    let aerosol_weight = if scene.atmosphere.has_aerosols {
        0.20 * aerosol_fraction
    } else {
        0.0
    };
    let cloud_weight = if scene.atmosphere.has_clouds {
        0.30 * cloud_fraction
    } else {
        0.0
    };
    let gas_weight = 1.0 - aerosol_weight - cloud_weight;
    (gas_weight * gas_ssa + aerosol_weight * aerosol_ssa + cloud_weight * cloud_ssa)
        .clamp(0.3, 0.999)
}

pub fn hg_phase_coefficients(asymmetry_factor: f64) -> PhaseCoefficients {
    hg_phase_coefficients_with_threshold(asymmetry_factor, VENDOR_HG_TRUNCATION_THRESHOLD)
}

pub fn hg_phase_coefficients_with_threshold(
    asymmetry_factor: f64,
    truncation_threshold: f64,
) -> PhaseCoefficients {
    let mut coefficients = zero_phase_coefficients();
    let truncation_g = asymmetry_factor.abs();
    if truncation_g <= 0.0 {
        return coefficients;
    }
    let threshold = truncation_threshold.max(0.0);

    let mut normalized_tail = 1.0;
    for (index, coefficient) in coefficients.iter_mut().enumerate().skip(1) {
        let order = index as f64;
        normalized_tail *= truncation_g * (2.0 * order - 1.0) / (2.0 * order + 1.0);
        if normalized_tail < threshold {
            break;
        }
        *coefficient = (2.0 * order + 1.0) * asymmetry_factor.powf(order);
    }
    coefficients
}

pub fn combine_phase_coefficients(
    wavelength_nm: f64,
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    aerosol_phase_coefficients: &PhaseCoefficients,
    cloud_phase_coefficients: &PhaseCoefficients,
) -> PhaseCoefficients {
    combine_phase_coefficients_with_rayleigh2(
        rayleigh_phase_coefficient2_at_wavelength(wavelength_nm),
        gas_scattering_optical_depth,
        aerosol_scattering_optical_depth,
        cloud_scattering_optical_depth,
        aerosol_phase_coefficients,
        cloud_phase_coefficients,
    )
}

pub fn combine_phase_coefficients_with_rayleigh2(
    rayleigh_coef2: f64,
    gas_scattering_optical_depth: f64,
    aerosol_scattering_optical_depth: f64,
    cloud_scattering_optical_depth: f64,
    aerosol_phase_coefficients: &PhaseCoefficients,
    cloud_phase_coefficients: &PhaseCoefficients,
) -> PhaseCoefficients {
    let total_scattering = gas_scattering_optical_depth
        + aerosol_scattering_optical_depth
        + cloud_scattering_optical_depth;
    if total_scattering == 0.0 {
        return gas_phase_coefficients_from_rayleigh2(rayleigh_coef2);
    }

    let mut combined = [0.0; PHASE_COEFFICIENT_COUNT];
    for index in 0..PHASE_COEFFICIENT_COUNT {
        let gas_phase_coefficient = if index == 0 {
            1.0
        } else if index == 2 {
            rayleigh_coef2
        } else {
            0.0
        };
        let mut numerator = gas_scattering_optical_depth * gas_phase_coefficient;
        if aerosol_scattering_optical_depth != 0.0 {
            numerator += aerosol_scattering_optical_depth * aerosol_phase_coefficients[index];
        }
        if cloud_scattering_optical_depth != 0.0 {
            numerator += cloud_scattering_optical_depth * cloud_phase_coefficients[index];
        }
        combined[index] = numerator / total_scattering;
    }
    combined[0] = 1.0;
    combined
}

pub fn backscatter_fraction(phase_coefficients: &PhaseCoefficients) -> f64 {
    backscatter_fraction_from_asymmetry(phase_coefficients[1])
}

pub fn backscatter_fraction_from_asymmetry(asymmetry_factor: f64) -> f64 {
    let clamped_asymmetry = asymmetry_factor.clamp(-0.95, 0.95);
    (0.5 * (1.0 - clamped_asymmetry)).clamp(0.02, 0.95)
}

pub fn compute_layer_depolarization(
    scene: &Scene,
    gas_scattering_tau: f64,
    aerosol_scattering_tau: f64,
    cloud_scattering_tau: f64,
) -> f64 {
    let total = gas_scattering_tau + aerosol_scattering_tau + cloud_scattering_tau;
    if total == 0.0 {
        return 0.0;
    }
    let gas_fraction = gas_scattering_tau / total;
    let aerosol_fraction = aerosol_scattering_tau / total;
    let cloud_fraction = cloud_scattering_tau / total;
    gas_fraction * 0.0279
        + aerosol_fraction * (0.04 + 0.02 * (1.0 - scene.aerosol.asymmetry_factor))
        + cloud_fraction * (0.01 + 0.01 * (1.0 - scene.cloud.asymmetry_factor))
}
