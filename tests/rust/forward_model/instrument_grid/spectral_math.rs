use zdisamar::{
    forward_model::instrument_grid::spectral_math::{
        calibration, convolution, grid, noise, sampling,
    },
    input::{
        NodalCorrection, ReflectanceCalibration, RingControls, SimpleOffsets, SinusoidalFeatures,
    },
};

fn assert_close(left: f64, right: f64) {
    assert!((left - right).abs() <= 1.0e-10, "{left} != {right}");
}

#[test]
fn spectral_grid_validates_native_and_explicit_coordinates() {
    let native = grid::SpectralGrid {
        start_nm: 758.0,
        end_nm: 771.0,
        sample_count: 7,
    };

    native.validate().unwrap();
    assert_close(native.sample_at(0).unwrap(), 758.0);
    assert_close(native.sample_at(6).unwrap(), 771.0);
    assert_eq!(native.sample_at(7), Err(grid::Error::IndexOutOfRange));

    grid::validate_explicit_samples(&[760.8, 761.02, 761.31]).unwrap();
    assert_close(
        grid::sample_at_explicit(&[760.8, 761.02, 761.31], 1).unwrap(),
        761.02,
    );
    assert_eq!(
        grid::validate_explicit_samples(&[761.0, 760.9]),
        Err(grid::Error::InvalidExplicitSamples)
    );

    let measured = grid::ResolvedAxis {
        base: grid::SpectralGrid {
            start_nm: 760.0,
            end_nm: 761.0,
            sample_count: 3,
        },
        explicit_wavelengths_nm: &[760.02, 760.41, 760.93],
    };
    assert_close(measured.sample_at(1).unwrap(), 760.41);
}

#[test]
fn sampling_and_convolution_match_zig_edge_behavior() {
    let wavelengths = [760.0, 760.2, 760.4];
    let values = [1.0, 3.0, 5.0];

    assert_close(
        sampling::sample_linear_clamped(&wavelengths, &values, 760.1).unwrap(),
        2.0,
    );
    assert_eq!(
        sampling::sample_linear_clamped(&wavelengths, &values, 759.9).unwrap(),
        1.0
    );
    assert_eq!(
        sampling::sample_linear_clamped(&wavelengths, &values, 760.5).unwrap(),
        5.0
    );

    let signal = [0.0, 0.0, 10.0, 0.0, 0.0];
    let kernel = [1.0, 2.0, 1.0];
    let mut output = [0.0; 5];
    convolution::apply(&signal, &kernel, &mut output).unwrap();
    assert!(output[2] < signal[2]);
    assert!(output[1] > 0.0);
}

#[test]
fn noise_helpers_cover_sigma_and_whitening_contracts() {
    let signal = [100.0, 400.0];
    let mut sigma = [0.0; 2];
    noise::shot_noise_std(&signal, 2.0, &mut sigma).unwrap();

    let residual = [5.0, 10.0];
    let mut whitened = [0.0; 2];
    noise::whiten_residuals(&residual, &sigma, &mut whitened).unwrap();
    assert!(sigma[1] > sigma[0]);
    assert!(whitened[0] > 0.0);

    assert_eq!(
        noise::shot_noise_std(&[100.0], 0.0, &mut [0.0]),
        Err(noise::Error::InvalidNoiseScaleFactor)
    );
    assert_eq!(
        noise::whiten_residuals(&[5.0], &[0.0], &mut [0.0]),
        Err(noise::Error::SingularWhiteningWeight)
    );
    assert_eq!(
        noise::copy_input_sigma(&[], &mut [0.0, 0.0]),
        Err(noise::Error::MissingInputNoiseSigma)
    );
    assert_eq!(
        noise::copy_input_sigma(&[0.02, 0.0], &mut [0.0, 0.0]),
        Err(noise::Error::InvalidInputNoiseSigma)
    );
}

#[test]
fn noise_helpers_scale_reference_snr_and_operational_models() {
    let mut sigma = [0.0; 2];
    noise::scale_sigma_from_reference(
        &[10.0, 20.0],
        &[0.1, 0.2],
        &[40.0, 5.0],
        0.20,
        0.10,
        &mut sigma,
    )
    .unwrap();
    assert_close(sigma[0], 0.28284271247461906);
    assert_close(sigma[1], 0.14142135623730953);

    assert_eq!(
        noise::sigma_from_interpolated_signal_to_noise(
            &[310.0, 312.0],
            &[311.0],
            &[0.0],
            &[100.0, 120.0],
            &mut [0.0; 2],
        ),
        Err(noise::Error::InvalidNoiseScaleFactor)
    );

    let wavelengths = [290.0, 320.0, 450.0];
    let signal = [1.2e6, 1.5e6, 2.0e6];
    let mut lab_sigma = [0.0; 3];
    let mut s5_sigma = [0.0; 3];
    noise::sigma_from_lab_operational(&signal, 3.5e-6, 1500.0, &mut lab_sigma).unwrap();
    noise::sigma_from_s5_operational(&wavelengths, &signal, &mut s5_sigma).unwrap();
    assert!(lab_sigma[0] > 0.0);
    assert!(s5_sigma[0] > 0.0);
    assert_ne!(s5_sigma[1], s5_sigma[2]);
}

