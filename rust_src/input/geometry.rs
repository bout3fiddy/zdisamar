use crate::common::{
    errors::{Error, Result},
    units::{AzimuthAngleDeg, ZenithAngleDeg},
};

const EARTH_RADIUS_KM: f64 = 6371.0;

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum Model {
    #[default]
    PlaneParallel,
    PseudoSpherical,
    Spherical,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Geometry {
    pub model: Model,
    pub solar_zenith_deg: f64,
    pub viewing_zenith_deg: f64,
    pub relative_azimuth_deg: f64,
    pub surface_altitude_km: f64,
}

impl Default for Geometry {
    fn default() -> Self {
        Self {
            model: Model::PlaneParallel,
            solar_zenith_deg: 0.0,
            viewing_zenith_deg: 0.0,
            relative_azimuth_deg: 0.0,
            surface_altitude_km: 0.0,
        }
    }
}

impl Geometry {
    pub fn validate(self) -> Result<()> {
        ZenithAngleDeg {
            value: self.solar_zenith_deg,
        }
        .validate()
        .map_err(|_| Error::InvalidRequest)?;
        ZenithAngleDeg {
            value: self.viewing_zenith_deg,
        }
        .validate()
        .map_err(|_| Error::InvalidRequest)?;
        AzimuthAngleDeg {
            value: self.relative_azimuth_deg,
        }
        .validate()
        .map_err(|_| Error::InvalidRequest)?;
        if !self.surface_altitude_km.is_finite() || self.surface_altitude_km < 0.0 {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn solar_cosine_at_altitude(self, altitude_km: f64) -> f64 {
        self.propagation_cosine_at_altitude(self.solar_zenith_deg, altitude_km)
    }

    pub fn viewing_cosine_at_altitude(self, altitude_km: f64) -> f64 {
        self.propagation_cosine_at_altitude(self.viewing_zenith_deg, altitude_km)
    }

    fn propagation_cosine_at_altitude(self, zenith_deg: f64, altitude_km: f64) -> f64 {
        let base_zenith_rad = zenith_deg.to_radians();
        let base_mu = base_zenith_rad.cos();
        if self.model == Model::PlaneParallel {
            return base_mu.max(0.05);
        }

        let safe_altitude_km = altitude_km.max(0.0);
        let radius_ratio = EARTH_RADIUS_KM / (EARTH_RADIUS_KM + safe_altitude_km);
        let sin_at_altitude = (base_zenith_rad.sin() * radius_ratio).clamp(-0.999999, 0.999999);
        let local_mu = (1.0 - (sin_at_altitude * sin_at_altitude)).max(0.0).sqrt();

        match self.model {
            Model::PlaneParallel => base_mu.max(0.05),
            // Keep the floor because near-horizon paths otherwise explode upstream.
            Model::PseudoSpherical => local_mu.max(0.05),
            Model::Spherical => (local_mu * radius_ratio).max(0.05),
        }
    }
}
