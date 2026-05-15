use crate::{
    common::{errors, math::quadrature::gauss_legendre},
    forward_model::optical_properties::shared::particle_profiles,
    input::{
        atmosphere::PartitionLabel,
        instrument::{IntegrationMode, SpectralChannel},
        reference_data::ClimatologyProfile,
        scene::Scene,
    },
};

#[derive(Debug, Default, Clone, PartialEq)]
pub struct OwnedVerticalGrid {
    pub layer_top_altitudes_km: Vec<f64>,
    pub layer_bottom_altitudes_km: Vec<f64>,
    pub layer_top_pressures_hpa: Vec<f64>,
    pub layer_bottom_pressures_hpa: Vec<f64>,
    pub layer_interval_indices_1based: Vec<u32>,
    pub layer_sublayer_starts: Vec<u32>,
    pub layer_sublayer_counts: Vec<u32>,
    pub layer_subcolumn_labels: Vec<PartitionLabel>,
    pub sublayer_top_altitudes_km: Vec<f64>,
    pub sublayer_bottom_altitudes_km: Vec<f64>,
    pub sublayer_top_pressures_hpa: Vec<f64>,
    pub sublayer_bottom_pressures_hpa: Vec<f64>,
    pub sublayer_mid_altitudes_km: Vec<f64>,
    pub sublayer_support_weights_km: Vec<f64>,
    pub sublayer_interval_indices_1based: Vec<u32>,
    pub sublayer_subcolumn_labels: Vec<PartitionLabel>,
}

impl OwnedVerticalGrid {
    pub fn borrow(&self) -> particle_profiles::PreparedVerticalGrid<'_> {
        particle_profiles::PreparedVerticalGrid {
            layer_top_altitudes_km: &self.layer_top_altitudes_km,
            layer_bottom_altitudes_km: &self.layer_bottom_altitudes_km,
            layer_interval_indices_1based: &self.layer_interval_indices_1based,
            sublayer_top_altitudes_km: &self.sublayer_top_altitudes_km,
            sublayer_bottom_altitudes_km: &self.sublayer_bottom_altitudes_km,
            sublayer_mid_altitudes_km: &self.sublayer_mid_altitudes_km,
            sublayer_support_weights_km: &self.sublayer_support_weights_km,
            sublayer_parent_interval_indices_1based: &self.sublayer_interval_indices_1based,
        }
    }
}

pub fn build(
    scene: &Scene,
    profile: &ClimatologyProfile,
) -> Result<OwnedVerticalGrid, errors::Error> {
    if scene.atmosphere.interval_grid.enabled() {
        return build_explicit(scene, profile);
    }
    Ok(build_legacy(scene, profile))
}

