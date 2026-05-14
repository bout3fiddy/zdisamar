use crate::forward_model::radiative_transfer::{
    self, DerivativeSemantics, DispatchRequest, ForwardInput, ForwardResult, ImplementationClass,
    Route,
};

pub type PrepareRouteFn = fn(DispatchRequest) -> radiative_transfer::Result<Route>;
pub type ExecutePreparedFn = fn(Route, &ForwardInput) -> radiative_transfer::Result<ForwardResult>;
pub type ClassificationForRouteFn = fn(Route) -> ImplementationClass;
pub type ProvenanceLabelForRouteFn = fn(Route) -> &'static str;
pub type DerivativeSemanticsForRouteFn = fn(Route) -> DerivativeSemantics;

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub prepare_route: PrepareRouteFn,
    pub execute_prepared: ExecutePreparedFn,
    pub classification_for_route: ClassificationForRouteFn,
    pub provenance_label_for_route: ProvenanceLabelForRouteFn,
    pub derivative_semantics_for_route: DerivativeSemanticsForRouteFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    match provider_id {
        "builtin.dispatcher" => Some(Implementation {
            id: "builtin.dispatcher",
            prepare_route: radiative_transfer::dispatcher::prepare,
            execute_prepared: radiative_transfer::dispatcher::execute_prepared,
            classification_for_route,
            provenance_label_for_route,
            derivative_semantics_for_route,
        }),
        _ => None,
    }
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
