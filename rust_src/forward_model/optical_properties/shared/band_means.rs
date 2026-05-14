use crate::input::{OperationalCrossSectionLut, OperationalReferenceGrid, Scene};

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct LineBandMeans {
    pub line_mean_cross_section_cm2_per_molecule: f64,
    pub line_mixing_mean_cross_section_cm2_per_molecule: f64,
}

pub fn compute_operational_band_mean(
    scene: &Scene,
    lut: &OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) -> f64 {
    let operational_band_support = scene.observation_model.primary_operational_band_support();
    if operational_band_support.operational_refspec_grid.enabled() {
        return compute_weighted_operational_band_mean(
            &operational_band_support.operational_refspec_grid,
            lut,
            effective_temperature_k,
            effective_pressure_hpa,
        );
    }

    let sample_count = scene.spectral_grid.sample_count.max(1);
    let span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    let wavelength_step = if sample_count <= 1 {
        0.0
    } else {
        span_nm / f64::from(sample_count - 1)
    };

    let mut sigma_sum = 0.0;
    for index in 0..sample_count {
        let wavelength_nm = scene.spectral_grid.start_nm + wavelength_step * f64::from(index);
        sigma_sum += lut.sigma_at(
            wavelength_nm,
            effective_temperature_k.max(150.0),
            effective_pressure_hpa.max(1.0),
        );
    }

    sigma_sum / f64::from(sample_count)
}

pub fn compute_weighted_operational_band_mean(
    refspec_grid: &OperationalReferenceGrid,
    lut: &OperationalCrossSectionLut,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
) -> f64 {
    let mut sigma_sum = 0.0;
    let mut weight_sum = 0.0;
    for (&wavelength_nm, &weight) in refspec_grid
        .wavelengths_nm
        .iter()
        .zip(&refspec_grid.weights)
    {
        sigma_sum += weight
            * lut.sigma_at(
                wavelength_nm,
                effective_temperature_k.max(150.0),
                effective_pressure_hpa.max(1.0),
            );
        weight_sum += weight;
    }
    sigma_sum / weight_sum.max(1.0e-12)
}

pub fn compute_weighted_window_mean(values: &[f64], weights: &[f64]) -> f64 {
    if values.is_empty() || values.len() != weights.len() {
        return 0.0;
    }

    let mut numerator = 0.0;
    let mut denominator = 0.0;
    for (&value, &weight) in values.iter().zip(weights) {
        numerator += value * weight;
        denominator += weight;
    }
    numerator / denominator.max(1.0e-12)
}
