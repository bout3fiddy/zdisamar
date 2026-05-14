use crate::common::errors;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BindingKind {
    None,
    Atmosphere,
    BundleDefault,
    Asset,
    Ingest,
    StageProduct,
    ExternalObservation,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct NamedRef {
    pub name: String,
}

impl NamedRef {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.name.is_empty() {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct IngestRef {
    pub full_name: String,
    pub ingest_name: String,
    pub output_name: String,
}

impl IngestRef {
    pub fn from_full_name(full_name: impl Into<String>) -> Self {
        let full_name = full_name.into();
        let (ingest_name, output_name) = split_ingest_name(&full_name);
        let ingest_name = ingest_name.to_owned();
        let output_name = output_name.to_owned();
        Self {
            full_name,
            // Zig stores these as slices into full_name; owned strings keep the Rust value movable.
            ingest_name,
            output_name,
        }
    }

    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.full_name.is_empty() || self.ingest_name.is_empty() || self.output_name.is_empty() {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
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

    pub fn validate(&self) -> Result<(), errors::Error> {
        match self {
            Self::None | Self::Atmosphere | Self::BundleDefault => Ok(()),
            Self::Asset(value) | Self::StageProduct(value) | Self::ExternalObservation(value) => {
                value.validate()
            }
            Self::Ingest(value) => value.validate(),
        }
    }
}

fn split_ingest_name(full_name: &str) -> (&str, &str) {
    if let Some(dot_index) = full_name.find('.') {
        (&full_name[..dot_index], &full_name[dot_index + 1..])
    } else {
        ("", "")
    }
}
