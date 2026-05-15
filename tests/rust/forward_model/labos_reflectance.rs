use zdisamar::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_route,
        common_types::{
            ForwardInput, LayerInput, RadiativeTransferControls, RtmQuadratureGrid,
            RtmQuadratureLevel, SourceInterfaceInput,
        },
        labos::{
            FourierPlmBasis, Geometry, Mat, PhaseKernel, UdField, Vec as LabosVec, Vec2,
            calc_aerosol_layer_pressure_shift_weighting_with_basis,
            calc_aerosol_optical_depth_weighting_with_basis, calc_integrated_reflectance,
            calc_integrated_reflectance_with_basis, calc_reflectance,
            fill_adjacent_layer_phase_max_indices, fill_zplus_zmin_from_basis,
            fill_zplus_zmin_row_from_basis_limited, resolved_fourier_max,
            resolved_phase_coefficient_max,
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

fn zero_ud(n: usize) -> UdField {
    UdField {
        e: LabosVec::zero(n),
        u: Vec2::zero(n),
        d: Vec2::zero(n),
    }
}

fn direct_phase_source(
    phase_coefficients: PhaseCoefficients,
    level: &UdField,
    i_fourier: usize,
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> f64 {
    let view_idx = geometry.view_idx();
    let solar_idx = geometry.n_gauss + 1;
    let max_phase_index = phase_functions::max_phase_coefficient_index(&phase_coefficients);
    let row = fill_zplus_zmin_row_from_basis_limited(
        i_fourier,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        view_idx,
    );
    let pmin_direct = (0.25 * row.zmin[solar_idx] / geometry.u[view_idx].max(1.0e-12))
        / geometry.u[solar_idx].max(1.0e-12);
    level.e.get(view_idx) * pmin_direct * level.e.get(solar_idx)
}

#[test]
fn direct_reflectance_reads_solar_column_at_view_direction() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let mut ud = vec![zero_ud(geometry.nmutot); 3];
    ud[2].u.col[1].set(geometry.view_idx(), 0.42);

    assert_close(calc_reflectance(&ud, 2, &geometry), 0.42, 0.0);
}

#[test]
fn adjacent_layer_phase_max_indices_take_neighbor_ceiling() {
    let layer_indices = [2, 4, 1];
    let mut source_indices = [0; 4];

    fill_adjacent_layer_phase_max_indices(&mut source_indices, &layer_indices);

    assert_eq!(source_indices, [2, 4, 4, 1]);
}

#[test]
fn resolved_phase_and_fourier_max_use_source_interfaces_and_caps() {
    let input = ForwardInput {
        mu0: 0.58,
        muv: 0.64,
        layers: vec![LayerInput {
            phase_coefficients: phase_coefficients(&[(1, 0.2), (2, 0.1)]),
            ..LayerInput::default()
        }],
        source_interfaces: vec![
            SourceInterfaceInput {
                phase_coefficients_above: phase_coefficients(&[(5, 0.03)]),
                ..SourceInterfaceInput::default()
            },
            SourceInterfaceInput::default(),
        ],
        ..ForwardInput::default()
    };
    let controls = RadiativeTransferControls {
        performance_thresholds: zdisamar::forward_model::radiative_transfer::common_types::RadiativeTransferPerformanceThresholds {
            fourier_order_cap: Some(3),
            ..Default::default()
        },
        ..RadiativeTransferControls::default()
    };

    assert_eq!(resolved_phase_coefficient_max(&input), 5);
    assert_eq!(resolved_fourier_max(&input, controls), 3);

    let near_normal_input = ForwardInput { mu0: 1.0, ..input };
    assert_eq!(resolved_fourier_max(&near_normal_input, controls), 0);
}

#[test]
fn cached_layer_kernels_preserve_integrated_reflectance_when_source_interfaces_mirror_layers() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layers = vec![
        LayerInput {
            scattering_optical_depth: 0.22,
            phase_coefficients: phase_coefficients(&[(1, 0.56), (2, 0.24), (3, 0.09)]),
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 0.18,
            phase_coefficients: phase_coefficients(&[(1, 0.41), (2, 0.17), (3, 0.05)]),
            ..LayerInput::default()
        },
    ];
    let mut ud = vec![zero_ud(geometry.nmutot); 3];
    for (ilevel, field) in ud.iter_mut().enumerate() {
        for imu in 0..geometry.nmutot {
            field.e.set(imu, 0.8 - 0.1 * ilevel as f64);
            for imu0 in 0..2 {
                field.u.col[imu0].set(imu, 0.02 * ((ilevel + 1) * (imu + 1) * (imu0 + 1)) as f64);
                field.d.col[imu0].set(imu, 0.01 * ((ilevel + 2) * (imu + 1) * (imu0 + 1)) as f64);
            }
        }
    }

    let mut source_interfaces = vec![SourceInterfaceInput::default(); layers.len() + 1];
    common_route::fill_source_interfaces_from_layers(&layers, &mut source_interfaces);
    let input = ForwardInput {
        layers: layers.clone(),
        source_interfaces: source_interfaces.clone(),
        ..ForwardInput::default()
    };
    let i_fourier = 1;
    let plm_basis =
        FourierPlmBasis::init(i_fourier, resolved_phase_coefficient_max(&input), &geometry);
    let mut kernel_cache = vec![
        PhaseKernel {
            zplus: Mat::zero(geometry.nmutot),
            zmin: Mat::zero(geometry.nmutot),
        };
        3
    ];
    let mut kernel_valid = vec![false; 3];
    for (layer_idx, layer) in layers.iter().enumerate() {
        kernel_cache[layer_idx + 1] =
            fill_zplus_zmin_from_basis(i_fourier, layer.phase_coefficients, &geometry, &plm_basis);
        kernel_valid[layer_idx + 1] = true;
    }

    let baseline = calc_integrated_reflectance(
        &layers,
        &source_interfaces,
        &RtmQuadratureGrid::default(),
        &ud,
        layers.len(),
        i_fourier,
        &geometry,
    );
    let cached = calc_integrated_reflectance_with_basis(
        &layers,
        &source_interfaces,
        &RtmQuadratureGrid::default(),
        &ud,
        layers.len(),
        i_fourier,
        &geometry,
        &plm_basis,
        None,
        Some(&kernel_cache),
        Some(&kernel_valid),
    );

    assert_close(cached, baseline, 1.0e-12);
}

