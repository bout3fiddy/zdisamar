use crate::common::errors::{Error, Result};

#[derive(Debug, Clone, PartialEq)]
pub struct Parameter {
    pub name: String,
    pub value: f64,
}

impl Default for Parameter {
    fn default() -> Self {
        Self {
            name: String::new(),
            value: 0.0,
        }
    }
}

impl Parameter {
    pub fn validate(&self) -> Result<()> {
        if self.name.is_empty() || !self.value.is_finite() {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum SurfaceKind {
    #[default]
    Lambertian,
    WavelDependent,
}

impl SurfaceKind {
    pub fn parse(value: &str) -> Result<Self> {
        match value {
            "lambertian" => Ok(Self::Lambertian),
            "wavel_dependent" => Ok(Self::WavelDependent),
            _ => Err(Error::InvalidRequest),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Lambertian => "lambertian",
            Self::WavelDependent => "wavel_dependent",
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct Surface {
    pub kind: SurfaceKind,
    pub albedo: f64,
    pub pressure_hpa: f64,
    pub parameters: Vec<Parameter>,
}

impl Default for Surface {
    fn default() -> Self {
        Self {
            kind: SurfaceKind::Lambertian,
            albedo: 0.0,
            pressure_hpa: 0.0,
            parameters: Vec::new(),
        }
    }
}

impl Surface {
    pub fn validate(&self) -> Result<()> {
        if self.albedo < 0.0 || self.albedo > 1.0 {
            return Err(Error::InvalidRequest);
        }
        // A zero pressure means "not provided"; any provided pressure must be physical.
        if self.pressure_hpa != 0.0 && (!self.pressure_hpa.is_finite() || self.pressure_hpa <= 0.0)
        {
            return Err(Error::InvalidRequest);
        }
        for parameter in &self.parameters {
            parameter.validate()?;
        }
        Ok(())
    }
}
