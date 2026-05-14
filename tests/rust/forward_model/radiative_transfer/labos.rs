use zdisamar::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions,
    radiative_transfer::{
        ForwardInput, LayerInput, PseudoSphericalGrid, PseudoSphericalSample,
        RadiativeTransferControls, RadiativeTransferPerformanceThresholds, RtmQuadratureGrid,
        ScatteringMode, SourceInterfaceInput,
        labos::{
            DynamicAttenArray, FourierPlmBasis, Geometry, LayerRt, MAX_EXTRA, MAX_GAUSS, MAX_N2,
            MAX_NMUTOT, MAX_PHASE_COEF, Mat, OrdersWorkspace, PhaseKernel, Vec as LabosVec, Vec2,
            accumulate_order_contribution, attenuation, calc_integrated_reflectance,
            calc_integrated_reflectance_with_basis, calc_reflectance, calc_reflectance_tangent,
            calc_rt_layers, calc_rt_layers_into_with_basis, dot_gauss, dot_gauss_pair,
            fill_adjacent_layer_phase_max_indices, fill_layer_effective_scattering_suffixes,
            fill_layer_phase_max_indices, fill_surface, fill_zplus_zmin,
            fill_zplus_zmin_from_basis_limited, fill_zplus_zmin_row_from_basis_limited, matrix,
            max_outgoing_upward, orders_scat, orders_scat_into_with_active_local_sum,
            orders_scat_tangent, refresh_active_layer_mask, renormalize_zero_fourier_phase_kernel,
            resolved_fourier_max, resolved_phase_coefficient_max, total_scattering_optical_depth,
            transport_to_other_levels, transport_to_other_levels_tangent, zero_fourier_integral,
            zero_ud_field, zero_ud_local,
        },
    },
};

fn assert_close(left: f64, right: f64) {
    assert!((left - right).abs() <= 1.0e-12, "{left} != {right}");
}

#[test]
fn labos_fixed_size_types_match_zig_layout_limits() {
    assert_eq!(MAX_GAUSS, 10);
    assert_eq!(MAX_EXTRA, 2);
    assert_eq!(MAX_NMUTOT, 12);
    assert_eq!(MAX_N2, 144);

    let mut mat = Mat::identity(4);
    assert_eq!(mat.get(2, 2), 1.0);
    assert_eq!(mat.get(2, 1), 0.0);
    mat.set(2, 1, 3.5);
    assert_eq!(mat.get(2, 1), 3.5);

    let mut vector = LabosVec::zero(4);
    vector.set(3, 1.25);
    assert_eq!(vector.get(3), 1.25);

    let two = Vec2::zero(4);
    assert_eq!(two.n, 4);
    assert_eq!(two.col[0].n, 4);
    assert_eq!(two.col[1].get(0), 0.0);
}

#[test]
fn labos_matrix_products_use_only_active_gauss_columns() {
    let n = 3;
    let mut a = Mat::identity(n);
    let mut b = Mat::zero(n);
    for i in 0..n {
        for j in 0..n {
            b.set(i, j, 10.0 * i as f64 + j as f64 + 1.0);
        }
    }

    let product = matrix::smul(n, 2, 0.0, &a, &b);
    assert_close(product.get(0, 0), 1.0);
    assert_close(product.get(1, 2), 13.0);
    assert_close(product.get(2, 0), 0.0);

    a.set(0, 0, 0.0);
    a.set(1, 1, 0.0);
    let zeroed = matrix::smul(n, 2, 1.0e-12, &a, &b);
    assert_eq!(zeroed.data[..n * n], [0.0; 9]);
}

