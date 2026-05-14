use zdisamar::common::{
    errors::Error,
    lut_controls::{CompatibilityKey, Controls, Mode, ReflectanceControls, XsecControls},
};

#[test]
fn mode_labels_and_parsing_match_zig_tags() {
    assert_eq!(Mode::Direct.label(), "direct");
    assert_eq!(Mode::Generate.label(), "generate");
    assert_eq!(Mode::Consume.label(), "consume");
    assert_eq!(Mode::parse("generate"), Some(Mode::Generate));
    assert_eq!(Mode::parse("missing"), None);
}

#[test]
fn reflectance_controls_enable_and_validate_non_negative_albedo() {
    assert!(!ReflectanceControls::default().enabled());
    let controls = ReflectanceControls {
        reflectance_mode: Mode::Generate,
        surface_albedo: 0.2,
        ..ReflectanceControls::default()
    };

    assert!(controls.enabled());
    assert_eq!(controls.validate(), Ok(()));
    assert!(controls.matches(ReflectanceControls {
        reflectance_mode: Mode::Generate,
        surface_albedo: 0.2 + 5.0e-13,
        ..ReflectanceControls::default()
    }));
    assert_eq!(
        ReflectanceControls {
            surface_albedo: -0.1,
            ..ReflectanceControls::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn xsec_controls_validate_non_direct_dimensions() {
    assert_eq!(XsecControls::default().validate(), Ok(()));
    let controls = XsecControls {
        mode: Mode::Consume,
        min_temperature_k: 200.0,
        max_temperature_k: 300.0,
        min_pressure_hpa: 100.0,
        max_pressure_hpa: 900.0,
        temperature_grid_count: 5,
        pressure_grid_count: 4,
        temperature_coefficient_count: 3,
        pressure_coefficient_count: 2,
    };

    assert!(controls.enabled());
    assert_eq!(controls.validate(), Ok(()));
    assert_eq!(controls.coefficient_count(), 6);
    assert!(controls.matches(controls));
    assert_eq!(
        XsecControls {
            temperature_coefficient_count: 6,
            ..controls
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn compatibility_key_requires_one_sampling_grid_shape() {
    let controls = Controls {
        reflectance: ReflectanceControls {
            reflectance_mode: Mode::Generate,
            surface_albedo: 0.2,
            ..ReflectanceControls::default()
        },
        ..Controls::default()
    };
    let base = CompatibilityKey {
        controls,
        spectral_start_nm: 755.0,
        spectral_end_nm: 770.0,
        nominal_sample_count: 10,
        surface_albedo: 0.2,
        instrument_line_fwhm_nm: 0.4,
        ..CompatibilityKey::default()
    };

    assert_eq!(base.validate(), Ok(()));
    assert!(base.enabled());
    assert!(base.matches(CompatibilityKey {
        spectral_start_nm: 755.0 + 5.0e-13,
        ..base
    }));
    assert_eq!(
        CompatibilityKey {
            high_resolution_step_nm: 0.01,
            ..base
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
    assert_eq!(
        CompatibilityKey {
            high_resolution_step_nm: 0.01,
            high_resolution_half_span_nm: 0.5,
            nominal_sample_count: 0,
            ..base
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn disabled_compatibility_key_only_validates_nested_controls() {
    let key = CompatibilityKey::default();

    assert!(!key.enabled());
    assert_eq!(key.validate(), Ok(()));
}
