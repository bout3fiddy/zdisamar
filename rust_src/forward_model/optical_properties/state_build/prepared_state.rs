use super::{
    build_shared_rtm_geometry_from_layers,
    state_types::{
        GeneratedLutAsset, PreparedCrossSectionAbsorber, PreparedLayer, PreparedLineAbsorber,
        PreparedSublayer, SharedRtmGeometry,
    },
};
use crate::{
    common::lut_controls,
    forward_model::optical_properties::particle_support::{
        ParticleSingleScatterAlbedos, resolved_particle_single_scatter_albedos,
    },
    input::{
        atmosphere::{FractionControl, IntervalSemantics},
        atmospheric_types::AbsorberSpecies,
        instrument::OperationalCrossSectionLut,
        reference::airmass_phase::PhaseSupportKind,
        reference_data::{
            CollisionInducedAbsorptionTable, CrossSectionPoint, SpectroscopyLineList,
            StrongLinePreparedState, WeakLinePreparedState,
        },
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct PreparedOpticalState {
    pub layers: Vec<PreparedLayer>,
    pub sublayers: Option<Vec<PreparedSublayer>>,
    pub strong_line_states: Vec<StrongLinePreparedState>,
    pub spectroscopy_profile_strong_line_states: Vec<StrongLinePreparedState>,
    pub spectroscopy_profile_weak_line_states: Vec<WeakLinePreparedState>,
    pub shared_rtm_geometry: SharedRtmGeometry,
    pub continuum_points: Vec<CrossSectionPoint>,
    pub collision_induced_absorption: Option<CollisionInducedAbsorptionTable>,
    pub spectroscopy_lines: Option<SpectroscopyLineList>,
    pub spectroscopy_profile_altitudes_km: Vec<f64>,
    pub spectroscopy_profile_pressures_hpa: Vec<f64>,
    pub spectroscopy_profile_temperatures_k: Vec<f64>,
    pub cross_section_absorbers: Vec<PreparedCrossSectionAbsorber>,
    pub line_absorbers: Vec<PreparedLineAbsorber>,
    pub continuum_owner_species: Option<AbsorberSpecies>,
    pub operational_o2_lut: OperationalCrossSectionLut,
    pub operational_o2o2_lut: OperationalCrossSectionLut,
    pub mean_cross_section_cm2_per_molecule: f64,
    pub line_mean_cross_section_cm2_per_molecule: f64,
    pub line_mixing_mean_cross_section_cm2_per_molecule: f64,
    pub cia_mean_cross_section_cm5_per_molecule2: f64,
    pub effective_air_mass_factor: f64,
    pub effective_single_scatter_albedo: f64,
    pub aerosol_single_scatter_albedo: f64,
    pub cloud_single_scatter_albedo: f64,
    pub effective_temperature_k: f64,
    pub effective_pressure_hpa: f64,
    pub air_column_density_factor: f64,
    pub oxygen_column_density_factor: f64,
    pub column_density_factor: f64,
    pub cia_pair_path_factor_cm5: f64,
    pub aerosol_reference_wavelength_nm: f64,
    pub aerosol_angstrom_exponent: f64,
    pub cloud_reference_wavelength_nm: f64,
    pub cloud_angstrom_exponent: f64,
    pub gas_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_base_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_base_optical_depth: f64,
    pub d_optical_depth_d_temperature: f64,
    pub depolarization_factor: f64,
    pub total_optical_depth: f64,
    pub interval_semantics: IntervalSemantics,
    pub fit_interval_index_1based: u32,
    pub subcolumn_semantics_enabled: bool,
    pub aerosol_phase_support: PhaseSupportKind,
    pub cloud_phase_support: PhaseSupportKind,
    pub aerosol_fraction_control: FractionControl,
    pub cloud_fraction_control: FractionControl,
    pub generated_lut_assets: Vec<GeneratedLutAsset>,
    pub lut_execution_entries: Vec<String>,
}

impl Default for PreparedOpticalState {
    fn default() -> Self {
        Self {
            layers: Vec::new(),
            sublayers: None,
            strong_line_states: Vec::new(),
            spectroscopy_profile_strong_line_states: Vec::new(),
            spectroscopy_profile_weak_line_states: Vec::new(),
            shared_rtm_geometry: SharedRtmGeometry::default(),
            continuum_points: Vec::new(),
            collision_induced_absorption: None,
            spectroscopy_lines: None,
            spectroscopy_profile_altitudes_km: Vec::new(),
            spectroscopy_profile_pressures_hpa: Vec::new(),
            spectroscopy_profile_temperatures_k: Vec::new(),
            cross_section_absorbers: Vec::new(),
            line_absorbers: Vec::new(),
            continuum_owner_species: None,
            operational_o2_lut: OperationalCrossSectionLut::default(),
            operational_o2o2_lut: OperationalCrossSectionLut::default(),
            mean_cross_section_cm2_per_molecule: 0.0,
            line_mean_cross_section_cm2_per_molecule: 0.0,
            line_mixing_mean_cross_section_cm2_per_molecule: 0.0,
            cia_mean_cross_section_cm5_per_molecule2: 0.0,
            effective_air_mass_factor: 0.0,
            effective_single_scatter_albedo: 0.0,
            aerosol_single_scatter_albedo: -1.0,
            cloud_single_scatter_albedo: -1.0,
            effective_temperature_k: 0.0,
            effective_pressure_hpa: 0.0,
            air_column_density_factor: 0.0,
            oxygen_column_density_factor: 0.0,
            column_density_factor: 0.0,
            cia_pair_path_factor_cm5: 0.0,
            aerosol_reference_wavelength_nm: 0.0,
            aerosol_angstrom_exponent: 0.0,
            cloud_reference_wavelength_nm: 0.0,
            cloud_angstrom_exponent: 0.0,
            gas_optical_depth: 0.0,
            cia_optical_depth: 0.0,
            aerosol_optical_depth: 0.0,
            aerosol_base_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            cloud_base_optical_depth: 0.0,
            d_optical_depth_d_temperature: 0.0,
            depolarization_factor: 0.0,
            total_optical_depth: 0.0,
            interval_semantics: IntervalSemantics::None,
            fit_interval_index_1based: 0,
            subcolumn_semantics_enabled: false,
            aerosol_phase_support: PhaseSupportKind::None,
            cloud_phase_support: PhaseSupportKind::None,
            aerosol_fraction_control: FractionControl::default(),
            cloud_fraction_control: FractionControl::default(),
            generated_lut_assets: Vec::new(),
            lut_execution_entries: Vec::new(),
        }
    }
}

impl PreparedOpticalState {
    pub fn transport_layer_count(&self) -> usize {
        if self.interval_semantics_use_reduced_shared_rtm_layers() {
            return self.layers.len();
        }
        if let Some(sublayers) = &self.sublayers {
            return sublayers.len();
        }
        self.layers.len()
    }

    pub fn interval_semantics_use_reduced_shared_rtm_layers(&self) -> bool {
        if self.interval_semantics == IntervalSemantics::None {
            return false;
        }
        let Some(sublayers) = &self.sublayers else {
            return false;
        };
        let referenced_support_rows = self
            .layers
            .iter()
            .map(|layer| layer.sublayer_count as usize)
            .sum::<usize>();
        // Reduced RTM layers are only needed when logical layers share support
        // rows; otherwise the sublayer grid is already the transport grid.
        referenced_support_rows > sublayers.len()
    }

    pub fn ensure_shared_rtm_geometry_cache(&mut self) -> Result<(), crate::common::errors::Error> {
        if self
            .shared_rtm_geometry
            .is_valid_for(self.transport_layer_count())
        {
            return Ok(());
        }
        if !self.interval_semantics_use_reduced_shared_rtm_layers() {
            self.shared_rtm_geometry = SharedRtmGeometry::default();
            return Ok(());
        }
        let Some(sublayers) = &self.sublayers else {
            self.shared_rtm_geometry = SharedRtmGeometry::default();
            return Ok(());
        };
        self.shared_rtm_geometry = build_shared_rtm_geometry_from_layers(&self.layers, sublayers)?;
        Ok(())
    }

    pub fn resolved_particle_single_scatter_albedos(&self) -> ParticleSingleScatterAlbedos {
        resolved_particle_single_scatter_albedos(
            self.aerosol_single_scatter_albedo,
            self.cloud_single_scatter_albedo,
            self.effective_single_scatter_albedo,
        )
    }

    pub fn generated_lut_asset_modes(&self) -> impl Iterator<Item = lut_controls::Mode> + '_ {
        self.generated_lut_assets.iter().map(|asset| asset.mode)
    }
}