fn build_explicit(
    scene: &Scene,
    profile: &ClimatologyProfile,
) -> Result<OwnedVerticalGrid, errors::Error> {
    let intervals = &scene.atmosphere.interval_grid.intervals;
    let disamar_support_grid = uses_disamar_parity_support_grid(scene);
    let sublayer_order = usize::from(scene.atmosphere.sublayer_divisions).max(1);

    let mut layer_count = intervals.len();
    let mut total_sublayer_count = 0usize;
    if disamar_support_grid {
        layer_count = 0;
        total_sublayer_count = 1;
        for interval in intervals {
            let interval_layer_count = interval.altitude_divisions as usize + 1;
            layer_count += interval_layer_count;
            total_sublayer_count += interval_layer_count * (sublayer_order + 1);
        }
    } else {
        for interval in intervals {
            total_sublayer_count += interval.altitude_divisions as usize;
        }
    }

    let mut grid = allocate(layer_count, total_sublayer_count);
    if disamar_support_grid {
        return build_explicit_disamar_parity(scene, profile, grid, sublayer_order);
    }

    let mut sublayer_cursor = 0usize;
    for (output_layer_index, interval) in intervals.iter().rev().enumerate() {
        let has_altitude_bounds = interval.has_altitude_bounds();
        let layer_top_altitude_km = if has_altitude_bounds {
            interval.top_altitude_km
        } else {
            profile.interpolate_altitude_for_pressure(interval.top_pressure_hpa)
        };
        let layer_bottom_altitude_km = if has_altitude_bounds {
            interval.bottom_altitude_km
        } else {
            profile.interpolate_altitude_for_pressure(interval.bottom_pressure_hpa)
        };

        grid.layer_top_altitudes_km[output_layer_index] = layer_top_altitude_km;
        grid.layer_bottom_altitudes_km[output_layer_index] = layer_bottom_altitude_km;
        grid.layer_top_pressures_hpa[output_layer_index] = interval.top_pressure_hpa;
        grid.layer_bottom_pressures_hpa[output_layer_index] = interval.bottom_pressure_hpa;
        grid.layer_interval_indices_1based[output_layer_index] = interval.index_1based;
        grid.layer_sublayer_starts[output_layer_index] = sublayer_cursor as u32;
        grid.layer_sublayer_counts[output_layer_index] = interval.altitude_divisions;
        grid.layer_subcolumn_labels[output_layer_index] = scene
            .atmosphere
            .subcolumns
            .label_for_altitude(0.5 * (layer_top_altitude_km + layer_bottom_altitude_km));

        let log_bottom_pressure = interval.bottom_pressure_hpa.max(1.0e-9).ln();
        let log_top_pressure = interval.top_pressure_hpa.max(1.0e-9).ln();
        let layer_altitude_span_km = layer_top_altitude_km - layer_bottom_altitude_km;
        for sublayer_index in 0..interval.altitude_divisions as usize {
            let bottom_fraction = sublayer_index as f64 / interval.altitude_divisions as f64;
            let top_fraction = (sublayer_index + 1) as f64 / interval.altitude_divisions as f64;
            let bottom_pressure_hpa = (log_bottom_pressure
                + (log_top_pressure - log_bottom_pressure) * bottom_fraction)
                .exp();
            let top_pressure_hpa = (log_bottom_pressure
                + (log_top_pressure - log_bottom_pressure) * top_fraction)
                .exp();
            let bottom_altitude_km = if has_altitude_bounds {
                layer_bottom_altitude_km + layer_altitude_span_km * bottom_fraction
            } else {
                profile.interpolate_altitude_for_pressure(bottom_pressure_hpa)
            };
            let top_altitude_km = if has_altitude_bounds {
                layer_bottom_altitude_km + layer_altitude_span_km * top_fraction
            } else {
                profile.interpolate_altitude_for_pressure(top_pressure_hpa)
            };
            let global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = top_altitude_km;
            grid.sublayer_bottom_altitudes_km[global_index] = bottom_altitude_km;
            grid.sublayer_top_pressures_hpa[global_index] = top_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[global_index] = bottom_pressure_hpa;
            grid.sublayer_mid_altitudes_km[global_index] =
                0.5 * (top_altitude_km + bottom_altitude_km);
            grid.sublayer_support_weights_km[global_index] =
                (top_altitude_km - bottom_altitude_km).max(0.0);
            grid.sublayer_interval_indices_1based[global_index] = interval.index_1based;
            grid.sublayer_subcolumn_labels[global_index] = scene
                .atmosphere
                .subcolumns
                .label_for_altitude(grid.sublayer_mid_altitudes_km[global_index]);
        }
        sublayer_cursor += interval.altitude_divisions as usize;
    }
    Ok(grid)
}

