use zdisamar::{
    forward_model::{
        instrument_grid::{InstrumentGridProduct, InstrumentGridSummary},
        radiative_transfer::common_types::ExecutionMode,
    },
    input::{
        atmosphere::ParticlePlacementSemantics,
        geometry,
        instrument::{BuiltinLineShapeKind, IntegrationMode, SamplingMode, SlitIndex},
        o2a_reference::{
            self, AssessmentVerdict, PlanError, PlanSpec, ReferenceSample, SolarSpectrumSample,
            TrendState, TrendTolerances,
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
fn o2a_runtime_loaders_parse_reference_and_solar_csv() {
    let reference_path = temp_csv_path("zdisamar-rust-reference.csv");
    std::fs::write(
        &reference_path,
        "wavelength_nm,irradiance,radiance,reflectance\n755.0,1.0,2.0,0.2\n756.0,3.0,4.0,0.4\n",
    )
    .unwrap();
    let reference =
        o2a_reference::load_reference_samples(reference_path.to_str().unwrap()).unwrap();
    std::fs::remove_file(&reference_path).unwrap();

    assert_eq!(reference.len(), 2);
    assert_eq!(reference[0].wavelength_nm, 755.0);
    assert_eq!(reference[0].irradiance, 1.0);
    assert_eq!(reference[1].reflectance, 0.4);

    let solar_path = temp_csv_path("zdisamar-rust-solar.csv");
    std::fs::write(
        &solar_path,
        "wavelength_nm,irradiance\n754.5,10.0\n755.0,11.0\n776.5,12.0\n",
    )
    .unwrap();
    let mut input = o2a_reference::default_input();
    input.inputs.raw_solar_reference.path = solar_path.to_string_lossy().into_owned();
    let solar =
        o2a_reference::load_solar_spectrum_samples(&input.inputs.raw_solar_reference).unwrap();
    std::fs::remove_file(&solar_path).unwrap();

    assert_eq!(solar.len(), 3);
    assert_eq!(solar[2].wavelength_nm, 776.5);
    assert_eq!(solar[2].irradiance, 12.0);

    let profile_path = temp_csv_path("zdisamar-rust-profile.csv");
    std::fs::write(
        &profile_path,
        "altitude_km,pressure_hpa,temperature_k,air_number_density_cm3\n0.0,1000.0,300.0,2.0\n10.0,100.0,230.0,1.0\n",
    )
    .unwrap();
    let mut input = o2a_reference::default_input();
    input.inputs.atmosphere_profile.path = profile_path.to_string_lossy().into_owned();
    let profile =
        o2a_reference::load_climatology_profile(&input.inputs.atmosphere_profile).unwrap();
    std::fs::remove_file(&profile_path).unwrap();

    assert_eq!(profile.rows.len(), 2);
    assert_eq!(profile.rows[0].pressure_hpa, 1000.0);
    assert_eq!(profile.rows[1].temperature_k, 230.0);

    let cia_path = temp_csv_path("zdisamar-rust-cia.dat");
    std::fs::write(
        &cia_path,
        "1.0E-46 ! scale factor\n0 ! header lines\n2 ! data lines\n755.0 1.0 0.1 0.01\n756.0 2.0 0.2 0.02\n",
    )
    .unwrap();
    let mut input = o2a_reference::default_input();
    input.o2o2.cia_asset.as_mut().unwrap().path = cia_path.to_string_lossy().into_owned();
    let cia = o2a_reference::load_cia_table(input.o2o2.cia_asset.as_ref().unwrap()).unwrap();
    std::fs::remove_file(&cia_path).unwrap();

    assert_eq!(cia.points.len(), 2);
    assert_eq!(cia.scale_factor_cm5_per_molecule2, 1.0e-46);
    assert_eq!(cia.points[1].a2, 0.02);

    let airmass_path = temp_csv_path("zdisamar-rust-airmass.csv");
    std::fs::write(
        &airmass_path,
        "solar_zenith_deg,view_zenith_deg,relative_azimuth_deg,airmass_factor\n20.0,0.0,0.0,1.064\n60.0,20.0,60.0,1.756\n",
    )
    .unwrap();
    let mut input = o2a_reference::default_input();
    input.inputs.airmass_factor_lut.path = airmass_path.to_string_lossy().into_owned();
    let lut = o2a_reference::load_airmass_factor_lut(&input.inputs.airmass_factor_lut).unwrap();
    std::fs::remove_file(&airmass_path).unwrap();

    assert_eq!(lut.points.len(), 2);
    assert_eq!(lut.nearest(58.0, 19.0, 61.0), 1.756);
}

#[test]
fn o2a_runtime_builds_trace_gas_spectroscopy_profile_from_dense_altitudes() {
    let source = zdisamar::input::reference_data::ClimatologyProfile {
        rows: vec![
            zdisamar::input::reference_data::ClimatologyPoint {
                altitude_km: 0.0,
                pressure_hpa: 1000.0,
                temperature_k: 300.0,
                air_number_density_cm3: 0.0,
            },
            zdisamar::input::reference_data::ClimatologyPoint {
                altitude_km: 12.0,
                pressure_hpa: 100.0,
                temperature_k: 230.0,
                air_number_density_cm3: 0.0,
            },
        ],
    };
    let dense = zdisamar::input::reference_data::ClimatologyProfile {
        rows: vec![
            zdisamar::input::reference_data::ClimatologyPoint {
                altitude_km: 0.0,
                pressure_hpa: 1000.0,
                temperature_k: 300.0,
                air_number_density_cm3: 0.0,
            },
            zdisamar::input::reference_data::ClimatologyPoint {
                altitude_km: 6.0,
                pressure_hpa: 316.22776601683796,
                temperature_k: 260.0,
                air_number_density_cm3: 0.0,
            },
            zdisamar::input::reference_data::ClimatologyPoint {
                altitude_km: 12.0,
                pressure_hpa: 100.0,
                temperature_k: 230.0,
                air_number_density_cm3: 0.0,
            },
        ],
    };

    let spectroscopy_profile =
        o2a_reference::build_vendor_trace_gas_spectroscopy_profile(&source, &dense);

    assert_eq!(spectroscopy_profile.rows.len(), 2);
    assert_eq!(spectroscopy_profile.rows[0].altitude_km, 0.0);
    assert_eq!(spectroscopy_profile.rows[1].altitude_km, 12.0);
    assert_eq!(
        spectroscopy_profile.rows[0].air_number_density_cm3,
        1000.0 / 300.0 / 1.380658e-19
    );
}

#[test]
fn o2a_runtime_loads_vendor_spectroscopy_sidecars() {
    let mut input = o2a_reference::default_input();
    input.o2.line_list_asset.path =
        "data/reference_data/cross_sections/o2a_hitran_subset_07_hit08_tropomi.par".to_string();
    input.o2.strong_lines_asset.path =
        "data/reference_data/cross_sections/o2a_lisa_sdf_subset.dat".to_string();
    input.o2.line_mixing_asset.path =
        "data/reference_data/cross_sections/o2a_lisa_rmf_subset.dat".to_string();

    let line_list = o2a_reference::load_resolved_vendor_o2a_line_list(&input.o2).unwrap();

    assert_eq!(line_list.lines.len(), 52);
    assert_eq!(line_list.strong_lines.as_ref().unwrap().len(), 8);
    assert_eq!(line_list.relaxation_matrix.as_ref().unwrap().line_count, 8);
    assert!(line_list.has_strong_line_sidecars());
    assert!(line_list.vendor_strong_line_partition);

    let first_line = line_list.lines[0];
    assert_eq!(first_line.gas_index, 7);
    assert_eq!(first_line.isotope_number, 1);
    assert_eq!(first_line.branch_ic1, Some(5));
    assert_eq!(first_line.branch_ic2, Some(1));
    assert_eq!(first_line.rotational_nf, Some(3));
    assert!(first_line.center_wavenumber_cm1.unwrap() > 12_900.0);

    let first_strong = line_list.strong_lines.as_ref().unwrap()[0];
    assert_eq!(first_strong.rotational_index_m1, -35);
    assert!(first_strong.air_half_width_cm1 > 0.0);
}

#[test]
fn o2a_runtime_builds_scene_and_route_from_resolved_case() {
    let input = o2a_reference::default_input();
    let raw_solar_spectrum = vec![
        SolarSpectrumSample {
            wavelength_nm: 754.0,
            irradiance: 9.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 754.5,
            irradiance: 10.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 755.0,
            irradiance: 11.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 760.0,
            irradiance: 12.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 776.0,
            irradiance: 13.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 776.5,
            irradiance: 14.0,
        },
        SolarSpectrumSample {
            wavelength_nm: 777.0,
            irradiance: 15.0,
        },
    ];

    let scene =
        o2a_reference::build_resolved_vendor_o2a_scene(&input, &raw_solar_spectrum).unwrap();
    let route = o2a_reference::prepare_resolved_vendor_o2a_route(&scene, &input).unwrap();

    assert_eq!(scene.id, "o2a_disamar_reference_python");
    assert_eq!(scene.atmosphere.interval_grid.intervals.len(), 3);
    assert_eq!(scene.atmosphere.interval_grid.fit_interval_index_1based, 2);
    assert_eq!(scene.absorbers.items.len(), 1);
    assert_eq!(scene.absorbers.items[0].id, "o2");
    assert_eq!(
        scene.absorbers.items[0]
            .spectroscopy
            .line_gas_controls
            .isotopes_sim,
        vec![1, 2, 3]
    );
    assert_eq!(
        scene
            .observation_model
            .operational_solar_spectrum
            .wavelengths_nm,
        vec![754.5, 755.0, 760.0, 776.0, 776.5]
    );
    let response = &scene
        .observation_model
        .measurement_pipeline
        .radiance
        .response;
    assert!(response.explicit);
    assert_eq!(response.slit_index, SlitIndex::FlatTopN4);
    assert_eq!(response.integration_mode, IntegrationMode::DisamarHrGrid);
    assert_eq!(route.execution_mode, ExecutionMode::Scalar);
    assert_eq!(route.derivative_mode, DerivativeMode::None);
    assert_eq!(route.rtm_controls.n_streams, 20);
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

fn temp_csv_path(name: &str) -> std::path::PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!("{}-{}", std::process::id(), name));
    path
}
