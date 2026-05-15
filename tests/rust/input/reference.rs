use zdisamar::input::reference::airmass_phase::{
    AirmassFactorLut, AirmassFactorPoint, Error, MiePhasePoint, MiePhaseTable,
    spectral_profile_from_optical_depth,
};
use zdisamar::input::reference::solar_irradiance::{
    bundled_solar_irradiance, default_solar_continuum_irradiance, irradiance_at_wavelength,
};
use zdisamar::input::reference::spectroscopy::line_list_ops;
use zdisamar::input::reference_data::{
    ClimatologyPoint, ClimatologyProfile, CollisionInducedAbsorptionPoint,
    CollisionInducedAbsorptionTable, CrossSectionPoint, CrossSectionTable, RelaxationMatrix,
    SpectroscopyLine, SpectroscopyLineList, SpectroscopyStrongLine,
};
use zdisamar::input::{binding::Binding, scene::Scene};

fn assert_close(actual: f64, expected: f64, tolerance: f64) {
    assert!(
        (actual - expected).abs() <= tolerance,
        "actual={actual:?} expected={expected:?} tolerance={tolerance:?}"
    );
}

fn spectroscopy_line(gas_index: u16, isotope_number: u8, wavelength_nm: f64) -> SpectroscopyLine {
    SpectroscopyLine {
        gas_index,
        isotope_number,
        center_wavelength_nm: wavelength_nm,
        center_wavenumber_cm1: Some(1.0e7 / wavelength_nm),
        line_strength_cm2_per_molecule: 1.0e-24,
        air_half_width_cm1: Some(0.05),
        ..SpectroscopyLine::default()
    }
}

fn vendor_o2a_candidate(wavelength_nm: f64) -> SpectroscopyLine {
    SpectroscopyLine {
        vendor_filter_metadata_from_source: true,
        branch_ic1: Some(5),
        branch_ic2: Some(1),
        rotational_nf: Some(12),
        ..spectroscopy_line(7, 1, wavelength_nm)
    }
}

fn spectroscopy_strong_line(wavelength_nm: f64) -> SpectroscopyStrongLine {
    SpectroscopyStrongLine {
        center_wavenumber_cm1: 1.0e7 / wavelength_nm,
        center_wavelength_nm: wavelength_nm,
        population_t0: 1.0e-20,
        dipole_ratio: 1.0,
        dipole_t0: 1.0e-5,
        lower_state_energy_cm1: 10.0,
        air_half_width_cm1: 0.05,
        air_half_width_nm: 0.001,
        temperature_exponent: 0.75,
        rotational_index_m1: 1,
        ..SpectroscopyStrongLine::default()
    }
}

fn one_line_relaxation_matrix() -> RelaxationMatrix {
    RelaxationMatrix {
        line_count: 1,
        wt0: vec![0.0],
        bw: vec![0.0],
    }
}

#[test]
fn spectroscopy_line_list_runtime_controls_filter_lines_and_record_controls() {
    let mut line_list = SpectroscopyLineList {
        lines: vec![
            spectroscopy_line(7, 1, 760.5),
            spectroscopy_line(7, 2, 760.6),
            spectroscopy_line(8, 1, 760.7),
        ],
        lines_sorted_ascending: true,
        strong_line_match_by_line: Some(vec![Some(0), None, None]),
        ..SpectroscopyLineList::default()
    };

    line_list
        .apply_runtime_controls(Some(7), &[1], Some(0.25), Some(10.0), 0.5)
        .unwrap();

    assert_eq!(line_list.lines.len(), 1);
    assert_eq!(line_list.lines[0].gas_index, 7);
    assert_eq!(line_list.lines[0].isotope_number, 1);
    assert!(!line_list.lines_sorted_ascending);
    assert_eq!(line_list.strong_line_match_by_line, None);
    assert_eq!(line_list.runtime_controls.gas_index, Some(7));
    assert_eq!(line_list.runtime_controls.active_isotopes, vec![1]);
    assert_eq!(line_list.runtime_controls.threshold_line_scale, Some(0.25));
    assert_eq!(line_list.runtime_controls.cutoff_cm1, Some(10.0));
    assert_close(line_list.runtime_controls.line_mixing_factor, 0.5, 0.0);
}

