use zdisamar::{
    forward_model::{
        instrument_grid::{InstrumentGridProduct, InstrumentGridSummary},
        radiative_transfer::common_types::ExecutionMode,
    },
    input::{
        atmosphere::ParticlePlacementSemantics,
        geometry,
        instrument::{BuiltinLineShapeKind, SamplingMode},
        o2a_reference::{
            self, AssessmentVerdict, PlanError, PlanSpec, ReferenceSample, TrendState,
            TrendTolerances,
        },
        scene::DerivativeMode,
    },
};

#[test]
fn default_o2a_reference_input_matches_zig_reference_case() {
    let input = o2a_reference::default_input();

    input.validate().unwrap();
    assert_eq!(input.metadata.id, "disamar_reference_o2a");
    assert_eq!(input.scene_id, "o2a_disamar_reference_python");
    assert_eq!(input.spectral_grid.start_nm, 755.0);
    assert_eq!(input.spectral_grid.end_nm, 776.0);
    assert_eq!(input.spectral_grid.sample_count, 701);
    assert_eq!(input.layer_count, 3);
    assert_eq!(input.sublayer_divisions, 4);
    assert_eq!(input.fit_interval_index_1based, 2);
    assert_eq!(input.intervals.len(), 3);
    assert_eq!(input.intervals[1].top_pressure_hpa, 500.0);
    assert_eq!(input.intervals[1].bottom_pressure_hpa, 520.0);
    assert_eq!(input.geometry.model, geometry::Model::PseudoSpherical);
    assert_eq!(
        input.aerosol.placement.semantics,
        ParticlePlacementSemantics::ExplicitIntervalBounds
    );
    assert_eq!(input.observation.sampling, SamplingMode::Native);
    assert_eq!(
        input.observation.builtin_line_shape,
        BuiltinLineShapeKind::FlatTopN4
    );
    assert_eq!(
        input.observation.adaptive_reference_grid.points_per_fwhm,
        20
    );
    assert_eq!(input.o2.isotopes_sim, vec![1, 2, 3]);
    assert_eq!(input.o2.line_mixing_factor, Some(1.0));
    assert!(input.o2o2.enabled);
    assert_eq!(input.rtm_controls.n_streams, 20);
    assert!(input.rtm_controls.use_spherical_correction);
}

#[test]
fn o2a_plan_spec_resolves_execution_and_derivative_modes() {
    let plan = PlanSpec {
        model_family: "disamar_standard".to_string(),
        transport_solver: "dispatcher".to_string(),
        execution_solver_mode: "scalar".to_string(),
        execution_derivative_mode: "semi_analytical".to_string(),
    };

    plan.validate().unwrap();
    assert_eq!(plan.execution_mode().unwrap(), ExecutionMode::Scalar);
    assert_eq!(
        plan.derivative_mode().unwrap(),
        DerivativeMode::SemiAnalytical
    );
}

#[test]
fn o2a_plan_spec_rejects_unsupported_modes() {
    let mut plan = PlanSpec {
        model_family: "wrong".to_string(),
        transport_solver: "dispatcher".to_string(),
        execution_solver_mode: "scalar".to_string(),
        execution_derivative_mode: "none".to_string(),
    };
    assert_eq!(
        plan.validate().unwrap_err(),
        PlanError::UnsupportedModelFamily
    );

    plan.model_family = "disamar_standard".to_string();
    plan.execution_solver_mode = "parallel".to_string();
    assert_eq!(
        plan.validate().unwrap_err(),
        PlanError::UnsupportedExecutionMode
    );
}

