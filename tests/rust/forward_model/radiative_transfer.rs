use zdisamar::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::shared::phase_functions,
        radiative_transfer::{
            common_route,
            common_types::{
                DerivativeSemantics, DispatchRequest, Error, ExecutionMode, LayerInput,
                PseudoSphericalGrid, PseudoSphericalSample, RadiativeTransferControls,
                RadiativeTransferPerformanceThresholds, ScatteringMode, SourceInterfaceInput,
                TransportFamily,
            },
            derivatives,
        },
    },
    input::{observation_model::ObservationRegime, scene::DerivativeMode},
};

#[test]
fn jacobian_vectors_and_masks_follow_state_order() {
    let mut vector = jacobian::zero();
    jacobian::set(&mut vector, State::AerosolOpticalDepth, 2.0);
    assert_eq!(jacobian::get(vector, State::AerosolOpticalDepth), 2.0);
    assert!(jacobian::includes(
        jacobian::state_mask(State::SurfaceAlbedo)
            | jacobian::state_mask(State::AerosolOpticalDepth),
        State::SurfaceAlbedo
    ));
    assert_eq!(jacobian::sanitized_mask(0xff), jacobian::ALL_STATES_MASK);
    jacobian::add_scaled(&mut vector, [1.0, 1.0, 1.0], 0.5);
    assert_eq!(vector, [0.5, 2.5, 0.5]);
    assert_eq!(jacobian::scale(vector, 2.0), [1.0, 5.0, 1.0]);
}

#[test]
fn radiative_transfer_controls_validate_vendor_limits() {
    let controls = RadiativeTransferControls::default();
    assert_eq!(controls.validate(ExecutionMode::Scalar), Ok(()));
    assert_eq!(controls.n_gauss(), 8);
    assert_eq!(controls.n_directions(), 10);
    assert_eq!(controls.supermatrix_size(), 10);
    assert_eq!(controls.resolved_num_orders_max(3.5), 18);

    assert_eq!(
        RadiativeTransferControls {
            n_streams: 12,
            ..controls
        }
        .validate(ExecutionMode::Scalar),
        Err(Error::UnsupportedRadiativeTransferControls)
    );
    assert_eq!(
        RadiativeTransferControls {
            scattering: ScatteringMode::Single,
            use_adding: true,
            ..controls
        }
        .validate(ExecutionMode::Scalar),
        Err(Error::UnsupportedRadiativeTransferControls)
    );
    assert_eq!(
        RadiativeTransferPerformanceThresholds {
            threshold_mul: 0.0,
            ..RadiativeTransferPerformanceThresholds::default()
        }
        .validate(),
        Err(Error::UnsupportedRadiativeTransferControls)
    );
}

#[test]
fn route_preparation_rejects_unsupported_modes_and_reports_semantics() {
    let route = common_route::prepare_route(DispatchRequest {
        derivative_mode: DerivativeMode::SemiAnalytical,
        ..DispatchRequest::default()
    })
    .unwrap();
    assert_eq!(route.family, TransportFamily::Labos);
    assert_eq!(
        route.derivative_semantics(),
        DerivativeSemantics::Analytical
    );
    assert_eq!(route.family.provenance_label(), "baseline_labos");

    assert_eq!(
        common_route::prepare_route(DispatchRequest {
            regime: ObservationRegime::Limb,
            ..DispatchRequest::default()
        }),
        Err(Error::UnsupportedObservationRegime)
    );
    assert_eq!(
        common_route::prepare_route(DispatchRequest {
            derivative_mode: DerivativeMode::Numerical,
            ..DispatchRequest::default()
        }),
        Err(Error::UnsupportedDerivativeMode)
    );
}

#[test]
fn source_interfaces_derive_boundary_weights_from_layers() {
    let mut phase = phase_functions::zero_phase_coefficients();
    phase[1] = 0.4;
    let layers = vec![
        LayerInput {
            scattering_optical_depth: 2.0,
            phase_coefficients: phase,
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: -1.0,
            ..LayerInput::default()
        },
    ];
    let top = common_route::source_interface_from_layers(&layers, 0);
    assert_eq!(top.source_weight, 2.0);
    assert_eq!(top.particle_ksca_below, 0.0);
    assert_eq!(top.phase_coefficients_above[1], 0.4);

    let bottom = common_route::source_interface_from_layers(&layers, 2);
    assert_eq!(bottom.source_weight, 0.0);
    assert_eq!(bottom.ksca_below, 0.0);

    let mut interfaces = vec![SourceInterfaceInput::default(); 3];
    common_route::fill_source_interfaces_from_layers(&layers, &mut interfaces);
    assert_eq!(interfaces[0].source_weight, 2.0);
    assert_eq!(interfaces[2].source_weight, 0.0);
}

#[test]
fn pseudo_spherical_grid_and_derivative_helpers_match_zig_contracts() {
    let grid = PseudoSphericalGrid {
        samples: vec![
            PseudoSphericalSample::default(),
            PseudoSphericalSample::default(),
        ],
        level_sample_starts: vec![0, 1, 2],
        level_altitudes_km: vec![0.0, 1.0, 2.0],
    };
    assert!(grid.is_valid_for(2));
    assert!(!PseudoSphericalGrid::default().is_valid_for(0));

    assert_eq!(derivatives::transmittance(0.0), 1.0);
    assert_eq!(derivatives::d_transmittance_d_optical_depth(0.0), -1.0);
    assert_eq!(
        derivatives::proxy_optical_depth_sensitivity(2.0, 3.0, 4.0, 5.0),
        -23.0
    );
    assert!((derivatives::proxy_jacobian_column(2.0, 0.0, 0.5) + 3.0).abs() < 1.0e-14);
}
