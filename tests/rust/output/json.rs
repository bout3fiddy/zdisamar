use std::{fs, path::PathBuf};

use zdisamar::{
    forward_model::instrument_grid::grid_calculation::types::{
        InstrumentGridProduct, InstrumentGridSummary,
    },
    output::json::{
        SPECTRUM_NAME, SummaryReport, summary_report_from_product, write_generated_spectrum_csv,
        write_summary_report,
    },
};

fn temp_path(name: &str) -> PathBuf {
    let mut path = std::env::temp_dir();
    path.push(format!("zdisamar-rust-port-{}-{name}", std::process::id()));
    path
}

#[test]
fn summary_report_projects_product_summary_fields() {
    let product = InstrumentGridProduct {
        summary: InstrumentGridSummary {
            sample_count: 2,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 761.0,
            mean_radiance: 4.0,
            mean_irradiance: 8.0,
            mean_reflectance: 0.5,
            mean_noise_sigma: 0.02,
            mean_jacobian: None,
        },
        ..InstrumentGridProduct::default()
    };

    assert_eq!(
        summary_report_from_product(&product),
        SummaryReport {
            sample_count: 2,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 761.0,
            mean_radiance: 4.0,
            mean_irradiance: 8.0,
            mean_reflectance: 0.5,
        }
    );
}

#[test]
fn summary_report_writer_emits_indented_json() {
    let path = temp_path("summary.json");
    let _ = fs::remove_file(&path);

    write_summary_report(
        &path,
        SummaryReport {
            sample_count: 2,
            wavelength_start_nm: 760.0,
            wavelength_end_nm: 761.0,
            mean_radiance: 4.0,
            mean_irradiance: 8.0,
            mean_reflectance: 0.5,
        },
    )
    .unwrap();

    let text = fs::read_to_string(&path).unwrap();
    fs::remove_file(&path).unwrap();

    assert!(text.starts_with("{\n  \"sample_count\": 2,"));
    assert!(text.contains("\"mean_reflectance\": 0.5"));
}

#[test]
fn generated_spectrum_csv_writer_matches_export_name_and_columns() {
    let path = temp_path(SPECTRUM_NAME);
    let _ = fs::remove_file(&path);
    let product = InstrumentGridProduct {
        wavelengths: vec![760.0, 761.0],
        irradiance: vec![2.0, 4.0],
        radiance: vec![1.0, 2.0],
        reflectance: vec![0.5, 0.5],
        ..InstrumentGridProduct::default()
    };

    write_generated_spectrum_csv(&path, &product).unwrap();

    let text = fs::read_to_string(&path).unwrap();
    fs::remove_file(&path).unwrap();

    assert!(text.starts_with("wavelength_nm,irradiance,radiance,reflectance\n"));
    assert!(text.contains(
        "760.00000000,2.00000000000000000e0,1.00000000000000000e0,5.00000000000000000e-1"
    ));
}
