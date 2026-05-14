use crate::common::errors::{Error, Result};

use super::{
    CloudType, FractionControl, FractionTarget, IntervalPlacement, ParticlePlacementSemantics,
};

#[derive(Debug, Clone, PartialEq)]
pub struct Cloud {
    pub id: String,
    pub cloud_type: CloudType,
    pub provider: String,
    pub enabled: bool,
    pub optical_thickness: f64,
    pub single_scatter_albedo: f64,
    pub asymmetry_factor: f64,
    pub angstrom_exponent: f64,
    pub reference_wavelength_nm: f64,
    pub top_altitude_km: f64,
    pub thickness_km: f64,
    pub placement: IntervalPlacement,
    pub fraction: FractionControl,
}

impl Default for Cloud {
    fn default() -> Self {
        Self {
            id: String::new(),
            cloud_type: CloudType::None,
            provider: String::new(),
            enabled: false,
            optical_thickness: 0.0,
            single_scatter_albedo: 0.999,
            asymmetry_factor: 0.85,
            angstrom_exponent: 0.3,
            reference_wavelength_nm: 550.0,
            top_altitude_km: 6.0,
            thickness_km: 1.5,
            placement: IntervalPlacement::default(),
            fraction: FractionControl::default(),
        }
    }
}

impl Cloud {
    pub fn resolved_placement(&self) -> IntervalPlacement {
        if self.placement.enabled() {
            return self.placement;
        }
        IntervalPlacement {
            semantics: ParticlePlacementSemantics::AltitudeCenterWidthApproximation,
            top_altitude_km: self.top_altitude_km,
            bottom_altitude_km: (self.top_altitude_km - self.thickness_km).max(0.0),
            ..IntervalPlacement::default()
        }
    }

    pub fn validate(&self) -> Result<()> {
        if self.optical_thickness < 0.0 {
            return Err(Error::InvalidRequest);
        }
        if self.single_scatter_albedo < 0.0 || self.single_scatter_albedo > 1.0 {
            return Err(Error::InvalidRequest);
        }
        if self.asymmetry_factor < -1.0 || self.asymmetry_factor > 1.0 {
            return Err(Error::InvalidRequest);
        }
        if !self.angstrom_exponent.is_finite() || self.reference_wavelength_nm <= 0.0 {
            return Err(Error::InvalidRequest);
        }
        if !self.placement.enabled() {
            if self.top_altitude_km < 0.0 || self.thickness_km <= 0.0 {
                return Err(Error::InvalidRequest);
            }
        } else {
            self.placement.validate()?;
        }
        self.fraction.validate()?;
        if self.fraction.enabled && self.fraction.target != FractionTarget::Cloud {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}
