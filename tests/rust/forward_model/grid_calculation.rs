use zdisamar::{
    forward_model::{
        implementations::{
            instrument::{
                DEFAULT_SLIT_KERNEL, GENERIC_RESPONSE_ID, integration_for_wavelength_checked,
                resolve,
            },
            noise as noise_provider, root as implementation_root,
        },
        instrument_grid::grid_calculation::cache::SpectralEvaluationCache,
        instrument_grid::grid_calculation::forward_input::{
            ForwardInputBuffers, configured_forward_input,
        },
        instrument_grid::grid_calculation::postprocess::{
            apply_channel_corrections, apply_channel_jacobian_corrections,
            materialize_channel_sigma,
        },
        instrument_grid::grid_calculation::product as grid_product,
        instrument_grid::grid_calculation::simulate::simulate_product,
        instrument_grid::grid_calculation::spectral_eval::{
            IntegrationKernel, cached_irradiance_at_wavelength, integrate_forward_at_nominal,
            integrate_irradiance_at_nominal,
        },
        instrument_grid::grid_calculation::spectral_forward::compute_forward_sample_at_wavelength,
        instrument_grid::grid_calculation::storage::{
            Buffers, Error as StorageError, ProductStorage, SummaryStorage,
            pseudo_spherical_sample_count_hint, resolved_pseudo_spherical_sample_count,
            transport_layer_count_hint, validate_buffers,
        },
        instrument_grid::grid_calculation::wavelength_plan::{
            ForwardCacheMiss, WavelengthSampling,
        },
        instrument_grid::grid_calculation::wavelength_sampling::{
            build_wavelength_sampling, collect_unique_forward_misses,
        },
        instrument_grid::spectral_math::{
            calibration::Calibration,
            grid::{ResolvedAxis, SpectralGrid},
        },
        jacobian,
        method::Method,
        optical_properties::shared::phase_functions,
        optical_properties::state_build::{
            PreparedLayer, PreparedOpticalState, PreparedSublayer, SharedOpticalCarrier,
            SharedRtmGeometry, SharedRtmLayerGeometry,
        },
        radiative_transfer::common_types::{
            ExecutionMode, LayerInput, PseudoSphericalSample, RadiativeTransferControls, Route,
            RtmQuadratureLevel, ScatteringMode, SourceInterfaceInput, TransportFamily,
        },
        run_spectrum,
    },
    input::{
        atmosphere::{IntervalSemantics, VerticalInterval},
        instrument::{
            InstrumentLineShape, IntegrationMode, NoiseModelKind, SlitIndex, SpectralChannel,
        },
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
fn summary_storage_allocates_reusable_buffers_and_invalidates_plan_state() {
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 762.0;
    scene.spectral_grid.sample_count = 3;
    scene.atmosphere.layer_count = 2;
    scene.atmosphere.sublayer_divisions = 1;
    let mut storage = SummaryStorage::default();

    {
        let buffers = storage.buffers(&scene, route(), implementation_root::exact());
        assert_eq!(buffers.wavelengths.len(), 3);
        assert_eq!(buffers.radiance.len(), 3);
        assert_eq!(buffers.layer_inputs.len(), 2);
        assert_eq!(buffers.source_interfaces.len(), 3);
        assert!(buffers.jacobian.is_none());
        assert!(buffers.noise_sigma.is_none());
    }
    assert_eq!(storage.wavelengths.len(), 3);
    assert_eq!(storage.layer_inputs.len(), 2);

    storage.evaluation_cache.put_irradiance(760.0, 1.0);
    assert_eq!(storage.evaluation_cache.irradiance_len(), 1);
    assert_eq!(storage.spectral_cache().irradiance_len(), 0);

    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .noise
        .enabled = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .noise
        .model = NoiseModelKind::ShotNoise;
    let mut derivative_route = route();
    derivative_route.derivative_mode = DerivativeMode::SemiAnalytical;
    {
        let buffers = storage.buffers(&scene, derivative_route, implementation_root::exact());
        assert_eq!(buffers.jacobian.unwrap().len(), 3 * jacobian::STATE_COUNT);
        assert_eq!(buffers.noise_sigma.unwrap().len(), 3);
        assert_eq!(buffers.radiance_noise_sigma.unwrap().len(), 3);
        assert_eq!(buffers.irradiance_noise_sigma.unwrap().len(), 3);
        assert_eq!(buffers.reflectance_noise_sigma.unwrap().len(), 3);
    }

    storage.wavelength_sampling.push(WavelengthSampling {
        nominal_wavelength_nm: 760.0,
        radiance_wavelength_nm: 760.0,
        irradiance_wavelength_nm: 760.0,
        radiance_integration: IntegrationKernel::disabled(),
        irradiance_integration: IntegrationKernel::disabled(),
    });
    storage.forward_misses.push(ForwardCacheMiss {
        key: SpectralEvaluationCache::key_for(760.0),
        wavelength_nm: 760.0,
    });
    storage.wavelength_plan_key = 42;
    storage.wavelength_plan_valid = true;
    storage.forward_misses_valid = true;
    storage.profile_spectroscopy_cache_key = 24;
    storage.profile_spectroscopy_cache_valid = true;

    storage.invalidate_wavelength_plan();

    assert!(storage.wavelength_sampling.is_empty());
    assert!(storage.forward_misses.is_empty());
    assert_eq!(storage.wavelength_plan_key, 0);
    assert!(!storage.wavelength_plan_valid);
    assert!(!storage.forward_misses_valid);
    assert_eq!(storage.profile_spectroscopy_cache_key, 0);
    assert!(!storage.profile_spectroscopy_cache_valid);

    let _: ProductStorage = SummaryStorage::default();
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
    let mut support_valid = vec![false; 2];
    let mut support_carriers = vec![SharedOpticalCarrier::default(); 2];

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
            support_carrier_valid: &mut support_valid,
            support_carriers: &mut support_carriers,
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
    let mut support_valid = vec![false; 5];
    let mut support_carriers = vec![SharedOpticalCarrier::default(); 5];

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
            support_carrier_valid: &mut support_valid,
            support_carriers: &mut support_carriers,
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
    let mut support_valid = vec![false; 1];
    let mut support_carriers = vec![SharedOpticalCarrier::default(); 1];

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
            support_carrier_valid: &mut support_valid,
            support_carriers: &mut support_carriers,
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
fn spectral_eval_caches_forward_and_integrates_kernel_samples() {
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
    let mut support_valid = vec![false; 1];
    let mut support_carriers = vec![SharedOpticalCarrier::default(); 1];
    let mut buffers = ForwardInputBuffers {
        layer_inputs: &mut layers,
        pseudo_spherical_layers: &mut pseudo_layers,
        source_interfaces: &mut source_interfaces,
        rtm_quadrature_levels: &mut rtm_levels,
        pseudo_spherical_samples: &mut pseudo_samples,
        pseudo_spherical_level_starts: &mut pseudo_starts,
        pseudo_spherical_level_altitudes: &mut pseudo_altitudes,
        support_carrier_valid: &mut support_valid,
        support_carriers: &mut support_carriers,
    };
    let mut cache = SpectralEvaluationCache::default();
    let integration = IntegrationKernel::from_samples(vec![-1.0, 1.0], vec![0.25, 0.75]);

    let sample = integrate_forward_at_nominal(
        &scene,
        route,
        &prepared,
        760.0,
        &mut buffers,
        &mut cache,
        &integration,
    )
    .unwrap();
    let irradiance =
        integrate_irradiance_at_nominal(&scene, 760.0, &mut cache, &integration).unwrap();
    let expected_radiance = 0.23 * irradiance / std::f64::consts::PI;

    assert_close(sample.radiance, expected_radiance, 1.0);
    assert_eq!(sample.jacobian, jacobian::zero());
    assert_eq!(cache.forward_len(), 2);
    assert_eq!(cache.irradiance_len(), 2);

    let cached = cached_irradiance_at_wavelength(&scene, 759.0, &mut cache);
    assert_close(
        cached,
        zdisamar::input::reference::solar_irradiance::irradiance_at_wavelength(&scene, 759.0),
        0.0,
    );
    assert_eq!(cache.irradiance_len(), 2);
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

#[test]
fn simulate_product_uses_resolved_line_shape_integration_kernels() {
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
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    let line_shape = InstrumentLineShape {
        sample_count: 2,
        offsets_nm: vec![-1.0, 1.0],
        weights: vec![1.0, 3.0],
    };
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
        .instrument_line_shape = line_shape.clone();
    scene
        .observation_model
        .measurement_pipeline
        .irradiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .irradiance
        .response
        .instrument_line_shape = line_shape;
    let kernel = integration_for_wavelength_checked(
        &scene,
        Some(&prepared),
        SpectralChannel::Radiance,
        760.0,
    )
    .unwrap();
    assert!(kernel.enabled);
    assert_eq!(kernel.sample_count, 2);
    assert_close(kernel.weights[0], 0.25, 1.0e-14);
    assert_close(kernel.weights[1], 0.75, 1.0e-14);
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;

    let product = simulate_product(&scene, route, &prepared).unwrap();

    for reflectance in product.reflectance {
        assert_close(reflectance, 0.23, 1.0e-14);
    }
}

#[test]
fn simulate_product_applies_radiance_channel_corrections() {
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
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .multiplicative_offset = 2.0;
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;

    let product = simulate_product(&scene, route, &prepared).unwrap();

    for reflectance in product.reflectance {
        assert_close(reflectance, 0.46, 1.0e-14);
    }
    assert_close(product.summary.mean_reflectance, 0.46, 1.0e-14);
}

#[test]
fn product_wrapper_uses_explicit_implementation_bindings() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        }]),
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.surface.albedo = 0.19;
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;

    let product =
        grid_product::simulate_product(&scene, route, &prepared, implementation_root::exact())
            .unwrap();

    assert_close(product.summary.mean_reflectance, 0.19, 1.0e-14);
    assert_eq!(product.wavelengths, vec![760.0, 761.0]);
}

