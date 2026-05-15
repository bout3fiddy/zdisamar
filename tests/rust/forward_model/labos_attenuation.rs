use zdisamar::forward_model::radiative_transfer::{
    common_types::{LayerInput, PseudoSphericalGrid, PseudoSphericalSample},
    labos::{
        Geometry, fill_attenuation, fill_attenuation_dynamic, fill_attenuation_dynamic_with_grid,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn fixed_and_dynamic_attenuation_match_plane_parallel_layers() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.3,
            ..LayerInput::default()
        },
    ];

    let fixed = fill_attenuation(&layers, &geometry, false);
    let dynamic = fill_attenuation_dynamic(&layers, &geometry, false);
    let imu = 0;
    let expected = (-(0.2 + 0.3) / geometry.u[imu].max(1.0e-6)).exp();

    assert_eq!(fixed.nlayer, 2);
    assert_eq!(dynamic.nlevel, 3);
    assert_close(fixed.get(imu, 0, 2), expected, 1.0e-12);
    assert_close(fixed.get(imu, 2, 0), expected, 1.0e-12);
    assert_close(dynamic.get(imu, 0, 2), expected, 1.0e-12);
    assert_close(dynamic.get(imu, 2, 0), expected, 1.0e-12);
}

#[test]
fn spherical_correction_uses_layer_specific_view_and_solar_cosines_at_top_level() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![
        LayerInput {
            optical_depth: 0.2,
            view_mu: 0.7,
            solar_mu: 0.6,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.3,
            view_mu: 0.8,
            solar_mu: 0.5,
            ..LayerInput::default()
        },
    ];

    let attenuation = fill_attenuation(&layers, &geometry, true);
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let expected_view = (-0.3_f64 / 0.8).exp() * (-0.2_f64 / 0.7).exp();
    let expected_solar = (-0.3_f64 / 0.5).exp() * (-0.2_f64 / 0.6).exp();

    assert_close(attenuation.get(view_idx, 2, 0), expected_view, 1.0e-12);
    assert_close(attenuation.get(solar_idx, 2, 0), expected_solar, 1.0e-12);
}

#[test]
fn pseudo_spherical_grid_overrides_top_level_dynamic_attenuation() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.3,
            ..LayerInput::default()
        },
    ];
    let grid = PseudoSphericalGrid {
        samples: vec![
            PseudoSphericalSample {
                altitude_km: 1.0,
                thickness_km: 0.5,
                optical_depth: 0.1,
            },
            PseudoSphericalSample {
                altitude_km: 2.0,
                thickness_km: 0.5,
                optical_depth: 0.2,
            },
        ],
        level_sample_starts: vec![0, 1, 2],
        level_altitudes_km: vec![0.0, 1.0, 2.0],
    };

    let plane = fill_attenuation_dynamic(&layers, &geometry, true);
    let curved = fill_attenuation_dynamic_with_grid(&layers, &grid, &geometry, true);

    assert_ne!(plane.get(0, 2, 0), curved.get(0, 2, 0));
    assert_close(curved.get(0, 2, 2), 1.0, 0.0);
}