#[test]
fn calibration_applies_signal_offsets_features_and_smear() {
    let cal = calibration::Calibration {
        gain: 2.0,
        offset: -1.0,
        wavelength_shift_nm: 0.2,
        stray_light: 0.25,
    };
    let signal = [1.0, 2.0, 3.0];
    let mut output = [0.0; 3];
    calibration::apply_signal(cal, &signal, &mut output).unwrap();
    assert_close(output[0], 1.5);
    assert_close(output[1], 3.0);
    assert_close(output[2], 4.5);
    assert_close(calibration::shifted_wavelength(cal, 410.0), 410.2);

    calibration::apply_signal_derivative(cal, &signal, &mut output).unwrap();
    assert_close(output[0], 2.5);
    assert_close(output[1], 4.0);
    assert_close(output[2], 5.5);

    let wavelengths = [760.8, 761.0, 761.2];
    let mut corrected = [10.0, 11.0, 12.0];
    let mut scratch = [0.0; 3];
    calibration::apply_simple_offsets(
        SimpleOffsets {
            multiplicative_percent: 2.0,
            additive_percent_of_first: 1.0,
        },
        &mut corrected,
    )
    .unwrap();
    calibration::apply_spectral_features(
        SinusoidalFeatures {
            multiplicative_amplitude_percent: 1.0,
            multiplicative_period_nm: 0.4,
            additive_amplitude_percent: 0.5,
            additive_period_nm: 0.4,
            ..SinusoidalFeatures::default()
        },
        &wavelengths,
        &mut corrected,
    )
    .unwrap();
    calibration::apply_smear(2.0, &mut corrected, &mut scratch).unwrap();
    calibration::apply_multiplicative_nodes(
        &NodalCorrection {
            wavelengths_nm: wavelengths.to_vec(),
            values: vec![1.0, 0.0, -1.0],
            use_linear_interpolation: true,
            ..NodalCorrection::default()
        },
        &wavelengths,
        &mut corrected,
        &mut scratch,
    )
    .unwrap();
    assert!(corrected[0] > 10.0);
    assert!(corrected[2] > corrected[0]);
}

#[test]
fn calibration_derivatives_and_biases_match_zig_rules() {
    let wavelengths = [760.8, 760.9, 761.0];
    let mut signal = [10.0, 11.0, 12.0];

    calibration::apply_simple_offset_derivatives(
        SimpleOffsets {
            multiplicative_percent: 2.0,
            additive_percent_of_first: 5.0,
        },
        &mut signal,
    )
    .unwrap();
    calibration::apply_spectral_feature_derivatives(
        SinusoidalFeatures {
            additive_amplitude_percent: 3.0,
            additive_period_nm: 0.4,
            multiplicative_amplitude_percent: 1.0,
            multiplicative_period_nm: 0.4,
            ..SinusoidalFeatures::default()
        },
        &wavelengths,
        &mut signal,
    )
    .unwrap();

    assert_close(signal[0], 10.7);
    assert_close(signal[1], 12.1582);
    assert_close(signal[2], 12.74);

    let mut disabled_signal = [10.0, 10.0, 10.0];
    let mut enabled_signal = [10.0, 10.0, 10.0];
    calibration::apply_polarization_scrambler_bias(false, 0.03, &wavelengths, &mut disabled_signal)
        .unwrap();
    calibration::apply_polarization_scrambler_bias(true, 0.03, &wavelengths, &mut enabled_signal)
        .unwrap();
    assert!(disabled_signal[0] < 10.0);
    assert_close(disabled_signal[1], 10.0);
    assert!(disabled_signal[2] > 10.0);
    assert_eq!(enabled_signal, [10.0, 10.0, 10.0]);
}

#[test]
fn calibration_handles_stray_light_ring_and_systematic_sigma_nodes() {
    let wavelengths = [760.0, 761.0, 762.0];
    let source = [100.0, 120.0, 140.0];
    let mut signal = [10.0, 11.0, 12.0];
    let mut scratch = [0.0; 3];

    calibration::apply_stray_light_nodes(
        &NodalCorrection {
            wavelengths_nm: vec![760.0, 762.0],
            values: vec![1.0, 2.0],
            characteristic_bias: vec![1.0, 0.5],
            use_linear_interpolation: true,
            ..NodalCorrection::default()
        },
        &wavelengths,
        &source,
        &mut signal,
        &mut scratch,
    )
    .unwrap();
    assert!(signal[0] > 10.0);
    assert!(signal[2] > 12.0);

    let mut radiance = [0.10, 0.11, 0.12];
    calibration::apply_ring_spectrum(
        &RingControls {
            enabled: true,
            coefficient: 0.01,
            fraction_raman_lines: 0.5,
            differential: true,
            ..RingControls::default()
        },
        &wavelengths,
        &source,
        &mut radiance,
        &mut scratch,
    )
    .unwrap();
    assert_ne!(radiance, [0.10, 0.11, 0.12]);

    let reflectance = [0.2, 0.25, 0.3];
    let mut sigma = [0.01, 0.01, 0.01];
    calibration::apply_reflectance_calibration_error_sigma(
        &ReflectanceCalibration {
            multiplicative_error: NodalCorrection {
                wavelengths_nm: vec![760.0, 762.0],
                values: vec![1.0, 2.0],
                use_linear_interpolation: true,
                ..NodalCorrection::default()
            },
            additive_error: NodalCorrection {
                wavelengths_nm: vec![760.0, 762.0],
                values: vec![0.5, 1.0],
                use_linear_interpolation: true,
                ..NodalCorrection::default()
            },
        },
        &wavelengths,
        &reflectance,
        &mut sigma,
        &mut scratch,
    )
    .unwrap();
    assert!(sigma.iter().all(|value| *value > 0.01));
}