#[test]
fn labos_matrix_scale_and_add_helpers_match_column_and_row_rules() {
    let n = 3;
    let mut e = LabosVec::zero(n);
    e.set(0, 2.0);
    e.set(1, 3.0);
    e.set(2, 4.0);

    let mut a = Mat::zero(n);
    let mut b = Mat::zero(n);
    for i in 0..n {
        for j in 0..n {
            a.set(i, j, 1.0 + i as f64 + j as f64);
            b.set(i, j, 10.0 + i as f64 + j as f64);
        }
    }

    assert_close(matrix::esmul(n, &e, &a).get(2, 1), e.get(2) * a.get(2, 1));
    assert_close(matrix::semul(n, &a, &e).get(2, 1), a.get(2, 1) * e.get(1));
    assert_close(
        matrix::mat_add(n, &a, &b).get(0, 2),
        a.get(0, 2) + b.get(0, 2),
    );
    assert_close(
        matrix::mat_add_semul3(n, &a, &b, &e, &a).get(1, 2),
        a.get(1, 2) + b.get(1, 2) * e.get(2) + a.get(1, 2),
    );
    assert_close(
        matrix::esmul_semul_add(n, &e, &a, &b, &a).get(1, 2),
        e.get(1) * a.get(1, 2) + b.get(1, 2) * e.get(2) + a.get(1, 2),
    );
}

#[test]
fn labos_qseries_solves_gauss_block_and_preserves_weak_products() {
    let n = 3;
    let mut small = Mat::zero(n);
    small.set(0, 0, 1.0e-4);
    small.set(1, 1, 1.0e-4);

    let weak = matrix::qseries_known_nonzero_product(n, 2, &small, &Mat::identity(n));
    assert_close(weak.get(0, 0), 1.0e-4);

    let mut a = Mat::zero(n);
    a.set(0, 0, 0.2);
    a.set(1, 1, 0.1);
    a.set(2, 0, 0.4);
    let mut b = Mat::zero(n);
    b.set(0, 0, 1.0);
    b.set(0, 2, 1.5);
    b.set(1, 1, 1.0);

    let series = matrix::qseries_known_nonzero_product(n, 2, &a, &b);
    assert_close(series.get(0, 0), 0.25);
    assert_close(series.get(1, 1), 1.0 / 0.9 - 1.0);
    assert_close(series.get(0, 2), 0.375);
    assert_close(series.get(2, 0), 0.5);
    assert_close(series.get(2, 2), 0.75);
}

#[test]
fn labos_attenuation_builds_symmetric_level_transmittance() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
    ];
    let u = geometry.u[0];

    let atten = attenuation::fill_attenuation(&layers, &geometry, false);
    assert_close(atten.get(0, 0, 0), 1.0);
    assert_close(atten.get(0, 0, 1), (-0.1 / u).exp());
    assert_close(atten.get(0, 0, 2), (-(0.1 + 0.2) / u).exp());
    assert_close(atten.get(0, 2, 0), atten.get(0, 0, 2));

    let dynamic = attenuation::fill_attenuation_dynamic(&layers, &geometry, false);
    assert_close(dynamic.get(0, 0, 2), atten.get(0, 0, 2));
}

#[test]
fn labos_attenuation_uses_pseudo_spherical_top_level_direction_cosines() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            view_mu: 0.5,
            solar_mu: 0.7,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            view_mu: 0.4,
            solar_mu: 0.6,
            ..LayerInput::default()
        },
    ];

    let atten = attenuation::fill_attenuation(&layers, &geometry, true);
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    assert_close(
        atten.get(view_idx, 2, 0),
        (-0.2_f64 / 0.4).exp() * (-0.1_f64 / 0.5).exp(),
    );
    assert_close(
        atten.get(solar_idx, 2, 0),
        (-0.2_f64 / 0.6).exp() * (-0.1_f64 / 0.7).exp(),
    );
}

#[test]
fn labos_dynamic_attenuation_uses_explicit_pseudo_spherical_grid_when_valid() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput {
            optical_depth: 0.1,
            ..LayerInput::default()
        },
        LayerInput {
            optical_depth: 0.2,
            ..LayerInput::default()
        },
    ];
    let grid = PseudoSphericalGrid {
        samples: vec![
            PseudoSphericalSample {
                altitude_km: 1.0,
                thickness_km: 1.0,
                optical_depth: 0.05,
            },
            PseudoSphericalSample {
                altitude_km: 3.0,
                thickness_km: 1.0,
                optical_depth: 0.07,
            },
        ],
        level_sample_starts: vec![0, 1, 2],
        level_altitudes_km: vec![0.5, 2.5, 3.5],
    };

    let dynamic = attenuation::fill_attenuation_dynamic_with_grid(&layers, &grid, &geometry, true);
    assert_close(dynamic.get(0, 2, 2), 1.0);
    assert!(dynamic.get(0, 2, 0) < 1.0);
    assert!(dynamic.get(0, 2, 0) > 0.0);
}

