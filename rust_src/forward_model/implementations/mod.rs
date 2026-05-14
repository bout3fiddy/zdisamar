pub mod instrument;
pub mod noise;
pub mod surface;
pub mod transport;

pub type Bindings = crate::forward_model::instrument_grid::grid_calculation::types::Implementations;

pub fn exact() -> Bindings {
    Bindings {
        transport: transport::resolve("builtin.dispatcher")
            .expect("builtin dispatcher provider must exist"),
        surface: surface::resolve("builtin.lambertian_surface")
            .expect("builtin Lambertian surface provider must exist"),
        instrument: instrument::resolve("builtin.generic_response")
            .expect("builtin generic response provider must exist"),
        noise: noise::resolve("builtin.scene_noise")
            .expect("builtin scene noise provider must exist"),
    }
}
