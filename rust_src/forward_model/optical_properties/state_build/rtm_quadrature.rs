use super::{
    PreparedOpticalState, PreparedSublayer, ProfileNodeSpectroscopyCache,
    carrier_eval::{
        WavelengthCarrierCache, quadrature_carrier_at_altitude_with_cache,
        shared_boundary_carrier_at_level_with_cache,
        shared_boundary_carrier_at_level_with_carrier_cache,
    },
};
use crate::{
    common::{errors, math::quadrature::gauss_legendre},
    forward_model::{
        jacobian,
        optical_properties::{
            shared::phase_functions::{self, PhaseCoefficients},
            state_build::level_altitude_from_sublayers,
        },
        radiative_transfer::common_types::{LayerInput, RtmQuadratureLevel},
    },
};

fn fill_aerosol_source_jacobian(
    prepared: &PreparedOpticalState,
    rtm_level: &mut RtmQuadratureLevel,
    aerosol_scattering_optical_depth_per_km: f64,
    aerosol_phase_coefficients: PhaseCoefficients,
) {
    if prepared.aerosol_optical_depth <= 0.0 || aerosol_scattering_optical_depth_per_km <= 0.0 {
        return;
    }
    let state_index = jacobian::state_index(jacobian::State::AerosolOpticalDepth);
    let derivative_scale = aerosol_scattering_optical_depth_per_km / prepared.aerosol_optical_depth;
    for (index, coefficient) in aerosol_phase_coefficients.iter().enumerate() {
        rtm_level.ksca_phase_coefficient_jacobian[state_index][index] =
            derivative_scale * coefficient;
    }
}

fn scaled_aerosol_phase_per_km(
    aerosol_scattering_optical_depth_per_km: f64,
    aerosol_phase_coefficients: PhaseCoefficients,
) -> PhaseCoefficients {
    let mut scaled = phase_functions::zero_phase_coefficients();
    if aerosol_scattering_optical_depth_per_km <= 0.0 {
        return scaled;
    }
    for (index, coefficient) in aerosol_phase_coefficients.iter().enumerate() {
        scaled[index] = aerosol_scattering_optical_depth_per_km * coefficient;
    }
    scaled
}

fn fill_shared_aerosol_source_jacobian_from_layers(
    sublayers: &[PreparedSublayer],
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
) {
    let state_index = jacobian::state_index(jacobian::State::AerosolOpticalDepth);
    let phase_coefficients = sublayers
        .iter()
        .find(|sublayer| sublayer.aerosol_optical_depth > 0.0)
        .map(|sublayer| sublayer.aerosol_phase_coefficients)
        .unwrap_or_else(phase_functions::zero_phase_coefficients);
    if phase_coefficients[0] == 0.0 {
        return;
    }

    let total_scattering_derivative = layer_inputs
        .iter()
        .map(|layer| {
            jacobian::get(
                layer.scattering_optical_depth_jacobian,
                jacobian::State::AerosolOpticalDepth,
            )
        })
        .filter(|derivative| *derivative > 0.0)
        .sum::<f64>();
    if total_scattering_derivative <= 0.0 {
        return;
    }

    let mut total_weight = 0.0;
    for (level_index, level) in rtm_levels.iter().enumerate() {
        if level.weight <= 0.0 {
            continue;
        }
        let below_active = level_index > 0
            && jacobian::get(
                layer_inputs[level_index - 1].scattering_optical_depth_jacobian,
                jacobian::State::AerosolOpticalDepth,
            ) > 0.0;
        let above_active = level_index < layer_inputs.len()
            && jacobian::get(
                layer_inputs[level_index].scattering_optical_depth_jacobian,
                jacobian::State::AerosolOpticalDepth,
            ) > 0.0;
        if below_active || above_active {
            total_weight += level.weight;
        }
    }
    if total_weight <= 0.0 {
        return;
    }

    // Shared RTM levels can sit on clean interval boundaries, so their sampled
    // aerosol carrier may be zero even though adjacent layers carry aerosol.
    // Spread the layer derivative over the active shared source weights.
    let derivative_per_km = total_scattering_derivative / total_weight;
    for (level_index, level) in rtm_levels.iter_mut().enumerate() {
        if level.weight <= 0.0 {
            continue;
        }
        let below_active = level_index > 0
            && jacobian::get(
                layer_inputs[level_index - 1].scattering_optical_depth_jacobian,
                jacobian::State::AerosolOpticalDepth,
            ) > 0.0;
        let above_active = level_index < layer_inputs.len()
            && jacobian::get(
                layer_inputs[level_index].scattering_optical_depth_jacobian,
                jacobian::State::AerosolOpticalDepth,
            ) > 0.0;
        if !below_active && !above_active {
            continue;
        }
        for (index, coefficient) in phase_coefficients.iter().enumerate() {
            level.ksca_phase_coefficient_jacobian[state_index][index] =
                derivative_per_km * coefficient;
        }
    }
}

