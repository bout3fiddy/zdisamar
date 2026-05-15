use super::PreparedOpticalState;
use crate::{
    forward_model::radiative_transfer::common_types::{LayerInput, PseudoSphericalSample},
    input::scene::Scene,
};

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
