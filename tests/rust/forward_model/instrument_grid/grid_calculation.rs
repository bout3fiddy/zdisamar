use zdisamar::{
    forward_model::{
        instrument_grid::grid_calculation::{
            cache::SpectralEvaluationCache,
            spectral_forward::{
                ForwardIntegratedSample, MIN_PARALLEL_FORWARD_MISS_COUNT, radiance_from_forward,
                radiance_jacobian_from_forward,
            },
            types::{
                FITTED_REFLECTANCE_EXPORT_NAME, InstrumentGridProductView, InstrumentGridSummary,
                REFLECTANCE_EXPORT_NAME,
            },
            wavelength_sampling::{build_wavelength_sampling, collect_unique_forward_misses},
        },
        instrument_grid::spectral_math::{calibration, grid},
        jacobian::{self, State},
        radiative_transfer::{ExecutionMode, ForwardResult, TransportFamily},
    },
    input::{
        Binding, DerivativeMode, Geometry, MeasurementPipeline, ObservationModel,
        ObservationRegime, Scene, SpectralChannelControls, SpectralGrid, SpectralResponse,
    },
};

fn assert_close(actual: f64, expected: f64) {
    let tolerance = expected.abs().max(1.0) * 1.0e-12;
    assert!(
        (actual - expected).abs() <= tolerance,
        "{actual} != {expected}"
    );
}

#[test]
fn instrument_grid_export_names_match_zig_constants() {
    assert_eq!(REFLECTANCE_EXPORT_NAME, "reflectance");
    assert_eq!(FITTED_REFLECTANCE_EXPORT_NAME, "fitted_reflectance");
}

#[test]
fn product_view_clones_all_measurement_columns() {
    let jacobian_values = [0.1, 0.2, 0.3];
    let view = InstrumentGridProductView {
        summary: InstrumentGridSummary {
            sample_count: 2,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 761.0,
            mean_radiance: 4.0,
            mean_irradiance: 8.0,
            mean_reflectance: 0.5,
            mean_noise_sigma: 0.02,
            mean_jacobian: Some([1.0, 2.0, 3.0]),
        },
        wavelengths: &[760.0, 761.0],
        radiance: &[3.0, 5.0],
        irradiance: &[6.0, 10.0],
        reflectance: &[0.5, 0.5],
        noise_sigma: &[0.01, 0.03],
        radiance_noise_sigma: &[0.01, 0.03],
        irradiance_noise_sigma: &[0.02, 0.04],
        reflectance_noise_sigma: &[0.001, 0.003],
        jacobian: Some(&jacobian_values),
        effective_air_mass_factor: 2.4,
        effective_single_scatter_albedo: 0.9,
        effective_temperature_k: 250.0,
        effective_pressure_hpa: 700.0,
        gas_optical_depth: 0.2,
        cia_optical_depth: 0.01,
        aerosol_optical_depth: 0.03,
        cloud_optical_depth: 0.04,
        total_optical_depth: 0.28,
        depolarization_factor: 0.02,
        d_optical_depth_d_temperature: 1.0e-4,
    };

    let product = view.to_owned_product();

    assert_eq!(product.summary.sample_count, 2);
    assert_eq!(product.wavelengths, vec![760.0, 761.0]);
    assert_eq!(product.radiance, vec![3.0, 5.0]);
    assert_eq!(product.irradiance_noise_sigma, vec![0.02, 0.04]);
    assert_eq!(product.jacobian, Some(vec![0.1, 0.2, 0.3]));
    assert_eq!(product.effective_air_mass_factor, 2.4);
}

#[test]
fn empty_product_view_owns_empty_vectors() {
    let product = InstrumentGridProductView::default().to_owned_product();

    assert_eq!(product.summary.sample_count, 0);
    assert!(product.wavelengths.is_empty());
    assert!(product.radiance.is_empty());
    assert!(product.jacobian.is_none());
}

#[test]
fn spectral_cache_uses_exact_wavelength_bits_and_resets_maps() {
    assert_eq!(MIN_PARALLEL_FORWARD_MISS_COUNT, 32);
    let next_760 = f64::from_bits(760.0_f64.to_bits() + 1);
    assert_ne!(
        SpectralEvaluationCache::key_for(760.0),
        SpectralEvaluationCache::key_for(next_760)
    );

    let mut cache = SpectralEvaluationCache::default();
    cache.forward.insert(
        SpectralEvaluationCache::key_for(760.0),
        ForwardIntegratedSample {
            radiance: 1.0,
            jacobian: jacobian::zero(),
        },
    );
    cache
        .irradiance
        .insert(SpectralEvaluationCache::key_for(760.0), 2.0);
    cache.reset();

    assert!(cache.forward.is_empty());
    assert!(cache.irradiance.is_empty());
}

