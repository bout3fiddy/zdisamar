use crate::common::errors::{Error, Result};

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum BindingKind {
    #[default]
    None,
    Atmosphere,
    BundleDefault,
    Asset,
    Ingest,
    StageProduct,
    ExternalObservation,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct NamedRef {
    pub name: String,
}

impl NamedRef {
    pub fn validate(&self) -> Result<()> {
        if self.name.is_empty() {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct IngestRef {
    pub full_name: String,
    pub ingest_name: String,
    pub output_name: String,
}

impl IngestRef {
    pub fn from_full_name(full_name: impl Into<String>) -> Self {
        let full_name = full_name.into();
        // Split once because output names may contain their own dots.
        let (ingest_name, output_name) = if let Some(index) = full_name.find('.') {
            (
                full_name[..index].to_string(),
                full_name[index + 1..].to_string(),
            )
        } else {
            (String::new(), String::new())
        };
        Self {
            full_name,
            ingest_name,
            output_name,
        }
    }

    pub fn validate(&self) -> Result<()> {
        if self.full_name.is_empty() || self.ingest_name.is_empty() || self.output_name.is_empty() {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub enum Binding {
    #[default]
    None,
    Atmosphere,
    BundleDefault,
    Asset(NamedRef),
    Ingest(IngestRef),
    StageProduct(NamedRef),
    ExternalObservation(NamedRef),
}

impl Binding {
    pub fn enabled(&self) -> bool {
        self.kind() != BindingKind::None
    }

    pub fn kind(&self) -> BindingKind {
        match self {
            Self::None => BindingKind::None,
            Self::Atmosphere => BindingKind::Atmosphere,
            Self::BundleDefault => BindingKind::BundleDefault,
            Self::Asset(_) => BindingKind::Asset,
            Self::Ingest(_) => BindingKind::Ingest,
            Self::StageProduct(_) => BindingKind::StageProduct,
            Self::ExternalObservation(_) => BindingKind::ExternalObservation,
        }
    }

    pub fn name(&self) -> &str {
        match self {
            Self::Asset(value) | Self::StageProduct(value) | Self::ExternalObservation(value) => {
                &value.name
            }
            Self::Ingest(value) => &value.full_name,
            Self::None | Self::Atmosphere | Self::BundleDefault => "",
        }
    }

    pub fn ingest_reference(&self) -> Option<&IngestRef> {
        match self {
            Self::Ingest(value) => Some(value),
            _ => None,
        }
    }

    pub fn validate(&self) -> Result<()> {
        match self {
            Self::None | Self::Atmosphere | Self::BundleDefault => Ok(()),
            Self::Asset(value) | Self::StageProduct(value) | Self::ExternalObservation(value) => {
                value.validate()
            }
            Self::Ingest(value) => value.validate(),
        }
    }
}