#[test]
fn spectroscopy_line_list_runtime_controls_disable_o2_sidecars_without_isotope_one() {
    let mut line_list = SpectroscopyLineList {
        lines: vec![spectroscopy_line(7, 2, 760.5)],
        strong_lines: Some(vec![spectroscopy_strong_line(760.5)]),
        relaxation_matrix: Some(one_line_relaxation_matrix()),
        vendor_strong_line_partition: true,
        strong_line_match_by_line: Some(vec![Some(0)]),
        ..SpectroscopyLineList::default()
    };

    line_list
        .apply_runtime_controls(Some(7), &[2], None, None, 1.0)
        .unwrap();

    assert!(line_list.strong_lines.is_none());
    assert!(line_list.relaxation_matrix.is_none());
    assert!(line_list.strong_line_match_by_line.is_none());
    assert!(!line_list.vendor_strong_line_partition);
}

#[test]
fn spectroscopy_line_list_builds_cached_vendor_strong_line_matches() {
    let mut line_list = SpectroscopyLineList {
        lines: vec![
            vendor_o2a_candidate(760.5),
            spectroscopy_line(7, 1, 760.5),
            spectroscopy_line(7, 2, 760.6),
        ],
        strong_lines: Some(vec![spectroscopy_strong_line(760.5)]),
        relaxation_matrix: Some(one_line_relaxation_matrix()),
        ..SpectroscopyLineList::default()
    };

    line_list
        .apply_runtime_controls(Some(7), &[1], None, None, 1.0)
        .unwrap();
    line_list.build_strong_line_match_index().unwrap();

    assert!(line_list.vendor_strong_line_partition);
    assert_eq!(
        line_list.strong_line_match_by_line,
        Some(vec![Some(0), None])
    );
    assert!(line_list_ops::should_exclude_weak_line(
        &line_list,
        0,
        &line_list.lines[0],
        0,
        &[],
    ));
    assert!(!line_list_ops::should_exclude_weak_line(
        &line_list,
        0,
        &line_list.lines[1],
        1,
        &[],
    ));
}

#[test]
fn spectroscopy_line_list_prepared_states_match_direct_sigma() {
    let weak_only = SpectroscopyLineList {
        lines: vec![spectroscopy_line(7, 1, 760.5)],
        ..SpectroscopyLineList::default()
    };
    let weak_state = weak_only.prepare_weak_line_state(296.0, 500.0);
    assert_eq!(weak_state.line_count, 1);
    assert_close(
        weak_only.sigma_at_with_prepared_profile_state(
            760.5,
            296.0,
            500.0,
            None,
            Some(&weak_state),
        ),
        weak_only.sigma_at(760.5, 296.0, 500.0),
        1.0e-40,
    );

    let mut with_sidecars = SpectroscopyLineList {
        lines: vec![vendor_o2a_candidate(760.5)],
        strong_lines: Some(vec![spectroscopy_strong_line(760.5)]),
        relaxation_matrix: Some(one_line_relaxation_matrix()),
        ..SpectroscopyLineList::default()
    };
    with_sidecars
        .apply_runtime_controls(Some(7), &[1], None, None, 1.0)
        .unwrap();
    with_sidecars.build_strong_line_match_index().unwrap();
    let strong_state = with_sidecars
        .prepare_strong_line_state(296.0, 500.0)
        .expect("strong sidecars should prepare");
    let weak_state = with_sidecars.prepare_weak_line_state(296.0, 500.0);

    assert_eq!(strong_state.line_count, 1);
    assert_close(
        with_sidecars.sigma_at_with_prepared_profile_state(
            760.5,
            296.0,
            500.0,
            Some(&strong_state),
            Some(&weak_state),
        ),
        with_sidecars.sigma_at(760.5, 296.0, 500.0),
        1.0e-55,
    );
}

