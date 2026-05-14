use crate::{
    forward_model::radiative_transfer::ForwardResult,
    input::{Scene, SurfaceKind},
};

pub type BrdfFactorFn = fn(EvaluationContext<'_>) -> f64;

#[derive(Debug, Clone, Copy)]
pub struct EvaluationContext<'a> {
    pub scene: &'a Scene,
    pub wavelength_nm: f64,
    pub safe_span: f64,
    pub phase: f64,
    pub forward: ForwardResult,
}

#[derive(Debug, Clone, Copy)]
pub struct Implementation {
    pub id: &'static str,
    pub brdf_factor: BrdfFactorFn,
}

pub fn resolve(provider_id: &str) -> Option<Implementation> {
    match provider_id {
        "builtin.lambertian_surface" => Some(Implementation {
            id: "builtin.lambertian_surface",
            brdf_factor: lambertian_brdf_factor,
        }),
        _ => None,
    }
}

fn lambertian_brdf_factor(context: EvaluationContext<'_>) -> f64 {
    let _ = context.wavelength_nm;
    let _ = context.safe_span;
    let _ = context.phase;
    let _ = context.forward;
    match context.scene.surface.kind {
        SurfaceKind::Lambertian => 1.0,
        // Spectral dependence is already in the albedo schedule; the directional BRDF factor stays isotropic.
        SurfaceKind::WavelDependent => 1.0,
    }
}
