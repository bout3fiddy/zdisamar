use zdisamar::forward_model::radiative_transfer::{
    common_types::{
        RadiativeTransferControls, RadiativeTransferPerformanceThresholds, ScatteringMode,
    },
    labos::{
        AttenuationLookup, Geometry, LayerRt, Mat, OrdersWorkspace, orders_scat_into,
        orders_scat_into_with_local_sum, orders_scat_tangent,
    },
};

struct UnitAtten;

impl AttenuationLookup for UnitAtten {
    fn get(&self, _imu: usize, _from: usize, _to: usize) -> f64 {
        1.0
    }
}

struct ShapeAtten;

impl AttenuationLookup for ShapeAtten {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        if from == to {
            return 0.0;
        }
        0.0002 * (imu as f64 + 1.0) + 0.0001 * (from as f64 + 1.0) - 0.00005 * (to as f64 + 1.0)
    }
}

struct PerturbedAtten {
    epsilon: f64,
}

impl AttenuationLookup for PerturbedAtten {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        UnitAtten.get(imu, from, to) + self.epsilon * ShapeAtten.get(imu, from, to)
    }
}

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn sample_rt(nlevel: usize, nmutot: usize) -> Vec<LayerRt> {
    let mut rt = vec![
        LayerRt {
            r: Mat::zero(nmutot),
            t: Mat::zero(nmutot),
        };
        nlevel
    ];
    for (level, layer) in rt.iter_mut().enumerate() {
        for row in 0..nmutot {
            for col in 0..nmutot {
                layer.r.set(
                    row,
                    col,
                    0.002 * (level as f64 + 1.0) + 0.0001 * (row as f64 + 1.0)
                        - 0.00004 * (col as f64 + 1.0),
                );
                layer.t.set(
                    row,
                    col,
                    0.0015 * (level as f64 + 1.0) - 0.00006 * (row as f64 + 1.0)
                        + 0.00008 * (col as f64 + 1.0),
                );
            }
        }
    }
    rt
}

fn sample_rt_tangent(nlevel: usize, nmutot: usize) -> Vec<LayerRt> {
    let mut rt = vec![
        LayerRt {
            r: Mat::zero(nmutot),
            t: Mat::zero(nmutot),
        };
        nlevel
    ];
    for (level, layer) in rt.iter_mut().enumerate() {
        for row in 0..nmutot {
            for col in 0..nmutot {
                layer.r.set(
                    row,
                    col,
                    0.0003 * (level as f64 + 1.0)
                        + 0.00002 * (row as f64 + 1.0)
                        + 0.00001 * (col as f64 + 1.0),
                );
                layer.t.set(
                    row,
                    col,
                    -0.0002 * (level as f64 + 1.0) + 0.00001 * (row as f64 + 1.0)
                        - 0.000015 * (col as f64 + 1.0),
                );
            }
        }
    }
    rt
}

fn perturb_rt(base: &[LayerRt], tangent: &[LayerRt], epsilon: f64, nmutot: usize) -> Vec<LayerRt> {
    let mut perturbed = base.to_vec();
    for ((out, base), tangent) in perturbed.iter_mut().zip(base.iter()).zip(tangent.iter()) {
        for row in 0..nmutot {
            for col in 0..nmutot {
                out.r.set(
                    row,
                    col,
                    base.r.get(row, col) + epsilon * tangent.r.get(row, col),
                );
                out.t.set(
                    row,
                    col,
                    base.t.get(row, col) + epsilon * tangent.t.get(row, col),
                );
            }
        }
    }
    perturbed
}

#[allow(clippy::too_many_arguments)]
fn assert_tangent_matches_finite_difference(
    base: &[LayerRt],
    tangent_rt: &[LayerRt],
    controls: RadiativeTransferControls,
    geometry: &Geometry,
    nlevel: usize,
    num_orders_max: usize,
    epsilon: f64,
    tolerance: f64,
) {
    let mut base_workspace = OrdersWorkspace::new(nlevel);
    let mut perturbed_workspace = OrdersWorkspace::new(nlevel);
    let perturbed_rt = perturb_rt(base, tangent_rt, epsilon, geometry.nmutot);
    let base_result = orders_scat_into(
        &mut base_workspace,
        0,
        nlevel - 1,
        geometry,
        &UnitAtten,
        base,
        controls,
        num_orders_max,
    );
    let perturbed_result = orders_scat_into(
        &mut perturbed_workspace,
        0,
        nlevel - 1,
        geometry,
        &PerturbedAtten { epsilon },
        &perturbed_rt,
        controls,
        num_orders_max,
    );
    let tangent_result = orders_scat_tangent(
        0,
        nlevel - 1,
        geometry,
        &UnitAtten,
        &ShapeAtten,
        base,
        tangent_rt,
        controls,
        num_orders_max,
    );

    for ilevel in 0..nlevel {
        for col in 0..2 {
            for imu in 0..geometry.nmutot {
                let expected_u = (perturbed_result.ud[ilevel].u.col[col].get(imu)
                    - base_result.ud[ilevel].u.col[col].get(imu))
                    / epsilon;
                let expected_d = (perturbed_result.ud[ilevel].d.col[col].get(imu)
                    - base_result.ud[ilevel].d.col[col].get(imu))
                    / epsilon;
                assert_close(
                    tangent_result.ud[ilevel].u.col[col].get(imu),
                    expected_u,
                    tolerance,
                );
                assert_close(
                    tangent_result.ud[ilevel].d.col[col].get(imu),
                    expected_d,
                    tolerance,
                );
            }
        }
    }
}