pub fn fill_rtm_quadrature_at_wavelength_with_layers(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
) -> Result<bool, errors::Error> {
    let Some(sublayers) = &prepared.sublayers else {
        return Ok(false);
    };
    if rtm_levels.len() != layer_inputs.len() + 1 {
        return Ok(false);
    }

    if prepared.interval_semantics_use_reduced_shared_rtm_layers()
        && layer_inputs.len() == prepared.layers.len()
    {
        let profile_cache = ProfileNodeSpectroscopyCache::new(prepared, wavelength_nm);
        return fill_shared_rtm_quadrature_at_wavelength(
            prepared,
            wavelength_nm,
            sublayers,
            layer_inputs,
            rtm_levels,
            &profile_cache,
        );
    }

    let profile_cache = ProfileNodeSpectroscopyCache::new(prepared, wavelength_nm);
    fill_sublayer_rtm_quadrature_at_wavelength(
        prepared,
        wavelength_nm,
        sublayers,
        layer_inputs,
        rtm_levels,
        &profile_cache,
    )
}

pub fn fill_rtm_quadrature_at_wavelength_with_layers_and_carrier_cache(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
    wavelength_cache: &mut WavelengthCarrierCache<'_>,
) -> Result<bool, errors::Error> {
    let Some(sublayers) = &prepared.sublayers else {
        return Ok(false);
    };
    if rtm_levels.len() != layer_inputs.len() + 1 {
        return Ok(false);
    }

    if prepared.interval_semantics_use_reduced_shared_rtm_layers()
        && layer_inputs.len() == prepared.layers.len()
    {
        return fill_shared_rtm_quadrature_at_wavelength_with_carrier_cache(
            prepared,
            wavelength_nm,
            sublayers,
            layer_inputs,
            rtm_levels,
            wavelength_cache,
        );
    }

    fill_sublayer_rtm_quadrature_at_wavelength(
        prepared,
        wavelength_nm,
        sublayers,
        layer_inputs,
        rtm_levels,
        &wavelength_cache.profile_cache,
    )
}