#[test]
fn labos_tangent_attenuation_tracks_optical_depth_jacobian() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let mut layer0 = LayerInput {
        optical_depth: 0.1,
        ..LayerInput::default()
    };
    let mut layer1 = LayerInput {
        optical_depth: 0.2,
        ..LayerInput::default()
    };
    jacobian::set(
        &mut layer0.optical_depth_jacobian,
        State::AerosolOpticalDepth,
        0.01,
    );
    jacobian::set(
        &mut layer1.optical_depth_jacobian,
        State::AerosolOpticalDepth,
        0.02,
    );
    let layers = vec![layer0, layer1];
    let u = geometry.u[0];

    let tangent = attenuation::fill_attenuation_tangent_dynamic(
        &layers,
        State::AerosolOpticalDepth,
        &geometry,
    );
    let base = (-(0.1 + 0.2) / u).exp();
    assert_close(tangent.get(0, 0, 2), base * (-(0.01 + 0.02) / u));
    assert_close(tangent.get(0, 2, 0), tangent.get(0, 0, 2));
}

#[test]
fn labos_geometry_adds_view_and_solar_extra_ordinates() {
    let geometry = Geometry::init(5, 0.8, 0.6).unwrap();

    assert_eq!(geometry.n_gauss, 5);
    assert_eq!(geometry.nmutot, 7);
    assert_eq!(geometry.view_idx(), 5);
    assert_close(geometry.u[5], 0.6);
    assert_close(geometry.u[6], 0.8);
    assert_close(geometry.w[5], 1.0);
    assert_close(geometry.w[6], 1.0);
    assert!(geometry.ug[0] > 0.0);
    assert!(geometry.ug[4] < 1.0);
    assert_close(geometry.wg.iter().take(5).sum::<f64>(), 1.0);
}

#[test]
fn labos_geometry_precomputes_same_and_different_mu_denominators() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let n = geometry.nmutot;

    let same_idx = n + 1;
    assert!(geometry.dmu_same[same_idx]);
    assert_close(
        geometry.dmu_plus[same_idx],
        0.25 / (geometry.u[1] + geometry.u[1]),
    );
    assert_close(
        geometry.dmu_min[same_idx],
        0.25 / (geometry.u[1] * geometry.u[1]),
    );

    let cross_idx = n;
    assert!(!geometry.dmu_same[cross_idx]);
    assert_close(
        geometry.dmu_min[cross_idx],
        0.25 / (geometry.u[1] - geometry.u[0]),
    );
}

#[test]
fn labos_fourier_plm_basis_starts_with_weighted_ordinates() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();

    let zero_fourier = FourierPlmBasis::init(0, 2, &geometry);
    for imu in 0..geometry.nmutot {
        assert_close(zero_fourier.plus[0][imu], geometry.w[imu]);
        assert_close(zero_fourier.minus[0][imu], geometry.w[imu]);
    }

    let first_fourier = FourierPlmBasis::init(1, 1, &geometry);
    for imu in 0..geometry.nmutot {
        let expected = (1.0 - geometry.u[imu] * geometry.u[imu]).max(0.0).sqrt() / 2.0_f64.sqrt()
            * geometry.w[imu];
        assert_close(first_fourier.plus[1][imu], expected);
        assert_close(first_fourier.minus[1][imu], expected);
    }
}

#[test]
fn labos_phase_kernel_zero_fourier_is_weight_outer_product() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let coefficients = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(0, 0, &geometry);

    let kernel = fill_zplus_zmin_from_basis_limited(0, &coefficients, 0, &geometry, &basis);
    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            let expected = geometry.w[i] * geometry.w[j];
            assert_close(kernel.zplus.get(i, j), expected);
            assert_close(kernel.zmin.get(i, j), expected);
        }
    }
}

#[test]
fn labos_phase_kernel_row_matches_full_kernel_row() {
    let geometry = Geometry::init(3, 0.8, 0.6).unwrap();
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[1] = 0.4;
    coefficients[2] = 0.15;
    let basis = FourierPlmBasis::init(0, 2, &geometry);
    let row_index = 2;

    let kernel = fill_zplus_zmin_from_basis_limited(0, &coefficients, 2, &geometry, &basis);
    let row =
        fill_zplus_zmin_row_from_basis_limited(0, &coefficients, 2, &geometry, &basis, row_index);

    assert_eq!(row.n, geometry.nmutot);
    for j in 0..geometry.nmutot {
        assert_close(row.zplus[j], kernel.zplus.get(row_index, j));
        assert_close(row.zmin[j], kernel.zmin.get(row_index, j));
    }
}

