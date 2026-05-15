use super::{
    PreparedOpticalState, PreparedSublayer, ProfileNodeSpectroscopyCache,
    carrier_eval::shared_optical_carrier_at_altitude_with_cache, level_altitude_from_sublayers,
    shared_carrier::fill_shared_pseudo_spherical_samples_from_support_rows_with_cache,
};
use crate::{
    common::{errors, math::quadrature::gauss_legendre},
    forward_model::radiative_transfer::common_types::{LayerInput, PseudoSphericalSample},
    input::scene::Scene,
};

struct PseudoSphericalInterval<'a> {
    support_sublayers: &'a [PreparedSublayer],
    lower_altitude_km: f64,
    upper_altitude_km: f64,
}

pub struct PseudoSphericalBuffers<'a> {
    pub attenuation_layers: &'a mut [LayerInput],
    pub attenuation_samples: &'a mut [PseudoSphericalSample],
    pub level_sample_starts: &'a mut [usize],
    pub level_altitudes_km: &'a mut [f64],
}

pub fn fill_shared_pseudo_spherical_grid_from_layer_inputs(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    layer_inputs: &[LayerInput],
    attenuation_layers: &mut [LayerInput],
    attenuation_samples: &mut [PseudoSphericalSample],
    level_sample_starts: &mut [usize],
    level_altitudes_km: &mut [f64],
) -> bool {
    if !prepared
        .shared_rtm_geometry
        .is_valid_for(layer_inputs.len())
    {
        return false;
    }
    let subgrid_divisions = usize::from(scene.atmosphere.sublayer_divisions).max(1);
    let sample_count = layer_inputs.len() * subgrid_divisions;
    if attenuation_samples.len() < sample_count
        || level_sample_starts.len() != layer_inputs.len() + 1
        || level_altitudes_km.len() != layer_inputs.len() + 1
    {
        return false;
    }

    for (altitude_km, level_geometry) in level_altitudes_km
        .iter_mut()
        .zip(prepared.shared_rtm_geometry.levels.iter())
    {
        *altitude_km = level_geometry.altitude_km;
    }

    let mut sample_index = 0;
    for (layer_index, (layer_geometry, layer_input)) in prepared
        .shared_rtm_geometry
        .layers
        .iter()
        .zip(layer_inputs.iter())
        .enumerate()
    {
        level_sample_starts[layer_index] = sample_index;
        if subgrid_divisions <= 1 {
            attenuation_samples[sample_index] = PseudoSphericalSample {
                altitude_km: layer_geometry.midpoint_altitude_km,
                thickness_km: layer_geometry.thickness_km,
                optical_depth: layer_input.optical_depth,
            };
            write_attenuation_layer_optical_depth(
                attenuation_layers,
                sample_index,
                layer_input.optical_depth,
            );
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = PseudoSphericalSample {
            altitude_km: layer_geometry.lower_altitude_km,
            thickness_km: 0.0,
            optical_depth: 0.0,
        };
        clear_attenuation_layer(attenuation_layers, sample_index);
        sample_index += 1;

        attenuation_samples[sample_index] = PseudoSphericalSample {
            altitude_km: layer_geometry.midpoint_altitude_km,
            thickness_km: layer_geometry.thickness_km,
            optical_depth: layer_input.optical_depth,
        };
        write_attenuation_layer_optical_depth(
            attenuation_layers,
            sample_index,
            layer_input.optical_depth,
        );
        sample_index += 1;

        for _ in 2..subgrid_divisions {
            attenuation_samples[sample_index] = PseudoSphericalSample {
                altitude_km: layer_geometry.upper_altitude_km,
                thickness_km: 0.0,
                optical_depth: 0.0,
            };
            clear_attenuation_layer(attenuation_layers, sample_index);
            sample_index += 1;
        }
    }

    level_sample_starts[layer_inputs.len()] = sample_index;
    true
}

pub fn fill_pseudo_spherical_grid_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    buffers: PseudoSphericalBuffers<'_>,
) -> Result<bool, errors::Error> {
    let Some(sublayers) = &prepared.sublayers else {
        return Ok(false);
    };
    let subgrid_divisions = usize::from(scene.atmosphere.sublayer_divisions).max(1);
    let sample_count = solver_layer_count * subgrid_divisions;
    if buffers.attenuation_samples.len() < sample_count
        || buffers.level_sample_starts.len() != solver_layer_count + 1
        || buffers.level_altitudes_km.len() != solver_layer_count + 1
    {
        return Ok(false);
    }
    if solver_layer_count != sublayers.len() && solver_layer_count != prepared.layers.len() {
        return Ok(false);
    }

    if prepared.interval_semantics_use_reduced_shared_rtm_layers()
        && solver_layer_count == prepared.layers.len()
    {
        let profile_cache = ProfileNodeSpectroscopyCache::new(prepared, wavelength_nm);
        return fill_shared_pseudo_spherical_grid_at_wavelength(
            prepared,
            wavelength_nm,
            solver_layer_count,
            sublayers,
            buffers,
            &profile_cache,
        );
    }

    let profile_cache = ProfileNodeSpectroscopyCache::new(prepared, wavelength_nm);
    fill_regular_pseudo_spherical_grid_at_wavelength(
        prepared,
        scene,
        wavelength_nm,
        solver_layer_count,
        sublayers,
        buffers,
        &profile_cache,
    )
}