#[test]
fn product_workspace_warms_sampling_and_returns_borrowed_view() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        }]),
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.surface.albedo = 0.21;
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    let mut route = route();
    route.rtm_controls.scattering = ScatteringMode::None;
    route.rtm_controls.integrate_source_function = false;
    let mut storage = ProductStorage::default();

    grid_product::warm_product_workspace(
        &mut storage,
        &scene,
        route,
        &prepared,
        implementation_root::exact(),
    )
    .unwrap();

    assert!(storage.wavelength_plan_valid);
    assert!(storage.forward_misses_valid);
    assert_eq!(storage.wavelength_sampling.len(), 2);
    assert_eq!(storage.forward_misses.len(), 2);

    let view = grid_product::simulate_product_with_workspace(
        &mut storage,
        &scene,
        route,
        &prepared,
        implementation_root::exact(),
    )
    .unwrap();
    assert_eq!(view.wavelengths, &[760.0, 761.0]);
    assert_close(view.summary.mean_reflectance, 0.21, 1.0e-14);
    assert_eq!(view.to_owned().reflectance, vec![0.21, 0.21]);
}

#[test]
fn generic_instrument_provider_matches_scene_controls() {
    let provider = resolve(GENERIC_RESPONSE_ID).unwrap();
    assert_eq!(provider.id, GENERIC_RESPONSE_ID);

    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 762.0;
    scene.spectral_grid.sample_count = 5;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .multiplicative_offset = 1.25;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .additive_offset = 0.5;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .wavelength_shift_nm = 0.03;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .stray_light = 0.02;

    let calibration = (provider.calibration_for_scene)(&scene, SpectralChannel::Radiance);
    assert_close(calibration.gain, 1.25, 0.0);
    assert_close(calibration.offset, 0.5, 0.0);
    assert_close(calibration.wavelength_shift_nm, 0.03, 0.0);
    assert_close(calibration.stray_light, 0.02, 0.0);
    assert!(!(provider.uses_integrated_sampling)(
        &scene,
        SpectralChannel::Radiance
    ));
    assert_eq!(
        (provider.slit_kernel_for_scene)(&scene, SpectralChannel::Radiance),
        DEFAULT_SLIT_KERNEL
    );

    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .response
        .fwhm_nm = 0.6;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .response
        .slit_index = SlitIndex::GaussianModulated;
    assert!((provider.uses_integrated_sampling)(
        &scene,
        SpectralChannel::Radiance
    ));

    let integration =
        (provider.integration_for_wavelength)(&scene, None, SpectralChannel::Radiance, 761.0)
            .unwrap();
    assert!(integration.enabled);
    assert_eq!(integration.sample_count, 5);

    let slit_kernel = (provider.slit_kernel_for_scene)(&scene, SpectralChannel::Radiance);
    assert_close(slit_kernel.iter().sum::<f64>(), 1.0, 1.0e-14);
    assert!(slit_kernel[2] > slit_kernel[1]);
    assert!(slit_kernel[1] > slit_kernel[0]);
}

