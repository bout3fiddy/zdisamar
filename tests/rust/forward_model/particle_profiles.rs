use zdisamar::{
    common::errors,
    forward_model::optical_properties::shared::particle_profiles::{
        PreparedVerticalGrid, build_finite_layer_sublayer_distribution,
        build_gaussian_sublayer_distribution, build_interval_matched_distribution,
        build_placement_bound_distribution, placement_supports_explicit_interval,
        scale_optical_depth,
    },
    input::atmosphere::{IntervalPlacement, ParticlePlacementSemantics},
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn grid() -> PreparedVerticalGrid<'static> {
    PreparedVerticalGrid {
        sublayer_top_altitudes_km: &[1.0, 2.0, 3.0],
        sublayer_bottom_altitudes_km: &[0.0, 1.0, 2.0],
        sublayer_mid_altitudes_km: &[0.5, 1.5, 2.5],
        sublayer_support_weights_km: &[1.0, 2.0, 1.0],
        sublayer_parent_interval_indices_1based: &[1, 2, 2],
        ..PreparedVerticalGrid::default()
    }
}

#[test]
fn optical_depth_scaling_uses_angstrom_power_law() {
    assert_close(scale_optical_depth(0.2, 760.0, 0.0, 750.0), 0.2, 0.0);
    assert_close(scale_optical_depth(0.0, 760.0, 1.5, 750.0), 0.0, 0.0);
    assert_close(scale_optical_depth(0.2, 760.0, 2.0, 380.0), 0.8, 1.0e-14);
}

#[test]
fn finite_layer_distribution_allocates_by_overlap_and_support_weight() {
    let weights =
        build_finite_layer_sublayer_distribution(grid(), true, 0.3, 0.5, 2.5, false).unwrap();

    assert_close(weights.iter().sum::<f64>(), 0.3, 1.0e-14);
    assert_close(weights[0], 0.05, 1.0e-14);
    assert_close(weights[1], 0.2, 1.0e-14);
    assert_close(weights[2], 0.05, 1.0e-14);
}

#[test]
fn interval_distribution_requires_matching_support() {
    let weights = build_interval_matched_distribution(grid(), true, 0.3, 2).unwrap();

    assert_close(weights.iter().sum::<f64>(), 0.3, 1.0e-14);
    assert_close(weights[0], 0.0, 0.0);
    assert_close(weights[1], 0.2, 1.0e-14);
    assert_close(weights[2], 0.1, 1.0e-14);
    assert_eq!(
        build_interval_matched_distribution(grid(), true, 0.3, 9),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn placement_bound_distribution_honors_explicit_interval_flag() {
    let placement = IntervalPlacement {
        semantics: ParticlePlacementSemantics::ExplicitIntervalBounds,
        interval_index_1based: 2,
        ..IntervalPlacement::default()
    };

    assert!(placement_supports_explicit_interval(placement));
    assert_eq!(
        build_placement_bound_distribution(grid(), false, true, 0.3, placement),
        Err(errors::Error::InvalidRequest)
    );
    assert_close(
        build_placement_bound_distribution(grid(), true, true, 0.3, placement)
            .unwrap()
            .iter()
            .sum::<f64>(),
        0.3,
        1.0e-14,
    );
}

#[test]
fn gaussian_distribution_normalizes_to_total_optical_depth() {
    let weights = build_gaussian_sublayer_distribution(grid(), true, 0.42, 1.5, 0.5);

    assert_close(weights.iter().sum::<f64>(), 0.42, 1.0e-14);
    assert!(weights[1] > weights[0]);
    assert!(weights[1] > weights[2]);
}