#[test]
fn labos_phase_kernel_can_extend_past_cached_basis() {
    let geometry = Geometry::init(3, 0.8, 0.6).unwrap();
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[1] = 0.2;
    coefficients[2] = 0.1;

    let partial_basis = FourierPlmBasis::init(0, 1, &geometry);
    let partial_kernel =
        fill_zplus_zmin_from_basis_limited(0, &coefficients, 2, &geometry, &partial_basis);
    let full_kernel = fill_zplus_zmin(0, &coefficients, &geometry);

    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            assert_close(partial_kernel.zplus.get(i, j), full_kernel.zplus.get(i, j));
            assert_close(partial_kernel.zmin.get(i, j), full_kernel.zmin.get(i, j));
        }
    }
}

#[test]
fn labos_phase_kernel_is_zero_when_fourier_order_exceeds_phase_terms() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let coefficients = phase_functions::zero_phase_coefficients();
    let basis = FourierPlmBasis::init(3, 0, &geometry);

    let kernel = fill_zplus_zmin_from_basis_limited(3, &coefficients, 0, &geometry, &basis);
    let row = fill_zplus_zmin_row_from_basis_limited(3, &coefficients, 0, &geometry, &basis, 0);

    assert!(
        kernel.zplus.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        kernel.zmin.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        row.zplus[..geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(
        row.zmin[..geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
}

#[test]
fn labos_surface_is_lambertian_only_for_zero_fourier() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let surface = fill_surface(0, 0.25, &geometry);
    for i in 0..geometry.nmutot {
        for j in 0..geometry.nmutot {
            assert_close(surface.r.get(i, j), geometry.w[i] * 0.25 * geometry.w[j]);
            assert_close(surface.t.get(i, j), 0.0);
        }
    }

    let higher_order = fill_surface(1, 0.25, &geometry);
    assert!(
        higher_order.r.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
}

#[test]
fn labos_zero_fourier_renormalization_restores_gauss_column_integral() {
    let geometry = Geometry::init(3, 0.8, 0.6).unwrap();
    let coefficients = phase_functions::zero_phase_coefficients();
    let mut kernel = fill_zplus_zmin(0, &coefficients, &geometry);
    for value in kernel
        .zplus
        .data
        .iter_mut()
        .take(geometry.nmutot * geometry.nmutot)
    {
        *value *= 0.8;
    }

    let before = zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, 0);
    assert!(before < 2.0);
    renormalize_zero_fourier_phase_kernel(&geometry, &mut kernel.zplus, &mut kernel.zmin);
    let after = zero_fourier_integral(&kernel.zplus, &kernel.zmin, &geometry, 0);
    assert_close(after, 2.0);
}

#[test]
fn labos_layer_phase_index_and_suffix_precompute_match_effective_scattering_rule() {
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[2] = 0.3;
    coefficients[3] = -0.4;
    let layers = vec![LayerInput {
        phase_coefficients: coefficients,
        ..LayerInput::default()
    }];

    let mut max_indices = [0usize; 1];
    fill_layer_phase_max_indices(&mut max_indices, &layers);
    assert_eq!(max_indices[0], 3);

    let mut suffixes = vec![0.0; MAX_PHASE_COEF];
    fill_layer_effective_scattering_suffixes(&mut suffixes, &layers, &max_indices);
    assert_close(suffixes[3], 0.4 / 7.0);
    assert_close(suffixes[2], (0.3_f64 / 5.0).max(0.4 / 7.0));
    assert_close(suffixes[0], 1.0);
}

#[test]
fn labos_layer_assembly_matches_single_scatter_formula_without_doubling() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layer = LayerInput {
        optical_depth: 0.2,
        scattering_optical_depth: 0.1,
        single_scatter_albedo: 0.7,
        phase_coefficients: phase_functions::zero_phase_coefficients(),
        ..LayerInput::default()
    };
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };

    let rt = calc_rt_layers(&[layer], 0, &geometry, controls);
    assert_eq!(rt.len(), 2);
    assert!(
        rt[0].r.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );

    let i = 0;
    let j = 1;
    let idx = i * geometry.nmutot + j;
    let ei = (-layer.optical_depth / geometry.u[i].max(1.0e-12)).exp();
    let ej = (-layer.optical_depth / geometry.u[j].max(1.0e-12)).exp();
    let z = geometry.w[i] * geometry.w[j];
    assert_close(
        rt[1].r.get(i, j),
        layer.single_scatter_albedo * z * (1.0 - ei * ej) * geometry.dmu_plus[idx],
    );
    assert_close(
        rt[1].t.get(i, j),
        layer.single_scatter_albedo * z * (ei - ej) * geometry.dmu_min[idx],
    );
}