#[test]
fn o2a_comparison_metrics_match_exact_reference_samples() {
    let wavelengths = vec![756.0, 760.5, 762.0, 764.5, 770.0];
    let reflectance = vec![5.0, 1.0, 3.0, 4.0, 6.0];
    let product = product_with_reflectance(wavelengths.clone(), reflectance.clone());
    let reference = wavelengths
        .iter()
        .zip(&reflectance)
        .map(|(&wavelength_nm, &reflectance)| ReferenceSample {
            wavelength_nm,
            irradiance: 0.0,
            reflectance,
        })
        .collect::<Vec<_>>();

    let metrics = o2a_reference::compute_comparison_metrics(&product, &reference, 0.0);

    assert_eq!(metrics.sample_count, 5);
    assert_eq!(metrics.nonzero_sample_count, 0);
    assert!(metrics.exact_match_within_zero_tolerance);
    assert_eq!(metrics.mean_abs_difference, 0.0);
    assert_eq!(metrics.root_mean_square_difference, 0.0);
    assert_eq!(metrics.max_abs_difference, 0.0);
    assert_eq!(metrics.correlation, 1.0);
    assert_eq!(metrics.trough_wavelength_difference_nm, 0.0);
    assert_eq!(metrics.red_wing_mean_difference, 0.0);
}

#[test]
fn o2a_assessment_reports_exact_and_regression_verdicts() {
    let tolerances = TrendTolerances::with_core_tolerances(0.01, 0.01, 0.01, 0.01);
    let exact = o2a_reference::ComparisonMetrics {
        exact_match_within_zero_tolerance: true,
        correlation: 1.0,
        ..o2a_reference::ComparisonMetrics::default()
    };

    assert_eq!(
        o2a_reference::assess_against_baseline(
            exact,
            o2a_reference::ComparisonMetrics::default(),
            tolerances,
            false,
        )
        .verdict,
        AssessmentVerdict::ExactZeroPass
    );

    let current = o2a_reference::ComparisonMetrics {
        mean_abs_difference: 0.5,
        root_mean_square_difference: 0.5,
        max_abs_difference: 0.5,
        correlation: 0.0,
        blue_wing_mean_difference: 0.5,
        ..o2a_reference::ComparisonMetrics::default()
    };
    let baseline = o2a_reference::ComparisonMetrics {
        correlation: 1.0,
        ..o2a_reference::ComparisonMetrics::default()
    };
    let outcome = o2a_reference::assess_against_baseline(current, baseline, tolerances, true);

    assert_eq!(outcome.verdict, AssessmentVerdict::RegressionFail);
    assert_eq!(outcome.trend.mean_abs_difference, TrendState::Regressed);
    assert_eq!(outcome.trend.correlation, TrendState::Regressed);
}

fn product_with_reflectance(wavelengths: Vec<f64>, reflectance: Vec<f64>) -> InstrumentGridProduct {
    InstrumentGridProduct {
        summary: InstrumentGridSummary {
            sample_count: wavelengths.len() as u32,
            wavelength_start_nm: wavelengths.first().copied().unwrap_or(0.0),
            wavelength_end_nm: wavelengths.last().copied().unwrap_or(0.0),
            mean_radiance: 0.0,
            mean_irradiance: 0.0,
            mean_reflectance: 0.0,
            mean_noise_sigma: 0.0,
            mean_jacobian: None,
        },
        wavelengths,
        radiance: Vec::new(),
        irradiance: Vec::new(),
        reflectance,
        noise_sigma: Vec::new(),
        radiance_noise_sigma: Vec::new(),
        irradiance_noise_sigma: Vec::new(),
        reflectance_noise_sigma: Vec::new(),
        jacobian: None,
        effective_air_mass_factor: 0.0,
        effective_single_scatter_albedo: 0.0,
        effective_temperature_k: 0.0,
        effective_pressure_hpa: 0.0,
        gas_optical_depth: 0.0,
        cia_optical_depth: 0.0,
        aerosol_optical_depth: 0.0,
        cloud_optical_depth: 0.0,
        total_optical_depth: 0.0,
        depolarization_factor: 0.0,
        d_optical_depth_d_temperature: 0.0,
    }
}
