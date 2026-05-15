use zdisamar::{
    forward_model::{
        instrument_grid::grid_calculation::storage::{
            Buffers, Error, pseudo_spherical_sample_count_hint,
            resolved_pseudo_spherical_sample_count, transport_layer_count_hint, validate_buffers,
        },
        jacobian,
        optical_properties::state_build::{
            PreparedLayer, PreparedOpticalState, PreparedSublayer, SharedRtmGeometry,
            SharedRtmLayerGeometry,
        },
        radiative_transfer::common_types::{
            ExecutionMode, LayerInput, RadiativeTransferControls, Route, RtmQuadratureLevel,
            SourceInterfaceInput, TransportFamily,
        },
    },
    input::{
        atmosphere::{IntervalSemantics, VerticalInterval},
        instrument::IntegrationMode,
        observation_model::ObservationRegime,
        scene::{DerivativeMode, Scene},
    },
};

fn route() -> Route {
    Route {
        family: TransportFamily::Labos,
        regime: ObservationRegime::Nadir,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::None,
        derivative_state_mask: 0,
        rtm_controls: RadiativeTransferControls::default(),
    }
}

#[test]
fn storage_hints_match_layer_and_interval_rules() {
    let mut scene = Scene::default();
    scene.atmosphere.layer_count = 2;
    scene.atmosphere.sublayer_divisions = 3;

    assert_eq!(transport_layer_count_hint(&scene, route()), 6);
    assert_eq!(pseudo_spherical_sample_count_hint(&scene, route()), 30);

    scene.atmosphere.interval_grid.intervals = vec![
        VerticalInterval {
            altitude_divisions: 2,
            ..VerticalInterval::default()
        },
        VerticalInterval {
            altitude_divisions: 3,
            ..VerticalInterval::default()
        },
    ];
    assert_eq!(transport_layer_count_hint(&scene, route()), 5);

    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .response
        .integration_mode = IntegrationMode::DisamarHrGrid;
    assert_eq!(transport_layer_count_hint(&scene, route()), 7);
}

#[test]
fn storage_resolved_pseudo_spherical_count_uses_prepared_shared_geometry() {
    let mut scene = Scene::default();
    scene.atmosphere.sublayer_divisions = 3;
    let prepared = PreparedOpticalState {
        interval_semantics: IntervalSemantics::ExplicitPressureBounds,
        layers: vec![
            PreparedLayer {
                sublayer_count: 3,
                ..PreparedLayer::default()
            },
            PreparedLayer {
                sublayer_count: 3,
                ..PreparedLayer::default()
            },
        ],
        sublayers: Some(vec![
            PreparedSublayer::default(),
            PreparedSublayer::default(),
            PreparedSublayer::default(),
        ]),
        shared_rtm_geometry: SharedRtmGeometry {
            layers: vec![
                SharedRtmLayerGeometry {
                    support_count: 4,
                    ..SharedRtmLayerGeometry::default()
                },
                SharedRtmLayerGeometry {
                    support_count: 2,
                    ..SharedRtmLayerGeometry::default()
                },
            ],
            levels: vec![Default::default(), Default::default(), Default::default()],
        },
        ..PreparedOpticalState::default()
    };

    assert_eq!(
        resolved_pseudo_spherical_sample_count(&scene, route(), &prepared),
        2,
    );
}

#[test]
fn storage_validate_buffers_checks_required_and_optional_shapes() {
    let sample_count = 3;
    let scalar = vec![0.0; sample_count];
    let layers = vec![LayerInput::default(); 2];
    let pseudo_layers = vec![LayerInput::default(); 4];
    let source_interfaces = vec![SourceInterfaceInput::default(); 3];
    let rtm_levels = vec![RtmQuadratureLevel::default(); 3];
    let pseudo_samples = vec![Default::default(); 4];
    let level_starts = vec![0; 3];
    let level_altitudes = vec![0.0; 3];
    let jacobian_values = vec![0.0; sample_count * jacobian::STATE_COUNT];
    let buffers = Buffers {
        wavelengths: &scalar,
        radiance: &scalar,
        irradiance: &scalar,
        reflectance: &scalar,
        scratch: &scalar,
        scratch_aux: &scalar,
        layer_inputs: &layers,
        pseudo_spherical_layers: &pseudo_layers,
        source_interfaces: &source_interfaces,
        rtm_quadrature_levels: &rtm_levels,
        pseudo_spherical_samples: &pseudo_samples,
        pseudo_spherical_level_starts: &level_starts,
        pseudo_spherical_level_altitudes: &level_altitudes,
        jacobian: Some(&jacobian_values),
        noise_sigma: Some(&scalar),
        radiance_noise_sigma: None,
        irradiance_noise_sigma: None,
        reflectance_noise_sigma: None,
    };

    assert_eq!(validate_buffers(sample_count, &buffers), Ok(()));

    let short_jacobian = vec![0.0; 1];
    let bad_buffers = Buffers {
        jacobian: Some(&short_jacobian),
        ..buffers
    };
    assert_eq!(
        validate_buffers(sample_count, &bad_buffers),
        Err(Error::ShapeMismatch),
    );
}