#[test]
fn labos_layer_assembly_populates_optional_caches_and_activity_mask() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let layers = vec![
        LayerInput::default(),
        LayerInput {
            optical_depth: 0.2,
            scattering_optical_depth: 0.1,
            single_scatter_albedo: 0.7,
            phase_coefficients: phase_functions::zero_phase_coefficients(),
            ..LayerInput::default()
        },
    ];
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let mut rt = vec![
        LayerRt {
            r: Mat::zero(geometry.nmutot),
            t: Mat::zero(geometry.nmutot),
        };
        layers.len() + 1
    ];
    let mut cache = vec![
        PhaseKernel {
            zplus: Mat::zero(geometry.nmutot),
            zmin: Mat::zero(geometry.nmutot),
        };
        layers.len() + 1
    ];
    let mut valid = vec![true; layers.len() + 1];
    let mut active = vec![true; layers.len() + 1];

    calc_rt_layers_into_with_basis(
        &mut rt,
        &layers,
        0,
        &geometry,
        controls,
        &basis,
        Some(&[0, 0]),
        None,
        Some(&mut cache),
        Some(&mut valid),
        Some(&mut active),
    );

    assert!(!active[0]);
    assert!(!active[1]);
    assert!(active[2]);
    assert!(!valid[0]);
    assert!(!valid[1]);
    assert!(valid[2]);
    assert!(
        rt[1].r.data[..geometry.nmutot * geometry.nmutot]
            .iter()
            .all(|value| *value == 0.0)
    );
    assert!(rt[2].r.get(0, 0) > 0.0);
    assert_close(cache[2].zplus.get(0, 0), geometry.w[0] * geometry.w[0]);
}

#[test]
fn labos_order_dot_helpers_use_only_gauss_columns() {
    let mut mat = Mat::zero(4);
    for i in 0..4 {
        for j in 0..4 {
            mat.set(i, j, 10.0 * i as f64 + j as f64 + 1.0);
        }
    }
    let mut col0 = LabosVec::zero(4);
    let mut col1 = LabosVec::zero(4);
    col0.set(0, 2.0);
    col0.set(1, 3.0);
    col0.set(2, 100.0);
    col1.set(0, 5.0);
    col1.set(1, 7.0);
    col1.set(2, 100.0);

    assert_close(
        matrix::smul(4, 2, 0.0, &Mat::identity(4), &mat).get(1, 3),
        14.0,
    );
    assert_close(dot_gauss(&mat, 1, &col0, 2), 11.0 * 2.0 + 12.0 * 3.0);
    let pair = dot_gauss_pair(&mat, 1, &col0, &col1, 2);
    assert_close(pair.col0, 11.0 * 2.0 + 12.0 * 3.0);
    assert_close(pair.col1, 11.0 * 5.0 + 12.0 * 7.0);
}

