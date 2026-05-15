use std::fs;

use zdisamar::{
    forward_model::{
        instrument_grid::{InstrumentGridProduct, InstrumentGridSummary},
        optical_properties::state_build::{
            PreparedLayer, PreparedLineAbsorber, PreparedOpticalState, PreparedSublayer,
            PreparedSupportRowKind,
        },
        radiative_transfer::{
            common_route,
            common_types::{DispatchRequest, ExecutionMode, RadiativeTransferControls},
        },
    },
    input::{
        atmosphere::PartitionLabel,
        instrument::IntegrationMode,
        reference_data::{
            CollisionInducedAbsorptionPoint, CollisionInducedAbsorptionTable, RelaxationMatrix,
            SpectroscopyLine, SpectroscopyLineList, SpectroscopyStrongLine,
        },
        scene::{DerivativeMode, Scene},
    },
    output::{
        self, CHANNEL_MASK_IRRADIANCE, CHANNEL_MASK_RADIANCE, InstrumentResponseRow, O2LineRowKind,
        O2LineStatus, SummaryReport, SupportRowKind,
    },
};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "expected {actual} to be within {tolerance} of {expected}"
    );
}

fn weak_o2_line() -> SpectroscopyLine {
    SpectroscopyLine {
        gas_index: 7,
        isotope_number: 1,
        center_wavelength_nm: 760.5,
        center_wavenumber_cm1: Some(1.0e7 / 760.5),
        line_strength_cm2_per_molecule: 1.0e-24,
        air_half_width_cm1: Some(0.05),
        temperature_exponent: 0.75,
        lower_state_energy_cm1: 10.0,
        pressure_shift_cm1: Some(0.0),
        ..SpectroscopyLine::default()
    }
}

fn strong_o2_line() -> SpectroscopyStrongLine {
    SpectroscopyStrongLine {
        center_wavenumber_cm1: 1.0e7 / 760.5,
        center_wavelength_nm: 760.5,
        population_t0: 1.0e-20,
        dipole_ratio: 1.0,
        dipole_t0: 1.0e-5,
        lower_state_energy_cm1: 10.0,
        air_half_width_cm1: 0.05,
        temperature_exponent: 0.75,
        rotational_index_m1: 1,
        ..SpectroscopyStrongLine::default()
    }
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
fn o2_line_contributions_report_weak_and_strong_rows() {
    let prepared = PreparedOpticalState {
        effective_temperature_k: 296.0,
        effective_pressure_hpa: 500.0,
        line_absorbers: vec![PreparedLineAbsorber {
            species: zdisamar::input::atmospheric_types::AbsorberSpecies::O2,
            line_list: SpectroscopyLineList {
                lines: vec![weak_o2_line()],
                strong_lines: Some(vec![strong_o2_line()]),
                relaxation_matrix: Some(RelaxationMatrix {
                    line_count: 1,
                    wt0: vec![0.05],
                    bw: vec![0.0],
                }),
                ..SpectroscopyLineList::default()
            },
            number_densities_cm3: Vec::new(),
            strong_line_states: Vec::new(),
            column_density_factor: 1.0,
        }],
        ..PreparedOpticalState::default()
    };

    let table = output::build_o2_line_contributions(&prepared, &[760.5], 10).unwrap();

    assert_eq!(table.total_row_count, 2);
    assert!(!table.truncated);
    assert_eq!(table.rows.len(), 2);
    assert_eq!(table.rows[0].row_kind, O2LineRowKind::WeakLine);
    assert_eq!(table.rows[0].status, O2LineStatus::WeakExcludedByStrongLine);
    assert_eq!(table.rows[0].matched_strong_line_index, 0);
    assert_eq!(table.rows[1].row_kind, O2LineRowKind::StrongLine);
    assert_eq!(table.rows[1].status, O2LineStatus::StrongSidecar);
    assert_close(
        table.rows[1].strong_line_sigma_cm2_per_molecule,
        5.786_354_609_661_759e-45,
        1.0e-57,
    );
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

#[test]
fn atmospheric_budget_reports_layer_totals_like_zig() {
    let scene = Scene::default();
    let prepared = PreparedOpticalState {
        layers: vec![PreparedLayer {
            layer_index: 4,
            altitude_km: 2.0,
            top_altitude_km: 3.0,
            bottom_altitude_km: 1.0,
            pressure_hpa: 500.0,
            temperature_k: 250.0,
            gas_optical_depth: 1.1,
            gas_scattering_optical_depth: 0.1,
            cia_optical_depth: 0.2,
            aerosol_optical_depth: 0.4,
            cloud_optical_depth: 0.8,
            interval_index_1based: 2,
            subcolumn_label: PartitionLabel::FitInterval,
            ..PreparedLayer::default()
        }],
        aerosol_single_scatter_albedo: 0.5,
        cloud_single_scatter_albedo: 0.25,
        aerosol_reference_wavelength_nm: 760.0,
        cloud_reference_wavelength_nm: 760.0,
        ..PreparedOpticalState::default()
    };

    let rows = output::build_atmospheric_budget(&scene, &prepared, &[760.0]).unwrap();

    assert_eq!(rows.len(), 1);
    let row = rows[0];
    assert_eq!(row.layer_index, 4);
    assert_eq!(row.sublayer_index, u32::MAX);
    assert_eq!(row.subcolumn_label as u32, 3);
    assert_close(row.gas_absorption_optical_depth, 1.0, 1.0e-14);
    assert_close(row.aerosol_scattering_optical_depth, 0.2, 1.0e-14);
    assert_close(row.cloud_absorption_optical_depth, 0.6, 1.0e-14);
    assert_close(row.total_absorption_optical_depth, 2.0, 1.0e-14);
    assert_close(row.total_scattering_optical_depth, 0.5, 1.0e-14);
    assert_close(row.total_optical_depth, 2.5, 1.0e-14);
    assert_close(row.single_scatter_albedo, 0.2, 1.0e-14);
}

#[test]
fn o2_o2_cia_rows_are_derived_from_sublayer_budget() {
    let scene = Scene::default();
    let prepared = PreparedOpticalState {
        sublayers: Some(vec![PreparedSublayer {
            parent_layer_index: 1,
            sublayer_index: 2,
            altitude_km: 4.0,
            pressure_hpa: 500.0,
            temperature_k: 273.15,
            number_density_cm3: 5.0,
            oxygen_number_density_cm3: 2.0,
            path_length_cm: 10.0,
            support_row_kind: PreparedSupportRowKind::ParityActive,
            subcolumn_label: PartitionLabel::BoundaryLayer,
            ..PreparedSublayer::default()
        }]),
        collision_induced_absorption: Some(CollisionInducedAbsorptionTable {
            scale_factor_cm5_per_molecule2: 1.0,
            points: vec![CollisionInducedAbsorptionPoint {
                wavelength_nm: 760.0,
                a0: 0.01,
                a1: 0.0,
                a2: 0.0,
            }],
        }),
        ..PreparedOpticalState::default()
    };

    let budget = output::build_atmospheric_budget(&scene, &prepared, &[760.0]).unwrap();
    assert_eq!(budget[0].support_row_kind, SupportRowKind::ParityActive);
    assert_eq!(budget[0].subcolumn_label as u32, 1);
    assert_close(budget[0].cia_optical_depth, 0.4, 1.0e-14);

    let rows = output::build_o2_o2_cia(&scene, &prepared, &[760.0]).unwrap();

    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0].layer_index, 1);
    assert_eq!(rows[0].sublayer_index, 2);
    assert_close(rows[0].cia_cross_section_cm5_per_molecule2, 0.01, 1.0e-14);
    assert_close(rows[0].cia_optical_depth, 0.4, 1.0e-14);
    assert_close(rows[0].cia_share_of_total_absorption, 1.0, 1.0e-14);
    assert_close(rows[0].cia_share_of_total_optical_depth, 1.0, 1.0e-12);
}

