use zdisamar::{
    forward_model::{
        implementations::{noise, surface, transport},
        radiative_transfer::{
            DerivativeSemantics, DispatchRequest, ExecutionMode, ForwardResult,
            ImplementationClass, ScatteringMode, TransportFamily,
        },
    },
    input::{
        InstrumentId, MeasurementPipeline, NoiseControls, NoiseModelKind, ObservationModel,
        OperationalReferenceGrid, Scene, SpectralChannel, SpectralChannelControls, SpectralGrid,
        Surface, SurfaceKind,
    },
};

fn assert_close(left: f64, right: f64) {
    assert!((left - right).abs() <= 1.0e-10, "{left} != {right}");
}

#[test]
fn noise_provider_resolution_matches_builtin_ids() {
    let scene_noise = noise::resolve("builtin.scene_noise").unwrap();
    assert_eq!(scene_noise.id, "builtin.scene_noise");
    assert!(noise::resolve("builtin.s5p_operational_noise").is_some());
    assert!(noise::resolve("unknown.noise").is_none());

    let scene = Scene {
        observation_model: ObservationModel {
            measurement_pipeline: MeasurementPipeline {
                radiance: SpectralChannelControls {
                    explicit: true,
                    noise: NoiseControls {
                        enabled: true,
                        model: NoiseModelKind::ShotNoise,
                        ..NoiseControls::default()
                    },
                    ..SpectralChannelControls::default()
                },
                ..MeasurementPipeline::default()
            },
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    assert!((scene_noise.materializes_sigma)(
        &scene,
        SpectralChannel::Radiance
    ));
}

#[test]
fn surface_provider_keeps_lambertian_directional_factor_isotropic() {
    let provider = surface::resolve("builtin.lambertian_surface").unwrap();
    assert_eq!(provider.id, "builtin.lambertian_surface");
    assert!(surface::resolve("unknown.surface").is_none());

    let mut scene = Scene {
        surface: Surface {
            kind: SurfaceKind::Lambertian,
            albedo: 0.2,
            ..Surface::default()
        },
        ..Scene::default()
    };
    let forward = ForwardResult {
        family: TransportFamily::Labos,
        regime: zdisamar::input::ObservationRegime::Nadir,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: zdisamar::input::DerivativeMode::None,
        toa_reflectance_factor: 0.3,
        jacobian: None,
    };

    assert_eq!(
        (provider.brdf_factor)(surface::EvaluationContext {
            scene: &scene,
            wavelength_nm: 760.0,
            safe_span: 1.0,
            phase: 0.0,
            forward,
        }),
        1.0
    );

    scene.surface.kind = SurfaceKind::WavelDependent;
    assert_eq!(
        (provider.brdf_factor)(surface::EvaluationContext {
            scene: &scene,
            wavelength_nm: 761.0,
            safe_span: 1.0,
            phase: 0.1,
            forward,
        }),
        1.0
    );
}

#[test]
fn transport_provider_prepares_labos_route_and_metadata() {
    let provider = transport::resolve("builtin.dispatcher").unwrap();
    assert_eq!(provider.id, "builtin.dispatcher");
    assert!(transport::resolve("unknown.transport").is_none());

    let route = (provider.prepare_route)(DispatchRequest::default()).unwrap();
    assert_eq!(route.family, TransportFamily::Labos);
    assert_eq!(
        (provider.classification_for_route)(route),
        ImplementationClass::Baseline
    );
    assert_eq!(
        (provider.provenance_label_for_route)(route),
        "baseline_labos"
    );
    assert_eq!(
        (provider.derivative_semantics_for_route)(route),
        DerivativeSemantics::None
    );

    let unsupported = DispatchRequest {
        execution_mode: ExecutionMode::Polarized,
        ..DispatchRequest::default()
    };
    assert!((provider.prepare_route)(unsupported).is_err());

    let unsupported = DispatchRequest {
        rtm_controls: zdisamar::forward_model::radiative_transfer::RadiativeTransferControls {
            scattering: ScatteringMode::Single,
            use_adding: true,
            ..Default::default()
        },
        ..DispatchRequest::default()
    };
    assert!((provider.prepare_route)(unsupported).is_err());
}

#[test]
fn s5p_operational_noise_reuses_ingested_reference_sigma() {
    let scene = Scene {
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            noise_model: NoiseModelKind::S5pOperational,
            measured_wavelengths_nm: vec![760.8, 761.0],
            reference_radiance: vec![10.0, 20.0],
            ingested_noise_sigma: vec![0.02, 0.03],
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    let signal = [40.0, 5.0];
    let mut sigma = [0.0; 2];

    noise::s5p_operational_sigma(
        &scene,
        SpectralChannel::Radiance,
        &[760.8, 761.0],
        &signal,
        &mut sigma,
    )
    .unwrap();

    assert_close(sigma[0], 0.04);
    assert_close(sigma[1], 0.015);
}

#[test]
fn s5p_operational_noise_uses_operational_reference_grid_spacing() {
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.8,
            end_nm: 761.2,
            sample_count: 5,
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            noise_model: NoiseModelKind::S5pOperational,
            reference_radiance: vec![10.0; 5],
            ingested_noise_sigma: vec![0.02; 5],
            operational_refspec_grid: OperationalReferenceGrid {
                wavelengths_nm: vec![760.8, 761.0, 761.2],
                weights: vec![0.15, 0.70, 0.15],
            },
            ..ObservationModel::default()
        },
        ..Scene::default()
    };

    let signal = [10.0; 5];
    let mut sigma = [0.0; 5];
    noise::s5p_operational_sigma(
        &scene,
        SpectralChannel::Radiance,
        &[760.8, 760.9, 761.0, 761.1, 761.2],
        &signal,
        &mut sigma,
    )
    .unwrap();

    assert_close(sigma[0], 0.028284271247461905);
    assert_close(sigma[4], 0.028284271247461905);
}

#[test]
fn s5p_operational_noise_falls_back_to_spectral_grid_spacing() {
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 761.0,
            sample_count: 3,
        },
        observation_model: ObservationModel {
            instrument: InstrumentId::Tropomi,
            noise_model: NoiseModelKind::S5pOperational,
            reference_radiance: vec![10.0, 20.0, 40.0],
            ingested_noise_sigma: vec![0.02, 0.03, 0.04],
            ..ObservationModel::default()
        },
        ..Scene::default()
    };

    let signal = [40.0, 80.0, 160.0];
    let mut sigma = [0.0; 3];
    noise::s5p_operational_sigma(
        &scene,
        SpectralChannel::Radiance,
        &[760.0, 760.25, 760.5],
        &signal,
        &mut sigma,
    )
    .unwrap();

    assert_close(sigma[0], 0.0565685424949238);
    assert_close(sigma[1], 0.0848528137423857);
    assert_close(sigma[2], 0.1131370849898476);
}

#[test]
fn lab_operational_noise_uses_explicit_channel_coefficients() {
    let scene = Scene {
        observation_model: ObservationModel {
            measurement_pipeline: MeasurementPipeline {
                radiance: SpectralChannelControls {
                    explicit: true,
                    noise: NoiseControls {
                        explicit: true,
                        enabled: true,
                        model: NoiseModelKind::LabOperational,
                        lab_a: 3.5e-6,
                        lab_b: 1500.0,
                        ..NoiseControls::default()
                    },
                    ..SpectralChannelControls::default()
                },
                ..MeasurementPipeline::default()
            },
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    let signal = [1.0e6, 1.5e6];
    let mut sigma = [0.0; 2];

    noise::lab_operational_sigma(
        &scene,
        SpectralChannel::Radiance,
        &[760.0, 761.0],
        &signal,
        &mut sigma,
    )
    .unwrap();

    assert!(sigma[0] > 0.0);
    assert!(sigma[1] > sigma[0]);
}
