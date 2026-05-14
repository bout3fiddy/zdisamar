pub mod atmospheric_types;
pub mod bands;
pub mod binding;
pub mod geometry;
pub mod surface;

pub use atmospheric_types::{AbsorberSpecies, AerosolType, CloudType};
pub use bands::{SpectralBand, SpectralBandSet, SpectralWindow};
pub use binding::{Binding, BindingKind, IngestRef, NamedRef};
pub use geometry::{Geometry, Model};
pub use surface::{Parameter, Surface, SurfaceKind};
