use zdisamar::forward_model::radiative_transfer::{
    common_types::{
        RadiativeTransferControls, RadiativeTransferPerformanceThresholds, ScatteringMode,
    },
    labos::{
        AttenuationLookup, Geometry, LayerRt, Mat, OrdersWorkspace, orders_scat_into,
        orders_scat_into_with_local_sum,
    },
};

struct UnitAtten;

impl AttenuationLookup for UnitAtten {
    fn get(&self, _imu: usize, _from: usize, _to: usize) -> f64 {
        1.0
    }
}

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
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
