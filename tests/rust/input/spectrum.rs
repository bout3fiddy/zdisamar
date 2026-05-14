use zdisamar::{common::errors, input::spectrum::SpectralGrid};

#[test]
fn spectral_grid_validates_wavelength_range_and_sample_count() {
    assert_eq!(
        SpectralGrid {
            start_nm: 758.0,
            end_nm: 771.0,
            sample_count: 121,
        }
        .validate(),
        Ok(())
    );
    assert_eq!(
        SpectralGrid {
            start_nm: 771.0,
            end_nm: 758.0,
            sample_count: 121,
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
    assert_eq!(
        SpectralGrid {
            start_nm: 758.0,
            end_nm: 771.0,
            sample_count: 0,
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}