fn build_explicit_disamar_parity(
    scene: &Scene,
    profile: &ClimatologyProfile,
    mut grid: OwnedVerticalGrid,
    sublayer_order: usize,
) -> Result<OwnedVerticalGrid, errors::Error> {
    let intervals = &scene.atmosphere.interval_grid.intervals;
    let mut support_nodes = vec![0.0; sublayer_order];
    let mut support_weights = vec![0.0; sublayer_order];
    gauss_legendre::fill_nodes_and_weights(
        sublayer_order as u32,
        &mut support_nodes,
        &mut support_weights,
    )
    .map_err(|_| errors::Error::InvalidRequest)?;

    let mut layer_cursor = 0usize;
    let mut support_cursor = 0usize;
    for (source_interval_index, interval) in intervals.iter().enumerate().rev() {
        let parity_interval_index_1based = (intervals.len() - source_interval_index) as u32;
        let has_altitude_bounds = interval.has_altitude_bounds();
        let interval_top_altitude_km = if has_altitude_bounds {
            interval.top_altitude_km
        } else {
            profile.interpolate_altitude_for_pressure_spline(interval.top_pressure_hpa)
        };
        let interval_bottom_altitude_km = if has_altitude_bounds {
            interval.bottom_altitude_km
        } else {
            profile.interpolate_altitude_for_pressure_spline(interval.bottom_pressure_hpa)
        };
        let interval_layer_count = interval.altitude_divisions as usize + 1;
        let interior_node_count = interval_layer_count - 1;

        let mut rtm_nodes = vec![0.0; interior_node_count];
        let mut rtm_weights = vec![0.0; interior_node_count];
        if interior_node_count > 0 {
            gauss_legendre::fill_disamar_div_points_interval(
                interior_node_count as u32,
                interval_bottom_altitude_km,
                interval_top_altitude_km,
                &mut rtm_nodes,
                &mut rtm_weights,
            )
            .map_err(|_| errors::Error::InvalidRequest)?;
        }

        if layer_cursor == 0 {
            grid.sublayer_top_altitudes_km[support_cursor] = interval_bottom_altitude_km;
            grid.sublayer_bottom_altitudes_km[support_cursor] = interval_bottom_altitude_km;
            grid.sublayer_top_pressures_hpa[support_cursor] = interval.bottom_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[support_cursor] = interval.bottom_pressure_hpa;
            grid.sublayer_mid_altitudes_km[support_cursor] = interval_bottom_altitude_km;
            grid.sublayer_support_weights_km[support_cursor] = 0.0;
        }

        // DISAMAR's diagnostic grid treats the shared boundary row as belonging
        // to the interval being materialized, so the boundary label is updated.
        grid.sublayer_interval_indices_1based[support_cursor] = parity_interval_index_1based;
        grid.sublayer_subcolumn_labels[support_cursor] = scene
            .atmosphere
            .subcolumns
            .label_for_altitude(interval_bottom_altitude_km);

        let mut boundary_altitudes_km = rtm_nodes;
        boundary_altitudes_km.push(interval_top_altitude_km);
        let mut previous_boundary_altitude_km = interval_bottom_altitude_km;
        let mut previous_boundary_pressure_hpa = interval.bottom_pressure_hpa;
        for (local_layer_index, &next_boundary_altitude_km) in
            boundary_altitudes_km.iter().enumerate()
        {
            let next_boundary_pressure_hpa = if local_layer_index == interior_node_count {
                interval.top_pressure_hpa
            } else {
                profile.interpolate_pressure_log_spline(next_boundary_altitude_km)
            };

            let global_layer_index = layer_cursor + local_layer_index;
            grid.layer_top_altitudes_km[global_layer_index] = next_boundary_altitude_km;
            grid.layer_bottom_altitudes_km[global_layer_index] = previous_boundary_altitude_km;
            grid.layer_top_pressures_hpa[global_layer_index] = next_boundary_pressure_hpa;
            grid.layer_bottom_pressures_hpa[global_layer_index] = previous_boundary_pressure_hpa;
            grid.layer_interval_indices_1based[global_layer_index] = parity_interval_index_1based;
            grid.layer_sublayer_starts[global_layer_index] = support_cursor as u32;
            grid.layer_sublayer_counts[global_layer_index] = (sublayer_order + 2) as u32;
            grid.layer_subcolumn_labels[global_layer_index] =
                scene.atmosphere.subcolumns.label_for_altitude(
                    0.5 * (previous_boundary_altitude_km + next_boundary_altitude_km),
                );

            let layer_span_km =
                (next_boundary_altitude_km - previous_boundary_altitude_km).max(0.0);
            for support_index in 0..sublayer_order {
                let global_support_index = support_cursor + 1 + support_index;
                let support_altitude_km = previous_boundary_altitude_km
                    + 0.5 * (support_nodes[support_index] + 1.0) * layer_span_km;
                grid.sublayer_top_altitudes_km[global_support_index] = next_boundary_altitude_km;
                grid.sublayer_bottom_altitudes_km[global_support_index] =
                    previous_boundary_altitude_km;
                grid.sublayer_top_pressures_hpa[global_support_index] = next_boundary_pressure_hpa;
                grid.sublayer_bottom_pressures_hpa[global_support_index] =
                    previous_boundary_pressure_hpa;
                grid.sublayer_mid_altitudes_km[global_support_index] = support_altitude_km;
                grid.sublayer_support_weights_km[global_support_index] =
                    0.5 * support_weights[support_index] * layer_span_km;
                grid.sublayer_interval_indices_1based[global_support_index] =
                    parity_interval_index_1based;
                grid.sublayer_subcolumn_labels[global_support_index] = scene
                    .atmosphere
                    .subcolumns
                    .label_for_altitude(support_altitude_km);
            }

            let upper_boundary_index = support_cursor + sublayer_order + 1;
            grid.sublayer_top_altitudes_km[upper_boundary_index] = next_boundary_altitude_km;
            grid.sublayer_bottom_altitudes_km[upper_boundary_index] = next_boundary_altitude_km;
            grid.sublayer_top_pressures_hpa[upper_boundary_index] = next_boundary_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[upper_boundary_index] = next_boundary_pressure_hpa;
            grid.sublayer_mid_altitudes_km[upper_boundary_index] = next_boundary_altitude_km;
            grid.sublayer_support_weights_km[upper_boundary_index] = 0.0;
            grid.sublayer_interval_indices_1based[upper_boundary_index] =
                parity_interval_index_1based;
            grid.sublayer_subcolumn_labels[upper_boundary_index] = scene
                .atmosphere
                .subcolumns
                .label_for_altitude(next_boundary_altitude_km);

            support_cursor = upper_boundary_index;
            previous_boundary_altitude_km = next_boundary_altitude_km;
            previous_boundary_pressure_hpa = next_boundary_pressure_hpa;
        }

        layer_cursor += interval_layer_count;
    }

    debug_assert_eq!(layer_cursor, grid.layer_top_altitudes_km.len());
    debug_assert_eq!(support_cursor + 1, grid.sublayer_mid_altitudes_km.len());
    Ok(grid)
}

