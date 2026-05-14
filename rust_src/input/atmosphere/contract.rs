use crate::{
    common::errors,
    input::{
        atmosphere::{interval_grid::IntervalGrid, subcolumns::SubcolumnLayout},
        binding::Binding,
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct Atmosphere {
    pub layer_count: u32,
    pub sublayer_divisions: u8,
    pub has_clouds: bool,
    pub has_aerosols: bool,
    pub profile_source: Binding,
    pub surface_pressure_hpa: f64,
    pub interval_grid: IntervalGrid,
    pub subcolumns: SubcolumnLayout,
}

impl Default for Atmosphere {
    fn default() -> Self {
        Self {
            layer_count: 0,
            sublayer_divisions: 3,
            has_clouds: false,
            has_aerosols: false,
            profile_source: Binding::None,
            surface_pressure_hpa: 0.0,
            interval_grid: IntervalGrid::default(),
            subcolumns: SubcolumnLayout::default(),
        }
    }
}

impl Atmosphere {
    pub fn prepared_layer_count(&self) -> u32 {
        if self.interval_grid.enabled() {
            self.interval_grid.interval_count()
        } else {
            self.layer_count
        }
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        self.profile_source.validate()?;
        self.interval_grid.validate(self.sublayer_divisions)?;
        self.subcolumns.validate()?;

        if self.prepared_layer_count() == 0
            && (self.has_clouds
                || self.has_aerosols
                || self.profile_source.enabled()
                || self.surface_pressure_hpa != 0.0)
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.sublayer_divisions == 0 {
            return Err(errors::Error::InvalidRequest);
        }
        if self.surface_pressure_hpa != 0.0
            && (!self.surface_pressure_hpa.is_finite() || self.surface_pressure_hpa <= 0.0)
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.interval_grid.enabled()
            && self.layer_count != 0
            && self.layer_count != self.interval_grid.interval_count()
        {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}
