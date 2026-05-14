use zdisamar::{
    forward_model::{
        jacobian::{self, State},
        optical_properties::shared::phase_functions,
        radiative_transfer::{
            self, DerivativeSemantics, Error, ExecutionMode, ForwardInput, ImplementationClass,
            LayerInput, RadiativeTransferControls, RadiativeTransferPerformanceThresholds, Route,
            ScatteringMode, SourceInterfaceInput, TransportFamily,
        },
    },
    input::{DerivativeMode, ObservationRegime, Scene},
};

fn assert_close(actual: f64, expected: f64) {
    assert!(
        (actual - expected).abs() < 1.0e-12,
        "{actual} != {expected}"
    );
}

#[test]
fn jacobian_vectors_support_state_masks_and_scaled_accumulation() {
    let mut vector = jacobian::zero();
    jacobian::set(&mut vector, State::AerosolOpticalDepth, 2.0);

    assert_eq!(jacobian::state_index(State::AerosolOpticalDepth), 1);
    assert!(jacobian::includes(
        jacobian::ALL_STATES_MASK,
        State::AerosolLayerMidPressureHpa
    ));
    assert_eq!(jacobian::get(vector, State::AerosolOpticalDepth), 2.0);
    assert_eq!(jacobian::sanitized_mask(0xff), jacobian::ALL_STATES_MASK);

    let mut accumulator = [1.0, 1.0, 1.0];
    jacobian::add_scaled(&mut accumulator, vector, 0.5);
    assert_eq!(accumulator, [1.0, 2.0, 1.0]);
    assert_eq!(jacobian::scale(accumulator, 2.0), [2.0, 4.0, 2.0]);
}

#[test]
fn phase_function_helpers_match_compact_and_hg_rules() {
    let compact = phase_functions::phase_coefficients_from_compact([1.0, 0.2, 0.3, 0.4]);

    assert_eq!(compact[0], 1.0);
    assert_eq!(compact[1], 0.2);
    assert_eq!(compact[3], 0.4);
    assert_eq!(phase_functions::max_phase_coefficient_index(compact), 3);
    assert!(phase_functions::hg_phase_coefficients(0.7)[1] > 0.0);
    assert_close(
        phase_functions::backscatter_fraction_from_asymmetry(0.4),
        0.3,
    );
}

#[test]
fn radiative_transfer_controls_validate_stream_and_threshold_contracts() {
    let controls = RadiativeTransferControls {
        n_streams: 20,
        ..RadiativeTransferControls::default()
    };

    assert_eq!(controls.validate(ExecutionMode::Scalar), Ok(()));
    assert_eq!(controls.n_gauss(), 10);
    assert_eq!(controls.n_directions(), 12);
    assert_eq!(controls.supermatrix_size(), 12);
    assert_eq!(controls.resolved_num_orders_max(2.0), 17);

    assert_eq!(
        RadiativeTransferControls {
            n_streams: 8,
            ..RadiativeTransferControls::default()
        }
        .validate(ExecutionMode::Scalar),
        Ok(())
    );
    assert_eq!(
        RadiativeTransferControls {
            n_streams: 14,
            ..RadiativeTransferControls::default()
        }
        .validate(ExecutionMode::Scalar),
        Err(Error::UnsupportedRadiativeTransferControls)
    );
    assert_eq!(
        RadiativeTransferControls {
            scattering: ScatteringMode::Single,
            use_adding: true,
            ..RadiativeTransferControls::default()
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
fn prepare_route_keeps_only_labos_scalar_paths_executable() {
    let route = radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
        regime: ObservationRegime::Nadir,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::None,
        ..radiative_transfer::DispatchRequest::default()
    })
    .unwrap();

    assert_eq!(route.family, TransportFamily::Labos);
    assert_eq!(route.family.classification(), ImplementationClass::Baseline);
    assert_eq!(route.family.provenance_label(), "baseline_labos");
    assert_eq!(route.derivative_semantics(), DerivativeSemantics::None);

    let jacobian_route = radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
        derivative_mode: DerivativeMode::SemiAnalytical,
        ..radiative_transfer::DispatchRequest::default()
    })
    .unwrap();
    assert_eq!(
        jacobian_route.derivative_semantics(),
        DerivativeSemantics::Analytical
    );

    assert_eq!(
        radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
            rtm_controls: RadiativeTransferControls {
                use_adding: true,
                ..RadiativeTransferControls::default()
            },
            ..radiative_transfer::DispatchRequest::default()
        }),
        Err(Error::UnsupportedTransportSolver)
    );
    assert_eq!(
        radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
            regime: ObservationRegime::Limb,
            ..radiative_transfer::DispatchRequest::default()
        }),
        Err(Error::UnsupportedObservationRegime)
    );
    assert_eq!(
        radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
            execution_mode: ExecutionMode::Polarized,
            ..radiative_transfer::DispatchRequest::default()
        }),
        Err(Error::UnsupportedExecutionMode)
    );
    assert_eq!(
        radiative_transfer::prepare_route(radiative_transfer::DispatchRequest {
            derivative_mode: DerivativeMode::Numerical,
            ..radiative_transfer::DispatchRequest::default()
        }),
        Err(Error::UnsupportedDerivativeMode)
    );
}