#[test]
fn labos_order_transport_moves_local_sources_between_levels() {
    let nmutot = 3;
    let mut atten = DynamicAttenArray::new(3, 3);
    for imu in 0..nmutot {
        atten.set(imu, 0, 1, 0.5);
        atten.set(imu, 1, 2, 0.25);
        atten.set(imu, 2, 1, 0.4);
        atten.set(imu, 1, 0, 0.3);
    }

    let mut local = vec![zero_ud_local(nmutot); 3];
    local[0].u.col[0].set(0, 1.0);
    local[1].u.col[0].set(0, 2.0);
    local[2].u.col[0].set(0, 3.0);
    local[1].d.col[0].set(0, 4.0);
    local[0].d.col[0].set(0, 5.0);

    let mut transported = vec![zero_ud_field(nmutot); 3];
    transport_to_other_levels(0, 2, nmutot, &atten, &local, &mut transported);

    assert_close(transported[1].u.col[0].get(0), 2.0 + 0.5 * 1.0);
    assert_close(transported[2].u.col[0].get(0), 3.0 + 0.25 * (2.0 + 0.5));
    assert_close(transported[1].d.col[0].get(0), 4.0);
    assert_close(transported[0].d.col[0].get(0), 5.0 + 0.3 * 4.0);
}

#[test]
fn labos_order_tangent_transport_applies_product_rule_between_levels() {
    let nmutot = 3;
    let mut atten = DynamicAttenArray::new(nmutot, 3);
    let mut atten_tangent = DynamicAttenArray {
        data: vec![0.0; nmutot * 3 * 3],
        nmutot,
        nlevel: 3,
    };
    atten.set(0, 0, 1, 0.5);
    atten_tangent.set(0, 0, 1, 0.05);
    atten.set(0, 1, 0, 0.3);
    atten_tangent.set(0, 1, 0, 0.07);

    let mut base_orde = vec![zero_ud_field(nmutot); 3];
    base_orde[0].u.col[0].set(0, 2.0);
    base_orde[1].d.col[0].set(0, 3.0);
    let mut tangent_local = vec![zero_ud_local(nmutot); 3];
    tangent_local[0].u.col[0].set(0, 0.25);
    tangent_local[1].u.col[0].set(0, 4.0);
    tangent_local[0].d.col[0].set(0, 5.0);
    let mut tangent_orde = vec![zero_ud_field(nmutot); 3];

    transport_to_other_levels_tangent(
        0,
        1,
        nmutot,
        &atten,
        &atten_tangent,
        &base_orde,
        &tangent_local,
        &mut tangent_orde,
    );

    assert_close(
        tangent_orde[1].u.col[0].get(0),
        4.0 + 0.05 * 2.0 + 0.5 * 0.25,
    );
    assert_close(tangent_orde[0].d.col[0].get(0), 5.0 + 0.07 * 3.0);
}

#[test]
fn labos_order_activity_and_accumulation_helpers_match_layer_signal_rules() {
    let nmutot = 3;
    let zero = LayerRt {
        r: Mat::zero(nmutot),
        t: Mat::zero(nmutot),
    };
    let mut nonzero = zero;
    nonzero.t.set(1, 1, 0.2);
    let mut active = [true, false];

    refresh_active_layer_mask(&[zero, nonzero], &mut active, nmutot);
    assert_eq!(active, [false, true]);

    let mut ud = vec![zero_ud_field(nmutot); 2];
    let mut sum_local = vec![zero_ud_local(nmutot); 2];
    let mut orde = vec![zero_ud_field(nmutot); 2];
    let mut local = vec![zero_ud_local(nmutot); 2];
    orde[1].u.col[0].set(1, 1.5);
    orde[1].d.col[1].set(1, 2.5);
    local[1].u.col[0].set(1, 0.5);
    local[1].d.col[1].set(1, 0.75);

    accumulate_order_contribution(true, &mut ud, &mut sum_local, &orde, &local, 0, 1, nmutot);

    assert_close(ud[1].u.col[0].get(1), 1.5);
    assert_close(ud[1].d.col[1].get(1), 2.5);
    assert_close(sum_local[1].u.col[0].get(1), 0.5);
    assert_close(sum_local[1].d.col[1].get(1), 0.75);
    assert_close(max_outgoing_upward(&ud, 1, 1, nmutot), 1.5);
}

#[test]
fn labos_orders_scat_returns_direct_transmittance_when_layers_have_no_signal() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let atten = DynamicAttenArray::new(geometry.nmutot, 2);
    let rt = vec![
        LayerRt {
            r: Mat::zero(geometry.nmutot),
            t: Mat::zero(geometry.nmutot),
        };
        2
    ];
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };

    let result = orders_scat(0, 1, &geometry, &atten, &rt, controls, 4);

    assert_eq!(result.ud.len(), 2);
    for level in 0..2 {
        assert_close(result.ud[level].e.get(0), 1.0);
        assert_close(result.ud[level].u.col[0].get(0), 0.0);
        assert_close(result.ud[level].d.col[0].get(0), 0.0);
    }
}

