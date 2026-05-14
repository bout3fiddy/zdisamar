use crate::{
    common::errors,
    forward_model::optical_properties::particle_support,
    input::{
        atmosphere::{FractionControl, FractionTarget, IntervalPlacement},
        atmospheric_types::AerosolType,
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct Aerosol {
    pub id: String,
    pub aerosol_type: AerosolType,
    pub provider: String,
    pub enabled: bool,
    pub optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub asymmetry_factor: f64,
    pub angstrom_exponent: f64,
    pub reference_wavelength_nm: f64,
    pub layer_center_km: f64,
    pub layer_width_km: f64,
    pub placement: IntervalPlacement,
    pub fraction: FractionControl,
}

impl Default for Aerosol {
    fn default() -> Self {
        Self {
            id: String::new(),
            aerosol_type: AerosolType::None,
            provider: String::new(),
            enabled: false,
            optical_depth: 0.0,
            single_scatter_albedo: 0.93,
            asymmetry_factor: 0.65,
            angstrom_exponent: 1.3,
            reference_wavelength_nm: 550.0,
            layer_center_km: 2.5,
            layer_width_km: 3.0,
            placement: IntervalPlacement::default(),
            fraction: FractionControl::default(),
        }
    }
}

impl Aerosol {
    pub fn resolved_placement(&self) -> IntervalPlacement {
        particle_support::aerosol_placement(self)
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.optical_depth < 0.0
            || self.single_scatter_albedo < 0.0
            || self.single_scatter_albedo > 1.0
            || self.asymmetry_factor < -1.0
            || self.asymmetry_factor > 1.0
            || !self.angstrom_exponent.is_finite()
            || self.reference_wavelength_nm <= 0.0
        {
            return Err(errors::Error::InvalidRequest);
        }
        if !self.placement.enabled() {
            if self.layer_center_km < 0.0 || self.layer_width_km <= 0.0 {
                return Err(errors::Error::InvalidRequest);
            }
        } else {
            self.placement.validate()?;
        }
        self.fraction.validate()?;
        if self.fraction.enabled && self.fraction.target != FractionTarget::Aerosol {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}