fn fill_shared_pseudo_spherical_grid_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    solver_layer_count: usize,
    sublayers: &[PreparedSublayer],
    buffers: PseudoSphericalBuffers<'_>,
    profile_cache: &ProfileNodeSpectroscopyCache,
) -> Result<bool, errors::Error> {
    if !prepared
        .shared_rtm_geometry
        .is_valid_for(solver_layer_count)
    {
        return Ok(false);
    }

    for (altitude_km, level_geometry) in buffers
        .level_altitudes_km
        .iter_mut()
        .zip(prepared.shared_rtm_geometry.levels.iter())
    {
        *altitude_km = level_geometry.altitude_km;
    }

    let mut sample_index = 0;
    for (layer_index, layer_geometry) in prepared.shared_rtm_geometry.layers.iter().enumerate() {
        buffers.level_sample_starts[layer_index] = sample_index;
        let support_start_index = layer_geometry.support_start_index as usize;
        let support_count = layer_geometry.support_count as usize;
        let support_end_index = support_start_index + support_count;
        let Some(support_sublayers) = sublayers.get(support_start_index..support_end_index) else {
            return Err(errors::Error::InvalidRequest);
        };
        sample_index = fill_shared_pseudo_spherical_samples_from_support_rows_with_cache(
            prepared,
            wavelength_nm,
            support_sublayers,
            &mut *buffers.attenuation_layers,
            &mut *buffers.attenuation_samples,
            sample_index,
            Some(profile_cache),
        )?;
    }
    buffers.level_sample_starts[solver_layer_count] = sample_index;
    Ok(true)
}

fn fill_regular_pseudo_spherical_grid_at_wavelength(
    prepared: &PreparedOpticalState,
    scene: &Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    sublayers: &[PreparedSublayer],
    buffers: PseudoSphericalBuffers<'_>,
    profile_cache: &ProfileNodeSpectroscopyCache,
) -> Result<bool, errors::Error> {
    fill_regular_level_altitudes(
        prepared,
        solver_layer_count,
        sublayers,
        &mut *buffers.level_altitudes_km,
    );

    let subgrid_divisions = usize::from(scene.atmosphere.sublayer_divisions).max(1);
    let mut sample_index = 0;
    let mut solver_level = 0;
    while solver_level < solver_layer_count {
        let interval =
            pseudo_spherical_interval(prepared, solver_layer_count, sublayers, solver_level)?;
        let altitude_span_km = (interval.upper_altitude_km - interval.lower_altitude_km).max(0.0);
        let active_count = subgrid_divisions - 1;
        buffers.level_sample_starts[solver_level] = sample_index;

        if active_count == 0 {
            let sample_altitude_km = if altitude_span_km > 0.0 {
                interval.lower_altitude_km + 0.5 * altitude_span_km
            } else {
                interval.lower_altitude_km
            };
            let optical_depth = shared_optical_carrier_at_altitude_with_cache(
                prepared,
                wavelength_nm,
                interval.support_sublayers,
                sample_altitude_km,
                Some(profile_cache),
            )?
            .total_optical_depth_per_km()
                * altitude_span_km;
            write_attenuation_sample(
                &mut *buffers.attenuation_layers,
                &mut *buffers.attenuation_samples,
                sample_index,
                sample_altitude_km,
                altitude_span_km,
                optical_depth,
            )?;
            sample_index += 1;
            solver_level += 1;
            continue;
        }

        write_attenuation_sample(
            &mut *buffers.attenuation_layers,
            &mut *buffers.attenuation_samples,
            sample_index,
            interval.lower_altitude_km,
            0.0,
            0.0,
        )?;
        sample_index += 1;

        if altitude_span_km <= 0.0 {
            for _ in 0..active_count {
                write_attenuation_sample(
                    &mut *buffers.attenuation_layers,
                    &mut *buffers.attenuation_samples,
                    sample_index,
                    interval.lower_altitude_km,
                    0.0,
                    0.0,
                )?;
                sample_index += 1;
            }
            solver_level += 1;
            continue;
        }

        let mut nodes = vec![0.0; active_count];
        let mut weights = vec![0.0; active_count];
        gauss_legendre::fill_nodes_and_weights(active_count as u32, &mut nodes, &mut weights)
            .map_err(|_| errors::Error::InvalidRequest)?;
        for node_index in 0..active_count {
            let normalized_position = 0.5 * (nodes[node_index] + 1.0);
            let node_altitude_km =
                interval.lower_altitude_km + normalized_position * altitude_span_km;
            let weight_km = 0.5 * weights[node_index] * altitude_span_km;
            let optical_depth = shared_optical_carrier_at_altitude_with_cache(
                prepared,
                wavelength_nm,
                interval.support_sublayers,
                node_altitude_km,
                Some(profile_cache),
            )?
            .total_optical_depth_per_km()
                * weight_km;
            write_attenuation_sample(
                &mut *buffers.attenuation_layers,
                &mut *buffers.attenuation_samples,
                sample_index,
                node_altitude_km,
                weight_km,
                optical_depth,
            )?;
            sample_index += 1;
        }
        solver_level += 1;
    }

    buffers.level_sample_starts[solver_layer_count] = sample_index;
    Ok(true)
}