fn fill_shared_rtm_quadrature_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
    profile_cache: &ProfileNodeSpectroscopyCache,
) -> Result<bool, errors::Error> {
    if !prepared
        .shared_rtm_geometry
        .is_valid_for(layer_inputs.len())
    {
        for rtm_level in rtm_levels {
            *rtm_level = RtmQuadratureLevel::default();
        }
        return Ok(false);
    }

    for (rtm_level, &level_geometry) in rtm_levels
        .iter_mut()
        .zip(prepared.shared_rtm_geometry.levels.iter())
    {
        let boundary_carrier = shared_boundary_carrier_at_level_with_cache(
            prepared,
            wavelength_nm,
            sublayers,
            level_geometry,
            Some(profile_cache),
        )?;
        *rtm_level = RtmQuadratureLevel {
            altitude_km: level_geometry.altitude_km,
            weight: level_geometry.weight_km,
            ksca: boundary_carrier.ksca_above,
            phase_coefficients: boundary_carrier.phase_coefficients_above,
            aerosol_ksca_phase_above_per_km: scaled_aerosol_phase_per_km(
                boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
                boundary_carrier.aerosol_phase_coefficients_above,
            ),
            aerosol_ksca_phase_below_per_km: scaled_aerosol_phase_per_km(
                boundary_carrier.aerosol_scattering_optical_depth_below_per_km,
                boundary_carrier.aerosol_phase_coefficients_below,
            ),
            ..RtmQuadratureLevel::default()
        };
        fill_aerosol_source_jacobian(
            prepared,
            rtm_level,
            boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
            boundary_carrier.aerosol_phase_coefficients_above,
        );
    }
    fill_shared_aerosol_source_jacobian_from_layers(sublayers, layer_inputs, rtm_levels);

    // DISAMAR uses the coarse shared level carrier directly for integrated
    // source terms; it is not renormalized to the layer scattering totals.
    Ok(rtm_levels
        .iter()
        .any(|rtm_level| rtm_level.weighted_scattering() > 0.0))
}

fn fill_shared_rtm_quadrature_at_wavelength_with_carrier_cache(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
    wavelength_cache: &mut WavelengthCarrierCache<'_>,
) -> Result<bool, errors::Error> {
    if !prepared
        .shared_rtm_geometry
        .is_valid_for(layer_inputs.len())
    {
        for rtm_level in rtm_levels {
            *rtm_level = RtmQuadratureLevel::default();
        }
        return Ok(false);
    }

    for (rtm_level, &level_geometry) in rtm_levels
        .iter_mut()
        .zip(prepared.shared_rtm_geometry.levels.iter())
    {
        let boundary_carrier = shared_boundary_carrier_at_level_with_carrier_cache(
            prepared,
            wavelength_nm,
            sublayers,
            level_geometry,
            wavelength_cache,
        )?;
        *rtm_level = RtmQuadratureLevel {
            altitude_km: level_geometry.altitude_km,
            weight: level_geometry.weight_km,
            ksca: boundary_carrier.ksca_above,
            phase_coefficients: boundary_carrier.phase_coefficients_above,
            aerosol_ksca_phase_above_per_km: scaled_aerosol_phase_per_km(
                boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
                boundary_carrier.aerosol_phase_coefficients_above,
            ),
            aerosol_ksca_phase_below_per_km: scaled_aerosol_phase_per_km(
                boundary_carrier.aerosol_scattering_optical_depth_below_per_km,
                boundary_carrier.aerosol_phase_coefficients_below,
            ),
            ..RtmQuadratureLevel::default()
        };
        fill_aerosol_source_jacobian(
            prepared,
            rtm_level,
            boundary_carrier.aerosol_scattering_optical_depth_above_per_km,
            boundary_carrier.aerosol_phase_coefficients_above,
        );
    }
    fill_shared_aerosol_source_jacobian_from_layers(sublayers, layer_inputs, rtm_levels);

    Ok(rtm_levels
        .iter()
        .any(|rtm_level| rtm_level.weighted_scattering() > 0.0))
}