#[test]
fn noise_provider_materializes_scene_and_zero_sigma() {
    let scene_provider = noise_provider::resolve(noise_provider::SCENE_NOISE_ID).unwrap();
    let none_provider = noise_provider::resolve(noise_provider::NONE_NOISE_ID).unwrap();
    assert_eq!(scene_provider.id, noise_provider::SCENE_NOISE_ID);
    assert_eq!(none_provider.id, noise_provider::NONE_NOISE_ID);

    let mut scene = Scene::default();
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .noise
        .enabled = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .noise
        .model = NoiseModelKind::ShotNoise;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .noise
        .electrons_per_count = 4.0;

    assert!((scene_provider.materializes_sigma)(
        &scene,
        SpectralChannel::Radiance
    ));
    let wavelengths_nm = [760.0, 761.0];
    let signal = [4.0, 9.0];
    let mut output = [0.0, 0.0];
    (scene_provider.materialize_sigma)(
        &scene,
        SpectralChannel::Radiance,
        &wavelengths_nm,
        &signal,
        &mut output,
    )
    .unwrap();
    assert_close(output[0], 1.0, 1.0e-14);
    assert_close(output[1], 1.5, 1.0e-14);

    assert!(!(none_provider.materializes_sigma)(
        &scene,
        SpectralChannel::Radiance
    ));
    output = [-1.0, -1.0];
    (none_provider.materialize_sigma)(
        &scene,
        SpectralChannel::Radiance,
        &wavelengths_nm,
        &signal,
        &mut output,
    )
    .unwrap();
    assert_eq!(output, [0.0, 0.0]);
}

