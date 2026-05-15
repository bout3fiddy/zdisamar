use super::{
    OpticalDepthBreakdown, PreparedOpticalState, collision_induced_sigma_at_wavelength,
    particle_optical_depth_at_wavelength, total_cross_section_at_wavelength,
};
use crate::{common::errors, input::reference::rayleigh};

pub fn optical_depth_breakdown_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<OpticalDepthBreakdown, errors::Error> {
    if prepared.sublayers.is_some() {
        // The sublayer branch needs the full layer evaluator and spectroscopy
        // cache. Erroring here avoids treating the single-layer shortcut as a
        // vertical-grid implementation.
        return Err(errors::Error::InvalidRequest);
    }

    let gas_absorption_optical_depth = total_cross_section_at_wavelength(prepared, wavelength_nm)?
        * prepared.column_density_factor;
    let gas_scattering_optical_depth =
        rayleigh::cross_section_cm2(wavelength_nm) * prepared.air_column_density_factor;
    let cia_optical_depth = collision_induced_sigma_at_wavelength(prepared, wavelength_nm)
        * prepared.cia_pair_path_factor_cm5;
    let aerosol_optical_depth = particle_optical_depth_at_wavelength(
        prepared.aerosol_optical_depth,
        prepared.aerosol_base_optical_depth,
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        &prepared.aerosol_fraction_control,
        wavelength_nm,
    );
    let cloud_optical_depth = particle_optical_depth_at_wavelength(
        prepared.cloud_optical_depth,
        prepared.cloud_base_optical_depth,
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        &prepared.cloud_fraction_control,
        wavelength_nm,
    );
    let particle_albedos = prepared.resolved_particle_single_scatter_albedos();

    Ok(OpticalDepthBreakdown {
        gas_absorption_optical_depth,
        gas_scattering_optical_depth,
        cia_optical_depth,
        aerosol_optical_depth,
        aerosol_scattering_optical_depth: aerosol_optical_depth * particle_albedos.aerosol,
        cloud_optical_depth,
        cloud_scattering_optical_depth: cloud_optical_depth * particle_albedos.cloud,
    })
}

pub fn collision_induced_optical_depth_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    Ok(optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?.cia_optical_depth)
}

pub fn gas_optical_depth_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    let breakdown = optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?;
    Ok(breakdown.gas_absorption_optical_depth + breakdown.gas_scattering_optical_depth)
}

pub fn aerosol_optical_depth_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    Ok(optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?.aerosol_optical_depth)
}

pub fn cloud_optical_depth_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    Ok(optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?.cloud_optical_depth)
}

pub fn total_optical_depth_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    Ok(optical_depth_breakdown_at_wavelength(prepared, wavelength_nm)?.total_optical_depth())
}