fn fill_sublayer_rtm_quadrature_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    layer_inputs: &[LayerInput],
    rtm_levels: &mut [RtmQuadratureLevel],
    profile_cache: &ProfileNodeSpectroscopyCache,
) -> Result<bool, errors::Error> {
    if layer_inputs.len() != sublayers.len() {
        return Ok(false);
    }

    for (level, rtm_level) in rtm_levels.iter_mut().enumerate() {
        *rtm_level = RtmQuadratureLevel {
            altitude_km: level_altitude_from_sublayers(sublayers, level),
            ..RtmQuadratureLevel::default()
        };
    }

    let mut has_active_quadrature = false;
    for layer in &prepared.layers {
        let start = layer.sublayer_start_index as usize;
        let count = layer.sublayer_count as usize;
        if count == 0 {
            continue;
        }
        let stop = start + count;
        if stop >= rtm_levels.len()
            || stop > sublayers.len()
            || stop > layer_inputs.len()
            || start >= stop
        {
            return Ok(false);
        }

        let active_count = count.saturating_sub(1);
        if active_count == 0 {
            continue;
        }
        let mut nodes = vec![0.0; active_count];
        let mut weights = vec![0.0; active_count];
        gauss_legendre::fill_nodes_and_weights(active_count as u32, &mut nodes, &mut weights)
            .map_err(|_| errors::Error::InvalidRequest)?;

        let lower_altitude_km = rtm_levels[start].altitude_km;
        let upper_altitude_km = rtm_levels[stop].altitude_km;
        let altitude_span_km = (upper_altitude_km - lower_altitude_km).max(0.0);
        let total_span_km = sublayers[start..stop]
            .iter()
            .map(|sublayer| (sublayer.path_length_cm / 1.0e5).max(0.0))
            .sum::<f64>();
        let total_scattering = layer_inputs[start..stop]
            .iter()
            .map(|layer_input| layer_input.scattering_optical_depth.max(0.0))
            .sum::<f64>();
        if total_span_km <= 0.0 {
            continue;
        }

        let mut raw_scattering_sum = 0.0;
        for node_index in 0..active_count {
            let level = start + 1 + node_index;
            let normalized_position = 0.5 * (nodes[node_index] + 1.0);
            let node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
            let carrier = quadrature_carrier_at_altitude_with_cache(
                prepared,
                wavelength_nm,
                &sublayers[start..stop],
                node_altitude_km,
                Some(profile_cache),
            )?;
            rtm_levels[level] = RtmQuadratureLevel {
                altitude_km: node_altitude_km,
                weight: 0.5 * weights[node_index] * total_span_km,
                ksca: carrier.ksca,
                phase_coefficients: carrier.phase_coefficients,
                aerosol_ksca_phase_above_per_km: scaled_aerosol_phase_per_km(
                    carrier.aerosol_scattering_optical_depth_per_km,
                    carrier.aerosol_phase_coefficients,
                ),
                aerosol_ksca_phase_below_per_km: scaled_aerosol_phase_per_km(
                    carrier.aerosol_scattering_optical_depth_per_km,
                    carrier.aerosol_phase_coefficients,
                ),
                ..RtmQuadratureLevel::default()
            };
            fill_aerosol_source_jacobian(
                prepared,
                &mut rtm_levels[level],
                carrier.aerosol_scattering_optical_depth_per_km,
                carrier.aerosol_phase_coefficients,
            );
            raw_scattering_sum += rtm_levels[level].weighted_scattering();
        }

        if total_scattering <= 0.0 {
            for rtm_level in &mut rtm_levels[start + 1..stop] {
                rtm_level.ksca = 0.0;
            }
            continue;
        }
        if raw_scattering_sum > 0.0 {
            let scale = total_scattering / raw_scattering_sum;
            for rtm_level in &mut rtm_levels[start + 1..stop] {
                rtm_level.ksca *= scale;
                for value in &mut rtm_level.aerosol_ksca_phase_above_per_km {
                    *value *= scale;
                }
                for value in &mut rtm_level.aerosol_ksca_phase_below_per_km {
                    *value *= scale;
                }
                for state_row in &mut rtm_level.ksca_phase_coefficient_jacobian {
                    for value in state_row {
                        *value *= scale;
                    }
                }
            }
            has_active_quadrature = true;
        } else {
            for rtm_level in &mut rtm_levels[start + 1..stop] {
                rtm_level.weight = 0.0;
                rtm_level.ksca = 0.0;
            }
        }
    }

    Ok(has_active_quadrature)
}