#[test]
fn labos_orders_scat_uses_initial_surface_and_layer_sources() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let mut atten = DynamicAttenArray::new(geometry.nmutot, 2);
    for imu in 0..geometry.nmutot {
        atten.set(imu, 0, 1, 0.5);
        atten.set(imu, 1, 0, 0.25);
    }

    let mut rt = vec![
        LayerRt {
            r: Mat::zero(geometry.nmutot),
            t: Mat::zero(geometry.nmutot),
        };
        2
    ];
    let view_col = geometry.n_gauss;
    rt[0].r.set(0, view_col, 2.0);
    rt[1].r.set(0, view_col, 3.0);
    rt[1].t.set(0, view_col, 4.0);

    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };
    let mut workspace = OrdersWorkspace::new(2, geometry.nmutot);
    workspace.rt_active = vec![true, true];
    let result = orders_scat_into_with_active_local_sum(
        &mut workspace,
        0,
        1,
        &geometry,
        &atten,
        &rt,
        controls,
        4,
    );

    assert_close(result.ud_sum_local[0].u.col[0].get(0), 2.0 * 0.25);
    assert_close(result.ud_sum_local[1].u.col[0].get(0), 3.0);
    assert_close(result.ud_sum_local[0].d.col[0].get(0), 4.0);
    assert_close(result.ud[1].u.col[0].get(0), 3.0 + 0.5 * (2.0 * 0.25));
    assert_close(result.ud[0].d.col[0].get(0), 4.0);
}

#[test]
fn labos_orders_scat_tangent_tracks_initial_source_and_transport_derivatives() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let mut atten = DynamicAttenArray::new(geometry.nmutot, 2);
    let mut atten_tangent = DynamicAttenArray {
        data: vec![0.0; geometry.nmutot * 2 * 2],
        nmutot: geometry.nmutot,
        nlevel: 2,
    };
    for imu in 0..geometry.nmutot {
        atten.set(imu, 0, 1, 0.5);
        atten.set(imu, 1, 0, 0.25);
    }
    atten_tangent.set(0, 0, 1, 0.05);
    atten_tangent.set(geometry.n_gauss, 1, 0, 0.1);
    atten_tangent.set(geometry.n_gauss, 1, 1, 0.2);

    let mut rt = vec![
        LayerRt {
            r: Mat::zero(geometry.nmutot),
            t: Mat::zero(geometry.nmutot),
        };
        2
    ];
    let mut rt_tangent = rt.clone();
    let view_col = geometry.n_gauss;
    rt[0].r.set(0, view_col, 2.0);
    rt[1].r.set(0, view_col, 3.0);
    rt[1].t.set(0, view_col, 4.0);
    rt_tangent[0].r.set(0, view_col, 0.5);
    rt_tangent[1].r.set(0, view_col, 0.7);
    rt_tangent[1].t.set(0, view_col, 0.6);

    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };
    let result = orders_scat_tangent(
        0,
        1,
        &geometry,
        &atten,
        &atten_tangent,
        &rt,
        &rt_tangent,
        controls,
        4,
    );

    let surface_du = 0.5 * 0.25 + 2.0 * 0.1;
    let layer_du = 0.7 * 1.0 + 3.0 * 0.2;
    assert_close(result.ud[0].u.col[0].get(0), surface_du);
    assert_close(
        result.ud[1].u.col[0].get(0),
        layer_du + 0.05 * (2.0 * 0.25) + 0.5 * surface_du,
    );
    assert_close(result.ud[0].d.col[0].get(0), 0.6 * 1.0 + 4.0 * 0.2);
    assert_close(result.ud[0].e.get(0), 0.0);
}

#[test]
fn labos_reflectance_reads_solar_column_at_requested_level() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let mut ud = vec![zero_ud_field(geometry.nmutot); 2];
    ud[1].u.col[1].set(geometry.view_idx(), 1.23);

    assert_close(calc_reflectance(&ud, 1, &geometry), 1.23);
    assert_close(calc_reflectance_tangent(&ud, 1, &geometry), 1.23);
}

