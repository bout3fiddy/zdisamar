use zdisamar::forward_model::{
    optical_properties::shared::phase_functions::{self, PhaseCoefficients},
    radiative_transfer::{
        common_route,
        common_types::{
            ForwardInput, LayerInput, RadiativeTransferControls, RtmQuadratureGrid,
            RtmQuadratureLevel, SourceInterfaceInput,
        },
        labos::{
            FourierPlmBasis, Geometry, Mat, PhaseKernel, UdField, Vec as LabosVec, Vec2,
            calc_integrated_reflectance, calc_integrated_reflectance_with_basis, calc_reflectance,
            fill_adjacent_layer_phase_max_indices, fill_zplus_zmin_from_basis,
            resolved_fourier_max, resolved_phase_coefficient_max,
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