#[test]
fn postprocess_applies_channel_corrections_and_noise_materialization() {
    let mut scene = Scene::default();
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .simple_offsets
        .multiplicative_percent = 10.0;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .simple_offsets
        .additive_percent_of_first = 5.0;
    let wavelengths_nm = [760.0, 761.0];
    let mut signal = [10.0, 20.0];
    let mut scratch = [0.0, 0.0];

    apply_channel_corrections(
        &scene,
        SpectralChannel::Radiance,
        Calibration {
            gain: 2.0,
            offset: 1.0,
            wavelength_shift_nm: 0.0,
            stray_light: 0.0,
        },
        0.0,
        &wavelengths_nm,
        &mut signal,
        &mut scratch,
    )
    .unwrap();

    assert_close(signal[0], 24.15, 1.0e-14);
    assert_close(signal[1], 46.15, 1.0e-14);

    let mut jacobian = [10.0, 20.0];
    apply_channel_jacobian_corrections(
        &scene,
        SpectralChannel::Radiance,
        Calibration {
            gain: 2.0,
            offset: 1.0,
            wavelength_shift_nm: 0.0,
            stray_light: 0.0,
        },
        0.0,
        &wavelengths_nm,
        &mut jacobian,
        &mut scratch,
    )
    .unwrap();
    assert_close(jacobian[0], 23.0, 1.0e-14);
    assert_close(jacobian[1], 45.0, 1.0e-14);

    let none_provider = noise_provider::resolve(noise_provider::NONE_NOISE_ID).unwrap();
    let mut sigma = [-1.0, -1.0];
    materialize_channel_sigma(
        none_provider,
        &scene,
        SpectralChannel::Radiance,
        &wavelengths_nm,
        &signal,
        &mut sigma,
    )
    .unwrap();
    assert_eq!(sigma, [0.0, 0.0]);
}