fn fill_regular_level_altitudes(
    prepared: &PreparedOpticalState,
    solver_layer_count: usize,
    sublayers: &[PreparedSublayer],
    level_altitudes_km: &mut [f64],
) {
    level_altitudes_km[0] = level_altitude_from_sublayers(sublayers, 0);
    if solver_layer_count == sublayers.len() {
        for (ilevel, altitude_km) in level_altitudes_km
            .iter_mut()
            .enumerate()
            .take(solver_layer_count + 1)
            .skip(1)
        {
            *altitude_km = level_altitude_from_sublayers(sublayers, ilevel);
        }
        return;
    }

    for (ilevel, altitude_km) in level_altitudes_km
        .iter_mut()
        .enumerate()
        .take(solver_layer_count)
        .skip(1)
    {
        let start_index = prepared.layers[ilevel].sublayer_start_index as usize;
        *altitude_km = level_altitude_from_sublayers(sublayers, start_index);
    }
    level_altitudes_km[solver_layer_count] =
        level_altitude_from_sublayers(sublayers, sublayers.len());
}

fn pseudo_spherical_interval<'a>(
    prepared: &PreparedOpticalState,
    solver_layer_count: usize,
    sublayers: &'a [PreparedSublayer],
    solver_level: usize,
) -> Result<PseudoSphericalInterval<'a>, errors::Error> {
    if solver_layer_count == sublayers.len() {
        return Ok(PseudoSphericalInterval {
            support_sublayers: &sublayers[solver_level..solver_level + 1],
            lower_altitude_km: level_altitude_from_sublayers(sublayers, solver_level),
            upper_altitude_km: level_altitude_from_sublayers(sublayers, solver_level + 1),
        });
    }

    let layer = prepared.layers[solver_level];
    let start = layer.sublayer_start_index as usize;
    let count = layer.sublayer_count as usize;
    if count == 0 {
        return Err(errors::Error::InvalidRequest);
    }
    let stop = start + count;
    let Some(support_sublayers) = sublayers.get(start..stop) else {
        return Err(errors::Error::InvalidRequest);
    };
    Ok(PseudoSphericalInterval {
        support_sublayers,
        lower_altitude_km: level_altitude_from_sublayers(sublayers, start),
        upper_altitude_km: level_altitude_from_sublayers(sublayers, stop),
    })
}

fn write_attenuation_sample(
    attenuation_layers: &mut [LayerInput],
    attenuation_samples: &mut [PseudoSphericalSample],
    sample_index: usize,
    altitude_km: f64,
    thickness_km: f64,
    optical_depth: f64,
) -> Result<(), errors::Error> {
    let Some(sample) = attenuation_samples.get_mut(sample_index) else {
        return Err(errors::Error::InvalidRequest);
    };
    *sample = PseudoSphericalSample {
        altitude_km,
        thickness_km,
        optical_depth,
    };
    if let Some(layer) = attenuation_layers.get_mut(sample_index) {
        *layer = LayerInput {
            optical_depth,
            ..LayerInput::default()
        };
    }
    Ok(())
}

fn write_attenuation_layer_optical_depth(
    attenuation_layers: &mut [LayerInput],
    sample_index: usize,
    optical_depth: f64,
) {
    if let Some(layer) = attenuation_layers.get_mut(sample_index) {
        *layer = LayerInput {
            optical_depth,
            ..LayerInput::default()
        };
    }
}

fn clear_attenuation_layer(attenuation_layers: &mut [LayerInput], sample_index: usize) {
    if let Some(layer) = attenuation_layers.get_mut(sample_index) {
        *layer = LayerInput::default();
    }
}
