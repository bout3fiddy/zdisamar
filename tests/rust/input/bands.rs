use zdisamar::{
    common::errors,
    input::bands::{SpectralBand, SpectralBandSet, SpectralWindow},
};

#[test]
fn spectral_band_set_rejects_duplicate_ids_and_invalid_exclusion_windows() {
    let valid = SpectralBandSet {
        items: vec![SpectralBand {
            id: "o2a".to_string(),
            start_nm: 758.0,
            end_nm: 771.0,
            step_nm: 0.01,
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
        }],
    };
    assert_eq!(valid.validate(), Ok(()));

    assert_eq!(
        SpectralBandSet {
            items: vec![
                SpectralBand {
                    id: "o2a".to_string(),
                    start_nm: 758.0,
                    end_nm: 771.0,
                    step_nm: 0.01,
                    ..SpectralBand::default()
                },
                SpectralBand {
                    id: "o2a".to_string(),
                    start_nm: 772.0,
                    end_nm: 775.0,
                    step_nm: 0.01,
                    ..SpectralBand::default()
                },
            ],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );

    assert_eq!(
        SpectralBand {
            id: "o2a".to_string(),
            start_nm: 758.0,
            end_nm: 771.0,
            step_nm: 0.01,
            exclude: vec![
                SpectralWindow {
                    start_nm: 759.8,
                    end_nm: 760.0,
                },
                SpectralWindow {
                    start_nm: 759.9,
                    end_nm: 760.1,
                },
            ],
        }
        .validate(),
        Err(errors::Error::InvalidRequest)
    );
}
