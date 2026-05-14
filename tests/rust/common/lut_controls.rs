use zdisamar::common::{
    errors,
    lut_controls::{CompatibilityKey, Controls, Mode, ReflectanceControls, XsecControls},
};

#[test]
fn mode_labels_and_parser_match_control_file_values() {
    assert_eq!(Mode::Direct.label(), "direct");
    assert_eq!(Mode::Generate.label(), "generate");
    assert_eq!(Mode::Consume.label(), "consume");
    assert_eq!(Mode::parse("generate"), Some(Mode::Generate));
    assert_eq!(Mode::parse("unknown"), None);
}

#[test]
fn lut_controls_reject_incomplete_non_direct_xsec_settings() {
    assert_eq!(
        Controls {
            xsec: XsecControls {
                mode: Mode::Generate,
                ..XsecControls::default()
            },
            ..Controls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Controls {
            xsec: XsecControls {
                mode: Mode::Consume,
                ..XsecControls::default()
            },
            ..Controls::default()
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}

#[test]
fn lut_compatibility_keys_compare_all_scientific_inputs_explicitly() {
    let lhs = compatibility_key();
    let mut rhs = lhs;

    assert_eq!(lhs.validate(), Ok(()));
    assert_eq!(rhs.validate(), Ok(()));
    assert!(lhs.matches(rhs));

    rhs.lut_sampling_half_span_nm = 1.5;
    assert!(!lhs.matches(rhs));
}

#[test]
fn lut_compatibility_keys_tolerate_numerically_equivalent_float_inputs() {
    let lhs = compatibility_key();
    let mut rhs = lhs;

    rhs.controls.reflectance.surface_albedo += 5.0e-13;
    rhs.controls.xsec.max_temperature_k += 1.0e-10;
    rhs.spectral_start_nm += 5.0e-13;
    rhs.relative_azimuth_deg += 5.0e-13;
    rhs.high_resolution_half_span_nm += 5.0e-13;

    assert_eq!(lhs.validate(), Ok(()));
    assert_eq!(rhs.validate(), Ok(()));
    assert!(lhs.matches(rhs));

    rhs.instrument_line_fwhm_nm += 1.0e-6;
    assert!(!lhs.matches(rhs));
}

fn compatibility_key() -> CompatibilityKey {
    CompatibilityKey {
        controls: Controls {
            reflectance: ReflectanceControls {
                reflectance_mode: Mode::Generate,
                surface_albedo: 0.1,
                ..ReflectanceControls::default()
            },
            xsec: XsecControls {
                mode: Mode::Consume,
                min_temperature_k: 180.0,
                max_temperature_k: 325.0,
                min_pressure_hpa: 0.03,
                max_pressure_hpa: 1050.0,
                temperature_grid_count: 10,
                pressure_grid_count: 20,
                temperature_coefficient_count: 5,
                pressure_coefficient_count: 10,
            },
        },
        spectral_start_nm: 758.0,
        spectral_end_nm: 770.0,
        solar_zenith_deg: 60.0,
        viewing_zenith_deg: 30.0,
        relative_azimuth_deg: 120.0,
        surface_albedo: 0.1,
        instrument_line_fwhm_nm: 0.38,
        high_resolution_step_nm: 0.01,
        high_resolution_half_span_nm: 1.14,
        lut_sampling_half_span_nm: 1.14,
        ..CompatibilityKey::default()
    }
}
