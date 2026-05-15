use zdisamar::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_types::LayerInput,
        labos::{
            FourierPlmBasis, Geometry, MAX_PHASE_COEF, Mat, PhaseKernel, calc_rt_layers,
            calc_rt_layers_into_with_basis, calc_rt_layers_tangent_into_with_basis,
            fill_layer_effective_scattering_suffixes, fill_layer_phase_max_indices, fill_surface,
            fill_zplus_zmin_from_basis, renormalize_zero_fourier_phase_kernel,
            zero_fourier_integral,
        },
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn phase_coefficients(entries: &[(usize, f64)]) -> PhaseCoefficients {
    let mut coefficients = phase_functions::zero_phase_coefficients();
    for &(index, value) in entries {
        coefficients[index] = value;
    }
    coefficients
}

#[test]
fn zero_fourier_surface_is_weight_outer_product() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let surface = fill_surface(0, 0.21, &geometry);

    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            assert_close(
                surface.r.get(i, j),
                geometry.w[i] * 0.21 * geometry.w[j],
                1.0e-12,
            );
            assert_close(surface.t.get(i, j), 0.0, 0.0);
        }
    }

    let nonzero_fourier_surface = fill_surface(1, 0.21, &geometry);
    for value in nonzero_fourier_surface
        .r
        .data
        .iter()
        .take(geometry.nmutot * geometry.nmutot)
    {
        assert_close(*value, 0.0, 0.0);
    }
}

#[test]
fn layer_phase_max_and_effective_scattering_suffixes_match_phase_support() {
    let layers = vec![
        LayerInput {
            phase_coefficients: phase_coefficients(&[(1, 0.5), (3, 0.25)]),
            ..LayerInput::default()
        },
        LayerInput {
            phase_coefficients: phase_coefficients(&[(2, -0.3)]),
            ..LayerInput::default()
        },
    ];
    let mut max_indices = vec![0; layers.len()];
    fill_layer_phase_max_indices(&mut max_indices, &layers);
    assert_eq!(max_indices, [3, 2]);

    let mut suffixes = vec![0.0; layers.len() * MAX_PHASE_COEF];
    fill_layer_effective_scattering_suffixes(&mut suffixes, &layers, &max_indices);
    let first = &suffixes[..MAX_PHASE_COEF];
    assert_close(first[3], 0.25 / 7.0, 1.0e-12);
    assert_close(first[2], 0.25 / 7.0, 1.0e-12);
    assert_close(first[1], 0.5 / 3.0, 1.0e-12);
    assert_close(first[0], 1.0, 1.0e-12);
}

#[test]
fn zero_fourier_integral_reads_unweighted_phase_column() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let phase = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let kernel = fill_zplus_zmin_from_basis(0, phase, &geometry, &basis);

    assert_close(
        zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, 0),
        2.0,
        1.0e-12,
    );
}

#[test]
fn zero_fourier_renormalization_restores_column_integrals() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let phase = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let mut kernel = fill_zplus_zmin_from_basis(0, phase, &geometry, &basis);

    for value in kernel
        .zplus
        .data
        .iter_mut()
        .take(geometry.nmutot * geometry.nmutot)
    {
        *value *= 0.8;
    }
    renormalize_zero_fourier_phase_kernel(&geometry, &mut kernel.zplus, &mut kernel.zmin);

    for column in 0..geometry.nmutot {
        assert_close(
            zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, column),
            2.0,
            1.0e-10,
        );
    }
}

#[test]
fn rt_layer_builder_skips_fourier_orders_without_phase_support() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![LayerInput {
        optical_depth: 0.2,
        scattering_optical_depth: 0.1,
        single_scatter_albedo: 0.7,
        phase_coefficients: phase_coefficients(&[(1, 0.2)]),
        ..LayerInput::default()
    }];

    let rt = calc_rt_layers(&layers, 2, &geometry, Default::default());
    for value in rt[1].r.data.iter().take(geometry.nmutot * geometry.nmutot) {
        assert_close(*value, 0.0, 0.0);
    }
}

