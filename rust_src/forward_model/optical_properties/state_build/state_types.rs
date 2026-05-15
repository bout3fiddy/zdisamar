use crate::{
    common::lut_controls,
    forward_model::optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    input::{
        atmosphere::{FractionControl, PartitionLabel},
        reference::airmass_phase::PhaseSupportKind,
    },
};

pub const PHASE_COEFFICIENT_COUNT: usize = phase_functions::PHASE_COEFFICIENT_COUNT;

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct PreparedLayer {
    pub layer_index: u32,
    pub sublayer_start_index: u32,
    pub sublayer_count: u32,
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub number_density_cm3: f64,
    pub continuum_cross_section_cm2_per_molecule: f64,
    pub line_cross_section_cm2_per_molecule: f64,
    pub line_mixing_cross_section_cm2_per_molecule: f64,
    pub cia_optical_depth: f64,
    pub d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    pub gas_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_base_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_base_optical_depth: f64,
    pub layer_single_scatter_albedo: f64,
    pub depolarization_factor: f64,
    pub optical_depth: f64,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub interval_index_1based: u32,
    pub subcolumn_label: PartitionLabel,
    pub aerosol_fraction: f64,
    pub cloud_fraction: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum PreparedSupportRowKind {
    #[default]
    Physical,
    ParityBoundary,
    ParityActive,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PreparedSublayer {
    pub parent_layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub number_density_cm3: f64,
    pub oxygen_number_density_cm3: f64,
    pub cia_pair_density_cm6: f64,
    pub absorber_number_density_cm3: f64,
    pub path_length_cm: f64,
    pub continuum_cross_section_cm2_per_molecule: f64,
    pub line_cross_section_cm2_per_molecule: f64,
    pub line_mixing_cross_section_cm2_per_molecule: f64,
    pub cia_sigma_cm5_per_molecule2: f64,
    pub cia_optical_depth: f64,
    pub d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub gas_extinction_optical_depth: f64,
    pub d_gas_optical_depth_d_temperature: f64,
    pub d_cia_optical_depth_d_temperature: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_base_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_base_optical_depth: f64,
    pub aerosol_single_scatter_albedo: f64,
    pub cloud_single_scatter_albedo: f64,
    pub aerosol_phase_coefficients: PhaseCoefficients,
    pub cloud_phase_coefficients: PhaseCoefficients,
    pub combined_phase_coefficients: PhaseCoefficients,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub interval_index_1based: u32,
    pub subcolumn_label: PartitionLabel,
    pub aerosol_fraction: f64,
    pub cloud_fraction: f64,
    pub support_row_kind: PreparedSupportRowKind,
}

impl Default for PreparedSublayer {
    fn default() -> Self {
        Self {
            parent_layer_index: 0,
            sublayer_index: 0,
            global_sublayer_index: 0,
            altitude_km: 0.0,
            pressure_hpa: 0.0,
            temperature_k: 0.0,
            number_density_cm3: 0.0,
            oxygen_number_density_cm3: 0.0,
            cia_pair_density_cm6: 0.0,
            absorber_number_density_cm3: 0.0,
            path_length_cm: 0.0,
            continuum_cross_section_cm2_per_molecule: 0.0,
            line_cross_section_cm2_per_molecule: 0.0,
            line_mixing_cross_section_cm2_per_molecule: 0.0,
            cia_sigma_cm5_per_molecule2: 0.0,
            cia_optical_depth: 0.0,
            d_cross_section_d_temperature_cm2_per_molecule_per_k: 0.0,
            gas_absorption_optical_depth: 0.0,
            gas_scattering_optical_depth: 0.0,
            gas_extinction_optical_depth: 0.0,
            d_gas_optical_depth_d_temperature: 0.0,
            d_cia_optical_depth_d_temperature: 0.0,
            aerosol_optical_depth: 0.0,
            aerosol_base_optical_depth: 0.0,
            cloud_optical_depth: 0.0,
            cloud_base_optical_depth: 0.0,
            aerosol_single_scatter_albedo: 0.0,
            cloud_single_scatter_albedo: 0.0,
            aerosol_phase_coefficients: phase_functions::zero_phase_coefficients(),
            cloud_phase_coefficients: phase_functions::zero_phase_coefficients(),
            combined_phase_coefficients: phase_functions::zero_phase_coefficients(),
            top_altitude_km: 0.0,
            bottom_altitude_km: 0.0,
            top_pressure_hpa: 0.0,
            bottom_pressure_hpa: 0.0,
            interval_index_1based: 0,
            subcolumn_label: PartitionLabel::Unspecified,
            aerosol_fraction: 0.0,
            cloud_fraction: 0.0,
            support_row_kind: PreparedSupportRowKind::Physical,
        }
    }
}

impl PreparedSublayer {
    pub fn cia_pair_density_cm6_value(self) -> f64 {
        if self.cia_pair_density_cm6 > 0.0 {
            self.cia_pair_density_cm6
        } else {
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct OpticalDepthBreakdown {
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_scattering_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_scattering_optical_depth: f64,
}

impl OpticalDepthBreakdown {
    pub fn total_scattering_optical_depth(self) -> f64 {
        self.gas_scattering_optical_depth
            + self.aerosol_scattering_optical_depth
            + self.cloud_scattering_optical_depth
    }

    pub fn total_optical_depth(self) -> f64 {
        self.gas_absorption_optical_depth
            + self.gas_scattering_optical_depth
            + self.cia_optical_depth
            + self.aerosol_optical_depth
            + self.cloud_optical_depth
    }

    pub fn single_scatter_albedo(self) -> f64 {
        let total_optical_depth = self.total_optical_depth();
        if total_optical_depth <= 0.0 {
            return 0.0;
        }
        (self.total_scattering_optical_depth() / total_optical_depth).clamp(0.0, 1.0)
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct EvaluatedLayer {
    pub breakdown: OpticalDepthBreakdown,
    pub phase_coefficients: PhaseCoefficients,
    pub solar_mu: f64,
    pub view_mu: f64,
}

impl Default for EvaluatedLayer {
    fn default() -> Self {
        Self {
            breakdown: OpticalDepthBreakdown::default(),
            phase_coefficients: phase_functions::gas_phase_coefficients(),
            solar_mu: 1.0,
            view_mu: 1.0,
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct SharedRtmLayerGeometry {
    pub lower_altitude_km: f64,
    pub upper_altitude_km: f64,
    pub midpoint_altitude_km: f64,
    pub thickness_km: f64,
    pub support_start_index: u32,
    pub support_count: u32,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SharedRtmLevelGeometry {
    pub altitude_km: f64,
    pub weight_km: f64,
    pub support_start_index: u32,
    pub support_count: u32,
    pub support_row_index: u32,
    pub particle_above_support_row_index: u32,
    pub particle_below_support_row_index: u32,
}

impl Default for SharedRtmLevelGeometry {
    fn default() -> Self {
        Self {
            altitude_km: 0.0,
            weight_km: 0.0,
            support_start_index: 0,
            support_count: 0,
            support_row_index: 0,
            particle_above_support_row_index: u32::MAX,
            particle_below_support_row_index: u32::MAX,
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SharedRtmGeometry {
    pub layers: Vec<SharedRtmLayerGeometry>,
    pub levels: Vec<SharedRtmLevelGeometry>,
}

impl SharedRtmGeometry {
    pub fn is_valid_for(&self, layer_count: usize) -> bool {
        self.layers.len() == layer_count && self.levels.len() == layer_count + 1
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum GeneratedLutAssetKind {
    #[default]
    Reflectance,
    Correction,
    Xsec,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct GeneratedLutAsset {
    pub dataset_id: String,
    pub lut_id: String,
    pub provenance_label: String,
    pub kind: GeneratedLutAssetKind,
    pub mode: lut_controls::Mode,
    pub spectral_bin_count: u32,
    pub layer_count: u32,
    pub coefficient_count: u32,
    pub compatibility: lut_controls::CompatibilityKey,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct PreparedStateFractions {
    pub aerosol_phase_support: PhaseSupportKind,
    pub cloud_phase_support: PhaseSupportKind,
    pub aerosol_fraction_control: FractionControl,
    pub cloud_fraction_control: FractionControl,
}
