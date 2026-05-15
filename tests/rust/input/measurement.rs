use zdisamar::{
    common::errors,
    input::{
        bands::SpectralWindow,
        binding::{Binding, NamedRef},
        measurement::{ErrorModel, Measurement, Quantity, SpectralMask},
    },
};

#[test]
fn measurement_validates_source_masks_and_error_model() {
    assert_eq!(
        Measurement {
            product_name: "radiance".to_string(),
            observable: Quantity::Radiance,
            sample_count: 121,
            source: Binding::StageProduct(NamedRef {
                name: "truth_radiance".to_string(),
            }),
            mask: SpectralMask {
                band: "o2a".to_string(),
                exclude: vec![
                    SpectralWindow {
                        start_nm: 759.35,
                        end_nm: 759.55,
                    },
                    SpectralWindow {
                        start_nm: 770.50,
                        end_nm: 770.80,
                    },
                ],
            },
            error_model: ErrorModel {
                from_source_noise: true,
                floor: 1.0e-4,
            },
        }
        .validate(),
        Ok(())
    );
}

#[test]
fn measurement_sample_selection_honors_excluded_spectral_windows() {
    let value = Measurement {
        product_name: "radiance".to_string(),
        observable: Quantity::Radiance,
        sample_count: 3,
        source: Binding::StageProduct(NamedRef {
            name: "truth_radiance".to_string(),
        }),
        mask: SpectralMask {
            exclude: vec![SpectralWindow {
                start_nm: 760.0,
                end_nm: 761.0,
            }],
            ..SpectralMask::default()
        },
        ..Measurement::default()
    };
    let wavelengths = [759.5, 760.5, 761.5, 762.0];

    assert!(value.includes_wavelength(759.5));
    assert!(!value.includes_wavelength(760.5));
    assert_eq!(value.selected_sample_count(&wavelengths), 3);
}

#[test]
fn measurement_labels_and_covariance_flags_match_public_semantics() {
    assert_eq!(Quantity::parse("reflectance"), Ok(Quantity::Reflectance));
    assert_eq!(
        Quantity::parse("bad_quantity"),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        Measurement {
            observable: Quantity::SlantColumn,
            ..Measurement::default()
        }
        .resolved_product_name(),
        "slant_column"
    );
    assert!(
        ErrorModel {
            from_source_noise: false,
            floor: 0.1,
        }
        .defines_covariance()
    );
}
