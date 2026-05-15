use zdisamar::{
    forward_model::{
        instrument_grid::grid_calculation::forward_input::{
            ForwardInputBuffers, configured_forward_input,
        },
        instrument_grid::grid_calculation::simulate::simulate_product,
        instrument_grid::grid_calculation::spectral_forward::compute_forward_sample_at_wavelength,
        instrument_grid::grid_calculation::storage::{
            Buffers, Error as StorageError, pseudo_spherical_sample_count_hint,
            resolved_pseudo_spherical_sample_count, transport_layer_count_hint, validate_buffers,
        },
        jacobian,
        optical_properties::shared::phase_functions,
        optical_properties::state_build::{
            PreparedLayer, PreparedOpticalState, PreparedSublayer, SharedRtmGeometry,
            SharedRtmLayerGeometry,
        },
        radiative_transfer::common_types::{
            ExecutionMode, LayerInput, PseudoSphericalSample, RadiativeTransferControls, Route,
            RtmQuadratureLevel, ScatteringMode, SourceInterfaceInput, TransportFamily,
        },
    },
    input::{
        atmosphere::{IntervalSemantics, VerticalInterval},
        instrument::IntegrationMode,
        observation_model::ObservationRegime,
        reference_data::CrossSectionPoint,
        scene::{DerivativeMode, Scene},
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

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
        Err(StorageError::ShapeMismatch),
    );
}

#[test]
fn configured_forward_input_uses_source_interfaces_when_integrated_source_is_disabled() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![
            PreparedSublayer {
                altitude_km: 1.0,
                absorber_number_density_cm3: 2.0e18,
                path_length_cm: 100_000.0,
                aerosol_optical_depth: 0.1,
                aerosol_single_scatter_albedo: 0.5,
                ..PreparedSublayer::default()
            },
            PreparedSublayer {
                altitude_km: 2.0,
                absorber_number_density_cm3: 3.0e18,
                path_length_cm: 100_000.0,
                aerosol_optical_depth: 0.2,
                aerosol_single_scatter_albedo: 0.5,
                ..PreparedSublayer::default()
            },
        ]),
        continuum_points: vec![CrossSectionPoint {
            wavelength_nm: 760.0,
            sigma_cm2_per_molecule: 1.0e-24,
        }],
        aerosol_reference_wavelength_nm: 760.0,
        cloud_reference_wavelength_nm: 760.0,
        ..PreparedOpticalState::default()
    };
    let mut route = route();
    route.rtm_controls.integrate_source_function = false;
    let scene = Scene::default();
    let mut layers = vec![LayerInput::default(); 2];
    let mut pseudo_layers = vec![LayerInput::default(); 2];
    let mut source_interfaces = vec![SourceInterfaceInput::default(); 3];
    let mut rtm_levels = vec![RtmQuadratureLevel::default(); 3];
    let mut pseudo_samples = vec![PseudoSphericalSample::default(); 2];
    let mut pseudo_starts = vec![0; 3];
    let mut pseudo_altitudes = vec![0.0; 3];

    let input = configured_forward_input(
        &scene,
        route,
        &prepared,
        760.0,
        ForwardInputBuffers {
            layer_inputs: &mut layers,
            pseudo_spherical_layers: &mut pseudo_layers,
            source_interfaces: &mut source_interfaces,
            rtm_quadrature_levels: &mut rtm_levels,
            pseudo_spherical_samples: &mut pseudo_samples,
            pseudo_spherical_level_starts: &mut pseudo_starts,
            pseudo_spherical_level_altitudes: &mut pseudo_altitudes,
        },
    )
    .unwrap();

    assert_eq!(input.layers.len(), 2);
    assert_eq!(input.source_interfaces.len(), 3);
    assert!(input.rtm_quadrature.levels.is_empty());
    assert_close(input.layers[0].optical_depth, 0.3, 1.0e-14);
    assert_close(input.source_interfaces[1].rtm_weight, 1.0, 1.0e-14);
}

