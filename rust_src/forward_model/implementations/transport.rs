use crate::forward_model::radiative_transfer::{
    common_route,
    common_types::{
        DerivativeSemantics, DispatchRequest, Error, ForwardInput, ForwardResult,
        ImplementationClass, Route,
    },
    labos::{execute, workspace::Workspace},
};

pub const DISPATCHER_ID: &str = "builtin.dispatcher";

pub type PrepareRouteFn = fn(DispatchRequest) -> Result<Route, Error>;
pub type ExecutePreparedFn = fn(Route, &ForwardInput) -> Result<ForwardResult, Error>;
pub type ExecutePreparedWithLabosWorkspaceFn =
    for<'a> fn(Route, &'a ForwardInput, Option<&'a mut Workspace>) -> Result<ForwardResult, Error>;

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub prepare_route: PrepareRouteFn,
    pub execute_prepared: ExecutePreparedFn,
    pub execute_prepared_with_labos_workspace: Option<ExecutePreparedWithLabosWorkspaceFn>,
    pub classification_for_route: fn(Route) -> ImplementationClass,
    pub provenance_label_for_route: fn(Route) -> &'static str,
    pub derivative_semantics_for_route: fn(Route) -> DerivativeSemantics,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    if provider_id == DISPATCHER_ID {
        return Some(Implementation {
            id: DISPATCHER_ID,
            prepare_route: common_route::prepare_route,
            execute_prepared,
            execute_prepared_with_labos_workspace: Some(execute::execute_with_workspace),
            classification_for_route,
            provenance_label_for_route,
            derivative_semantics_for_route,
        });
    }
    None
}

fn execute_prepared(route: Route, input: &ForwardInput) -> Result<ForwardResult, Error> {
    execute::execute(route, input)
}

fn classification_for_route(route: Route) -> ImplementationClass {
    route.family.classification()
}

fn provenance_label_for_route(route: Route) -> &'static str {
    route.family.provenance_label()
}

fn derivative_semantics_for_route(route: Route) -> DerivativeSemantics {
    route.derivative_semantics()
}
