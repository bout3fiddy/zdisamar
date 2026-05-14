use std::{
    fs::File,
    io::{Result, Write},
    path::Path,
};

use crate::forward_model::instrument_grid::grid_calculation::types::InstrumentGridProduct;

pub const SPECTRUM_NAME: &str = "generated_spectrum.csv";

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SummaryReport {
    pub sample_count: u32,
    pub wavelength_start_nm: f64,
    pub wavelength_end_nm: f64,
    pub mean_radiance: f64,
    pub mean_irradiance: f64,
    pub mean_reflectance: f64,
}

pub fn write_summary_report(path: impl AsRef<Path>, report: SummaryReport) -> Result<()> {
    let mut file = File::create(path)?;
    // The report is a fixed scalar shape, so this avoids a serialization dependency
    // while keeping the same indented field order as the Zig output.
    write!(
        file,
        "{{\n  \"sample_count\": {},\n  \"wavelength_start_nm\": {},\n  \"wavelength_end_nm\": {},\n  \"mean_radiance\": {},\n  \"mean_irradiance\": {},\n  \"mean_reflectance\": {}\n}}",
        report.sample_count,
        report.wavelength_start_nm,
        report.wavelength_end_nm,
        report.mean_radiance,
        report.mean_irradiance,
        report.mean_reflectance,
    )
}

pub fn summary_report_from_product(product: &InstrumentGridProduct) -> SummaryReport {
    SummaryReport {
        sample_count: product.summary.sample_count,
        wavelength_start_nm: product.summary.wavelength_start_nm,
        wavelength_end_nm: product.summary.wavelength_end_nm,
        mean_radiance: product.summary.mean_radiance,
        mean_irradiance: product.summary.mean_irradiance,
        mean_reflectance: product.summary.mean_reflectance,
    }
}

pub fn write_generated_spectrum_csv(
    path: impl AsRef<Path>,
    product: &InstrumentGridProduct,
) -> Result<()> {
    let mut file = File::create(path)?;
    writeln!(file, "wavelength_nm,irradiance,radiance,reflectance")?;
    for (((&wavelength_nm, &irradiance), &radiance), &reflectance) in product
        .wavelengths
        .iter()
        .zip(&product.irradiance)
        .zip(&product.radiance)
        .zip(&product.reflectance)
    {
        writeln!(
            file,
            "{wavelength_nm:.8},{irradiance:.17e},{radiance:.17e},{reflectance:.17e}"
        )?;
    }
    Ok(())
}
