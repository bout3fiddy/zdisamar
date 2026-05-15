use zdisamar::forward_model::{
    jacobian::{self, State},
    optical_properties::{
        shared::phase_functions,
        state_build::{
            EvaluatedLayer, OpticalDepthBreakdown, PreparedSublayer, SharedRtmGeometry,
            SharedRtmLayerGeometry, SharedRtmLevelGeometry, accumulate_breakdown,
            layer_input_from_evaluated,
        },
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

#[test]
fn optical_depth_breakdown_computes_totals_and_single_scatter_albedo() {
    let mut totals = OpticalDepthBreakdown {
        gas_absorption_optical_depth: 0.2,
        gas_scattering_optical_depth: 0.03,
        ..OpticalDepthBreakdown::default()
    };
    accumulate_breakdown(
        &mut totals,
        OpticalDepthBreakdown {
            cia_optical_depth: 0.01,
            aerosol_optical_depth: 0.12,
            aerosol_scattering_optical_depth: 0.08,
            cloud_optical_depth: 0.2,
            cloud_scattering_optical_depth: 0.05,
            ..OpticalDepthBreakdown::default()
        },
    );

    assert_close(totals.total_optical_depth(), 0.56, 1.0e-14);
    assert_close(totals.total_scattering_optical_depth(), 0.16, 1.0e-14);
    assert_close(totals.single_scatter_albedo(), 0.16 / 0.56, 1.0e-14);
    assert_close(
        OpticalDepthBreakdown::default().single_scatter_albedo(),
        0.0,
        0.0,
    );
}

#[test]
fn evaluated_layer_maps_to_radiative_transfer_input() {
    let mut phase = phase_functions::gas_phase_coefficients();
    phase[2] = 0.25;
    let evaluated = EvaluatedLayer {
        breakdown: OpticalDepthBreakdown {
            gas_absorption_optical_depth: 0.2,
            gas_scattering_optical_depth: 0.03,
            cia_optical_depth: 0.01,
            aerosol_optical_depth: 0.12,
            aerosol_scattering_optical_depth: 0.08,
            cloud_optical_depth: 0.2,
            cloud_scattering_optical_depth: 0.05,
        },
        phase_coefficients: phase,
        solar_mu: 0.61,
        view_mu: 0.72,
    };

    let layer = layer_input_from_evaluated(evaluated);

    assert_close(layer.optical_depth, 0.56, 1.0e-14);
    assert_close(layer.scattering_optical_depth, 0.16, 1.0e-14);
    assert_close(layer.single_scatter_albedo, 0.16 / 0.56, 1.0e-14);
    assert_eq!(layer.phase_coefficients, phase);
    assert_close(layer.solar_mu, 0.61, 0.0);
    assert_close(layer.view_mu, 0.72, 0.0);
    assert_close(
        jacobian::get(layer.optical_depth_jacobian, State::AerosolOpticalDepth),
        0.0,
        0.0,
    );
}

#[test]
fn prepared_sublayer_and_shared_geometry_match_zig_defaults() {
    let sublayer = PreparedSublayer {
        oxygen_number_density_cm3: 2.0,
        ..PreparedSublayer::default()
    };
    assert_close(sublayer.cia_pair_density_cm6_value(), 4.0, 0.0);
    let explicit_pair_density = PreparedSublayer {
        oxygen_number_density_cm3: 2.0,
        cia_pair_density_cm6: 7.0,
        ..PreparedSublayer::default()
    };
    assert_close(explicit_pair_density.cia_pair_density_cm6_value(), 7.0, 0.0);

    let geometry = SharedRtmGeometry {
        layers: vec![
            SharedRtmLayerGeometry::default(),
            SharedRtmLayerGeometry::default(),
        ],
        levels: vec![
            SharedRtmLevelGeometry::default(),
            SharedRtmLevelGeometry::default(),
            SharedRtmLevelGeometry::default(),
        ],
    };
    assert!(geometry.is_valid_for(2));
    assert!(!geometry.is_valid_for(1));
    assert_eq!(
        SharedRtmLevelGeometry::default().particle_above_support_row_index,
        u32::MAX
    );
}