#[test]
fn multiple_scattering_drops_the_first_below_threshold_order() {
    let geometry = Geometry::init(2, 0.58, 0.64);
    let nlevel = 2;
    let nmutot = geometry.nmutot;
    let mut rt = vec![
        LayerRt {
            r: Mat::zero(nmutot),
            t: Mat::zero(nmutot),
        };
        nlevel
    ];

    for imu in 0..nmutot {
        for extra in 0..2 {
            let source_col = geometry.n_gauss + extra;
            rt[0].r.set(imu, source_col, 0.02);
            rt[1].r.set(imu, source_col, 0.01);
            rt[1].t.set(imu, source_col, 0.03);
        }
        for gauss_col in 0..geometry.n_gauss {
            rt[0].r.set(imu, gauss_col, 0.02);
            rt[1].r.set(imu, gauss_col, 0.01);
            rt[1].t.set(imu, gauss_col, 0.03);
        }
    }

    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        performance_thresholds: RadiativeTransferPerformanceThresholds {
            threshold_conv_first: 1.0e-12,
            threshold_conv_mult: 1.0,
            ..RadiativeTransferPerformanceThresholds::default()
        },
        ..RadiativeTransferControls::default()
    };
    let mut single_workspace = OrdersWorkspace::new(nlevel);
    let mut multiple_workspace = OrdersWorkspace::new(nlevel);
    let mut local_sum_workspace = OrdersWorkspace::new(nlevel);

    let single_result = orders_scat_into(
        &mut single_workspace,
        0,
        1,
        &geometry,
        &UnitAtten,
        &rt,
        controls,
        20,
    );
    let multiple_result = orders_scat_into(
        &mut multiple_workspace,
        0,
        1,
        &geometry,
        &UnitAtten,
        &rt,
        RadiativeTransferControls {
            scattering: ScatteringMode::Multiple,
            ..controls
        },
        20,
    );
    let local_sum_result = orders_scat_into_with_local_sum(
        &mut local_sum_workspace,
        0,
        1,
        &geometry,
        &UnitAtten,
        &rt,
        RadiativeTransferControls {
            scattering: ScatteringMode::Multiple,
            ..controls
        },
        20,
    );

    assert_eq!(single_result.ud_sum_local.len(), 0);
    assert_eq!(multiple_result.ud_sum_local.len(), 0);
    assert_eq!(local_sum_result.ud_sum_local.len(), nlevel);

    for ilevel in 0..nlevel {
        for col in 0..2 {
            for imu in 0..nmutot {
                assert_close(
                    single_result.ud[ilevel].u.col[col].get(imu),
                    multiple_result.ud[ilevel].u.col[col].get(imu),
                    1.0e-15,
                );
                assert_close(
                    single_result.ud[ilevel].d.col[col].get(imu),
                    multiple_result.ud[ilevel].d.col[col].get(imu),
                    1.0e-15,
                );
            }
        }
    }
}

#[test]
fn single_scattering_tangent_matches_finite_difference() {
    let geometry = Geometry::init(2, 0.58, 0.64);
    let nlevel = 3;
    let base = sample_rt(nlevel, geometry.nmutot);
    let tangent_rt = sample_rt_tangent(nlevel, geometry.nmutot);
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Single,
        ..RadiativeTransferControls::default()
    };

    assert_tangent_matches_finite_difference(
        &base,
        &tangent_rt,
        controls,
        &geometry,
        nlevel,
        6,
        1.0e-6,
        2.0e-8,
    );
}

#[test]
fn multiple_scattering_tangent_matches_finite_difference() {
    let geometry = Geometry::init(2, 0.58, 0.64);
    let nlevel = 3;
    let base = sample_rt(nlevel, geometry.nmutot);
    let tangent_rt = sample_rt_tangent(nlevel, geometry.nmutot);
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::Multiple,
        performance_thresholds: RadiativeTransferPerformanceThresholds {
            threshold_conv_first: 0.0,
            threshold_conv_mult: 0.0,
            ..RadiativeTransferPerformanceThresholds::default()
        },
        ..RadiativeTransferControls::default()
    };

    assert_tangent_matches_finite_difference(
        &base,
        &tangent_rt,
        controls,
        &geometry,
        nlevel,
        3,
        1.0e-6,
        5.0e-8,
    );
}
