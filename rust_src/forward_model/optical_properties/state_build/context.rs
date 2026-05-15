use super::{OwnedVerticalGrid, PreparedLayer, PreparedSublayer, build_vertical_grid};
use crate::{
    common::errors,
    input::{
        atmosphere::FractionControl,
        instrument::OperationalCrossSectionLut,
        reference::airmass_phase::{AirmassFactorLut, MiePhaseTable},
        reference_data::{
            ClimatologyProfile, CollisionInducedAbsorptionTable, CrossSectionPoint,
            CrossSectionTable, SpectroscopyLineList,
        },
        scene::Scene,
    },
};

#[derive(Debug, Clone, Copy)]
pub struct PreparationInputs<'a> {
    pub profile: &'a ClimatologyProfile,
    pub spectroscopy_profile: Option<&'a ClimatologyProfile>,
    pub cross_sections: &'a CrossSectionTable,
    pub lut: &'a AirmassFactorLut,
    pub collision_induced_absorption: Option<&'a CollisionInducedAbsorptionTable>,
    pub spectroscopy_lines: Option<&'a SpectroscopyLineList>,
    pub aerosol_mie: Option<&'a MiePhaseTable>,
    pub cloud_mie: Option<&'a MiePhaseTable>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct PreparationContext<'a> {
    pub scene: &'a Scene,
    pub profile: &'a ClimatologyProfile,
    pub cross_sections: &'a CrossSectionTable,
    pub lut: &'a AirmassFactorLut,
    pub collision_induced_absorption: Option<CollisionInducedAbsorptionTable>,
    pub spectroscopy_lines: Option<SpectroscopyLineList>,
    pub aerosol_mie: Option<&'a MiePhaseTable>,
    pub cloud_mie: Option<&'a MiePhaseTable>,
    pub vertical_grid: OwnedVerticalGrid,
    pub layers: Vec<PreparedLayer>,
    pub sublayers: Vec<PreparedSublayer>,
    pub continuum_points: Vec<CrossSectionPoint>,
    pub spectroscopy_profile_altitudes_km: Vec<f64>,
    pub spectroscopy_profile_pressures_hpa: Vec<f64>,
    pub spectroscopy_profile_temperatures_k: Vec<f64>,
    pub aerosol_fraction_control: FractionControl,
    pub cloud_fraction_control: FractionControl,
    pub operational_o2_lut: OperationalCrossSectionLut,
    pub operational_o2o2_lut: OperationalCrossSectionLut,
    pub midpoint_nm: f64,
}

impl<'a> PreparationContext<'a> {
    pub fn init(scene: &'a Scene, inputs: PreparationInputs<'a>) -> Result<Self, errors::Error> {
        scene.validate()?;

        let vertical_grid = build_vertical_grid(scene, inputs.profile)?;
        let layer_count = vertical_grid.layer_top_altitudes_km.len();
        let total_sublayer_count = vertical_grid.sublayer_mid_altitudes_km.len();
        let layers = vec![PreparedLayer::default(); layer_count];
        let sublayers = vec![PreparedSublayer::default(); total_sublayer_count];
        let continuum_points = inputs.cross_sections.points.clone();

        let spectroscopy_profile = inputs.spectroscopy_profile.unwrap_or(inputs.profile);
        let spectroscopy_profile_altitudes_km = spectroscopy_profile
            .rows
            .iter()
            .map(|row| row.altitude_km)
            .collect();
        let spectroscopy_profile_pressures_hpa = spectroscopy_profile
            .rows
            .iter()
            .map(|row| row.pressure_hpa)
            .collect();
        let spectroscopy_profile_temperatures_k = spectroscopy_profile
            .rows
            .iter()
            .map(|row| row.temperature_k)
            .collect();

        let operational_band_support = scene.observation_model.primary_operational_band_support();
        let operational_o2_lut = if operational_band_support.o2_operational_lut.enabled() {
            operational_band_support.o2_operational_lut
        } else {
            OperationalCrossSectionLut::default()
        };
        let operational_o2o2_lut = if operational_band_support.o2o2_operational_lut.enabled() {
            operational_band_support.o2o2_operational_lut
        } else {
            OperationalCrossSectionLut::default()
        };

        Ok(Self {
            scene,
            profile: inputs.profile,
            cross_sections: inputs.cross_sections,
            lut: inputs.lut,
            collision_induced_absorption: inputs.collision_induced_absorption.cloned(),
            spectroscopy_lines: inputs.spectroscopy_lines.cloned(),
            aerosol_mie: inputs.aerosol_mie,
            cloud_mie: inputs.cloud_mie,
            vertical_grid,
            layers,
            sublayers,
            continuum_points,
            spectroscopy_profile_altitudes_km,
            spectroscopy_profile_pressures_hpa,
            spectroscopy_profile_temperatures_k,
            aerosol_fraction_control: scene.aerosol.fraction.clone(),
            cloud_fraction_control: scene.cloud.fraction.clone(),
            operational_o2_lut,
            operational_o2o2_lut,
            midpoint_nm: (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        })
    }
}
