use crate::{
    forward_model::radiative_transfer::{
        self, DispatchRequest, Error, ForwardInput, ForwardResult, Result, Route,
    },
    input::{DerivativeMode, ObservationRegime},
};

pub fn prepare(request: DispatchRequest) -> Result<Route> {
    radiative_transfer::prepare_route(request)
}

pub fn execute_prepared(route: Route, input: &ForwardInput) -> Result<ForwardResult> {
    if route.regime != ObservationRegime::Nadir {
        return Err(Error::UnsupportedObservationRegime);
    }
    if route.execution_mode != radiative_transfer::ExecutionMode::Scalar {
        return Err(Error::UnsupportedExecutionMode);
    }
    if route.derivative_mode == DerivativeMode::Numerical {
        return Err(Error::UnsupportedDerivativeMode);
    }
    radiative_transfer::labos::execute(route, input)
}

pub fn execute(request: DispatchRequest, input: &ForwardInput) -> Result<ForwardResult> {
    let route = prepare(request)?;
    execute_prepared(route, input)
}
