use crate::{
    common::errors,
    forward_model::optical_properties::state_build::{
        OpticalDepthBreakdown, PreparedLayer, PreparedOpticalState, PreparedSublayer,
        PreparedSupportRowKind, ProfileNodeSpectroscopyCache, particle_optical_depth_at_wavelength,
        state_optical_depth::evaluate_layer_at_wavelength_with_spectroscopy_cache,
    },
    input::{atmosphere::PartitionLabel, reference::rayleigh, scene::Scene},
};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum SupportRowKind {
    #[default]
    Physical = 0,
    ParityBoundary = 1,
    ParityActive = 2,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum SubcolumnLabel {
    #[default]
    Unspecified = 0,
    BoundaryLayer = 1,
    FreeTroposphere = 2,
    FitInterval = 3,
    Stratosphere = 4,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AtmosphericBudgetRow {
    pub wavelength_nm: f64,
    pub layer_index: u32,
    pub sublayer_index: u32,
    pub global_sublayer_index: u32,
    pub interval_index_1based: u32,
    pub support_row_kind: SupportRowKind,
    pub subcolumn_label: SubcolumnLabel,
    pub altitude_km: f64,
    pub top_altitude_km: f64,
    pub bottom_altitude_km: f64,
    pub pressure_hpa: f64,
    pub top_pressure_hpa: f64,
    pub bottom_pressure_hpa: f64,
    pub temperature_k: f64,
    pub number_density_cm3: f64,
    pub oxygen_number_density_cm3: f64,
    pub absorber_number_density_cm3: f64,
    pub path_length_cm: f64,
    pub aerosol_fraction: f64,
    pub cloud_fraction: f64,
    pub gas_absorption_optical_depth: f64,
    pub gas_scattering_optical_depth: f64,
    pub cia_optical_depth: f64,
    pub aerosol_optical_depth: f64,
    pub aerosol_scattering_optical_depth: f64,
    pub aerosol_absorption_optical_depth: f64,
    pub cloud_optical_depth: f64,
    pub cloud_scattering_optical_depth: f64,
    pub cloud_absorption_optical_depth: f64,
    pub total_absorption_optical_depth: f64,
    pub total_scattering_optical_depth: f64,
    pub total_optical_depth: f64,
    pub single_scatter_albedo: f64,
}

pub fn build(
    scene: &Scene,
    prepared: &PreparedOpticalState,
    wavelengths_nm: &[f64],
) -> Result<Vec<AtmosphericBudgetRow>, errors::Error> {
    let vertical_count = prepared
        .sublayers
        .as_ref()
        .map_or(prepared.layers.len(), Vec::len);
    let mut rows = Vec::with_capacity(wavelengths_nm.len() * vertical_count);
    for &wavelength_nm in wavelengths_nm {
        if let Some(sublayers) = &prepared.sublayers {
            let profile_cache = ProfileNodeSpectroscopyCache::new(prepared, wavelength_nm);
            for (sublayer_index, &sublayer) in sublayers.iter().enumerate() {
                rows.push(sublayer_row(
                    prepared,
                    scene,
                    wavelength_nm,
                    sublayers,
                    sublayer,
                    sublayer_index,
                    &profile_cache,
                )?);
            }
        } else {
            for &layer in &prepared.layers {
                rows.push(layer_row(prepared, wavelength_nm, layer));
            }
        }
    }
    Ok(rows)
}

fn sublayer_row(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    sublayer: PreparedSublayer,
    sublayer_index: usize,
    profile_cache: &ProfileNodeSpectroscopyCache,
) -> Result<AtmosphericBudgetRow, errors::Error> {
    let evaluated = evaluate_layer_at_wavelength_with_spectroscopy_cache(
        prepared,
        Some(scene),
        sublayer.altitude_km,
        wavelength_nm,
        sublayer_index,
        &sublayers[sublayer_index..sublayer_index + 1],
        Some(profile_cache),
    )?;
    let totals = derived_totals(evaluated.breakdown);

    Ok(AtmosphericBudgetRow {
        wavelength_nm,
        layer_index: sublayer.parent_layer_index,
        sublayer_index: sublayer.sublayer_index,
        global_sublayer_index: if sublayer.global_sublayer_index != 0 {
            sublayer.global_sublayer_index
        } else {
            sublayer_index as u32
        },
        interval_index_1based: sublayer.interval_index_1based,
        support_row_kind: support_row_kind(sublayer.support_row_kind),
        subcolumn_label: subcolumn_label(sublayer.subcolumn_label),
        altitude_km: sublayer.altitude_km,
        top_altitude_km: sublayer.top_altitude_km,
        bottom_altitude_km: sublayer.bottom_altitude_km,
        pressure_hpa: sublayer.pressure_hpa,
        top_pressure_hpa: sublayer.top_pressure_hpa,
        bottom_pressure_hpa: sublayer.bottom_pressure_hpa,
        temperature_k: sublayer.temperature_k,
        number_density_cm3: sublayer.number_density_cm3,
        oxygen_number_density_cm3: sublayer.oxygen_number_density_cm3,
        absorber_number_density_cm3: sublayer.absorber_number_density_cm3,
        path_length_cm: sublayer.path_length_cm,
        aerosol_fraction: sublayer.aerosol_fraction,
        cloud_fraction: sublayer.cloud_fraction,
        gas_absorption_optical_depth: evaluated.breakdown.gas_absorption_optical_depth,
        gas_scattering_optical_depth: evaluated.breakdown.gas_scattering_optical_depth,
        cia_optical_depth: evaluated.breakdown.cia_optical_depth,
        aerosol_optical_depth: evaluated.breakdown.aerosol_optical_depth,
        aerosol_scattering_optical_depth: evaluated.breakdown.aerosol_scattering_optical_depth,
        aerosol_absorption_optical_depth: totals.aerosol_absorption,
        cloud_optical_depth: evaluated.breakdown.cloud_optical_depth,
        cloud_scattering_optical_depth: evaluated.breakdown.cloud_scattering_optical_depth,
        cloud_absorption_optical_depth: totals.cloud_absorption,
        total_absorption_optical_depth: totals.absorption,
        total_scattering_optical_depth: totals.scattering,
        total_optical_depth: totals.optical_depth,
        single_scatter_albedo: totals.single_scatter_albedo,
    })
}

fn layer_row(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    layer: PreparedLayer,
) -> AtmosphericBudgetRow {
    let particle_albedos = prepared.resolved_particle_single_scatter_albedos();
    let aerosol_optical_depth = particle_optical_depth_at_wavelength(
        layer.aerosol_optical_depth,
        layer.aerosol_base_optical_depth,
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        &prepared.aerosol_fraction_control,
        wavelength_nm,
    );
    let cloud_optical_depth = particle_optical_depth_at_wavelength(
        layer.cloud_optical_depth,
        layer.cloud_base_optical_depth,
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        &prepared.cloud_fraction_control,
        wavelength_nm,
    );
    let gas_scattering_optical_depth = if layer.gas_scattering_optical_depth > 0.0 {
        layer.gas_scattering_optical_depth
    } else {
        rayleigh::cross_section_cm2(wavelength_nm)
            * layer.number_density_cm3
            * (layer.top_altitude_km - layer.bottom_altitude_km).max(0.0)
            * 1.0e5
    };
    let breakdown = OpticalDepthBreakdown {
        gas_absorption_optical_depth: (layer.gas_optical_depth - gas_scattering_optical_depth)
            .max(0.0),
        gas_scattering_optical_depth,
        cia_optical_depth: layer.cia_optical_depth,
        aerosol_optical_depth,
        aerosol_scattering_optical_depth: aerosol_optical_depth * particle_albedos.aerosol,
        cloud_optical_depth,
        cloud_scattering_optical_depth: cloud_optical_depth * particle_albedos.cloud,
    };
    let totals = derived_totals(breakdown);

    AtmosphericBudgetRow {
        wavelength_nm,
        layer_index: layer.layer_index,
        sublayer_index: u32::MAX,
        global_sublayer_index: u32::MAX,
        interval_index_1based: layer.interval_index_1based,
        support_row_kind: SupportRowKind::Physical,
        subcolumn_label: subcolumn_label(layer.subcolumn_label),
        altitude_km: layer.altitude_km,
        top_altitude_km: layer.top_altitude_km,
        bottom_altitude_km: layer.bottom_altitude_km,
        pressure_hpa: layer.pressure_hpa,
        top_pressure_hpa: layer.top_pressure_hpa,
        bottom_pressure_hpa: layer.bottom_pressure_hpa,
        temperature_k: layer.temperature_k,
        number_density_cm3: layer.number_density_cm3,
        oxygen_number_density_cm3: 0.0,
        absorber_number_density_cm3: 0.0,
        path_length_cm: (layer.top_altitude_km - layer.bottom_altitude_km).max(0.0) * 1.0e5,
        aerosol_fraction: layer.aerosol_fraction,
        cloud_fraction: layer.cloud_fraction,
        gas_absorption_optical_depth: breakdown.gas_absorption_optical_depth,
        gas_scattering_optical_depth: breakdown.gas_scattering_optical_depth,
        cia_optical_depth: breakdown.cia_optical_depth,
        aerosol_optical_depth: breakdown.aerosol_optical_depth,
        aerosol_scattering_optical_depth: breakdown.aerosol_scattering_optical_depth,
        aerosol_absorption_optical_depth: totals.aerosol_absorption,
        cloud_optical_depth: breakdown.cloud_optical_depth,
        cloud_scattering_optical_depth: breakdown.cloud_scattering_optical_depth,
        cloud_absorption_optical_depth: totals.cloud_absorption,
        total_absorption_optical_depth: totals.absorption,
        total_scattering_optical_depth: totals.scattering,
        total_optical_depth: totals.optical_depth,
        single_scatter_albedo: totals.single_scatter_albedo,
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct DerivedTotals {
    aerosol_absorption: f64,
    cloud_absorption: f64,
    absorption: f64,
    scattering: f64,
    optical_depth: f64,
    single_scatter_albedo: f64,
}

fn derived_totals(breakdown: OpticalDepthBreakdown) -> DerivedTotals {
    let aerosol_absorption =
        (breakdown.aerosol_optical_depth - breakdown.aerosol_scattering_optical_depth).max(0.0);
    let cloud_absorption =
        (breakdown.cloud_optical_depth - breakdown.cloud_scattering_optical_depth).max(0.0);
    let scattering = breakdown.total_scattering_optical_depth();
    let optical_depth = breakdown.total_optical_depth();
    DerivedTotals {
        aerosol_absorption,
        cloud_absorption,
        absorption: breakdown.gas_absorption_optical_depth
            + breakdown.cia_optical_depth
            + aerosol_absorption
            + cloud_absorption,
        scattering,
        optical_depth,
        single_scatter_albedo: if optical_depth > 0.0 {
            (scattering / optical_depth).clamp(0.0, 1.0)
        } else {
            0.0
        },
    }
}

fn support_row_kind(kind: PreparedSupportRowKind) -> SupportRowKind {
    match kind {
        PreparedSupportRowKind::Physical => SupportRowKind::Physical,
        PreparedSupportRowKind::ParityBoundary => SupportRowKind::ParityBoundary,
        PreparedSupportRowKind::ParityActive => SupportRowKind::ParityActive,
    }
}

fn subcolumn_label(label: PartitionLabel) -> SubcolumnLabel {
    match label {
        PartitionLabel::Unspecified => SubcolumnLabel::Unspecified,
        PartitionLabel::BoundaryLayer => SubcolumnLabel::BoundaryLayer,
        PartitionLabel::FreeTroposphere => SubcolumnLabel::FreeTroposphere,
        PartitionLabel::FitInterval => SubcolumnLabel::FitInterval,
        PartitionLabel::Stratosphere => SubcolumnLabel::Stratosphere,
    }
}
