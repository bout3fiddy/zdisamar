use super::state_types::{
    PreparedLayer, PreparedSublayer, SharedRtmGeometry, SharedRtmLayerGeometry,
    SharedRtmLevelGeometry,
};
use crate::common::{errors, math::quadrature::gauss_legendre};

pub const MAX_DYNAMIC_GAUSS_ORDER: usize = 128;
pub const INVALID_SUPPORT_ROW_INDEX: u32 = u32::MAX;

#[derive(Debug, Clone, PartialEq)]
pub struct ResolvedGaussRule {
    pub nodes: Vec<f64>,
    pub weights: Vec<f64>,
}

pub fn resolve_gauss_rule(order: usize) -> Result<ResolvedGaussRule, errors::Error> {
    if order == 0 || order > MAX_DYNAMIC_GAUSS_ORDER {
        return Err(errors::Error::InvalidRequest);
    }

    let mut nodes = vec![0.0; order];
    let mut weights = vec![0.0; order];
    gauss_legendre::fill_nodes_and_weights(order as u32, &mut nodes, &mut weights)
        .map_err(|_| errors::Error::InvalidRequest)?;
    Ok(ResolvedGaussRule { nodes, weights })
}

pub fn interval_altitude_at_node(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_node: f64,
) -> f64 {
    let altitude_span_km = (upper_altitude_km - lower_altitude_km).max(0.0);
    lower_altitude_km + 0.5 * (normalized_node + 1.0) * altitude_span_km
}

pub fn interval_weight_km(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_weight: f64,
) -> f64 {
    let altitude_span_km = (upper_altitude_km - lower_altitude_km).max(0.0);
    0.5 * normalized_weight * altitude_span_km
}

pub fn build_shared_rtm_geometry_from_layers(
    layers: &[PreparedLayer],
    sublayers: &[PreparedSublayer],
) -> Result<SharedRtmGeometry, errors::Error> {
    if layers.is_empty() || sublayers.is_empty() {
        return Ok(SharedRtmGeometry::default());
    }

    let mut rtm_layers = vec![SharedRtmLayerGeometry::default(); layers.len()];
    let mut levels = vec![SharedRtmLevelGeometry::default(); layers.len() + 1];

    for (layer_index, layer) in layers.iter().copied().enumerate() {
        rtm_layers[layer_index] = SharedRtmLayerGeometry {
            lower_altitude_km: layer.bottom_altitude_km,
            upper_altitude_km: layer.top_altitude_km,
            midpoint_altitude_km: 0.5 * (layer.bottom_altitude_km + layer.top_altitude_km),
            thickness_km: (layer.top_altitude_km - layer.bottom_altitude_km).max(0.0),
            support_start_index: layer.sublayer_start_index,
            support_count: layer.sublayer_count,
        };
    }

    let first_layer = layers[0];
    let first_support_row_index = first_layer.sublayer_start_index as usize;
    let first_sublayer = sublayers
        .get(first_support_row_index)
        .ok_or(errors::Error::InvalidRequest)?;
    levels[0] = SharedRtmLevelGeometry {
        altitude_km: first_sublayer.altitude_km,
        weight_km: 0.0,
        support_start_index: first_layer.sublayer_start_index,
        support_count: first_layer.sublayer_count,
        support_row_index: first_support_row_index as u32,
        particle_above_support_row_index: first_active_support_row_index(first_layer),
        particle_below_support_row_index: INVALID_SUPPORT_ROW_INDEX,
    };

    for level_index in 1..layers.len() {
        let below_layer = layers[level_index - 1];
        let above_layer = layers[level_index];
        let boundary_support_row_index = above_layer.sublayer_start_index as usize;
        let boundary_sublayer = sublayers
            .get(boundary_support_row_index)
            .ok_or(errors::Error::InvalidRequest)?;
        levels[level_index] = SharedRtmLevelGeometry {
            altitude_km: boundary_sublayer.altitude_km,
            weight_km: 0.0,
            support_start_index: above_layer.sublayer_start_index,
            support_count: above_layer.sublayer_count,
            support_row_index: boundary_support_row_index as u32,
            particle_above_support_row_index: first_active_support_row_index(above_layer),
            particle_below_support_row_index: last_active_support_row_index(below_layer),
        };
    }

    let last_layer = layers[layers.len() - 1];
    let last_support_row_index =
        last_layer.sublayer_start_index as usize + last_layer.sublayer_count as usize - 1;
    let last_sublayer = sublayers
        .get(last_support_row_index)
        .ok_or(errors::Error::InvalidRequest)?;
    levels[layers.len()] = SharedRtmLevelGeometry {
        altitude_km: last_sublayer.altitude_km,
        weight_km: 0.0,
        support_start_index: last_layer.sublayer_start_index,
        support_count: last_layer.sublayer_count,
        support_row_index: last_support_row_index as u32,
        particle_above_support_row_index: INVALID_SUPPORT_ROW_INDEX,
        particle_below_support_row_index: last_active_support_row_index(last_layer),
    };

    fill_interval_weights(layers, &mut levels)?;

    Ok(SharedRtmGeometry {
        layers: rtm_layers,
        levels,
    })
}

fn fill_interval_weights(
    layers: &[PreparedLayer],
    levels: &mut [SharedRtmLevelGeometry],
) -> Result<(), errors::Error> {
    let mut interval_start = 0;
    while interval_start < layers.len() {
        let interval_index_1based = layers[interval_start].interval_index_1based;
        let mut interval_stop = interval_start + 1;
        while interval_stop < layers.len()
            && layers[interval_stop].interval_index_1based == interval_index_1based
        {
            interval_stop += 1;
        }

        let interior_level_count = interval_stop - interval_start - 1;
        if interior_level_count > 0 {
            let interval_first_layer = layers[interval_start];
            let interval_last_layer = layers[interval_stop - 1];
            let rule = resolve_gauss_rule(interior_level_count)?;
            for offset in 0..interior_level_count {
                levels[interval_start + 1 + offset].weight_km = interval_weight_km(
                    interval_first_layer.bottom_altitude_km,
                    interval_last_layer.top_altitude_km,
                    rule.weights[offset],
                );
            }
        }
        interval_start = interval_stop;
    }
    Ok(())
}

pub fn first_active_support_row_index(layer: PreparedLayer) -> u32 {
    let start_index = layer.sublayer_start_index as usize;
    let count = layer.sublayer_count as usize;
    if count <= 2 {
        return INVALID_SUPPORT_ROW_INDEX;
    }
    (start_index + 1) as u32
}

pub fn last_active_support_row_index(layer: PreparedLayer) -> u32 {
    let start_index = layer.sublayer_start_index as usize;
    let count = layer.sublayer_count as usize;
    if count <= 2 {
        return INVALID_SUPPORT_ROW_INDEX;
    }
    (start_index + count - 2) as u32
}

pub fn level_altitude_from_sublayers(sublayers: &[PreparedSublayer], level: usize) -> f64 {
    if sublayers.is_empty() {
        return 0.0;
    }
    if level == 0 {
        let first = sublayers[0];
        return (first.altitude_km - 0.5 * first.path_length_cm / 1.0e5).max(0.0);
    }
    if level >= sublayers.len() {
        let last = sublayers[sublayers.len() - 1];
        return (last.altitude_km + 0.5 * last.path_length_cm / 1.0e5).max(0.0);
    }
    let sample = sublayers[level];
    (sample.altitude_km - 0.5 * sample.path_length_cm / 1.0e5).max(0.0)
}
