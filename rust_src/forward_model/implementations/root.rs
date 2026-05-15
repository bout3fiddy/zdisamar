use crate::forward_model::{
    implementations::{instrument, noise, surface, transport},
    instrument_grid::grid_calculation::types,
};

pub type Bindings = types::Implementations;

pub fn exact() -> Bindings {
    Bindings {
        transport: transport::resolve(transport::DISPATCHER_ID)
            .expect("built-in transport provider must exist"),
        surface: surface::resolve(surface::LAMBERTIAN_SURFACE_ID)
            .expect("built-in surface provider must exist"),
        instrument: instrument::resolve(instrument::GENERIC_RESPONSE_ID)
            .expect("built-in instrument provider must exist"),
        noise: noise::resolve(noise::SCENE_NOISE_ID).expect("built-in noise provider must exist"),
    }
}
