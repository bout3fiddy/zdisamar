use crate::{
    common::{errors, units},
    input::atmosphere::types::{IntervalSemantics, ParticlePlacementSemantics},
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct VerticalInterval {
    pub index_1based: u32,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
    pub top_pressure_variance_hpa2: f64,
    pub bottom_pressure_variance_hpa2: f64,
    pub altitude_divisions: u32,
}

impl Default for VerticalInterval {
    fn default() -> Self {
        Self {
            index_1based: 0,
            top_pressure_hpa: 0.0,
            bottom_pressure_hpa: 0.0,
            top_altitude_km: f64::NAN,
            bottom_altitude_km: f64::NAN,
            top_pressure_variance_hpa2: 0.0,
            bottom_pressure_variance_hpa2: 0.0,
            altitude_divisions: 0,
        }
    }
}

impl VerticalInterval {
    pub fn has_altitude_bounds(self) -> bool {
        self.top_altitude_km.is_finite() && self.bottom_altitude_km.is_finite()
    }

    pub fn validate(self) -> Result<(), errors::Error> {
        if self.index_1based == 0 || self.altitude_divisions == 0 {
            return Err(errors::Error::InvalidRequest);
        }

        units::PressureRangeHpa {
            top_hpa: self.top_pressure_hpa,
            bottom_hpa: self.bottom_pressure_hpa,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;

        let has_top_altitude = self.top_altitude_km.is_finite();
        let has_bottom_altitude = self.bottom_altitude_km.is_finite();
        if has_top_altitude != has_bottom_altitude {
            return Err(errors::Error::InvalidRequest);
        }
        if self.has_altitude_bounds() {
            units::AltitudeRangeKm {
                bottom_km: self.bottom_altitude_km,
                top_km: self.top_altitude_km,
            }
            .validate()
            .map_err(|_| errors::Error::InvalidRequest)?;
        }
        if self.top_pressure_variance_hpa2 < 0.0 || self.bottom_pressure_variance_hpa2 < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn midpoint_altitude_km(self) -> f64 {
        if self.has_altitude_bounds() {
            0.5 * (self.top_altitude_km + self.bottom_altitude_km)
        } else {
            0.0
        }
    }

    pub fn thickness_km(self) -> f64 {
        if self.has_altitude_bounds() {
            (self.top_altitude_km - self.bottom_altitude_km).max(0.0)
        } else {
            0.0
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct IntervalGrid {
    pub semantics: IntervalSemantics,
    pub fit_interval_index_1based: u32,
    pub intervals: Vec<VerticalInterval>,
}

impl IntervalGrid {
    pub fn enabled(&self) -> bool {
        !self.intervals.is_empty()
    }

    pub fn interval_count(&self) -> u32 {
        self.intervals.len() as u32
    }

    pub fn fit_interval(&self) -> Option<VerticalInterval> {
        if !self.enabled() || self.fit_interval_index_1based == 0 {
            return None;
        }
        self.intervals
            .get((self.fit_interval_index_1based - 1) as usize)
            .copied()
    }

    pub fn validate(&self, fallback_sublayer_divisions: u8) -> Result<(), errors::Error> {
        if !self.enabled() {
            if self.semantics == IntervalSemantics::ExplicitPressureBounds
                || self.fit_interval_index_1based != 0
            {
                return Err(errors::Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.semantics == IntervalSemantics::None {
            return Err(errors::Error::InvalidRequest);
        }

        let mut previous_bottom_pressure_hpa = 0.0;
        let mut previous_bottom_altitude_km = 0.0;
        let mut previous_has_altitude_bounds = false;
        for (index, interval) in self.intervals.iter().copied().enumerate() {
            interval.validate()?;
            if interval.index_1based != index as u32 + 1 {
                return Err(errors::Error::InvalidRequest);
            }
            if index != 0 {
                if !approx_eq_abs(
                    interval.top_pressure_hpa,
                    previous_bottom_pressure_hpa,
                    1.0e-9,
                ) {
                    return Err(errors::Error::InvalidRequest);
                }
                if previous_has_altitude_bounds
                    && interval.has_altitude_bounds()
                    && !approx_eq_abs(
                        previous_bottom_altitude_km,
                        interval.top_altitude_km,
                        1.0e-9,
                    )
                {
                    return Err(errors::Error::InvalidRequest);
                }
            }
            previous_bottom_pressure_hpa = interval.bottom_pressure_hpa;
            previous_bottom_altitude_km = interval.bottom_altitude_km;
            previous_has_altitude_bounds = interval.has_altitude_bounds();
        }
        if self.fit_interval_index_1based > self.intervals.len() as u32
            || fallback_sublayer_divisions == 0
        {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct IntervalPlacement {
    pub semantics: ParticlePlacementSemantics,
    pub interval_index_1based: u32,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
}

impl Default for IntervalPlacement {
    fn default() -> Self {
        Self {
            semantics: ParticlePlacementSemantics::None,
            interval_index_1based: 0,
            top_pressure_hpa: 0.0,
            bottom_pressure_hpa: 0.0,
            top_altitude_km: f64::NAN,
            bottom_altitude_km: f64::NAN,
        }
    }
}

impl IntervalPlacement {
    pub fn enabled(self) -> bool {
        self.semantics != ParticlePlacementSemantics::None
    }

    pub fn has_altitude_bounds(self) -> bool {
        self.top_altitude_km.is_finite() && self.bottom_altitude_km.is_finite()
    }

    pub fn validate(self) -> Result<(), errors::Error> {
        match self.semantics {
            ParticlePlacementSemantics::None => Ok(()),
            ParticlePlacementSemantics::AltitudeCenterWidthApproximation => {
                units::AltitudeRangeKm {
                    bottom_km: self.bottom_altitude_km,
                    top_km: self.top_altitude_km,
                }
                .validate()
                .map_err(|_| errors::Error::InvalidRequest)
            }
            ParticlePlacementSemantics::ExplicitIntervalBounds => {
                if self.interval_index_1based == 0 {
                    return Err(errors::Error::InvalidRequest);
                }
                units::PressureRangeHpa {
                    top_hpa: self.top_pressure_hpa,
                    bottom_hpa: self.bottom_pressure_hpa,
                }
                .validate()
                .map_err(|_| errors::Error::InvalidRequest)?;
                let has_top_altitude = self.top_altitude_km.is_finite();
                let has_bottom_altitude = self.bottom_altitude_km.is_finite();
                if has_top_altitude != has_bottom_altitude {
                    return Err(errors::Error::InvalidRequest);
                }
                if self.has_altitude_bounds() {
                    units::AltitudeRangeKm {
                        bottom_km: self.bottom_altitude_km,
                        top_km: self.top_altitude_km,
                    }
                    .validate()
                    .map_err(|_| errors::Error::InvalidRequest)?;
                }
                Ok(())
            }
        }
    }

    pub fn midpoint_altitude_km(self) -> f64 {
        if self.has_altitude_bounds() {
            0.5 * (self.top_altitude_km + self.bottom_altitude_km)
        } else {
            0.0
        }
    }

    pub fn thickness_km(self) -> f64 {
        if self.has_altitude_bounds() {
            (self.top_altitude_km - self.bottom_altitude_km).max(0.0)
        } else {
            0.0
        }
    }
}

fn approx_eq_abs(lhs: f64, rhs: f64, tolerance: f64) -> bool {
    (lhs - rhs).abs() <= tolerance
}
