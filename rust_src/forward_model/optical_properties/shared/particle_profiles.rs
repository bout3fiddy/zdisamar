use crate::{
    common::errors,
    input::atmosphere::{IntervalPlacement, ParticlePlacementSemantics},
};

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct PreparedVerticalGrid<'a> {
    pub layer_top_altitudes_km: &'a [f64],
    pub layer_bottom_altitudes_km: &'a [f64],
    pub layer_interval_indices_1based: &'a [u32],
    pub sublayer_top_altitudes_km: &'a [f64],
    pub sublayer_bottom_altitudes_km: &'a [f64],
    pub sublayer_mid_altitudes_km: &'a [f64],
    pub sublayer_support_weights_km: &'a [f64],
    pub sublayer_parent_interval_indices_1based: &'a [u32],
}

pub fn scale_optical_depth(
    optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    wavelength_nm: f64,
) -> f64 {
    if optical_depth == 0.0 {
        return 0.0;
    }
    if angstrom_exponent == 0.0 || reference_wavelength_nm == wavelength_nm {
        return optical_depth;
    }
    let safe_wavelength = wavelength_nm.max(1.0);
    let safe_reference = reference_wavelength_nm.max(1.0);
    optical_depth * (safe_reference / safe_wavelength).powf(angstrom_exponent)
}

pub fn build_placement_bound_distribution(
    grid: PreparedVerticalGrid<'_>,
    has_explicit_interval_grid: bool,
    enabled: bool,
    total_optical_depth: f64,
    placement: IntervalPlacement,
) -> Result<Vec<f64>, errors::Error> {
    if placement.interval_index_1based != 0 {
        if !has_explicit_interval_grid {
            return Err(errors::Error::InvalidRequest);
        }
        return build_interval_matched_distribution(
            grid,
            enabled,
            total_optical_depth,
            placement.interval_index_1based,
        );
    }
    build_finite_layer_sublayer_distribution(
        grid,
        enabled,
        total_optical_depth,
        placement.bottom_altitude_km,
        placement.top_altitude_km,
        false,
    )
}

pub fn build_interval_matched_distribution(
    grid: PreparedVerticalGrid<'_>,
    enabled: bool,
    total_optical_depth: f64,
    interval_index_1based: u32,
) -> Result<Vec<f64>, errors::Error> {
    let mut weights = vec![0.0; grid.sublayer_mid_altitudes_km.len()];
    if !enabled || total_optical_depth == 0.0 || interval_index_1based == 0 {
        return Ok(weights);
    }

    let mut total_weight = 0.0;
    for ((slot, parent_interval_index_1based), support_weight_km) in weights
        .iter_mut()
        .zip(grid.sublayer_parent_interval_indices_1based.iter())
        .zip(grid.sublayer_support_weights_km.iter())
    {
        if *parent_interval_index_1based != interval_index_1based {
            continue;
        }
        let weight = support_weight_km.max(0.0);
        *slot = weight;
        total_weight += weight;
    }

    if total_weight == 0.0 {
        return Err(errors::Error::InvalidRequest);
    }
    for slot in &mut weights {
        *slot = total_optical_depth * (*slot / total_weight);
    }
    Ok(weights)
}

pub fn build_finite_layer_sublayer_distribution(
    grid: PreparedVerticalGrid<'_>,
    enabled: bool,
    total_optical_depth: f64,
    bottom_altitude_km: f64,
    top_altitude_km: f64,
    pad_to_slot_height: bool,
) -> Result<Vec<f64>, errors::Error> {
    let mut weights = vec![0.0; grid.sublayer_mid_altitudes_km.len()];
    if !enabled || total_optical_depth == 0.0 {
        return Ok(weights);
    }

    let mut layer_bottom_km = bottom_altitude_km.max(0.0);
    let mut layer_top_km = top_altitude_km.max(layer_bottom_km);
    if pad_to_slot_height && !grid.sublayer_top_altitudes_km.is_empty() {
        let center_km = 0.5 * (layer_top_km + layer_bottom_km);
        let slot_height_km =
            (grid.sublayer_top_altitudes_km[0] - grid.sublayer_bottom_altitudes_km[0]).max(1.0e-9);
        let padded_half_thickness_km = 0.5 * (layer_top_km - layer_bottom_km).max(slot_height_km);
        let grid_top_km = grid.sublayer_top_altitudes_km[grid.sublayer_top_altitudes_km.len() - 1];
        layer_bottom_km = (center_km - padded_half_thickness_km).max(0.0);
        layer_top_km = (center_km + padded_half_thickness_km).min(grid_top_km);
    }

    let mut total_weight = 0.0;
    for (((slot, slot_top_km), slot_bottom_km), support_weight_km) in weights
        .iter_mut()
        .zip(grid.sublayer_top_altitudes_km.iter())
        .zip(grid.sublayer_bottom_altitudes_km.iter())
        .zip(grid.sublayer_support_weights_km.iter())
    {
        let slot_height_km = (slot_top_km - slot_bottom_km).max(1.0e-9);
        let overlap_km =
            (slot_top_km.min(layer_top_km) - slot_bottom_km.max(layer_bottom_km)).max(0.0);
        let weight = support_weight_km.max(0.0) * (overlap_km / slot_height_km);
        *slot = weight;
        total_weight += weight;
    }

    if total_weight == 0.0
        && let Some(index) = nearest_sublayer_index(
            grid.sublayer_mid_altitudes_km,
            0.5 * (layer_top_km + layer_bottom_km),
        )
    {
        weights[index] = 1.0;
        total_weight = 1.0;
    }

    if total_weight == 0.0 {
        return Ok(weights);
    }
    for slot in &mut weights {
        *slot = total_optical_depth * (*slot / total_weight);
    }
    Ok(weights)
}

pub fn build_gaussian_sublayer_distribution(
    grid: PreparedVerticalGrid<'_>,
    enabled: bool,
    total_optical_depth: f64,
    center_km: f64,
    width_km: f64,
) -> Vec<f64> {
    let mut weights = vec![0.0; grid.sublayer_mid_altitudes_km.len()];
    if !enabled || total_optical_depth == 0.0 {
        return weights;
    }

    let mut total_weight = 0.0;
    for ((slot, altitude_km), support_weight_km) in weights
        .iter_mut()
        .zip(grid.sublayer_mid_altitudes_km.iter())
        .zip(grid.sublayer_support_weights_km.iter())
    {
        let delta = (altitude_km - center_km) / width_km.max(0.25);
        let weight = (-0.5 * delta * delta).exp() * support_weight_km.max(0.0);
        *slot = weight;
        total_weight += weight;
    }
    if total_weight == 0.0 {
        total_weight = 1.0;
    }
    for slot in &mut weights {
        *slot = total_optical_depth * (*slot / total_weight);
    }
    weights
}

fn nearest_sublayer_index(altitudes_km: &[f64], target_altitude_km: f64) -> Option<usize> {
    let mut best_index = None;
    let mut best_distance = f64::INFINITY;
    for (index, altitude_km) in altitudes_km.iter().enumerate() {
        let distance = (altitude_km - target_altitude_km).abs();
        if distance < best_distance {
            best_distance = distance;
            best_index = Some(index);
        }
    }
    best_index
}

pub fn placement_supports_explicit_interval(placement: IntervalPlacement) -> bool {
    placement.semantics == ParticlePlacementSemantics::ExplicitIntervalBounds
        && placement.interval_index_1based != 0
}
