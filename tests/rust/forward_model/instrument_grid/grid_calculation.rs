use zdisamar::forward_model::instrument_grid::grid_calculation::types::{
    FITTED_REFLECTANCE_EXPORT_NAME, InstrumentGridProductView, InstrumentGridSummary,
    REFLECTANCE_EXPORT_NAME,
};

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
