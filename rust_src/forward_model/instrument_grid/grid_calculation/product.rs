use super::{
    simulate::{self, simulate_product_with_implementations},
    types::{Implementations, InstrumentGridProduct},
};
use crate::forward_model::{
    optical_properties::state_build::PreparedOpticalState, radiative_transfer::common_types::Route,
};
use crate::input::scene::Scene;

pub fn simulate_product(
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    implementations: Implementations,
) -> Result<InstrumentGridProduct, simulate::Error> {
    simulate_product_with_implementations(scene, route, prepared, implementations)
}
