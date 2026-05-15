use std::fs;

use zdisamar::{
    forward_model::{
        instrument_grid::{InstrumentGridProduct, InstrumentGridSummary},
        optical_properties::state_build::PreparedOpticalState,
    },
    input::{instrument::IntegrationMode, scene::Scene},
    output::{
        self, CHANNEL_MASK_IRRADIANCE, CHANNEL_MASK_RADIANCE, InstrumentResponseRow, SummaryReport,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "expected {actual} to be within {tolerance} of {expected}"
    );
}

#[test]
fn summary_report_copies_product_summary_fields() {
    let product = InstrumentGridProduct {
        summary: InstrumentGridSummary {
            sample_count: 3,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 762.0,
            mean_radiance: 1.2,
            mean_irradiance: 2.4,
            mean_reflectance: 0.5,
            mean_noise_sigma: 0.0,
            mean_jacobian: None,
        },
        wavelengths: Vec::new(),
        radiance: Vec::new(),
        irradiance: Vec::new(),
        reflectance: Vec::new(),
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
    };

    assert_eq!(
        output::summary_report_from_product(&product),
        SummaryReport {
            sample_count: 3,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 762.0,
            mean_radiance: 1.2,
            mean_irradiance: 2.4,
            mean_reflectance: 0.5,
        }
    );
}

#[test]
fn summary_report_writer_matches_zig_field_names() {
    let path = std::env::temp_dir().join(format!(
        "zdisamar-summary-report-{}.json",
        std::process::id()
    ));
    output::write_summary_report(
        &path,
        SummaryReport {
            sample_count: 2,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 761.0,
            mean_radiance: 1.0,
            mean_irradiance: 2.0,
            mean_reflectance: 0.5,
        },
    )
    .unwrap();
    let content = fs::read_to_string(&path).unwrap();
    fs::remove_file(path).unwrap();

    assert!(content.contains("\"sample_count\": 2"));
    assert!(content.contains("\"wavelength_start_nm\": 760"));
    assert!(content.contains("\"mean_reflectance\": 0.5"));
}

#[test]
fn instrument_response_reports_disabled_native_sampling_like_zig() {
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 762.0;
    scene.spectral_grid.sample_count = 3;

    let rows = output::build_instrument_response(
        &scene,
        &PreparedOpticalState::default(),
        &[760.0, 762.0],
        CHANNEL_MASK_RADIANCE,
    )
    .unwrap();

    assert_eq!(rows.len(), 2);
    assert_eq!(
        rows[0],
        InstrumentResponseRow {
            nominal_index: 0,
            nominal_wavelength_nm: 760.0,
            channel: 0,
            sample_index: 0,
            support_count: 1,
            offset_nm: 0.0,
            support_wavelength_nm: 760.0,
            weight: 1.0,
            support_width_nm: 0.0,
            instrument_fwhm_nm: 0.0,
            high_resolution_step_nm: 0.0,
            high_resolution_half_span_nm: 0.0,
            integration_mode: 0,
            response_enabled: 0,
        }
    );
    assert_eq!(rows[1].nominal_index, 2);
    assert_eq!(rows[1].support_wavelength_nm, 762.0);
}

#[test]
fn instrument_response_reports_explicit_support_rows_for_each_channel() {
    let mut scene = Scene::default();
    scene.spectral_grid.start_nm = 760.0;
    scene.spectral_grid.end_nm = 761.0;
    scene.spectral_grid.sample_count = 2;
    scene.observation_model.instrument_line_fwhm_nm = 0.2;
    scene.observation_model.high_resolution_step_nm = 0.1;
    scene.observation_model.high_resolution_half_span_nm = 0.1;

    let rows = output::build_instrument_response(
        &scene,
        &PreparedOpticalState::default(),
        &[760.0],
        CHANNEL_MASK_RADIANCE | CHANNEL_MASK_IRRADIANCE,
    )
    .unwrap();

    assert_eq!(rows.len(), 6);
    assert_eq!(rows[0].channel, 0);
    assert_eq!(rows[0].sample_index, 0);
    assert_eq!(rows[0].support_count, 3);
    assert_close(rows[0].offset_nm, -0.1, 1.0e-14);
    assert_close(rows[2].offset_nm, 0.1, 1.0e-14);
    assert_close(rows[0].support_width_nm, 0.2, 1.0e-14);
    assert_eq!(
        rows[0].integration_mode,
        IntegrationMode::ExplicitHrGrid as u32
    );
    assert_eq!(rows[0].response_enabled, 1);
    assert_eq!(rows[3].channel, 1);
}

#[test]
fn instrument_response_rejects_empty_requests() {
    let scene = Scene::default();
    let prepared = PreparedOpticalState::default();

    assert!(
        output::build_instrument_response(&scene, &prepared, &[], CHANNEL_MASK_RADIANCE).is_err()
    );
    assert!(output::build_instrument_response(&scene, &prepared, &[760.0], 0).is_err());
}
