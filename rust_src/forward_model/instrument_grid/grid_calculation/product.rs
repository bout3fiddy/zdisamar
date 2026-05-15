use super::{
    simulate::{self, simulate_product_with_implementations},
    storage::ProductStorage,
    types::{Implementations, InstrumentGridProduct, InstrumentGridProductView},
    wavelength_sampling,
};
use crate::forward_model::{
    instrument_grid::spectral_math::grid::{ResolvedAxis, SpectralGrid},
    optical_properties::state_build::PreparedOpticalState,
    radiative_transfer::common_types::Route,
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

pub fn warm_product_workspace(
    storage: &mut ProductStorage,
    scene: &Scene,
    route: Route,
    _prepared: &PreparedOpticalState,
    implementations: Implementations,
) -> Result<(), simulate::Error> {
    scene.validate()?;
    {
        let _ = storage.buffers(scene, route, implementations);
    }
    let axis = ResolvedAxis {
        base: SpectralGrid {
            start_nm: scene.spectral_grid.start_nm,
            end_nm: scene.spectral_grid.end_nm,
            sample_count: scene.spectral_grid.sample_count,
        },
        explicit_wavelengths_nm: scene.observation_model.measured_wavelengths_nm.clone(),
    };
    axis.validate()?;
    storage.wavelength_sampling =
        wavelength_sampling::build_wavelength_sampling(scene, &axis, implementations.instrument)?;
    storage.forward_misses =
        wavelength_sampling::collect_unique_forward_misses(&storage.wavelength_sampling);
    storage.wavelength_plan_valid = true;
    storage.forward_misses_valid = true;
    Ok(())
}

pub fn simulate_product_with_workspace<'a>(
    storage: &'a mut ProductStorage,
    scene: &Scene,
    route: Route,
    prepared: &PreparedOpticalState,
    implementations: Implementations,
) -> Result<InstrumentGridProductView<'a>, simulate::Error> {
    let product = simulate_product(scene, route, prepared, implementations)?;
    let summary = product.summary.clone();
    storage.wavelengths = product.wavelengths;
    storage.radiance = product.radiance;
    storage.irradiance = product.irradiance;
    storage.reflectance = product.reflectance;
    storage.noise_sigma = product.noise_sigma;
    storage.radiance_noise_sigma = product.radiance_noise_sigma;
    storage.irradiance_noise_sigma = product.irradiance_noise_sigma;
    storage.reflectance_noise_sigma = product.reflectance_noise_sigma;
    if let Some(jacobian) = product.jacobian {
        storage.jacobian = jacobian;
    } else {
        storage.jacobian.clear();
    }

    Ok(InstrumentGridProductView {
        summary,
        wavelengths: &storage.wavelengths,
        radiance: &storage.radiance,
        irradiance: &storage.irradiance,
        reflectance: &storage.reflectance,
        noise_sigma: &storage.noise_sigma,
        radiance_noise_sigma: &storage.radiance_noise_sigma,
        irradiance_noise_sigma: &storage.irradiance_noise_sigma,
        reflectance_noise_sigma: &storage.reflectance_noise_sigma,
        jacobian: (!storage.jacobian.is_empty()).then_some(storage.jacobian.as_slice()),
        effective_air_mass_factor: product.effective_air_mass_factor,
        effective_single_scatter_albedo: product.effective_single_scatter_albedo,
        effective_temperature_k: product.effective_temperature_k,
        effective_pressure_hpa: product.effective_pressure_hpa,
        gas_optical_depth: product.gas_optical_depth,
        cia_optical_depth: product.cia_optical_depth,
        aerosol_optical_depth: product.aerosol_optical_depth,
        cloud_optical_depth: product.cloud_optical_depth,
        total_optical_depth: product.total_optical_depth,
        depolarization_factor: product.depolarization_factor,
        d_optical_depth_d_temperature: product.d_optical_depth_d_temperature,
    })
}
