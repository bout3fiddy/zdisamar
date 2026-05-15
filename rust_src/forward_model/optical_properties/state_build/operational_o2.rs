use crate::input::{
    instrument::OperationalCrossSectionLut, reference_data::SpectroscopyEvaluation,
};

pub fn operational_o2_evaluation_at_wavelength(
    operational_o2_lut: &OperationalCrossSectionLut,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> SpectroscopyEvaluation {
    let sigma = operational_o2_lut.sigma_at(wavelength_nm, temperature_k, pressure_hpa);
    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: sigma,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_sigma_cm2_per_molecule: sigma,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: sigma,
        d_sigma_d_temperature_cm2_per_molecule_per_k: operational_o2_lut.d_sigma_d_temperature_at(
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        ),
    }
}