#[test]
fn wavelength_sampling_applies_channel_shift_and_collects_forward_misses() {
    let provider = resolve(GENERIC_RESPONSE_ID).unwrap();
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .explicit = true;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .wavelength_shift_nm = 0.1;
    scene
        .observation_model
        .measurement_pipeline
        .radiance
        .response
        .instrument_line_shape = InstrumentLineShape {
        sample_count: 2,
        offsets_nm: vec![-0.1, 0.2],
        weights: vec![1.0, 3.0],
    };
    let axis = ResolvedAxis {
        base: SpectralGrid {
            start_nm: scene.spectral_grid.start_nm,
            end_nm: scene.spectral_grid.end_nm,
            sample_count: scene.spectral_grid.sample_count,
        },
        explicit_wavelengths_nm: Vec::new(),
    };

    let plans =
        build_wavelength_sampling(&scene, &axis, &PreparedOpticalState::default(), provider)
            .unwrap();

    assert_eq!(plans.len(), 2);
    assert_close(plans[0].nominal_wavelength_nm, 760.0, 0.0);
    assert_close(plans[0].radiance_wavelength_nm, 760.1, 1.0e-14);
    assert_close(plans[0].irradiance_wavelength_nm, 760.0, 0.0);
    assert_eq!(plans[0].radiance_integration.sample_count, 2);
    assert_close(plans[0].radiance_integration.weights[0], 0.25, 1.0e-14);
    assert_close(plans[0].radiance_integration.weights[1], 0.75, 1.0e-14);

    let misses = collect_unique_forward_misses(&plans);

    assert_eq!(misses.len(), 4);
    assert_close(misses[0].wavelength_nm, 760.0, 1.0e-14);
    assert_close(misses[1].wavelength_nm, 760.3, 1.0e-12);
    assert_close(misses[2].wavelength_nm, 761.0, 1.0e-14);
    assert_close(misses[3].wavelength_nm, 761.3, 1.0e-12);
    for miss in misses {
        assert_eq!(
            miss.key,
            SpectralEvaluationCache::key_for(miss.wavelength_nm)
        );
    }
}

#[test]
fn run_spectrum_exposes_exact_spectrum_product_path() {
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            altitude_km: 1.0,
            path_length_cm: 100_000.0,
            ..PreparedSublayer::default()
        }]),
        ..PreparedOpticalState::default()
    };
    let mut scene = Scene::default();
    scene.surface.albedo = 0.17;
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    let controls = RadiativeTransferControls {
        scattering: ScatteringMode::None,
        integrate_source_function: false,
        ..RadiativeTransferControls::default()
    };

    let product = run_spectrum::run(&scene, &prepared, Method::Exact, controls).unwrap();

    assert_eq!(product.wavelengths, vec![760.0, 761.0]);
    assert_close(product.summary.mean_reflectance, 0.17, 1.0e-14);
}