#[test]
fn rt_layer_builder_populates_phase_cache_and_active_mask() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![LayerInput {
        optical_depth: 0.2,
        scattering_optical_depth: 0.1,
        single_scatter_albedo: 0.7,
        phase_coefficients: phase_coefficients(&[(1, 0.2), (2, 0.05)]),
        ..LayerInput::default()
    }];
    let mut rt = vec![
        fill_surface(0, 0.0, &geometry),
        fill_surface(0, 0.0, &geometry),
    ];
    let mut max_indices = vec![0; layers.len()];
    fill_layer_phase_max_indices(&mut max_indices, &layers);
    let mut suffixes = vec![0.0; layers.len() * MAX_PHASE_COEF];
    fill_layer_effective_scattering_suffixes(&mut suffixes, &layers, &max_indices);
    let basis = FourierPlmBasis::init(0, max_indices[0], &geometry);
    let mut phase_cache = vec![
        PhaseKernel {
            zplus: Mat::zero(geometry.nmutot),
            zmin: Mat::zero(geometry.nmutot),
        };
        2
    ];
    let mut phase_valid = vec![true; 2];
    let mut active = vec![true; 2];

    calc_rt_layers_into_with_basis(
        &mut rt,
        &layers,
        0,
        &geometry,
        Default::default(),
        &basis,
        Some(&max_indices),
        Some(&suffixes),
        Some(&mut phase_cache),
        Some(&mut phase_valid),
        Some(&mut active),
    );

    assert!(!active[0]);
    assert!(active[1]);
    assert!(!phase_valid[0]);
    assert!(phase_valid[1]);
    assert!(
        rt[1].r.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .any(|value| *value != 0.0)
    );
}

#[test]
fn rt_layer_tangent_matches_local_finite_difference() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let mut layer = LayerInput {
        optical_depth: 0.2,
        scattering_optical_depth: 0.12,
        single_scatter_albedo: 0.7,
        phase_coefficients: phase_coefficients(&[(1, 0.2), (2, 0.05)]),
        ..LayerInput::default()
    };
    jacobian::set(
        &mut layer.optical_depth_jacobian,
        State::AerosolLayerMidPressureHpa,
        0.003,
    );
    jacobian::set(
        &mut layer.scattering_optical_depth_jacobian,
        State::AerosolLayerMidPressureHpa,
        0.002,
    );
    jacobian::set(
        &mut layer.single_scatter_albedo_jacobian,
        State::AerosolLayerMidPressureHpa,
        -0.001,
    );
    let layers = vec![layer.clone()];
    let basis = FourierPlmBasis::init(0, 2, &geometry);
    let mut tangent_rt = vec![fill_surface(0, 0.0, &geometry); 2];

    calc_rt_layers_tangent_into_with_basis(
        &mut tangent_rt,
        &layers,
        State::AerosolLayerMidPressureHpa,
        0,
        &geometry,
        Default::default(),
        &basis,
    );

    let eps = 1.0e-5;
    let mut plus_layer = layer.clone();
    plus_layer.optical_depth += eps
        * jacobian::get(
            layer.optical_depth_jacobian,
            State::AerosolLayerMidPressureHpa,
        );
    plus_layer.scattering_optical_depth += eps
        * jacobian::get(
            layer.scattering_optical_depth_jacobian,
            State::AerosolLayerMidPressureHpa,
        );
    plus_layer.single_scatter_albedo += eps
        * jacobian::get(
            layer.single_scatter_albedo_jacobian,
            State::AerosolLayerMidPressureHpa,
        );
    let mut minus_layer = layer.clone();
    minus_layer.optical_depth -= eps
        * jacobian::get(
            layer.optical_depth_jacobian,
            State::AerosolLayerMidPressureHpa,
        );
    minus_layer.scattering_optical_depth -= eps
        * jacobian::get(
            layer.scattering_optical_depth_jacobian,
            State::AerosolLayerMidPressureHpa,
        );
    minus_layer.single_scatter_albedo -= eps
        * jacobian::get(
            layer.single_scatter_albedo_jacobian,
            State::AerosolLayerMidPressureHpa,
        );

    let plus_rt = calc_rt_layers(&[plus_layer], 0, &geometry, Default::default());
    let minus_rt = calc_rt_layers(&[minus_layer], 0, &geometry, Default::default());
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let finite_difference = (plus_rt[1].r.get(view_idx, solar_idx)
        - minus_rt[1].r.get(view_idx, solar_idx))
        / (2.0 * eps);

    assert_close(
        tangent_rt[1].r.get(view_idx, solar_idx),
        finite_difference,
        1.0e-10,
    );
}