#[test]
fn radiative_transfer_diagnostics_accumulate_depth_and_interpolate_spectrum() {
    let mut scene = Scene::default();
    scene.geometry.solar_zenith_deg = 60.0;
    scene.geometry.viewing_zenith_deg = 0.0;
    let prepared = PreparedOpticalState {
        layers: vec![
            PreparedLayer {
                layer_index: 0,
                altitude_km: 2.0,
                gas_optical_depth: 0.2,
                gas_scattering_optical_depth: 0.1,
                ..PreparedLayer::default()
            },
            PreparedLayer {
                layer_index: 1,
                altitude_km: 1.0,
                gas_optical_depth: 0.3,
                gas_scattering_optical_depth: 0.1,
                ..PreparedLayer::default()
            },
        ],
        ..PreparedOpticalState::default()
    };
    let route = common_route::prepare_route(DispatchRequest {
        execution_mode: ExecutionMode::Scalar,
        derivative_mode: DerivativeMode::None,
        rtm_controls: RadiativeTransferControls {
            n_streams: 8,
            integrate_source_function: false,
            ..RadiativeTransferControls::default()
        },
        ..DispatchRequest::default()
    })
    .unwrap();
    let spectrum = output::SpectrumView {
        wavelength_nm: &[759.0, 761.0],
        reflectance: &[0.2, 0.4],
        radiance: &[10.0, 14.0],
    };

    let rows = output::build_radiative_transfer_diagnostics(
        &scene,
        &prepared,
        route,
        &[760.0],
        Some(spectrum),
    )
    .unwrap();

    assert_eq!(rows.len(), 2);
    assert_close(rows[0].pseudo_spherical_airmass_factor, 3.0, 1.0e-14);
    assert_eq!(rows[0].n_streams, 8);
    assert_eq!(rows[0].integrate_source_function, 0);
    assert_close(rows[0].cumulative_optical_depth_above, 0.0, 1.0e-14);
    assert_close(
        rows[0].mid_layer_transmission_proxy,
        (-0.3_f64).exp(),
        1.0e-14,
    );
    assert_close(
        rows[0].direct_surface_transmission_proxy,
        (-0.6_f64).exp(),
        1.0e-14,
    );
    assert_close(rows[0].final_reflectance, 0.3, 1.0e-14);
    assert_close(rows[0].final_radiance, 12.0, 1.0e-14);
    assert_close(rows[1].cumulative_optical_depth_above, 0.2, 1.0e-14);
}