#[test]
fn integrated_source_truncates_quadrature_phase_kernels_by_adjacent_layers() {
    let geometry = Geometry::init(4, 0.58, 0.64);
    let layer_phase = phase_coefficients(&[(1, 0.18), (2, 0.31)]);
    let source_phase_with_tail = phase_coefficients(&[(1, 0.18), (2, 0.31), (3, 4.0)]);
    let source_phase_truncated = phase_coefficients(&[(1, 0.18), (2, 0.31)]);
    let layers = vec![
        LayerInput {
            scattering_optical_depth: 0.1,
            phase_coefficients: layer_phase,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 0.1,
            phase_coefficients: layer_phase,
            ..LayerInput::default()
        },
    ];
    let mut ud = vec![zero_ud(geometry.nmutot); 3];
    for (ilevel, field) in ud.iter_mut().enumerate() {
        for imu in 0..geometry.nmutot {
            field.e.set(imu, 0.8 + 0.03 * (ilevel + imu) as f64);
            for col in 0..2 {
                field.u.col[col].set(imu, 0.015 * ((ilevel + 1) * (imu + 2) * (col + 1)) as f64);
                field.d.col[col].set(imu, 0.011 * ((ilevel + 2) * (imu + 1) * (col + 1)) as f64);
            }
        }
    }

    let rtm_quadrature_with_tail = RtmQuadratureGrid {
        levels: vec![
            RtmQuadratureLevel::default(),
            RtmQuadratureLevel {
                weight: 1.0,
                ksca: 1.0,
                phase_coefficients: source_phase_with_tail,
                ..RtmQuadratureLevel::default()
            },
            RtmQuadratureLevel::default(),
        ],
    };
    let rtm_quadrature_truncated = RtmQuadratureGrid {
        levels: vec![
            RtmQuadratureLevel::default(),
            RtmQuadratureLevel {
                weight: 1.0,
                ksca: 1.0,
                phase_coefficients: source_phase_truncated,
                ..RtmQuadratureLevel::default()
            },
            RtmQuadratureLevel::default(),
        ],
    };
    let i_fourier = 0;
    let plm_basis = FourierPlmBasis::init(i_fourier, 3, &geometry);

    let actual = calc_integrated_reflectance_with_basis(
        &layers,
        &[],
        &rtm_quadrature_with_tail,
        &ud,
        layers.len(),
        i_fourier,
        &geometry,
        &plm_basis,
        None,
        None,
        None,
    );
    let expected = calc_integrated_reflectance_with_basis(
        &layers,
        &[],
        &rtm_quadrature_truncated,
        &ud,
        layers.len(),
        i_fourier,
        &geometry,
        &plm_basis,
        None,
        None,
        None,
    );

    assert_close(actual, expected, 1.0e-12);
}

