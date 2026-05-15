use super::atmospheric_budget::{self, AtmosphericBudgetRow};
use crate::{
    common::errors, forward_model::optical_properties::state_build::PreparedOpticalState,
    input::scene::Scene,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct O2O2CiaRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub oxygen_number_density_cm3: f64,
    pub path_length_cm: f64,
    pub cia_cross_section_cm5_per_molecule2: f64,
    pub cia_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_optical_depth: f64,
    pub cia_share_of_total_absorption: f64,
    pub cia_share_of_total_optical_depth: f64,
}

pub fn build(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    wavelengths_nm: &[f64],
) -> Result<Vec<O2O2CiaRow>, errors::Error> {
    Ok(atmospheric_budget::build(scene, prepared, wavelengths_nm)?
        .into_iter()
        .map(row_from_budget)
        .collect())
}

fn row_from_budget(row: AtmosphericBudgetRow) -> O2O2CiaRow {
    let pair_path =
        row.oxygen_number_density_cm3 * row.oxygen_number_density_cm3 * row.path_length_cm;
    O2O2CiaRow {
        wavelength_nm: row.wavelength_nm,
        layer_index: row.layer_index,
        sublayer_index: row.sublayer_index,
        global_sublayer_index: row.global_sublayer_index,
        interval_index_1based: row.interval_index_1based,
        altitude_km: row.altitude_km,
        pressure_hpa: row.pressure_hpa,
        temperature_k: row.temperature_k,
        oxygen_number_density_cm3: row.oxygen_number_density_cm3,
        path_length_cm: row.path_length_cm,
        cia_cross_section_cm5_per_molecule2: safe_divide(row.cia_optical_depth, pair_path),
        cia_optical_depth: row.cia_optical_depth,
        total_absorption_optical_depth: row.total_absorption_optical_depth,
        total_optical_depth: row.total_optical_depth,
        cia_share_of_total_absorption: safe_divide(
            row.cia_optical_depth,
            row.total_absorption_optical_depth,
        ),
        cia_share_of_total_optical_depth: safe_divide(
            row.cia_optical_depth,
            row.total_optical_depth,
        ),
    }
}

fn safe_divide(numerator: f64, denominator: f64) -> f64 {
    if denominator <= 0.0 || !denominator.is_finite() {
        return 0.0;
    }
    numerator / denominator
}
