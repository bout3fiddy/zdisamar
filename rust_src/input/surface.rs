use crate::common::errors;

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Parameter {
    pub name: String,
    pub value: f64,
}

impl Parameter {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.name.is_empty() || !self.value.is_finite() {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum Kind {
    #[default]
    Lambertian,
    WavelDependent,
}

impl Kind {
    pub fn parse(value: &str) -> Result<Self, errors::Error> {
        match value {
            "lambertian" => Ok(Self::Lambertian),
            "wavel_dependent" => Ok(Self::WavelDependent),
            _ => Err(errors::Error::InvalidRequest),
        }
    }

    pub fn label(self) -> &'static str {
        match self {
            Self::Lambertian => "lambertian",
            Self::WavelDependent => "wavel_dependent",
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Surface {
    pub kind: Kind,
    pub albedo: f64,
    pub pressure_hpa: f64,
    pub parameters: Vec<Parameter>,
}

impl Surface {
    pub fn validate(&self) -> Result<(), errors::Error> {
        // Albedo is unitless reflectance; validation only bounds finite values by compare.
        if self.albedo < 0.0 || self.albedo > 1.0 {
            return Err(errors::Error::InvalidRequest);
        }
        if self.pressure_hpa != 0.0 && (!self.pressure_hpa.is_finite() || self.pressure_hpa <= 0.0)
        {
            return Err(errors::Error::InvalidRequest);
        }
        for parameter in &self.parameters {
            parameter.validate()?;
        }
        Ok(())
    }
}