#[test]
fn solar_irradiance_uses_bundled_o2a_source_or_continuum_fallback() {
    assert_close(
        bundled_solar_irradiance(760.01).unwrap(),
        4.858697784e14,
        1.0,
    );
    assert!(bundled_solar_irradiance(700.0).is_none());
    assert_close(default_solar_continuum_irradiance(760.0), 4.87401e14, 1.0);

    let mut scene = Scene::default();
    scene.observation_model.solar_spectrum_source = Binding::BundleDefault;
    assert_close(
        irradiance_at_wavelength(&scene, 760.01),
        4.858697784e14,
        1.0,
    );

    scene.observation_model.solar_spectrum_source = Binding::None;
    assert_close(irradiance_at_wavelength(&scene, 760.0), 4.87401e14, 1.0);
}

#[test]
fn mie_phase_table_interpolates_spectral_support() {
    let table = MiePhaseTable {
        points: vec![
            MiePhasePoint {
                wavelength_nm: 760.0,
                extinction_scale: 1.0,
                single_scatter_albedo: 0.9,
                phase_coefficients: [1.0, 0.2, 0.1, 0.0],
            },
            MiePhasePoint {
                wavelength_nm: 770.0,
                extinction_scale: 1.4,
                single_scatter_albedo: 0.8,
                phase_coefficients: [1.0, 0.4, 0.3, 0.2],
            },
        ],
    };

    let midpoint = table.interpolate(765.0);

    assert_close(midpoint.extinction_scale, 1.2, 1.0e-14);
    assert_close(midpoint.single_scatter_albedo, 0.85, 1.0e-14);
    for (actual, expected) in midpoint.phase_coefficients.iter().zip([1.0, 0.3, 0.2, 0.1]) {
        assert_close(*actual, expected, 1.0e-14);
    }
    assert_eq!(table.interpolate(750.0), table.points[0]);
    assert_eq!(table.interpolate(780.0), table.points[1]);
}

#[test]
fn airmass_lut_selects_nearest_geometry() {
    let lut = AirmassFactorLut {
        points: vec![
            AirmassFactorPoint {
                solar_zenith_deg: 20.0,
                view_zenith_deg: 10.0,
                relative_azimuth_deg: 0.0,
                airmass_factor: 1.1,
            },
            AirmassFactorPoint {
                solar_zenith_deg: 60.0,
                view_zenith_deg: 30.0,
                relative_azimuth_deg: 90.0,
                airmass_factor: 2.4,
            },
        ],
    };

    assert_close(lut.nearest(58.0, 29.0, 80.0), 2.4, 0.0);
    assert!(lut.provides_support_only());
    assert_close(AirmassFactorLut::default().nearest(1.0, 2.0, 3.0), 1.0, 0.0);
}

#[test]
fn spectral_profile_preserves_requested_mean() {
    let wavelengths = [760.0, 761.0, 762.0];
    let proxy = [1.0, 2.0, 3.0];
    let profile = spectral_profile_from_optical_depth(&wavelengths, 2.0, &proxy).unwrap();
    let mean = profile.iter().sum::<f64>() / profile.len() as f64;

    assert_close(mean, 2.0, 1.0e-14);
    assert!(profile[2] > profile[1]);
    assert!(profile[1] > profile[0]);
    assert_eq!(
        spectral_profile_from_optical_depth(&wavelengths, 2.0, &proxy[..2]),
        Err(Error::ShapeMismatch)
    );
}

