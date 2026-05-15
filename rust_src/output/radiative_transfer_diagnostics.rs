use super::atmospheric_budget::{self, AtmosphericBudgetRow};
use crate::{
    common::errors,
    forward_model::{
        optical_properties::state_build::PreparedOpticalState,
        radiative_transfer::common_types::Route,
    },
    input::scene::Scene,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectrumView<'a> {
    pub wavelength_nm: &'a [f64],
    pub reflectance: &'a [f64],
    pub radiance: &'a [f64],
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct RadiativeTransferDiagnosticRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub altitude_km: f64,
    pub total_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_scattering_optical_depth: f64,
    pub single_scatter_albedo: f64,
    pub cumulative_optical_depth_above: f64,
    pub mid_layer_transmission_proxy: f64,
    pub direct_surface_transmission_proxy: f64,
    pub atmospheric_scattering_source_proxy: f64,
    pub absorption_loss_proxy: f64,
    pub pseudo_spherical_airmass_factor: f64,
    pub n_streams: u32,
    pub integrate_source_function: u8,
    pub final_reflectance: f64,
    pub final_radiance: f64,
}

pub fn build(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    route: Route,
    wavelengths_nm: &[f64],
    spectrum: Option<SpectrumView<'_>>,
) -> Result<Vec<RadiativeTransferDiagnosticRow>, errors::Error> {
    let budget = atmospheric_budget::build(scene, prepared, wavelengths_nm)?;
    let mut rows = vec![empty_row(); budget.len()];
    let airmass = airmass_factor(scene);
    let mut row_index = 0;
    while row_index < budget.len() {
        let wavelength_nm = budget[row_index].wavelength_nm;
        let mut end_index = row_index;
        while end_index < budget.len() && budget[end_index].wavelength_nm == wavelength_nm {
            end_index += 1;
        }
        fill_wavelength_rows(
            &budget[row_index..end_index],
            &mut rows[row_index..end_index],
            route,
            airmass,
            spectrum,
        );
        row_index = end_index;
    }
    Ok(rows)
}

fn fill_wavelength_rows(
    budget: &[AtmosphericBudgetRow],
    rows: &mut [RadiativeTransferDiagnosticRow],
    route: Route,
    airmass: f64,
    spectrum: Option<SpectrumView<'_>>,
) {
    let mut cumulative = 0.0;
    for (source, target) in budget.iter().zip(rows) {
        let optical_depth = source.total_optical_depth.max(0.0);
        let mid_depth = cumulative + 0.5 * optical_depth;
        let transmission = (-airmass * mid_depth).exp();
        *target = RadiativeTransferDiagnosticRow {
            wavelength_nm: source.wavelength_nm,
            layer_index: source.layer_index,
            sublayer_index: source.sublayer_index,
            global_sublayer_index: source.global_sublayer_index,
            interval_index_1based: source.interval_index_1based,
            altitude_km: source.altitude_km,
            total_optical_depth: source.total_optical_depth,
            total_absorption_optical_depth: source.total_absorption_optical_depth,
            total_scattering_optical_depth: source.total_scattering_optical_depth,
            single_scatter_albedo: source.single_scatter_albedo,
            cumulative_optical_depth_above: cumulative,
            mid_layer_transmission_proxy: transmission,
            direct_surface_transmission_proxy: (-airmass * (cumulative + optical_depth)).exp(),
            atmospheric_scattering_source_proxy: source.total_scattering_optical_depth
                * transmission,
            absorption_loss_proxy: source.total_absorption_optical_depth * transmission,
            pseudo_spherical_airmass_factor: airmass,
            n_streams: u32::from(route.rtm_controls.n_streams),
            integrate_source_function: u8::from(route.rtm_controls.integrate_source_function),
            final_reflectance: interpolate_spectrum(
                spectrum,
                SpectrumColumn::Reflectance,
                source.wavelength_nm,
            ),
            final_radiance: interpolate_spectrum(
                spectrum,
                SpectrumColumn::Radiance,
                source.wavelength_nm,
            ),
        };
        cumulative += optical_depth;
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum SpectrumColumn {
    Reflectance,
    Radiance,
}

fn interpolate_spectrum(
    spectrum: Option<SpectrumView<'_>>,
    column: SpectrumColumn,
    wavelength_nm: f64,
) -> f64 {
    let Some(spectrum) = spectrum else {
        return f64::NAN;
    };
    let values = match column {
        SpectrumColumn::Reflectance => spectrum.reflectance,
        SpectrumColumn::Radiance => spectrum.radiance,
    };
    if spectrum.wavelength_nm.is_empty() || values.is_empty() {
        return f64::NAN;
    }
    if wavelength_nm <= spectrum.wavelength_nm[0] {
        return values[0];
    }
    let last_index = spectrum.wavelength_nm.len().min(values.len()) - 1;
    if wavelength_nm >= spectrum.wavelength_nm[last_index] {
        return values[last_index];
    }

    let mut lower_index = 0;
    while lower_index + 1 < spectrum.wavelength_nm.len()
        && spectrum.wavelength_nm[lower_index + 1] < wavelength_nm
    {
        lower_index += 1;
    }
    let upper_index = lower_index + 1;
    let lower_wavelength = spectrum.wavelength_nm[lower_index];
    let upper_wavelength = spectrum.wavelength_nm[upper_index];
    let denominator = upper_wavelength - lower_wavelength;
    if denominator == 0.0 {
        return values[upper_index];
    }
    let blend = (wavelength_nm - lower_wavelength) / denominator;
    values[lower_index] + blend * (values[upper_index] - values[lower_index])
}

fn airmass_factor(scene: &Scene) -> f64 {
    let mu0 = scene.geometry.solar_cosine_at_altitude(0.0).max(0.05);
    let muv = scene.geometry.viewing_cosine_at_altitude(0.0).max(0.05);
    (1.0 / mu0) + (1.0 / muv)
}

fn empty_row() -> RadiativeTransferDiagnosticRow {
    RadiativeTransferDiagnosticRow {
        wavelength_nm: 0.0,
        layer_index: 0,
        sublayer_index: 0,
        global_sublayer_index: 0,
        interval_index_1based: 0,
        altitude_km: 0.0,
        total_optical_depth: 0.0,
        total_absorption_optical_depth: 0.0,
        total_scattering_optical_depth: 0.0,
        single_scatter_albedo: 0.0,
        cumulative_optical_depth_above: 0.0,
        mid_layer_transmission_proxy: 0.0,
        direct_surface_transmission_proxy: 0.0,
        atmospheric_scattering_source_proxy: 0.0,
        absorption_loss_proxy: 0.0,
        pseudo_spherical_airmass_factor: 0.0,
        n_streams: 0,
        integrate_source_function: 0,
        final_reflectance: 0.0,
        final_radiance: 0.0,
    }
}