#[test]
fn labos_reflectance_source_phase_indices_follow_adjacent_layers() {
    let mut source_indices = [99usize; 3];
    fill_adjacent_layer_phase_max_indices(&mut source_indices, &[1, 3]);
    assert_eq!(source_indices, [1, 3, 3]);

    let mut empty_source_indices = [99usize; 1];
    fill_adjacent_layer_phase_max_indices(&mut empty_source_indices, &[]);
    assert_eq!(empty_source_indices, [0]);
}

#[test]
fn labos_reflectance_resolved_phase_and_fourier_limits_follow_inputs() {
    let mut coefficients = phase_functions::zero_phase_coefficients();
    coefficients[4] = 0.2;
    let mut input = ForwardInput {
        mu0: 0.8,
        muv: 0.6,
        layers: vec![LayerInput {
            phase_coefficients: coefficients,
            ..LayerInput::default()
        }],
        ..ForwardInput::default()
    };
    let controls = RadiativeTransferControls {
        performance_thresholds: RadiativeTransferPerformanceThresholds {
            fourier_order_cap: Some(2),
            ..RadiativeTransferPerformanceThresholds::default()
        },
        ..RadiativeTransferControls::default()
    };

    assert_eq!(resolved_phase_coefficient_max(&input), 4);
    assert_eq!(resolved_fourier_max(&input, controls), 2);

    input.muv = 1.0;
    assert_eq!(resolved_fourier_max(&input, controls), 0);
}

#[test]
fn labos_reflectance_integrates_source_interface_and_direct_term() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let mut ud = vec![zero_ud_field(geometry.nmutot); 1];
    ud[0].e.set(view_idx, 2.0);
    ud[0].e.set(solar_idx, 3.0);
    ud[0].u.col[1].set(view_idx, 4.0);
    let source_interface = SourceInterfaceInput {
        source_weight: 2.0,
        phase_coefficients_above: phase_functions::zero_phase_coefficients(),
        ..SourceInterfaceInput::default()
    };

    let reflectance = calc_integrated_reflectance(
        &[],
        &[source_interface],
        &RtmQuadratureGrid::default(),
        &ud,
        0,
        0,
        &geometry,
    );

    let pmin_direct = (0.25 / geometry.muv) / geometry.mu0;
    let expected_source = 2.0 * 2.0 * pmin_direct * 3.0;
    let expected_direct = 2.0 * 4.0;
    assert_close(reflectance, expected_source + expected_direct);
}

#[test]
fn labos_reflectance_can_reuse_cached_layer_phase_rows() {
    let geometry = Geometry::init(2, 0.8, 0.6).unwrap();
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let layers = vec![LayerInput {
        scattering_optical_depth: 0.5,
        phase_coefficients: phase_functions::zero_phase_coefficients(),
        ..LayerInput::default()
    }];
    let mut ud = vec![zero_ud_field(geometry.nmutot); 1];
    ud[0].e.set(view_idx, 2.0);
    ud[0].e.set(solar_idx, 3.0);
    ud[0].u.col[1].set(view_idx, 4.0);
    let basis = FourierPlmBasis::init(0, 0, &geometry);
    let mut cache = vec![
        PhaseKernel {
            zplus: Mat::zero(geometry.nmutot),
            zmin: Mat::zero(geometry.nmutot),
        };
        2
    ];
    cache[1].zmin.set(view_idx, solar_idx, 2.0);
    let valid = [false, true];

    let reflectance = calc_integrated_reflectance_with_basis(
        &layers,
        &[],
        &RtmQuadratureGrid::default(),
        &ud,
        0,
        0,
        &geometry,
        &basis,
        None,
        Some(&cache),
        Some(&valid),
    );

    let pmin_direct = (0.25 * 2.0 / geometry.muv) / geometry.mu0;
    let expected_source = 0.5 * 2.0 * pmin_direct * 3.0;
    let expected_direct = 2.0 * 4.0;
    assert_close(reflectance, expected_source + expected_direct);
}

#[test]
fn labos_reflectance_sums_only_positive_scattering_optical_depth() {
    let layers = vec![
        LayerInput {
            scattering_optical_depth: 0.25,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: -0.5,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 0.75,
            ..LayerInput::default()
        },
    ];

    assert_close(total_scattering_optical_depth(&layers), 1.0);
}
