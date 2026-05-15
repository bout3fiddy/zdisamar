use super::{AbsorberBuildState, PreparationContext, layer_accumulation};
use crate::{common::errors, forward_model::optical_properties::shared::band_means::LineBandMeans};

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct PreparedMeans {
    pub cross_section_mean_cm2_per_molecule: f64,
    pub line_means: LineBandMeans,
    pub cia_mean_cross_section_cm5_per_molecule2: f64,
    pub effective_air_mass_factor: f64,
    pub effective_single_scatter_albedo: f64,
    pub effective_temperature_k: f64,
    pub effective_pressure_hpa: f64,
    pub air_column_density_factor: f64,
    pub oxygen_column_density_factor: f64,
    pub column_density_factor: f64,
    pub cia_pair_path_factor_cm5: f64,
    pub gas_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_base_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_base_optical_depth: f64,
    pub d_optical_depth_d_temperature: f64,
    pub total_optical_depth: f64,
    pub depolarization_factor: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct AccumulationResult {
    pub means: PreparedMeans,
}

pub fn accumulate(
    context: &mut PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
) -> Result<AccumulationResult, errors::Error> {
    let layer_totals = layer_accumulation::populate(context, absorbers)?;
    let means = layer_accumulation::compute_prepared_means(context, absorbers, layer_totals);
    Ok(AccumulationResult { means })
}
