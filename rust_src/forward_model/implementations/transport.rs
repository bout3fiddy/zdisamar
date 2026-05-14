use crate::forward_model::radiative_transfer::{
    self, DerivativeSemantics, DispatchRequest, ImplementationClass, Route,
};

pub type PrepareRouteFn = fn(DispatchRequest) -> radiative_transfer::Result<Route>;
pub type ClassificationForRouteFn = fn(Route) -> ImplementationClass;
pub type ProvenanceLabelForRouteFn = fn(Route) -> &'static str;
pub type DerivativeSemanticsForRouteFn = fn(Route) -> DerivativeSemantics;

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub prepare_route: PrepareRouteFn,
    pub classification_for_route: ClassificationForRouteFn,
    pub provenance_label_for_route: ProvenanceLabelForRouteFn,
    pub derivative_semantics_for_route: DerivativeSemanticsForRouteFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    match provider_id {
        // Execution is added with the real dispatcher; this resolver only exposes route metadata for now.
        "builtin.dispatcher" => Some(Implementation {
            id: "builtin.dispatcher",
            prepare_route: radiative_transfer::prepare_route,
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
