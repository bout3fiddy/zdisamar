use crate::common::errors;

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub enum Id {
    #[default]
    Unset,
    Generic,
    Tropomi,
    Synthetic,
    Custom(String),
}

impl Id {
    pub fn parse(value: &str) -> Self {
        match value {
            "" => Self::Unset,
            "generic" => Self::Generic,
            "tropomi" => Self::Tropomi,
            "synthetic" => Self::Synthetic,
            _ => Self::Custom(value.to_string()),
        }
    }

    pub fn label(&self) -> &str {
        match self {
            Self::Unset => "",
            Self::Generic => "generic",
            Self::Tropomi => "tropomi",
            Self::Synthetic => "synthetic",
            Self::Custom(value) => value,
        }
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        match self {
            Self::Unset => Err(errors::Error::MissingObservationInstrument),
            Self::Custom(value) if value.is_empty() => {
                Err(errors::Error::MissingObservationInstrument)
            }
            Self::Generic | Self::Tropomi | Self::Synthetic | Self::Custom(_) => Ok(()),
        }
    }
}