#[test]
fn configured_forward_input_attaches_rtm_quadrature_and_pseudo_spherical_grid() {
    let mut below_phase = phase_functions::zero_phase_coefficients();
    below_phase[1] = 0.2;
    let mut above_phase = phase_functions::zero_phase_coefficients();
    above_phase[1] = 0.8;
    let sublayers = vec![
        PreparedSublayer {
            global_sublayer_index: 0,
            altitude_km: 0.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 1,
            altitude_km: 1.0,
            absorber_number_density_cm3: 2.0e18,
            path_length_cm: 100_000.0,
            aerosol_optical_depth: 0.1,
            aerosol_single_scatter_albedo: 1.0,
            aerosol_phase_coefficients: below_phase,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 2,
            altitude_km: 2.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 3,
            altitude_km: 3.0,
            absorber_number_density_cm3: 4.0e18,
            path_length_cm: 100_000.0,
            aerosol_optical_depth: 0.3,
            aerosol_single_scatter_albedo: 1.0,
            aerosol_phase_coefficients: above_phase,
            ..PreparedSublayer::default()
        },
        PreparedSublayer {
            global_sublayer_index: 4,
            altitude_km: 4.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        },
    ];
    let mut prepared = PreparedOpticalState {
        layers: vec![
            PreparedLayer {
                sublayer_start_index: 0,
                sublayer_count: 3,
                bottom_altitude_km: 0.0,
                top_altitude_km: 2.0,
                interval_index_1based: 1,
                ..PreparedLayer::default()
            },
            PreparedLayer {
                sublayer_start_index: 2,
                sublayer_count: 3,
                bottom_altitude_km: 2.0,
                top_altitude_km: 4.0,
                interval_index_1based: 1,
                ..PreparedLayer::default()
            },
        ],
        sublayers: Some(sublayers),
        continuum_points: vec![CrossSectionPoint {
            wavelength_nm: 760.0,
            sigma_cm2_per_molecule: 1.0e-24,
        }],
        aerosol_optical_depth: 0.4,
        aerosol_reference_wavelength_nm: 760.0,
        cloud_reference_wavelength_nm: 760.0,
        interval_semantics: IntervalSemantics::ExplicitPressureBounds,
        ..PreparedOpticalState::default()
    };
    prepared.ensure_shared_rtm_geometry_cache().unwrap();
    let mut route = route();
    route.rtm_controls.use_spherical_correction = true;
    let mut scene = Scene::default();
    scene.atmosphere.sublayer_divisions = 1;
    let mut layers = vec![LayerInput::default(); 2];
    let mut pseudo_layers = vec![LayerInput::default(); 2];
    let mut source_interfaces = vec![SourceInterfaceInput::default(); 3];
    let mut rtm_levels = vec![RtmQuadratureLevel::default(); 3];
    let mut pseudo_samples = vec![PseudoSphericalSample::default(); 2];
    let mut pseudo_starts = vec![0; 3];
    let mut pseudo_altitudes = vec![0.0; 3];

    let input = configured_forward_input(
        &scene,
        route,
        &prepared,
        760.0,
        ForwardInputBuffers {
            layer_inputs: &mut layers,
            pseudo_spherical_layers: &mut pseudo_layers,
            source_interfaces: &mut source_interfaces,
            rtm_quadrature_levels: &mut rtm_levels,
            pseudo_spherical_samples: &mut pseudo_samples,
            pseudo_spherical_level_starts: &mut pseudo_starts,
            pseudo_spherical_level_altitudes: &mut pseudo_altitudes,
        },
    )
    .unwrap();

    assert_eq!(input.layers.len(), 2);
    assert!(input.source_interfaces.is_empty());
    assert!(input.rtm_quadrature.is_valid_for(2));
    assert!(input.pseudo_spherical_grid.is_valid_for(2));
    assert_close(input.rtm_quadrature.levels[1].ksca, 0.3, 1.0e-14);
    assert_close(
        input.pseudo_spherical_grid.samples[0].optical_depth,
        0.3,
        1.0e-14,
    );
    assert_close(
        input.pseudo_spherical_grid.samples[1].optical_depth,
        0.7,
        1.0e-14,
    );
    assert_eq!(input.rtm_controls, route.rtm_controls);
}

#[test]
fn compute_forward_sample_runs_configured_input_and_labos_radiance() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        }]),
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.surface.albedo = 0.23;
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;
    let mut layers = vec![LayerInput::default(); 1];
    let mut pseudo_layers = vec![LayerInput::default(); 1];
    let mut source_interfaces = vec![SourceInterfaceInput::default(); 2];
    let mut rtm_levels = vec![RtmQuadratureLevel::default(); 2];
    let mut pseudo_samples = vec![PseudoSphericalSample::default(); 1];
    let mut pseudo_starts = vec![0; 2];
    let mut pseudo_altitudes = vec![0.0; 2];

    let sample = compute_forward_sample_at_wavelength(
        &scene,
        route,
        &prepared,
        760.0,
        ForwardInputBuffers {
            layer_inputs: &mut layers,
            pseudo_spherical_layers: &mut pseudo_layers,
            source_interfaces: &mut source_interfaces,
            rtm_quadrature_levels: &mut rtm_levels,
            pseudo_spherical_samples: &mut pseudo_samples,
            pseudo_spherical_level_starts: &mut pseudo_starts,
            pseudo_spherical_level_altitudes: &mut pseudo_altitudes,
        },
    )
    .unwrap();

    assert_close(
        sample.radiance,
        0.23 * 4.87401e14 / std::f64::consts::PI,
        1.0,
    );
    assert_eq!(sample.jacobian, jacobian::zero());
}

#[test]
fn simulate_product_runs_forward_samples_on_scene_axis() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        }]),
        effective_air_mass_factor: 2.0,
        effective_single_scatter_albedo: 0.9,
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.surface.albedo = 0.23;
    scene.spectral_grid.start_nm = 759.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 3;
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;

    let product = simulate_product(&scene, route, &prepared).unwrap();

    assert_eq!(product.wavelengths, vec![759.0, 760.0, 761.0]);
    assert_eq!(product.radiance.len(), 3);
    assert_eq!(product.irradiance.len(), 3);
    assert_eq!(product.reflectance.len(), 3);
    for reflectance in product.reflectance {
        assert_close(reflectance, 0.23, 1.0e-14);
    }
    assert_close(product.summary.mean_reflectance, 0.23, 1.0e-14);
    assert_close(product.effective_air_mass_factor, 2.0, 0.0);
    assert_close(product.effective_single_scatter_albedo, 0.9, 0.0);
    assert!(product.jacobian.is_none());
}
