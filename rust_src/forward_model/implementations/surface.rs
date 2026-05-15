use crate::{
    forward_model::{
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::common_types::ForwardResult,
    },
    input::{scene::Scene, surface::Kind},
};

pub const LAMBERTIAN_SURFACE_ID: &str = "builtin.lambertian_surface";

pub struct EvaluationContext<'a> {
    pub scene: &'a Scene,
    pub prepared: &'a PreparedOpticalState,
    pub wavelength_nm: f64,
    pub safe_span: f64,
    pub phase: f64,
    pub forward: &'a ForwardResult,
}

pub type BrdfFactorFn = for<'a> fn(EvaluationContext<'a>) -> f64;

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub brdf_factor: BrdfFactorFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    if provider_id == LAMBERTIAN_SURFACE_ID {
        return Some(Implementation {
            id: LAMBERTIAN_SURFACE_ID,
            brdf_factor: lambertian_brdf_factor,
        });
    }
    None
}

fn lambertian_brdf_factor(context: EvaluationContext<'_>) -> f64 {
    let _ = context.prepared;
    let _ = context.wavelength_nm;
    let _ = context.safe_span;
    let _ = context.phase;
    let _ = context.forward;
    match context.scene.surface.kind {
        // Albedo already enters the RTM input, so isotropic surfaces keep this directional factor at one.
        Kind::Lambertian | Kind::WavelDependent => 1.0,
    }
}
