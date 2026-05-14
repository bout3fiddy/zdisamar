use crate::{
    common::{errors, units},
    input::geometry::Model::{PlaneParallel, PseudoSpherical, Spherical},
};

const EARTH_RADIUS_KM: f64 = 6371.0;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Model {
    #[default]
    PlaneParallel,
    PseudoSpherical,
    Spherical,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct Geometry {
    pub model: Model,
    pub solar_zenith_deg: f64,
    pub viewing_zenith_deg: f64,
    pub relative_azimuth_deg: f64,
    pub surface_altitude_km: f64,
}

impl Geometry {
    pub fn validate(self) -> Result<(), errors::Error> {
        units::ZenithAngleDeg {
            value: self.solar_zenith_deg,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;
        units::ZenithAngleDeg {
            value: self.viewing_zenith_deg,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;
        units::AzimuthAngleDeg {
            value: self.relative_azimuth_deg,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;
        if !self.surface_altitude_km.is_finite() || self.surface_altitude_km < 0.0 {
            return Err(errors::Error::InvalidRequest);
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
        if self.model == PlaneParallel {
            return base_mu.max(0.05);
        }

        let safe_altitude_km = altitude_km.max(0.0);
        let radius_ratio = EARTH_RADIUS_KM / (EARTH_RADIUS_KM + safe_altitude_km);
        let sin_at_altitude = (base_zenith_rad.sin() * radius_ratio).clamp(-0.999_999, 0.999_999);
        let local_mu = (1.0 - (sin_at_altitude * sin_at_altitude)).max(0.0).sqrt();

        // The floor keeps near-horizon slant paths finite before RTM layer setup.
        match self.model {
            PlaneParallel => base_mu.max(0.05),
            PseudoSpherical => local_mu.max(0.05),
            Spherical => (local_mu * radius_ratio).max(0.05),
        }
    }
}
