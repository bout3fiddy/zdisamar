use crate::{
    forward_model::{
        instrument_grid::grid_calculation::{
            simulate::{self, simulate_product},
            types::InstrumentGridProduct,
        },
        method::Method,
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::{
            common_route,
            common_types::{self, DispatchRequest, ExecutionMode, RadiativeTransferControls},
        },
    },
    input::scene::Scene,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    Route(common_types::Error),
    Simulation(simulate::Error),
}

impl From<common_types::Error> for Error {
    fn from(value: common_types::Error) -> Self {
        Self::Route(value)
    }
}

impl From<simulate::Error> for Error {
    fn from(value: simulate::Error) -> Self {
        Self::Simulation(value)
    }
}

pub fn run(
    scene: &Scene,
    optics: &PreparedOpticalState,
    method: Method,
    rtm_controls: RadiativeTransferControls,
) -> Result<InstrumentGridProduct, Error> {
    match method {
        Method::Exact => {}
    }

    let route = common_route::prepare_route(DispatchRequest {
        regime: scene.observation_model.regime,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: crate::input::scene::DerivativeMode::None,
        rtm_controls,
    })?;
    simulate_product(scene, route, optics).map_err(Error::from)
}
