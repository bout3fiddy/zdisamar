use crate::{
    common::{errors, units},
    input::atmosphere::types::PartitionLabel,
};

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Subcolumn {
    pub index_1based: u32,
    pub label: PartitionLabel,
    pub bottom_altitude_km: f64,
    pub top_altitude_km: f64,
    pub gaussian_nodes: Vec<f64>,
    pub gaussian_weights: Vec<f64>,
}

impl Subcolumn {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.index_1based == 0 {
            return Err(errors::Error::InvalidRequest);
        }
        units::AltitudeRangeKm {
            bottom_km: self.bottom_altitude_km,
            top_km: self.top_altitude_km,
        }
        .validate()
        .map_err(|_| errors::Error::InvalidRequest)?;
        if self.gaussian_nodes.len() != self.gaussian_weights.len() {
            return Err(errors::Error::InvalidRequest);
        }
        for node in &self.gaussian_nodes {
            if !node.is_finite() {
                return Err(errors::Error::InvalidRequest);
            }
        }
        for weight in &self.gaussian_weights {
            if !weight.is_finite() || *weight < 0.0 {
                return Err(errors::Error::InvalidRequest);
            }
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SubcolumnLayout {
    pub enabled: bool,
    pub boundary_layer_top_pressure_hpa: f64,
    pub boundary_layer_top_altitude_km: f64,
    pub tropopause_pressure_hpa: f64,
    pub tropopause_altitude_km: f64,
    pub subcolumns: Vec<Subcolumn>,
}

impl SubcolumnLayout {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if !self.enabled {
            if !self.subcolumns.is_empty() {
                return Err(errors::Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.boundary_layer_top_pressure_hpa < 0.0 || self.tropopause_pressure_hpa < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }
        if self.boundary_layer_top_altitude_km < 0.0 || self.tropopause_altitude_km < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }

        let mut previous_top_km = 0.0;
        for (index, subcolumn) in self.subcolumns.iter().enumerate() {
            subcolumn.validate()?;
            if subcolumn.index_1based != index as u32 + 1 {
                return Err(errors::Error::InvalidRequest);
            }
            if index != 0 && subcolumn.bottom_altitude_km < previous_top_km {
                return Err(errors::Error::InvalidRequest);
            }
            previous_top_km = subcolumn.top_altitude_km;
        }
        Ok(())
    }

    pub fn label_for_altitude(&self, altitude_km: f64) -> PartitionLabel {
        if !self.enabled || self.subcolumns.is_empty() {
            return PartitionLabel::Unspecified;
        }
        for subcolumn in &self.subcolumns {
            if altitude_km >= subcolumn.bottom_altitude_km
                && altitude_km <= subcolumn.top_altitude_km
            {
                return subcolumn.label;
            }
        }
        if altitude_km < self.subcolumns[0].bottom_altitude_km {
            self.subcolumns[0].label
        } else {
            self.subcolumns[self.subcolumns.len() - 1].label
        }
    }
}
