use super::{
    EvaluatedLayer, OpticalDepthBreakdown, PHASE_COEFFICIENT_COUNT, PreparedOpticalState,
    PreparedSublayer, cia_sigma_at_wavelength, collision_induced_sigma_at_wavelength,
    continuum_carrier_density_at_sublayer, line_spectroscopy_carrier_density_at_sublayer,
    particle_optical_depth_at_wavelength, total_cross_section_at_wavelength,
    weighted_spectroscopy_evaluation_at_wavelength,
};
use crate::{
    common::errors,
    forward_model::optical_properties::shared::phase_functions,
    input::{reference::rayleigh, reference_data::interpolate_cross_section_sigma, scene::Scene},
};

pub fn optical_depth_breakdown_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<OpticalDepthBreakdown, errors::Error> {
    if let Some(sublayers) = &prepared.sublayers {
        let mut totals = OpticalDepthBreakdown::default();
        for layer in &prepared.layers {
            let start_index = layer.sublayer_start_index as usize;
            let end_index = start_index + layer.sublayer_count as usize;
            if start_index >= sublayers.len() || end_index > sublayers.len() {
                return Err(errors::Error::InvalidRequest);
            }
            let evaluated = evaluate_layer_at_wavelength(
                prepared,
                None,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                &sublayers[start_index..end_index],
            )?;
            accumulate_breakdown_fields(&mut totals, evaluated.breakdown);
        }
        return Ok(totals);
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

pub fn evaluate_layer_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: Option<&Scene>,
    altitude_km: f64,
    wavelength_nm: f64,
    sublayer_start_index: usize,
    sublayers: &[PreparedSublayer],
) -> Result<EvaluatedLayer, errors::Error> {
    let mut breakdown = OpticalDepthBreakdown::default();
    let mut phase_numerator = [0.0; PHASE_COEFFICIENT_COUNT];
    let gas_phase_coefficients =
        phase_functions::gas_phase_coefficients_at_wavelength(wavelength_nm);

    for (sublayer_index, &sublayer) in sublayers.iter().enumerate() {
        let global_sublayer_index = sublayer_start_index + sublayer_index;
        let gas_absorption_optical_depth = gas_absorption_optical_depth_at_sublayer(
            prepared,
            sublayer,
            global_sublayer_index,
            wavelength_nm,
        )?;
        let gas_scattering_optical_depth = rayleigh::cross_section_cm2(wavelength_nm)
            * sublayer.number_density_cm3
            * sublayer.path_length_cm;
        let cia_optical_depth = cia_sigma_at_wavelength(
            prepared,
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        ) * sublayer.cia_pair_density_cm6_value()
            * sublayer.path_length_cm;
        let aerosol_optical_depth = particle_optical_depth_at_wavelength(
            sublayer.aerosol_optical_depth,
            sublayer.aerosol_base_optical_depth,
            prepared.aerosol_reference_wavelength_nm,
            prepared.aerosol_angstrom_exponent,
            &prepared.aerosol_fraction_control,
            wavelength_nm,
        );
        let cloud_optical_depth = particle_optical_depth_at_wavelength(
            sublayer.cloud_optical_depth,
            sublayer.cloud_base_optical_depth,
            prepared.cloud_reference_wavelength_nm,
            prepared.cloud_angstrom_exponent,
            &prepared.cloud_fraction_control,
            wavelength_nm,
        );
        let aerosol_scattering_optical_depth =
            aerosol_optical_depth * sublayer.aerosol_single_scatter_albedo;
        let cloud_scattering_optical_depth =
            cloud_optical_depth * sublayer.cloud_single_scatter_albedo;

        accumulate_breakdown_fields(
            &mut breakdown,
            OpticalDepthBreakdown {
                gas_absorption_optical_depth,
                gas_scattering_optical_depth,
                cia_optical_depth,
                aerosol_optical_depth,
                aerosol_scattering_optical_depth,
                cloud_optical_depth,
                cloud_scattering_optical_depth,
            },
        );

        for index in 0..PHASE_COEFFICIENT_COUNT {
            phase_numerator[index] += gas_scattering_optical_depth * gas_phase_coefficients[index]
                + aerosol_scattering_optical_depth * sublayer.aerosol_phase_coefficients[index]
                + cloud_scattering_optical_depth * sublayer.cloud_phase_coefficients[index];
        }
    }

    let total_scattering = breakdown.total_scattering_optical_depth();
    let mut phase_coefficients =
        phase_functions::gas_phase_coefficients_at_wavelength(wavelength_nm);
    if total_scattering > 0.0 {
        for index in 0..PHASE_COEFFICIENT_COUNT {
            phase_coefficients[index] = phase_numerator[index] / total_scattering;
        }
        phase_coefficients[0] = 1.0;
    }

    Ok(EvaluatedLayer {
        breakdown,
        phase_coefficients,
        solar_mu: scene
            .map(|owned_scene| owned_scene.geometry.solar_cosine_at_altitude(altitude_km))
            .unwrap_or(1.0),
        view_mu: scene
            .map(|owned_scene| owned_scene.geometry.viewing_cosine_at_altitude(altitude_km))
            .unwrap_or(1.0),
    })
}

fn gas_absorption_optical_depth_at_sublayer(
    prepared: &PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    let continuum_sigma = if prepared.cross_section_absorbers.is_empty() {
        interpolate_cross_section_sigma(&prepared.continuum_points, wavelength_nm)
    } else {
        0.0
    };
    let continuum_density_cm3 = if prepared.cross_section_absorbers.is_empty() {
        continuum_carrier_density_at_sublayer(prepared, sublayer, global_sublayer_index)
    } else {
        0.0
    };
    let continuum_optical_depth = continuum_sigma * continuum_density_cm3 * sublayer.path_length_cm;

    let mut cross_section_optical_depth = 0.0;
    for absorber in &prepared.cross_section_absorbers {
        let absorber_density_cm3 = absorber
            .number_densities_cm3
            .get(global_sublayer_index)
            .copied()
            .unwrap_or(0.0);
        if absorber_density_cm3 <= 0.0 {
            continue;
        }
        cross_section_optical_depth +=
            absorber.sigma_at(wavelength_nm, sublayer.temperature_k, sublayer.pressure_hpa)
                * absorber_density_cm3
                * sublayer.path_length_cm;
    }

    let line_optical_depth = if !prepared.line_absorbers.is_empty() {
        if !prepared.operational_o2_lut.enabled() {
            // The line-list evaluator is not ported yet. This branch supports
            // operational O2 only, so line absorbers without that LUT must not
            // silently disappear.
            return Err(errors::Error::InvalidRequest);
        }
        prepared.operational_o2_lut.sigma_at(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        ) * sublayer.oxygen_number_density_cm3
            * sublayer.path_length_cm
    } else {
        let spectroscopy_sigma = weighted_spectroscopy_evaluation_at_wavelength(
            prepared,
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        )?
        .total_sigma_cm2_per_molecule;
        let spectroscopy_density_cm3 = line_spectroscopy_carrier_density_at_sublayer(
            prepared,
            sublayer,
            global_sublayer_index,
        );
        spectroscopy_sigma * spectroscopy_density_cm3 * sublayer.path_length_cm
    };

    Ok(continuum_optical_depth + cross_section_optical_depth + line_optical_depth)
}

fn accumulate_breakdown_fields(
    totals: &mut OpticalDepthBreakdown,
    breakdown: OpticalDepthBreakdown,
) {
    totals.gas_absorption_optical_depth += breakdown.gas_absorption_optical_depth;
    totals.gas_scattering_optical_depth += breakdown.gas_scattering_optical_depth;
    totals.cia_optical_depth += breakdown.cia_optical_depth;
    totals.aerosol_optical_depth += breakdown.aerosol_optical_depth;
    totals.aerosol_scattering_optical_depth += breakdown.aerosol_scattering_optical_depth;
    totals.cloud_optical_depth += breakdown.cloud_optical_depth;
    totals.cloud_scattering_optical_depth += breakdown.cloud_scattering_optical_depth;
}
