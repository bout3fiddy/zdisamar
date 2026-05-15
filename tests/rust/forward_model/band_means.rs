use zdisamar::{
    forward_model::optical_properties::shared::band_means::{
        LineBandMeans, compute_operational_band_mean, compute_weighted_operational_band_mean,
        compute_weighted_window_mean,
    },
    input::{
        instrument::{
            OperationalBandSupport, OperationalCrossSectionLut, OperationalReferenceGrid,
        },
        scene::Scene,
        spectrum::SpectralGrid,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn linear_lut() -> OperationalCrossSectionLut {
    OperationalCrossSectionLut {
        wavelengths_nm: vec![760.0, 762.0],
        coefficients: vec![2.0, 6.0],
        temperature_coefficient_count: 1,
        pressure_coefficient_count: 1,
        min_temperature_k: 180.0,
        max_temperature_k: 320.0,
        min_pressure_hpa: 200.0,
        max_pressure_hpa: 1000.0,
    }
}

#[test]
fn weighted_window_mean_matches_zig_denominator_guard() {
    assert_close(
        compute_weighted_window_mean(&[2.0, 6.0], &[1.0, 3.0]),
        5.0,
        1.0e-14,
    );
    assert_close(compute_weighted_window_mean(&[], &[]), 0.0, 0.0);
    assert_close(compute_weighted_window_mean(&[1.0], &[]), 0.0, 0.0);
    assert_close(compute_weighted_window_mean(&[1.0], &[0.0]), 0.0, 0.0);
}

#[test]
fn operational_band_mean_uses_scene_grid_when_no_weighted_grid_is_enabled() {
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 762.0,
            sample_count: 3,
        },
        ..Scene::default()
    };

    assert_close(
        compute_operational_band_mean(&scene, &linear_lut(), 250.0, 500.0),
        4.0,
        1.0e-14,
    );
}

#[test]
fn operational_band_mean_prefers_weighted_operational_refspec_grid() {
    let refspec_grid = OperationalReferenceGrid {
        wavelengths_nm: vec![760.0, 762.0],
        weights: vec![1.0, 3.0],
    };
    let scene = Scene {
        observation_model: zdisamar::input::observation_model::ObservationModel {
            operational_band_support: vec![OperationalBandSupport {
                id: "o2-a".to_string(),
                operational_refspec_grid: refspec_grid.clone(),
                ..OperationalBandSupport::default()
            }],
            ..zdisamar::input::observation_model::ObservationModel::default()
        },
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 762.0,
            sample_count: 3,
        },
        ..Scene::default()
    };

    assert_close(
        compute_weighted_operational_band_mean(&refspec_grid, &linear_lut(), 250.0, 500.0),
        5.0,
        1.0e-14,
    );
    assert_close(
        compute_operational_band_mean(&scene, &linear_lut(), 250.0, 500.0),
        5.0,
        1.0e-14,
    );
}

#[test]
fn line_band_means_default_matches_zig_zero_state() {
    assert_eq!(
        LineBandMeans::default(),
        LineBandMeans {
            line_mean_cross_section_cm2_per_molecule: 0.0,
            line_mixing_mean_cross_section_cm2_per_molecule: 0.0,
        }
    );
}