#[test]
fn wavelength_sampling_uses_resolved_axis_and_channel_shifts() {
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 761.0,
            sample_count: 3,
        },
        ..Scene::default()
    };
    let axis = grid::ResolvedAxis {
        base: grid::SpectralGrid {
            start_nm: 760.0,
            end_nm: 761.0,
            sample_count: 3,
        },
        explicit_wavelengths_nm: &[760.02, 760.41, 760.93],
    };

    let plans = build_wavelength_sampling(
        &scene,
        axis,
        calibration::Calibration {
            wavelength_shift_nm: 0.01,
            ..calibration::Calibration::default()
        },
        calibration::Calibration {
            wavelength_shift_nm: -0.02,
            ..calibration::Calibration::default()
        },
        zdisamar::forward_model::implementations::exact(),
    )
    .unwrap();

    assert_eq!(plans.len(), 3);
    assert_close(plans[1].nominal_wavelength_nm, 760.41);
    assert_close(plans[1].radiance_wavelength_nm, 760.42);
    assert_close(plans[1].irradiance_wavelength_nm, 760.39);
    assert!(!plans[1].radiance_integration.enabled);
    assert_eq!(plans[1].radiance_integration.sample_count, 1);
}

#[test]
fn wavelength_sampling_collects_unique_radiance_integration_misses() {
    let scene = Scene {
        spectral_grid: SpectralGrid {
            start_nm: 760.0,
            end_nm: 760.2,
            sample_count: 2,
        },
        observation_model: ObservationModel {
            measurement_pipeline: MeasurementPipeline {
                radiance: SpectralChannelControls {
                    explicit: true,
                    response: SpectralResponse {
                        fwhm_nm: 0.4,
                        high_resolution_step_nm: 0.1,
                        high_resolution_half_span_nm: 0.1,
                        ..SpectralResponse::default()
                    },
                    ..SpectralChannelControls::default()
                },
                ..MeasurementPipeline::default()
            },
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    let axis = grid::ResolvedAxis {
        base: grid::SpectralGrid {
            start_nm: 760.0,
            end_nm: 760.1,
            sample_count: 2,
        },
        explicit_wavelengths_nm: &[],
    };

    let plans = build_wavelength_sampling(
        &scene,
        axis,
        calibration::Calibration::default(),
        calibration::Calibration::default(),
        zdisamar::forward_model::implementations::exact(),
    )
    .unwrap();
    let misses = collect_unique_forward_misses(&plans);

    assert_eq!(plans[0].radiance_integration.sample_count, 3);
    assert_eq!(misses.len(), 4);
    assert_close(misses[0].wavelength_nm, 759.9);
    assert_close(misses[3].wavelength_nm, 760.2);
}

#[test]
fn spectral_forward_converts_reflectance_to_radiance_and_jacobian() {
    let scene = Scene {
        geometry: Geometry {
            solar_zenith_deg: 60.0,
            ..Geometry::default()
        },
        observation_model: ObservationModel {
            solar_spectrum_source: Binding::BundleDefault,
            ..ObservationModel::default()
        },
        ..Scene::default()
    };
    let surface =
        zdisamar::forward_model::implementations::surface::resolve("builtin.lambertian_surface")
            .unwrap();
    let mut reflectance_jacobian = jacobian::zero();
    jacobian::set(&mut reflectance_jacobian, State::SurfaceAlbedo, 0.2);
    let forward = ForwardResult {
        family: TransportFamily::Labos,
        regime: ObservationRegime::Nadir,
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::SemiAnalytical,
        toa_reflectance_factor: 0.4,
        jacobian: Some(reflectance_jacobian),
    };

    let radiance = radiance_from_forward(&scene, surface, 758.0, 1.0, 0.0, forward);
    let expected_scale = 0.5 * 4.879049767e14 / std::f64::consts::PI;
    assert_close(radiance, 0.4 * expected_scale);

    let radiance_jacobian =
        radiance_jacobian_from_forward(&scene, surface, 758.0, 1.0, 0.0, forward);
    assert_close(
        jacobian::get(radiance_jacobian, State::SurfaceAlbedo),
        0.2 * expected_scale,
    );
}