#[test]
fn dispatcher_prepares_and_executes_labos_routes() {
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::None,
        n_streams: 4,
        ..RadiativeTransferControls::default()
    };
    let request = radiative_transfer::DispatchRequest {
        rtm_controls: controls,
        ..radiative_transfer::DispatchRequest::default()
    };
    let input = ForwardInput {
        mu0: 0.8,
        muv: 0.5,
        optical_depth: 0.2,
        surface_albedo: 0.3,
        ..ForwardInput::default()
    };

    let result = radiative_transfer::dispatcher::execute(request, &input).unwrap();

    let direct =
        (-input.optical_depth / input.mu0).exp() * (-input.optical_depth / input.muv).exp();
    assert_close(result.toa_reflectance_factor, input.surface_albedo * direct);
    assert_eq!(result.family, TransportFamily::Labos);
    assert!(result.jacobian.is_none());

    let unsupported = Route {
        family: TransportFamily::Labos,
        regime: ObservationRegime::Limb,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::None,
        derivative_state_mask: jacobian::ALL_STATES_MASK,
        rtm_controls: controls,
    };
    assert_eq!(
        radiative_transfer::dispatcher::execute_prepared(unsupported, &input),
        Err(Error::UnsupportedObservationRegime)
    );
}

#[test]
fn source_interface_builder_preserves_boundary_weights() {
    let layers = vec![
        LayerInput {
            scattering_optical_depth: 0.20,
            phase_coefficients: phase_functions::phase_coefficients_from_compact([
                1.0, 0.10, 0.0, 0.0,
            ]),
            ..LayerInput::default()
        },
        LayerInput {
            scattering_optical_depth: 0.40,
            phase_coefficients: phase_functions::phase_coefficients_from_compact([
                1.0, 0.30, 0.0, 0.0,
            ]),
            ..LayerInput::default()
        },
    ];
    let mut source_interfaces = vec![SourceInterfaceInput::default(); 3];
    radiative_transfer::fill_source_interfaces_from_layers(&layers, &mut source_interfaces);

    assert_close(source_interfaces[0].source_weight, 0.20);
    assert_close(source_interfaces[1].source_weight, 0.40);
    assert_close(source_interfaces[2].source_weight, 0.20);
    assert_close(source_interfaces[0].phase_coefficients_above[1], 0.10);
    assert_close(source_interfaces[1].phase_coefficients_above[1], 0.30);
    assert_close(source_interfaces[2].phase_coefficients_above[1], 0.30);
    assert_close(source_interfaces[0].phase_coefficients_below[1], 0.0);
    assert_close(source_interfaces[1].phase_coefficients_below[1], 0.10);
    assert_close(source_interfaces[2].phase_coefficients_below[1], 0.30);
}

#[test]
fn route_and_scattering_helpers_cover_remaining_small_methods() {
    let route = Route {
        family: TransportFamily::Labos,
        regime: ObservationRegime::Nadir,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::SemiAnalytical,
        derivative_state_mask: jacobian::ALL_STATES_MASK,
        rtm_controls: RadiativeTransferControls::default(),
    };
    assert_eq!(
        route.derivative_semantics(),
        DerivativeSemantics::Analytical
    );

    let source = SourceInterfaceInput {
        source_weight: 0.5,
        rtm_weight: 2.0,
        ksca_above: 0.25,
        ..SourceInterfaceInput::default()
    };
    assert_close(source.effective_weight(), 0.5);

    let mut scene = Scene {
        spectral_grid: zdisamar::input::SpectralGrid {
            sample_count: 2,
            ..zdisamar::input::SpectralGrid::default()
        },
        ..Scene::default()
    };
    scene.atmosphere.has_aerosols = true;
    scene.aerosol.single_scatter_albedo = 0.7;
    let ssa = phase_functions::compute_single_scatter_albedo(&scene, 760.0);
    assert!((0.3..=0.999).contains(&ssa));
}