#[test]
fn climatology_profile_interpolates_and_densifies_vendor_pressure_grid() {
    let profile = ClimatologyProfile {
        rows: vec![
            ClimatologyPoint {
                altitude_km: 0.0,
                pressure_hpa: 1000.0,
                temperature_k: 300.0,
                air_number_density_cm3: 2.0,
            },
            ClimatologyPoint {
                altitude_km: 8.0,
                pressure_hpa: 300.0,
                temperature_k: 250.0,
                air_number_density_cm3: 1.0,
            },
            ClimatologyPoint {
                altitude_km: 16.0,
                pressure_hpa: 100.0,
                temperature_k: 220.0,
                air_number_density_cm3: 0.5,
            },
        ],
    };

    assert_close(profile.mean_number_density(), 7.0 / 6.0, 1.0e-14);
    assert_close(profile.interpolate_density(4.0), 1.5, 1.0e-14);
    assert_close(profile.interpolate_temperature(4.0), 275.0, 1.0e-14);
    assert_close(profile.interpolate_pressure(4.0), 650.0, 1.0e-14);
    assert_close(profile.interpolate_pressure_log_linear(8.0), 300.0, 1.0e-12);
    assert_close(
        profile.interpolate_altitude_for_pressure(300.0),
        8.0,
        1.0e-12,
    );

    let dense = profile.densify_vendor_pressure_grid(1000.0).unwrap();
    assert!(dense.rows.len() > profile.rows.len());
    assert_close(dense.rows[0].pressure_hpa, 1000.0, 0.0);
    assert_close(dense.rows[0].altitude_km, 0.0, 1.0e-12);
    assert!(
        dense
            .rows
            .windows(2)
            .all(|pair| pair[0].pressure_hpa > pair[1].pressure_hpa)
    );
    assert!(
        dense
            .rows
            .windows(2)
            .all(|pair| pair[0].altitude_km < pair[1].altitude_km)
    );
    assert_close(
        dense.rows[0].air_number_density_cm3,
        1000.0 / 300.0 / 1.380658e-19,
        1.0e6,
    );
}

#[test]
fn cross_section_table_interpolates_and_averages_ranges() {
    let table = CrossSectionTable {
        points: vec![
            CrossSectionPoint {
                wavelength_nm: 760.0,
                sigma_cm2_per_molecule: 1.0,
            },
            CrossSectionPoint {
                wavelength_nm: 762.0,
                sigma_cm2_per_molecule: 3.0,
            },
            CrossSectionPoint {
                wavelength_nm: 764.0,
                sigma_cm2_per_molecule: 5.0,
            },
        ],
    };

    assert_close(table.interpolate_sigma(761.0), 2.0, 1.0e-14);
    assert_close(table.interpolate_sigma(700.0), 1.0, 0.0);
    assert_close(table.interpolate_sigma(800.0), 5.0, 0.0);
    assert_eq!(table.bracket_for_wavelength(761.0), Some((0, 1)));
    assert_close(table.sigma_at_high_resolution(763.0), 4.0, 1.0e-14);
    assert_close(table.mean_sigma_in_range(760.0, 762.0), 2.0, 1.0e-14);
    assert_close(table.mean_sigma_in_range(765.0, 766.0), 5.0, 0.0);
}

#[test]
fn collision_induced_absorption_table_evaluates_temperature_polynomial() {
    let table = CollisionInducedAbsorptionTable {
        scale_factor_cm5_per_molecule2: 2.0,
        points: vec![
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 760.0,
                a0: 1.0,
                a1: 0.1,
                a2: 0.01,
            },
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 762.0,
                a0: 3.0,
                a1: 0.3,
                a2: 0.03,
            },
            CollisionInducedAbsorptionPoint {
                wavelength_nm: 764.0,
                a0: 5.0,
                a1: 0.5,
                a2: 0.05,
            },
        ],
    };
    let temperature_k = 274.15;

    assert_close(table.sigma_at(761.0, temperature_k), 4.44, 1.0e-14);
    assert_close(
        table.d_sigma_d_temperature_at(761.0, temperature_k),
        0.48,
        1.0e-14,
    );
    assert_close(
        table.mean_sigma_in_range(760.0, 762.0, temperature_k),
        (2.22 + 6.66) * 0.5,
        1.0e-14,
    );
    let coefficients = table.interpolate_coefficients(765.0);
    assert_close(coefficients.a0, 5.0, 0.0);
}

#[test]
fn collision_induced_absorption_clamps_negative_sigma_and_derivative() {
    let table = CollisionInducedAbsorptionTable {
        scale_factor_cm5_per_molecule2: 3.0,
        points: vec![CollisionInducedAbsorptionPoint {
            wavelength_nm: 760.0,
            a0: -1.0,
            a1: 0.0,
            a2: 0.0,
        }],
    };

    assert_close(table.sigma_at(760.0, 273.15), 0.0, 0.0);
    assert_close(table.d_sigma_d_temperature_at(760.0, 273.15), 0.0, 0.0);
    assert_close(table.mean_sigma_in_range(761.0, 762.0, 273.15), 0.0, 0.0);
}
