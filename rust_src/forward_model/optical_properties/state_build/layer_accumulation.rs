use super::{
    AbsorberBuildState, PreparationContext, PreparedLayer, PreparedSublayer,
    PreparedSupportRowKind,
    accumulation::PreparedMeans,
    operational_o2_evaluation_at_wavelength,
    spectroscopy::{DEFAULT_O2_VOLUME_MIXING_RATIO, species_mixing_ratio_at_pressure},
};
use crate::{
    common::errors,
    forward_model::optical_properties::{
        particle_support,
        shared::{
            band_means::{LineBandMeans, compute_operational_band_mean},
            particle_profiles,
            phase_functions::{
                self, PhaseCoefficients, combine_phase_coefficients,
                hg_phase_coefficients_with_threshold, phase_coefficients_from_compact,
            },
        },
    },
    input::{
        atmospheric_types::{AbsorberSpecies, AerosolType},
        reference::{airmass_phase::MiePhasePoint, rayleigh},
        reference_data::SpectroscopyEvaluation,
    },
};

const CENTIMETERS_PER_KILOMETER: f64 = 1.0e5;

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct LayerAccumulation {
    pub base_single_scatter_albedo: f64,
    pub aerosol_single_scatter_albedo: f64,
    pub cloud_single_scatter_albedo: f64,
    pub total_optical_depth: f64,
    pub total_temperature_weighted: f64,
    pub total_pressure_weighted: f64,
    pub total_weight: f64,
    pub air_column_density_factor: f64,
    pub oxygen_column_density_factor: f64,
    pub column_density_factor: f64,
    pub cia_pair_path_factor_cm5: f64,
    pub total_gas_optical_depth: f64,
    pub total_cia_optical_depth: f64,
    pub total_aerosol_optical_depth: f64,
    pub total_aerosol_base_optical_depth: f64,
    pub total_cloud_optical_depth: f64,
    pub total_cloud_base_optical_depth: f64,
    pub total_scattering_optical_depth: f64,
    pub total_d_optical_depth_d_temperature: f64,
    pub depolarization_weighted: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct LayerGeometry {
    top_altitude_km: f64,
    bottom_altitude_km: f64,
    center_altitude_km: f64,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    sublayer_start_index: u32,
    sublayer_count: u32,
    interval_index_1based: u32,
    subcolumn_label: crate::input::atmosphere::PartitionLabel,
    thickness_km: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct LayerSums {
    density_weight: f64,
    density: f64,
    temperature_weighted: f64,
    pressure_weighted: f64,
    line_sigma: f64,
    line_mixing: f64,
    d_cross_section_d_temperature: f64,
    gas_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64,
    cloud_optical_depth: f64,
    cloud_base_optical_depth: f64,
}

impl LayerSums {
    fn add_sublayer(&mut self, terms: SublayerLayerTerms) {
        self.density_weight += terms.density * terms.weight;
        self.density += terms.density * terms.weight;
        self.temperature_weighted += terms.temperature * terms.density * terms.weight;
        self.pressure_weighted += terms.pressure * terms.density * terms.weight;
        self.line_sigma += terms.line_sigma;
        self.line_mixing += terms.line_mixing;
        self.d_cross_section_d_temperature += terms.d_cross_section_d_temperature;
        self.gas_optical_depth +=
            terms.gas_absorption_optical_depth + terms.gas_scattering_optical_depth;
        self.gas_scattering_optical_depth += terms.gas_scattering_optical_depth;
        self.cia_optical_depth += terms.cia_optical_depth;
        self.aerosol_optical_depth += terms.aerosol_optical_depth;
        self.aerosol_base_optical_depth += terms.aerosol_base_optical_depth;
        self.cloud_optical_depth += terms.cloud_optical_depth;
        self.cloud_base_optical_depth += terms.cloud_base_optical_depth;
    }

    fn temperature(self) -> f64 {
        if self.density_weight == 0.0 {
            0.0
        } else {
            self.temperature_weighted / self.density_weight
        }
    }

    fn pressure(self) -> f64 {
        if self.density_weight == 0.0 {
            0.0
        } else {
            self.pressure_weighted / self.density_weight
        }
    }

    fn mean_line_sigma(self, sublayer_count: u32) -> f64 {
        self.line_sigma / f64::from(sublayer_count.max(1))
    }

    fn mean_line_mixing(self, sublayer_count: u32) -> f64 {
        self.line_mixing / f64::from(sublayer_count.max(1))
    }

    fn mean_temperature_derivative(self, sublayer_count: u32) -> f64 {
        self.d_cross_section_d_temperature / f64::from(sublayer_count.max(1))
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct SublayerLayerTerms {
    density: f64,
    temperature: f64,
    pressure: f64,
    weight: f64,
    line_sigma: f64,
    line_mixing: f64,
    d_cross_section_d_temperature: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64,
    cloud_optical_depth: f64,
    cloud_base_optical_depth: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
struct SublayerGasState {
    write_index: usize,
    density: f64,
    pressure: f64,
    temperature: f64,
    oxygen_mixing_ratio: f64,
    path_length_cm: f64,
}

#[derive(Debug, Clone, Copy)]
struct ParticleOptics<'a> {
    aerosol_distribution: &'a [f64],
    cloud_distribution: &'a [f64],
    aerosol_phase_coefficients: PhaseCoefficients,
    cloud_phase_coefficients: PhaseCoefficients,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_extinction_scale: f64,
    cloud_extinction_scale: f64,
    aerosol_fraction: f64,
    cloud_fraction: f64,
}

pub fn populate(
    context: &mut PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
) -> Result<LayerAccumulation, errors::Error> {
    if uses_disamar_parity_support_grid(context) {
        // The parity grid shares boundary rows between layers. It needs its own
        // reduction path, so we keep this branch explicit instead of pretending
        // the ordinary layer loop is equivalent.
        return Err(errors::Error::InvalidRequest);
    }

    let aerosol_distribution = build_aerosol_sublayer_distribution(context)?;
    let cloud_distribution = build_cloud_sublayer_distribution(context)?;
    let optics = particle_optics(context, &aerosol_distribution, &cloud_distribution);
    let mut totals = LayerAccumulation {
        base_single_scatter_albedo: phase_functions::compute_single_scatter_albedo(
            context.scene,
            context.midpoint_nm,
        ),
        aerosol_single_scatter_albedo: optics.aerosol_single_scatter_albedo,
        cloud_single_scatter_albedo: optics.cloud_single_scatter_albedo,
        ..LayerAccumulation::default()
    };

    for index in 0..context.layers.len() {
        populate_layer(context, absorbers, &mut totals, &optics, index)?;
    }

    Ok(totals)
}

pub fn compute_prepared_means(
    context: &PreparationContext<'_>,
    absorbers: &AbsorberBuildState<'_>,
    layer_totals: LayerAccumulation,
) -> PreparedMeans {
    let effective_temperature = if layer_totals.total_weight == 0.0 {
        0.0
    } else {
        layer_totals.total_temperature_weighted / layer_totals.total_weight
    };
    let effective_pressure = if layer_totals.total_weight == 0.0 {
        0.0
    } else {
        layer_totals.total_pressure_weighted / layer_totals.total_weight
    };

    PreparedMeans {
        cross_section_mean_cm2_per_molecule: cross_section_mean(
            context,
            absorbers,
            effective_temperature,
            effective_pressure,
        ),
        line_means: line_means(
            context,
            absorbers,
            effective_temperature,
            effective_pressure,
            layer_totals.oxygen_column_density_factor,
        ),
        cia_mean_cross_section_cm5_per_molecule2: cia_mean_sigma(
            context,
            effective_temperature,
            effective_pressure,
        ),
        effective_air_mass_factor: absorbers.air_mass_factor,
        effective_single_scatter_albedo: if layer_totals.total_optical_depth == 0.0 {
            layer_totals.base_single_scatter_albedo
        } else {
            layer_totals.total_scattering_optical_depth / layer_totals.total_optical_depth
        },
        effective_temperature_k: effective_temperature,
        effective_pressure_hpa: effective_pressure,
        air_column_density_factor: layer_totals.air_column_density_factor,
        oxygen_column_density_factor: layer_totals.oxygen_column_density_factor,
        column_density_factor: layer_totals.column_density_factor,
        cia_pair_path_factor_cm5: layer_totals.cia_pair_path_factor_cm5,
        gas_optical_depth: layer_totals.total_gas_optical_depth,
        cia_optical_depth: layer_totals.total_cia_optical_depth,
        aerosol_optical_depth: layer_totals.total_aerosol_optical_depth,
        aerosol_base_optical_depth: layer_totals.total_aerosol_base_optical_depth,
        cloud_optical_depth: layer_totals.total_cloud_optical_depth,
        cloud_base_optical_depth: layer_totals.total_cloud_base_optical_depth,
        d_optical_depth_d_temperature: layer_totals.total_d_optical_depth_d_temperature,
        total_optical_depth: layer_totals.total_optical_depth,
        depolarization_factor: if layer_totals.total_optical_depth == 0.0 {
            0.0
        } else {
            layer_totals.depolarization_weighted / layer_totals.total_optical_depth
        },
    }
}

fn populate_layer(
    context: &mut PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
    totals: &mut LayerAccumulation,
    optics: &ParticleOptics<'_>,
    index: usize,
) -> Result<(), errors::Error> {
    let geometry = layer_geometry(context, index);
    let mut layer_sums = LayerSums::default();
    for sublayer_index in 0..geometry.sublayer_count as usize {
        let write_index = geometry.sublayer_start_index as usize + sublayer_index;
        populate_sublayer(
            context,
            absorbers,
            totals,
            optics,
            geometry.thickness_km,
            index,
            sublayer_index,
            write_index,
            &mut layer_sums,
        )?;
    }

    let density = layer_sums.density;
    let temperature = layer_sums.temperature();
    let pressure = layer_sums.pressure();
    let gas_optical_depth = layer_sums.gas_optical_depth;
    let aerosol_optical_depth = layer_sums.aerosol_optical_depth;
    let cloud_optical_depth = layer_sums.cloud_optical_depth;
    let optical_depth = gas_optical_depth
        + layer_sums.cia_optical_depth
        + aerosol_optical_depth
        + cloud_optical_depth;
    let gas_scattering = layer_sums.gas_scattering_optical_depth;
    let aerosol_scattering = aerosol_optical_depth * optics.aerosol_single_scatter_albedo;
    let cloud_scattering = cloud_optical_depth * optics.cloud_single_scatter_albedo;
    let scattering = gas_scattering + aerosol_scattering + cloud_scattering;
    let absorption = (optical_depth - scattering).max(1.0e-9);
    let layer_single_scatter_albedo = scattering / (scattering + absorption).max(1.0e-9);
    let depolarization = phase_functions::compute_layer_depolarization(
        context.scene,
        gas_scattering,
        aerosol_scattering,
        cloud_scattering,
    );

    totals.total_optical_depth += optical_depth;
    totals.total_temperature_weighted += temperature * density;
    totals.total_pressure_weighted += pressure * density;
    totals.total_weight += density;
    totals.total_gas_optical_depth += gas_optical_depth;
    totals.total_cia_optical_depth += layer_sums.cia_optical_depth;
    totals.total_aerosol_optical_depth += aerosol_optical_depth;
    totals.total_aerosol_base_optical_depth += layer_sums.aerosol_base_optical_depth;
    totals.total_cloud_optical_depth += cloud_optical_depth;
    totals.total_cloud_base_optical_depth += layer_sums.cloud_base_optical_depth;
    totals.total_scattering_optical_depth += scattering;
    totals.depolarization_weighted += depolarization * optical_depth;

    context.layers[index] = PreparedLayer {
        layer_index: index as u32,
        sublayer_start_index: geometry.sublayer_start_index,
        sublayer_count: geometry.sublayer_count,
        altitude_km: geometry.center_altitude_km,
        pressure_hpa: pressure,
        temperature_k: temperature,
        number_density_cm3: density,
        continuum_cross_section_cm2_per_molecule: absorbers.mean_sigma,
        line_cross_section_cm2_per_molecule: layer_sums.mean_line_sigma(geometry.sublayer_count),
        line_mixing_cross_section_cm2_per_molecule: layer_sums
            .mean_line_mixing(geometry.sublayer_count),
        cia_optical_depth: layer_sums.cia_optical_depth,
        d_cross_section_d_temperature_cm2_per_molecule_per_k: layer_sums
            .mean_temperature_derivative(geometry.sublayer_count),
        gas_optical_depth,
        gas_scattering_optical_depth: gas_scattering,
        aerosol_optical_depth,
        aerosol_base_optical_depth: layer_sums.aerosol_base_optical_depth,
        cloud_optical_depth,
        cloud_base_optical_depth: layer_sums.cloud_base_optical_depth,
        layer_single_scatter_albedo,
        depolarization_factor: depolarization,
        optical_depth,
        top_altitude_km: geometry.top_altitude_km,
        bottom_altitude_km: geometry.bottom_altitude_km,
        top_pressure_hpa: geometry.top_pressure_hpa,
        bottom_pressure_hpa: geometry.bottom_pressure_hpa,
        interval_index_1based: geometry.interval_index_1based,
        subcolumn_label: geometry.subcolumn_label,
        aerosol_fraction: optics.aerosol_fraction,
        cloud_fraction: optics.cloud_fraction,
    };
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn populate_sublayer(
    context: &mut PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
    totals: &mut LayerAccumulation,
    optics: &ParticleOptics<'_>,
    layer_thickness_km: f64,
    parent_layer_index: usize,
    sublayer_index: usize,
    write_index: usize,
    layer_sums: &mut LayerSums,
) -> Result<(), errors::Error> {
    let top_altitude_km = context.vertical_grid.sublayer_top_altitudes_km[write_index];
    let bottom_altitude_km = context.vertical_grid.sublayer_bottom_altitudes_km[write_index];
    let top_pressure_hpa = context.vertical_grid.sublayer_top_pressures_hpa[write_index];
    let bottom_pressure_hpa = context.vertical_grid.sublayer_bottom_pressures_hpa[write_index];
    let altitude_km = context.vertical_grid.sublayer_mid_altitudes_km[write_index];
    let pressure = if context.scene.atmosphere.interval_grid.enabled()
        && top_pressure_hpa > 0.0
        && bottom_pressure_hpa > 0.0
    {
        (top_pressure_hpa * bottom_pressure_hpa).sqrt()
    } else {
        context.profile.interpolate_pressure(altitude_km)
    };
    let temperature = context.profile.interpolate_temperature(altitude_km);
    let density = context.profile.interpolate_density(altitude_km);
    let support_weight_km = (top_altitude_km - bottom_altitude_km).max(0.0);
    let sublayer_path_length_cm = support_weight_km.max(1.0e-9) * CENTIMETERS_PER_KILOMETER;
    let sublayer_weight = support_weight_km / layer_thickness_km;
    let oxygen_mixing_ratio = species_mixing_ratio_at_pressure(
        context.scene,
        AbsorberSpecies::O2,
        &[],
        pressure,
        Some(DEFAULT_O2_VOLUME_MIXING_RATIO),
    )
    .unwrap_or(DEFAULT_O2_VOLUME_MIXING_RATIO);

    let mut absorber_density_cm3 = 0.0;
    let mut cross_section_absorber_density_cm3 = 0.0;
    let mut cross_section_optical_depth = 0.0;
    let mut cross_section_d_optical_depth_d_temperature = 0.0;
    for (cross_section_absorber, active_absorber) in absorbers
        .owned_cross_section_absorbers
        .iter_mut()
        .zip(&absorbers.active_cross_section_absorbers)
    {
        let absorber_mixing_ratio = species_mixing_ratio_at_pressure(
            context.scene,
            cross_section_absorber.species,
            active_absorber.volume_mixing_ratio_profile_ppmv,
            pressure,
            if cross_section_absorber.species == AbsorberSpecies::O2 {
                Some(DEFAULT_O2_VOLUME_MIXING_RATIO)
            } else {
                None
            },
        )
        .ok_or(errors::Error::InvalidRequest)?;
        let absorber_density = density * absorber_mixing_ratio;
        cross_section_absorber.number_densities_cm3[write_index] = absorber_density;
        cross_section_absorber_density_cm3 += absorber_density;
        if absorber_density <= 0.0 {
            continue;
        }
        let sigma = cross_section_absorber.sigma_at(context.midpoint_nm, temperature, pressure);
        let d_sigma_d_temperature = cross_section_absorber.d_sigma_d_temperature_at(
            context.midpoint_nm,
            temperature,
            pressure,
        );
        cross_section_optical_depth += sigma * absorber_density * sublayer_path_length_cm;
        cross_section_d_optical_depth_d_temperature +=
            d_sigma_d_temperature * absorber_density * sublayer_path_length_cm;
        cross_section_absorber.column_density_factor += absorber_density * sublayer_path_length_cm;
    }

    let spectroscopy_eval = resolve_spectroscopy_evaluation(
        context,
        absorbers,
        SublayerGasState {
            write_index,
            density,
            pressure,
            temperature,
            oxygen_mixing_ratio,
            path_length_cm: sublayer_path_length_cm,
        },
        &mut absorber_density_cm3,
    )?;

    let o2_density_cm3 = density * oxygen_mixing_ratio;
    let continuum_density_cm3 = continuum_carrier_density(
        absorbers,
        context,
        write_index,
        absorber_density_cm3,
        o2_density_cm3,
    );
    let total_gas_density_cm3 =
        if !absorbers.owned_cross_section_absorbers.is_empty() && !absorbers.has_line_absorbers {
            cross_section_absorber_density_cm3
        } else {
            absorber_density_cm3 + cross_section_absorber_density_cm3
        };
    let line_gas_column_density_cm2 = absorber_density_cm3 * sublayer_path_length_cm;
    let continuum_column_density_cm2 = continuum_density_cm3 * sublayer_path_length_cm;
    let total_gas_column_density_cm2 = total_gas_density_cm3 * sublayer_path_length_cm;
    let molecular_gas_optical_depth = absorbers.midpoint_continuum_sigma
        * continuum_column_density_cm2
        + spectroscopy_eval.total_sigma_cm2_per_molecule * line_gas_column_density_cm2
        + cross_section_optical_depth;

    let cia_sigma_cm5_per_molecule2 = if context.operational_o2o2_lut.enabled() {
        context
            .operational_o2o2_lut
            .sigma_at(context.midpoint_nm, temperature, pressure)
    } else if let Some(cia_table) = &context.collision_induced_absorption {
        cia_table.sigma_at(context.midpoint_nm, temperature)
    } else {
        0.0
    };
    let d_cia_sigma_d_temperature = if context.operational_o2o2_lut.enabled() {
        context.operational_o2o2_lut.d_sigma_d_temperature_at(
            context.midpoint_nm,
            temperature,
            pressure,
        )
    } else if let Some(cia_table) = &context.collision_induced_absorption {
        cia_table.d_sigma_d_temperature_at(context.midpoint_nm, temperature)
    } else {
        0.0
    };
    let cia_pair_density_cm6 = o2_density_cm3 * o2_density_cm3;
    let cia_pair_column_factor_cm5 = cia_pair_density_cm6 * sublayer_path_length_cm;
    let cia_optical_depth = cia_sigma_cm5_per_molecule2 * cia_pair_column_factor_cm5;
    let gas_scattering_optical_depth = rayleigh::scattering_optical_depth_for_column(
        context.midpoint_nm,
        density * sublayer_path_length_cm,
    );
    let gas_absorption_optical_depth = molecular_gas_optical_depth;
    let gas_extinction_optical_depth =
        gas_absorption_optical_depth + cia_optical_depth + gas_scattering_optical_depth;
    let d_cia_optical_depth_d_temperature = d_cia_sigma_d_temperature * cia_pair_column_factor_cm5;
    let d_gas_optical_depth_d_temperature = spectroscopy_eval
        .d_sigma_d_temperature_cm2_per_molecule_per_k
        * line_gas_column_density_cm2
        + cross_section_d_optical_depth_d_temperature;
    let aerosol_base_optical_depth =
        optics.aerosol_distribution[write_index] * optics.aerosol_extinction_scale;
    let cloud_base_optical_depth =
        optics.cloud_distribution[write_index] * optics.cloud_extinction_scale;
    let aerosol_optical_depth = aerosol_base_optical_depth * optics.aerosol_fraction;
    let cloud_optical_depth = cloud_base_optical_depth * optics.cloud_fraction;
    let aerosol_scattering_optical_depth =
        aerosol_optical_depth * optics.aerosol_single_scatter_albedo;
    let cloud_scattering_optical_depth = cloud_optical_depth * optics.cloud_single_scatter_albedo;
    let combined_phase_coefficients = combine_phase_coefficients(
        context.midpoint_nm,
        gas_scattering_optical_depth,
        aerosol_scattering_optical_depth,
        cloud_scattering_optical_depth,
        &optics.aerosol_phase_coefficients,
        &optics.cloud_phase_coefficients,
    );

    context.sublayers[write_index] = PreparedSublayer {
        parent_layer_index: parent_layer_index as u32,
        sublayer_index: sublayer_index as u32,
        global_sublayer_index: write_index as u32,
        altitude_km,
        pressure_hpa: pressure,
        temperature_k: temperature,
        number_density_cm3: density,
        oxygen_number_density_cm3: o2_density_cm3,
        cia_pair_density_cm6,
        absorber_number_density_cm3: total_gas_density_cm3,
        path_length_cm: sublayer_path_length_cm,
        continuum_cross_section_cm2_per_molecule: if absorbers
            .owned_cross_section_absorbers
            .is_empty()
        {
            absorbers.midpoint_continuum_sigma
        } else {
            0.0
        },
        line_cross_section_cm2_per_molecule: spectroscopy_eval.line_sigma_cm2_per_molecule,
        line_mixing_cross_section_cm2_per_molecule: spectroscopy_eval
            .line_mixing_sigma_cm2_per_molecule,
        cia_sigma_cm5_per_molecule2,
        cia_optical_depth,
        d_cross_section_d_temperature_cm2_per_molecule_per_k: spectroscopy_eval
            .d_sigma_d_temperature_cm2_per_molecule_per_k,
        gas_absorption_optical_depth,
        gas_scattering_optical_depth,
        gas_extinction_optical_depth,
        d_gas_optical_depth_d_temperature,
        d_cia_optical_depth_d_temperature,
        aerosol_optical_depth,
        aerosol_base_optical_depth,
        cloud_optical_depth,
        cloud_base_optical_depth,
        aerosol_single_scatter_albedo: optics.aerosol_single_scatter_albedo,
        cloud_single_scatter_albedo: optics.cloud_single_scatter_albedo,
        aerosol_phase_coefficients: optics.aerosol_phase_coefficients,
        cloud_phase_coefficients: optics.cloud_phase_coefficients,
        combined_phase_coefficients,
        top_altitude_km,
        bottom_altitude_km,
        top_pressure_hpa,
        bottom_pressure_hpa,
        interval_index_1based: context.vertical_grid.sublayer_interval_indices_1based[write_index],
        subcolumn_label: context.vertical_grid.sublayer_subcolumn_labels[write_index],
        aerosol_fraction: optics.aerosol_fraction,
        cloud_fraction: optics.cloud_fraction,
        support_row_kind: PreparedSupportRowKind::Physical,
    };

    layer_sums.add_sublayer(SublayerLayerTerms {
        density,
        temperature,
        pressure,
        weight: sublayer_weight,
        line_sigma: spectroscopy_eval.line_sigma_cm2_per_molecule,
        line_mixing: spectroscopy_eval.line_mixing_sigma_cm2_per_molecule,
        d_cross_section_d_temperature: spectroscopy_eval
            .d_sigma_d_temperature_cm2_per_molecule_per_k,
        gas_absorption_optical_depth,
        gas_scattering_optical_depth,
        cia_optical_depth,
        aerosol_optical_depth,
        aerosol_base_optical_depth,
        cloud_optical_depth,
        cloud_base_optical_depth,
    });
    totals.air_column_density_factor += density * sublayer_path_length_cm;
    totals.oxygen_column_density_factor += o2_density_cm3 * sublayer_path_length_cm;
    totals.column_density_factor += total_gas_column_density_cm2;
    totals.cia_pair_path_factor_cm5 += cia_pair_column_factor_cm5;
    totals.total_d_optical_depth_d_temperature +=
        d_gas_optical_depth_d_temperature + d_cia_optical_depth_d_temperature;
    Ok(())
}

fn resolve_spectroscopy_evaluation(
    context: &PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
    gas: SublayerGasState,
    absorber_density_cm3: &mut f64,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    if !absorbers.owned_line_absorbers.is_empty() {
        return resolve_prepared_line_evaluation(context, absorbers, gas, absorber_density_cm3);
    }
    Ok(resolve_single_line_evaluation(
        context,
        absorbers,
        gas,
        absorber_density_cm3,
    ))
}

fn resolve_prepared_line_evaluation(
    context: &PreparationContext<'_>,
    absorbers: &mut AbsorberBuildState<'_>,
    gas: SublayerGasState,
    absorber_density_cm3: &mut f64,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    let mut spectroscopy_weight = 0.0;
    let mut weighted = SpectroscopyEvaluation::default();

    if context.operational_o2_lut.enabled() {
        let o2_density_cm3 = gas.density * gas.oxygen_mixing_ratio;
        *absorber_density_cm3 += o2_density_cm3;
        if o2_density_cm3 > 0.0 {
            let o2_eval = operational_o2_evaluation_at_wavelength(
                &context.operational_o2_lut,
                context.midpoint_nm,
                gas.temperature,
                gas.pressure,
            );
            add_weighted_evaluation(&mut weighted, o2_eval, o2_density_cm3);
            spectroscopy_weight += o2_density_cm3;
        }
    }

    for (line_absorber, active_absorber) in absorbers
        .owned_line_absorbers
        .iter_mut()
        .zip(&absorbers.active_line_absorbers)
    {
        if context.operational_o2_lut.enabled() && line_absorber.species == AbsorberSpecies::O2 {
            line_absorber.number_densities_cm3[gas.write_index] = 0.0;
            continue;
        }
        let absorber_mixing_ratio = species_mixing_ratio_at_pressure(
            context.scene,
            line_absorber.species,
            &active_absorber.volume_mixing_ratio_profile_ppmv,
            gas.pressure,
            if line_absorber.species == AbsorberSpecies::O2 {
                Some(DEFAULT_O2_VOLUME_MIXING_RATIO)
            } else {
                None
            },
        )
        .ok_or(errors::Error::InvalidRequest)?;
        let density_cm3 = gas.density * absorber_mixing_ratio;
        line_absorber.number_densities_cm3[gas.write_index] = density_cm3;
        *absorber_density_cm3 += density_cm3;
        if density_cm3 <= 0.0 {
            continue;
        }
        let evaluation = line_absorber.evaluate_at_sublayer(
            context.midpoint_nm,
            gas.temperature,
            gas.pressure,
            gas.write_index,
        );
        add_weighted_evaluation(&mut weighted, evaluation, density_cm3);
        spectroscopy_weight += density_cm3;
        line_absorber.column_density_factor += density_cm3 * gas.path_length_cm;
    }

    if spectroscopy_weight <= 0.0 {
        return Ok(SpectroscopyEvaluation::default());
    }
    divide_evaluation(&mut weighted, spectroscopy_weight);
    Ok(weighted)
}

fn resolve_single_line_evaluation(
    context: &PreparationContext<'_>,
    absorbers: &AbsorberBuildState<'_>,
    gas: SublayerGasState,
    absorber_density_cm3: &mut f64,
) -> SpectroscopyEvaluation {
    let absorber_mixing_ratio = absorbers
        .active_line_species
        .and_then(|active_species| {
            species_mixing_ratio_at_pressure(
                context.scene,
                active_species,
                absorbers
                    .single_active_line_absorber
                    .as_ref()
                    .map(|line_absorber| line_absorber.volume_mixing_ratio_profile_ppmv.as_slice())
                    .unwrap_or(&[]),
                gas.pressure,
                if active_species == AbsorberSpecies::O2 {
                    Some(DEFAULT_O2_VOLUME_MIXING_RATIO)
                } else {
                    None
                },
            )
        })
        .unwrap_or(DEFAULT_O2_VOLUME_MIXING_RATIO);
    *absorber_density_cm3 = gas.density * absorber_mixing_ratio;

    if context.operational_o2_lut.enabled() {
        return operational_o2_evaluation_at_wavelength(
            &context.operational_o2_lut,
            context.midpoint_nm,
            gas.temperature,
            gas.pressure,
        );
    }
    if let Some(line_list) = &absorbers.owned_lines {
        return line_list.evaluate_at(context.midpoint_nm, gas.temperature, gas.pressure);
    }
    SpectroscopyEvaluation::default()
}

fn continuum_carrier_density(
    absorbers: &AbsorberBuildState<'_>,
    context: &PreparationContext<'_>,
    write_index: usize,
    absorber_density_cm3: f64,
    o2_density_cm3: f64,
) -> f64 {
    if !absorbers.owned_cross_section_absorbers.is_empty() {
        return 0.0;
    }
    if absorbers.owned_line_absorbers.is_empty() {
        return absorber_density_cm3;
    }
    let Some(owner_species) = absorbers.continuum_owner_species else {
        return absorber_density_cm3;
    };
    if context.operational_o2_lut.enabled() && owner_species == AbsorberSpecies::O2 {
        return o2_density_cm3;
    }
    absorbers
        .owned_line_absorbers
        .iter()
        .find(|line_absorber| line_absorber.species == owner_species)
        .and_then(|line_absorber| line_absorber.number_densities_cm3.get(write_index).copied())
        .unwrap_or(absorber_density_cm3)
}

fn build_aerosol_sublayer_distribution(
    context: &PreparationContext<'_>,
) -> Result<Vec<f64>, errors::Error> {
    let scene = context.scene;
    let total_optical_depth = scene.aerosol.optical_depth;
    let enabled =
        scene.atmosphere.has_aerosols && scene.aerosol.enabled && total_optical_depth > 0.0;
    if particle_profiles::placement_supports_explicit_interval(scene.aerosol.placement) {
        return particle_profiles::build_placement_bound_distribution(
            context.vertical_grid.borrow(),
            scene.atmosphere.interval_grid.enabled(),
            enabled,
            total_optical_depth,
            scene.aerosol.placement,
        );
    }
    let placement = particle_support::aerosol_placement(&scene.aerosol);
    if scene.aerosol.aerosol_type == AerosolType::HgScattering {
        return particle_profiles::build_finite_layer_sublayer_distribution(
            context.vertical_grid.borrow(),
            enabled,
            total_optical_depth,
            placement.bottom_altitude_km,
            placement.top_altitude_km,
            !scene.atmosphere.interval_grid.enabled(),
        );
    }
    Ok(particle_profiles::build_gaussian_sublayer_distribution(
        context.vertical_grid.borrow(),
        enabled,
        total_optical_depth,
        scene.aerosol.layer_center_km,
        scene.aerosol.layer_width_km,
    ))
}

fn build_cloud_sublayer_distribution(
    context: &PreparationContext<'_>,
) -> Result<Vec<f64>, errors::Error> {
    let scene = context.scene;
    let total_optical_depth = scene.cloud.optical_thickness;
    let enabled = scene.atmosphere.has_clouds && scene.cloud.enabled && total_optical_depth > 0.0;
    if particle_profiles::placement_supports_explicit_interval(scene.cloud.placement) {
        return particle_profiles::build_placement_bound_distribution(
            context.vertical_grid.borrow(),
            scene.atmosphere.interval_grid.enabled(),
            enabled,
            total_optical_depth,
            scene.cloud.placement,
        );
    }
    let placement = particle_support::cloud_placement(&scene.cloud);
    particle_profiles::build_finite_layer_sublayer_distribution(
        context.vertical_grid.borrow(),
        enabled,
        total_optical_depth,
        placement.bottom_altitude_km,
        placement.top_altitude_km,
        !scene.atmosphere.interval_grid.enabled(),
    )
}

fn particle_optics<'a>(
    context: &PreparationContext<'_>,
    aerosol_distribution: &'a [f64],
    cloud_distribution: &'a [f64],
) -> ParticleOptics<'a> {
    let aerosol_mie_point = context
        .aerosol_mie
        .map(|table| table.interpolate(context.midpoint_nm));
    let cloud_mie_point = context
        .cloud_mie
        .map(|table| table.interpolate(context.midpoint_nm));
    let aerosol_phase_coefficients = particle_phase_coefficients(
        aerosol_mie_point,
        context.scene.aerosol.asymmetry_factor,
        context,
    );
    let cloud_phase_coefficients = particle_phase_coefficients(
        cloud_mie_point,
        context.scene.cloud.asymmetry_factor,
        context,
    );
    let aerosol_single_scatter_albedo = aerosol_mie_point
        .map(|point| point.single_scatter_albedo)
        .unwrap_or(context.scene.aerosol.single_scatter_albedo);
    let cloud_single_scatter_albedo = cloud_mie_point
        .map(|point| point.single_scatter_albedo)
        .unwrap_or(context.scene.cloud.single_scatter_albedo);
    let aerosol_fraction = if context.scene.aerosol.fraction.enabled {
        context
            .scene
            .aerosol
            .fraction
            .value_at_wavelength(context.midpoint_nm)
    } else if context.scene.aerosol.enabled {
        1.0
    } else {
        0.0
    };
    let cloud_fraction = if context.scene.cloud.fraction.enabled {
        context
            .scene
            .cloud
            .fraction
            .value_at_wavelength(context.midpoint_nm)
    } else if context.scene.cloud.enabled {
        1.0
    } else {
        0.0
    };

    ParticleOptics {
        aerosol_distribution,
        cloud_distribution,
        aerosol_phase_coefficients,
        cloud_phase_coefficients,
        aerosol_single_scatter_albedo,
        cloud_single_scatter_albedo,
        aerosol_extinction_scale: aerosol_mie_point
            .map(|point| point.extinction_scale)
            .unwrap_or(1.0),
        cloud_extinction_scale: cloud_mie_point
            .map(|point| point.extinction_scale)
            .unwrap_or(1.0),
        aerosol_fraction,
        cloud_fraction,
    }
}

fn particle_phase_coefficients(
    mie_point: Option<MiePhasePoint>,
    asymmetry_factor: f64,
    context: &PreparationContext<'_>,
) -> PhaseCoefficients {
    mie_point
        .map(|point| phase_coefficients_from_compact(point.phase_coefficients))
        .unwrap_or_else(|| {
            hg_phase_coefficients_with_threshold(
                asymmetry_factor,
                context.scene.phase_function_truncation_threshold,
            )
        })
}

fn layer_geometry(context: &PreparationContext<'_>, index: usize) -> LayerGeometry {
    let top_altitude_km = context.vertical_grid.layer_top_altitudes_km[index];
    let bottom_altitude_km = context.vertical_grid.layer_bottom_altitudes_km[index];
    LayerGeometry {
        top_altitude_km,
        bottom_altitude_km,
        center_altitude_km: 0.5 * (top_altitude_km + bottom_altitude_km),
        top_pressure_hpa: context.vertical_grid.layer_top_pressures_hpa[index],
        bottom_pressure_hpa: context.vertical_grid.layer_bottom_pressures_hpa[index],
        sublayer_start_index: context.vertical_grid.layer_sublayer_starts[index],
        sublayer_count: context.vertical_grid.layer_sublayer_counts[index],
        interval_index_1based: context.vertical_grid.layer_interval_indices_1based[index],
        subcolumn_label: context.vertical_grid.layer_subcolumn_labels[index],
        thickness_km: (top_altitude_km - bottom_altitude_km).max(1.0e-9),
    }
}

fn cross_section_mean(
    context: &PreparationContext<'_>,
    absorbers: &AbsorberBuildState<'_>,
    effective_temperature: f64,
    effective_pressure: f64,
) -> f64 {
    if absorbers.owned_cross_section_absorbers.is_empty() {
        return absorbers.mean_sigma;
    }
    let mut total_weight = 0.0;
    let mut weighted_mean = 0.0;
    for absorber in &absorbers.owned_cross_section_absorbers {
        let weight = absorber.column_density_factor;
        if weight <= 0.0 {
            continue;
        }
        total_weight += weight;
        weighted_mean += absorber.mean_sigma_in_range(
            context.scene.spectral_grid.start_nm,
            context.scene.spectral_grid.end_nm,
            effective_temperature,
            effective_pressure,
        ) * weight;
    }
    if total_weight <= 0.0 {
        0.0
    } else {
        weighted_mean / total_weight
    }
}

fn line_means(
    context: &PreparationContext<'_>,
    absorbers: &AbsorberBuildState<'_>,
    effective_temperature: f64,
    effective_pressure: f64,
    oxygen_column_density_factor: f64,
) -> LineBandMeans {
    let mut total_weight = 0.0;
    let mut weighted = LineBandMeans::default();
    if context.operational_o2_lut.enabled() && absorbers.owned_lines.is_none() {
        let mean = compute_operational_band_mean(
            context.scene,
            &context.operational_o2_lut,
            effective_temperature,
            effective_pressure,
        );
        let weight = oxygen_column_density_factor;
        total_weight += weight;
        weighted.line_mean_cross_section_cm2_per_molecule += mean * weight;
    }
    for absorber in &absorbers.owned_line_absorbers {
        if context.operational_o2_lut.enabled() && absorber.species == AbsorberSpecies::O2 {
            continue;
        }
        let weight = absorber.column_density_factor;
        if weight <= 0.0 {
            continue;
        }
        let evaluation = absorber.line_list.evaluate_at(
            context.midpoint_nm,
            effective_temperature,
            effective_pressure,
        );
        total_weight += weight;
        weighted.line_mean_cross_section_cm2_per_molecule +=
            evaluation.line_sigma_cm2_per_molecule * weight;
        weighted.line_mixing_mean_cross_section_cm2_per_molecule +=
            evaluation.line_mixing_sigma_cm2_per_molecule * weight;
    }
    if total_weight > 0.0 {
        weighted.line_mean_cross_section_cm2_per_molecule /= total_weight;
        weighted.line_mixing_mean_cross_section_cm2_per_molecule /= total_weight;
        return weighted;
    }
    absorbers
        .owned_lines
        .as_ref()
        .map(|line_list| {
            let evaluation = line_list.evaluate_at(
                context.midpoint_nm,
                effective_temperature,
                effective_pressure,
            );
            LineBandMeans {
                line_mean_cross_section_cm2_per_molecule: evaluation.line_sigma_cm2_per_molecule,
                line_mixing_mean_cross_section_cm2_per_molecule: evaluation
                    .line_mixing_sigma_cm2_per_molecule,
            }
        })
        .unwrap_or_default()
}

fn cia_mean_sigma(
    context: &PreparationContext<'_>,
    effective_temperature: f64,
    effective_pressure: f64,
) -> f64 {
    if context.operational_o2o2_lut.enabled() {
        return compute_operational_band_mean(
            context.scene,
            &context.operational_o2o2_lut,
            effective_temperature.max(150.0),
            effective_pressure,
        );
    }
    context
        .collision_induced_absorption
        .as_ref()
        .map(|table| {
            table.mean_sigma_in_range(
                context.scene.spectral_grid.start_nm,
                context.scene.spectral_grid.end_nm,
                effective_temperature.max(150.0),
            )
        })
        .unwrap_or(0.0)
}

fn add_weighted_evaluation(
    weighted: &mut SpectroscopyEvaluation,
    evaluation: SpectroscopyEvaluation,
    weight: f64,
) {
    weighted.weak_line_sigma_cm2_per_molecule +=
        evaluation.weak_line_sigma_cm2_per_molecule * weight;
    weighted.strong_line_sigma_cm2_per_molecule +=
        evaluation.strong_line_sigma_cm2_per_molecule * weight;
    weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
    weighted.line_mixing_sigma_cm2_per_molecule +=
        evaluation.line_mixing_sigma_cm2_per_molecule * weight;
    weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
}

fn divide_evaluation(weighted: &mut SpectroscopyEvaluation, total_weight: f64) {
    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
}

fn uses_disamar_parity_support_grid(context: &PreparationContext<'_>) -> bool {
    use crate::input::instrument::{IntegrationMode, SpectralChannel};
    context
        .scene
        .observation_model
        .resolved_channel_controls(SpectralChannel::Radiance)
        .response
        .integration_mode
        == IntegrationMode::DisamarHrGrid
        || context
            .scene
            .observation_model
            .resolved_channel_controls(SpectralChannel::Irradiance)
            .response
            .integration_mode
            == IntegrationMode::DisamarHrGrid
}