fn build_legacy(scene: &Scene, profile: &ClimatologyProfile) -> OwnedVerticalGrid {
    let layer_count = scene.atmosphere.prepared_layer_count().max(1) as usize;
    let sublayer_divisions = scene.atmosphere.sublayer_divisions.max(1) as usize;
    let total_sublayer_count = layer_count * sublayer_divisions;
    let mut grid = allocate(layer_count, total_sublayer_count);

    let bottom_altitude_km = scene.geometry.surface_altitude_km;
    let top_altitude_km = profile.max_altitude().max(bottom_altitude_km + 1.0);
    let layer_span_km = (top_altitude_km - bottom_altitude_km) / layer_count as f64;

    let mut sublayer_cursor = 0usize;
    for index in 0..layer_count {
        let layer_top_altitude = bottom_altitude_km + layer_span_km * (index + 1) as f64;
        let layer_bottom_altitude = bottom_altitude_km + layer_span_km * index as f64;
        grid.layer_top_altitudes_km[index] = layer_top_altitude;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude;
        grid.layer_top_pressures_hpa[index] = profile.interpolate_pressure(layer_top_altitude);
        grid.layer_bottom_pressures_hpa[index] =
            profile.interpolate_pressure(layer_bottom_altitude);
        grid.layer_interval_indices_1based[index] = (index + 1) as u32;
        grid.layer_sublayer_starts[index] = sublayer_cursor as u32;
        grid.layer_sublayer_counts[index] = sublayer_divisions as u32;
        grid.layer_subcolumn_labels[index] = scene
            .atmosphere
            .subcolumns
            .label_for_altitude(0.5 * (layer_top_altitude + layer_bottom_altitude));

        for sublayer_index in 0..sublayer_divisions {
            let top_fraction = (sublayer_index + 1) as f64 / sublayer_divisions as f64;
            let bottom_fraction = sublayer_index as f64 / sublayer_divisions as f64;
            let sublayer_top_altitude = layer_bottom_altitude + layer_span_km * top_fraction;
            let sublayer_bottom_altitude = layer_bottom_altitude + layer_span_km * bottom_fraction;
            let global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = sublayer_top_altitude;
            grid.sublayer_bottom_altitudes_km[global_index] = sublayer_bottom_altitude;
            grid.sublayer_top_pressures_hpa[global_index] =
                profile.interpolate_pressure(sublayer_top_altitude);
            grid.sublayer_bottom_pressures_hpa[global_index] =
                profile.interpolate_pressure(sublayer_bottom_altitude);
            grid.sublayer_mid_altitudes_km[global_index] =
                0.5 * (sublayer_top_altitude + sublayer_bottom_altitude);
            grid.sublayer_support_weights_km[global_index] =
                (sublayer_top_altitude - sublayer_bottom_altitude).max(0.0);
            grid.sublayer_interval_indices_1based[global_index] = (index + 1) as u32;
            grid.sublayer_subcolumn_labels[global_index] = scene
                .atmosphere
                .subcolumns
                .label_for_altitude(grid.sublayer_mid_altitudes_km[global_index]);
        }
        sublayer_cursor += sublayer_divisions;
    }
    grid
}

