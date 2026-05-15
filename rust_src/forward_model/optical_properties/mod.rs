pub mod particle_support;
pub mod shared;
pub mod state_build;

pub use state_build::{
    OpticalDepthBreakdown, PreparationInputs, PreparedLayer, PreparedOpticalState, PreparedSublayer,
};

use crate::{common::errors, input::scene::Scene};

pub fn prepare(
    scene: &Scene,
    inputs: PreparationInputs<'_>,
) -> Result<PreparedOpticalState, errors::Error> {
    state_build::prepare(scene, inputs)
}