#[test]
fn aerosol_optical_depth_weighting_uses_scaled_phase_jacobian_source() {
    let geometry = Geometry::init(2, 0.58, 0.64);
    let i_fourier = 0;
    let plm_basis = FourierPlmBasis::init(i_fourier, 0, &geometry);
    let mut ud = vec![zero_ud(geometry.nmutot); 2];
    ud[0].e.set(geometry.view_idx(), 0.8);
    ud[0].e.set(geometry.n_gauss + 1, 0.6);

    let state_index = jacobian::state_index(State::AerosolOpticalDepth);
    let mut phase_jacobian = phase_functions::zero_phase_coefficients();
    phase_jacobian[0] = 0.2;
    let mut jacobian_by_state = [[0.0;
        zdisamar::forward_model::radiative_transfer::common_types::PHASE_COEFFICIENT_COUNT_RT];
        jacobian::STATE_COUNT];
    jacobian_by_state[state_index] = phase_jacobian;
    let rtm_quadrature = RtmQuadratureGrid {
        levels: vec![
            RtmQuadratureLevel {
                weight: 0.75,
                ksca_phase_coefficient_jacobian: jacobian_by_state,
                ..RtmQuadratureLevel::default()
            },
            RtmQuadratureLevel::default(),
        ],
    };
    let layers = vec![LayerInput::default()];

    let actual = calc_aerosol_optical_depth_weighting_with_basis(
        &layers,
        &rtm_quadrature,
        &ud,
        &[],
        layers.len(),
        i_fourier,
        false,
        &geometry,
        &plm_basis,
        None,
    );
    let expected = rtm_quadrature.levels[0].weight
        * direct_phase_source(phase_jacobian, &ud[0], i_fourier, &geometry, &plm_basis);

    assert_close(actual, expected, 1.0e-12);
}

#[test]
fn aerosol_pressure_shift_weighting_uses_interior_bounds() {
    let geometry = Geometry::init(2, 0.58, 0.64);
    let i_fourier = 0;
    let plm_basis = FourierPlmBasis::init(i_fourier, 0, &geometry);
    let mut ud = vec![zero_ud(geometry.nmutot); 3];
    ud[0].e.set(geometry.view_idx(), 0.7);
    ud[0].e.set(geometry.n_gauss + 1, 0.5);
    ud[2].e.set(geometry.view_idx(), 0.9);
    ud[2].e.set(geometry.n_gauss + 1, 0.4);

    let mut unit_phase = phase_functions::zero_phase_coefficients();
    unit_phase[0] = 1.0;
    let mut bottom_phase = phase_functions::zero_phase_coefficients();
    bottom_phase[0] = 0.2;
    let mut top_phase = phase_functions::zero_phase_coefficients();
    top_phase[0] = 0.4;
    let state_index = jacobian::state_index(State::AerosolOpticalDepth);
    let mut active_jacobian = [[0.0;
        zdisamar::forward_model::radiative_transfer::common_types::PHASE_COEFFICIENT_COUNT_RT];
        jacobian::STATE_COUNT];
    active_jacobian[state_index][0] = 0.1;
    let rtm_quadrature = RtmQuadratureGrid {
        levels: vec![
            RtmQuadratureLevel {
                altitude_km: 0.0,
                aerosol_ksca_phase_above_per_km: bottom_phase,
                ..RtmQuadratureLevel::default()
            },
            RtmQuadratureLevel {
                altitude_km: 1.0,
                ksca_phase_coefficient_jacobian: active_jacobian,
                ..RtmQuadratureLevel::default()
            },
            RtmQuadratureLevel {
                altitude_km: 2.0,
                aerosol_ksca_phase_below_per_km: top_phase,
                ..RtmQuadratureLevel::default()
            },
        ],
    };
    let layers = vec![
        LayerInput {
            aerosol_optical_depth: 0.3,
            aerosol_scattering_optical_depth: 0.3,
            ..LayerInput::default()
        },
        LayerInput {
            aerosol_optical_depth: 0.2,
            aerosol_scattering_optical_depth: 0.2,
            ..LayerInput::default()
        },
    ];

    let actual = calc_aerosol_layer_pressure_shift_weighting_with_basis(
        &layers,
        &rtm_quadrature,
        &ud,
        &[],
        layers.len(),
        i_fourier,
        false,
        &geometry,
        &plm_basis,
    );
    let top = direct_phase_source(unit_phase, &ud[2], i_fourier, &geometry, &plm_basis);
    let bottom = direct_phase_source(unit_phase, &ud[0], i_fourier, &geometry, &plm_basis);
    let expected = (top - bottom) * top_phase[0];

    assert_close(actual, expected, 1.0e-12);
}