fn allocate(layer_count: usize, total_sublayer_count: usize) -> OwnedVerticalGrid {
    OwnedVerticalGrid {
        layer_top_altitudes_km: vec![0.0; layer_count],
        layer_bottom_altitudes_km: vec![0.0; layer_count],
        layer_top_pressures_hpa: vec![0.0; layer_count],
        layer_bottom_pressures_hpa: vec![0.0; layer_count],
        layer_interval_indices_1based: vec![0; layer_count],
        layer_sublayer_starts: vec![0; layer_count],
        layer_sublayer_counts: vec![0; layer_count],
        layer_subcolumn_labels: vec![PartitionLabel::Unspecified; layer_count],
        sublayer_top_altitudes_km: vec![0.0; total_sublayer_count],
        sublayer_bottom_altitudes_km: vec![0.0; total_sublayer_count],
        sublayer_top_pressures_hpa: vec![0.0; total_sublayer_count],
        sublayer_bottom_pressures_hpa: vec![0.0; total_sublayer_count],
        sublayer_mid_altitudes_km: vec![0.0; total_sublayer_count],
        sublayer_support_weights_km: vec![0.0; total_sublayer_count],
        sublayer_interval_indices_1based: vec![0; total_sublayer_count],
        sublayer_subcolumn_labels: vec![PartitionLabel::Unspecified; total_sublayer_count],
    }
}

fn uses_disamar_parity_support_grid(scene: &Scene) -> bool {
    scene
        .observation_model
        .resolved_channel_controls(SpectralChannel::Radiance)
        .response
        .integration_mode
        == IntegrationMode::DisamarHrGrid
        || scene
            .observation_model
            .resolved_channel_controls(SpectralChannel::Irradiance)
            .response
            .integration_mode
            == IntegrationMode::DisamarHrGrid
}
