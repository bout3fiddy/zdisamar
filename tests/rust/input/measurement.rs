use zdisamar::{
    common::errors::Error,
    input::{
        Binding, ErrorModel, Measurement, NamedRef, Quantity, SpectralGrid, SpectralMask,
        SpectralWindow,
    },
};

#[test]
fn spectral_grid_requires_valid_bounds_and_samples() {
    assert_eq!(
        SpectralGrid {
            start_nm: 755.0,
            end_nm: 770.0,
            sample_count: 121,
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        SpectralGrid {
            sample_count: 0,
            ..SpectralGrid::default()
        }
        .validate(),
        Err(Error::InvalidRequest)
    );
}

#[test]
fn measurement_validates_source_masks_and_error_model() {
    let measurement = Measurement {
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
    };

    assert_eq!(measurement.validate(), Ok(()));
    assert_eq!(measurement.resolved_product_name(), "radiance");
    assert!(measurement.error_model.defines_covariance());
    assert_eq!(Quantity::parse("slant_column"), Ok(Quantity::SlantColumn));
}

#[test]
fn measurement_sample_selection_honors_excluded_windows() {
    let measurement = Measurement {
        product_name: "radiance".to_string(),
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

    assert!(measurement.includes_wavelength(759.5));
    assert!(!measurement.includes_wavelength(760.5));
    assert_eq!(measurement.selected_sample_count(&wavelengths), 3);
}
