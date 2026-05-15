use super::state_types::{PreparedLayer, PreparedSublayer};
use crate::forward_model::radiative_transfer::{
    common_route,
    common_types::{LayerInput, SourceInterfaceInput},
};

const CENTIMETERS_PER_KILOMETER: f64 = 1.0e5;

pub fn fill_source_interfaces_from_prepared_layers(
    layer_inputs: &[LayerInput],
    sublayers: Option<&[PreparedSublayer]>,
    layers: &[PreparedLayer],
    source_interfaces: &mut [SourceInterfaceInput],
) {
    if layer_inputs.is_empty() || source_interfaces.len() != layer_inputs.len() + 1 {
        return;
    }

    common_route::fill_source_interfaces_from_layers(layer_inputs, source_interfaces);

    let Some(sublayers) = sublayers else {
        return;
    };
    if layer_inputs.len() == sublayers.len() {
        fill_sublayer_source_interfaces(layer_inputs, sublayers, source_interfaces);
        return;
    }
    if layer_inputs.len() == 1 || layers.len() != layer_inputs.len() {
        return;
    }

    fill_layer_source_interfaces(layer_inputs, sublayers, layers, source_interfaces);
}

fn fill_sublayer_source_interfaces(
    layer_inputs: &[LayerInput],
    sublayers: &[PreparedSublayer],
    source_interfaces: &mut [SourceInterfaceInput],
) {
    for ilevel in 1..layer_inputs.len() {
        let sublayer = sublayers[ilevel];
        let scattering_optical_depth = layer_inputs[ilevel].scattering_optical_depth.max(0.0);
        let rtm_weight = (sublayer.path_length_cm / CENTIMETERS_PER_KILOMETER).max(0.0);
        source_interfaces[ilevel] = SourceInterfaceInput {
            source_weight: 0.0,
            rtm_weight,
            ksca_above: if rtm_weight > 0.0 {
                scattering_optical_depth / rtm_weight
            } else {
                0.0
            },
            phase_coefficients_above: layer_inputs[ilevel].phase_coefficients,
            ..SourceInterfaceInput::default()
        };
    }
}

fn fill_layer_source_interfaces(
    layer_inputs: &[LayerInput],
    sublayers: &[PreparedSublayer],
    layers: &[PreparedLayer],
    source_interfaces: &mut [SourceInterfaceInput],
) {
    for ilevel in 1..layer_inputs.len() {
        let layer = layers[ilevel];
        let start_index = layer.sublayer_start_index as usize;
        let sublayer_count = layer.sublayer_count as usize;
        if sublayer_count == 0 {
            source_interfaces[ilevel] = SourceInterfaceInput {
                source_weight: 0.0,
                phase_coefficients_above: layer_inputs[ilevel].phase_coefficients,
                ..SourceInterfaceInput::default()
            };
            continue;
        }

        let stop_index = start_index + sublayer_count;
        let Some(support_sublayers) = sublayers.get(start_index..stop_index) else {
            continue;
        };
        let rtm_weight = support_sublayers
            .iter()
            .map(|sublayer| (sublayer.path_length_cm / CENTIMETERS_PER_KILOMETER).max(0.0))
            .sum::<f64>();
        let scattering_optical_depth = layer_inputs[ilevel].scattering_optical_depth.max(0.0);
        source_interfaces[ilevel] = SourceInterfaceInput {
            source_weight: 0.0,
            rtm_weight,
            ksca_above: if rtm_weight > 0.0 {
                scattering_optical_depth / rtm_weight
            } else {
                0.0
            },
            phase_coefficients_above: layer_inputs[ilevel].phase_coefficients,
            ..SourceInterfaceInput::default()
        };
    }
}
