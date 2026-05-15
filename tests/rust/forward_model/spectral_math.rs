use zdisamar::{
    forward_model::instrument_grid::spectral_math::{
        calibration::{self, Calibration},
        convolution, grid, noise, sampling,
    },
    input::instrument::{
        NodalCorrection, ReflectanceCalibration, RingControls, SimpleOffsets, SinusoidalFeatures,
    },
};

#[test]
fn spectral_grid_samples_uniform_and_explicit_axes() {
    let base = grid::SpectralGrid {
        start_nm: 760.0,
        end_nm: 761.0,
        sample_count: 3,
    };
    assert_eq!(base.sample_at(1), Ok(760.5));
    assert_eq!(base.sample_at(3), Err(grid::Error::IndexOutOfRange));

    let axis = grid::ResolvedAxis {
        base,
        explicit_wavelengths_nm: vec![760.0, 760.2, 761.0],
    };
    assert_eq!(axis.validate(), Ok(()));
    assert_eq!(axis.sample_at(1), Ok(760.2));
    assert_eq!(
        grid::validate_explicit_samples(&[760.0, 760.0]),
        Err(grid::Error::InvalidExplicitSamples)
    );
}

#[test]
fn linear_sampling_clamps_and_interpolates() {
    let x = [1.0, 2.0, 4.0];
    let y = [10.0, 20.0, 60.0];
    assert_eq!(sampling::sample_linear_clamped(&x, &y, 0.0), Ok(10.0));
    assert_eq!(sampling::sample_linear_clamped(&x, &y, 3.0), Ok(40.0));
    assert_eq!(sampling::sample_linear_clamped(&x, &y, 5.0), Ok(60.0));
}

#[test]
fn noise_helpers_compute_sigma_and_whiten_residuals() {
    let mut output = [0.0; 2];
    noise::shot_noise_std(&[4.0, 9.0], 4.0, &mut output).unwrap();
    assert_eq!(output, [1.0, 1.5]);

    noise::whiten_residuals(&[2.0, -3.0], &[0.5, 1.5], &mut output).unwrap();
    assert_eq!(output, [4.0, -2.0]);
    assert_eq!(
        noise::copy_input_sigma(&[], &mut output),
        Err(noise::Error::MissingInputNoiseSigma)
    );
}

#[test]
fn noise_helpers_scale_reference_and_snr_inputs() {
    let mut output = [0.0; 2];
    noise::scale_sigma_from_reference(
        &[100.0, 400.0],
        &[1.0, 2.0],
        &[25.0, 100.0],
        0.2,
        0.05,
        &mut output,
    )
    .unwrap();
    assert_eq!(output, [1.0, 2.0]);

    noise::sigma_from_interpolated_signal_to_noise(
        &[760.0, 761.0],
        &[760.0, 762.0],
        &[10.0, 20.0],
        &[100.0, 150.0],
        &mut output,
    )
    .unwrap();
    assert_eq!(output, [10.0, 10.0]);
}

#[test]
fn operational_noise_models_match_reference_formulas() {
    let mut output = [0.0; 1];
    noise::sigma_from_lab_operational(&[100.0], 2.0, 3.0, &mut output).unwrap();
    assert!((output[0] - (209.0_f64.sqrt() / 2.0)).abs() < 1.0e-14);

    noise::sigma_from_s5_operational(&[300.0], &[100.0], &mut output).unwrap();
    let expected = (4.70194461239e-05_f64 * 100.0 + 3449239.8849).sqrt() / 4.70194461239e-05;
    assert!((output[0] - expected).abs() < 1.0e-6);
    assert_eq!(
        noise::sigma_from_s5_operational(&[301.0], &[100.0], &mut output),
        Err(noise::Error::UnsupportedS5OperationalRange)
    );
}

#[test]
fn convolution_normalizes_truncated_edge_kernels() {
    let mut output = [0.0; 3];
    convolution::apply(&[1.0, 2.0, 3.0], &[1.0, 1.0, 1.0], &mut output).unwrap();
    assert_eq!(output, [1.5, 2.0, 2.5]);
    assert_eq!(
        convolution::apply(&[1.0], &[], &mut [0.0]),
        Err(convolution::Error::KernelShapeMismatch)
    );
}

#[test]
fn calibration_applies_gain_offsets_smear_and_wavelength_shift() {
    let calibration = Calibration {
        gain: 2.0,
        offset: 1.0,
        wavelength_shift_nm: 0.2,
        stray_light: 0.5,
    };
    let mut output = [0.0; 2];
    calibration::apply_signal(calibration, &[2.0, 6.0], &mut output).unwrap();
    assert_eq!(output, [7.0, 11.0]);
    calibration::apply_signal_derivative(calibration, &[2.0, 6.0], &mut output).unwrap();
    assert_eq!(output, [6.0, 10.0]);
    assert_eq!(calibration::shifted_wavelength(calibration, 760.0), 760.2);

    let mut signal = [10.0, 20.0];
    calibration::apply_simple_offsets(
        SimpleOffsets {
            multiplicative_percent: 10.0,
            additive_percent_of_first: 5.0,
        },
        &mut signal,
    );
    assert_eq!(signal, [11.5, 22.5]);

    let mut scratch = [0.0; 3];
    let mut smeared = [10.0, 20.0, 30.0];
    calibration::apply_smear(10.0, &mut smeared, &mut scratch).unwrap();
    assert_eq!(smeared, [10.0, 18.9, 32.1]);
}

#[test]
fn calibration_applies_spectral_features_and_nodal_corrections() {
    let mut signal = [10.0, 10.0, 10.0];
    calibration::apply_spectral_features(
        SinusoidalFeatures {
            additive_amplitude_percent: 10.0,
            additive_period_nm: 2.0,
            additive_phase_deg: 0.0,
            ..SinusoidalFeatures::default()
        },
        &[760.0, 760.5, 761.0],
        &mut signal,
    )
    .unwrap();
    assert!((signal[1] - 11.0).abs() < 1.0e-14);

    let correction = NodalCorrection {
        wavelengths_nm: vec![760.0, 761.0],
        values: vec![0.0, 10.0],
        use_linear_interpolation: true,
        ..NodalCorrection::default()
    };
    let mut multiplicative = [10.0, 10.0, 10.0];
    let mut scratch = [0.0; 3];
    calibration::apply_multiplicative_nodes(
        &correction,
        &[760.0, 760.5, 761.0],
        &mut multiplicative,
        &mut scratch,
    )
    .unwrap();
    assert_eq!(multiplicative, [10.0, 10.5, 11.0]);
}

#[test]
fn calibration_applies_ring_polarization_and_reflectance_sigma() {
    let ring = RingControls {
        enabled: true,
        coefficient: 0.1,
        fraction_raman_lines: 1.0,
        ..RingControls::default()
    };
    let mut radiance = [1.0, 1.0, 1.0];
    let mut scratch = [0.0; 3];
    calibration::apply_ring_spectrum(
        &ring,
        &[760.0, 761.0, 762.0],
        &[8.0, 10.0, 12.0],
        &mut radiance,
        &mut scratch,
    )
    .unwrap();
    assert_eq!(radiance, [1.1600000000000001, 1.0, 0.76]);

    calibration::apply_polarization_scrambler_bias(
        false,
        0.2,
        &[760.0, 761.0, 762.0],
        &mut radiance,
    )
    .unwrap();
    assert!((radiance[0] - 1.0788).abs() < 1.0e-14);

    let calibration_error = ReflectanceCalibration {
        multiplicative_error: NodalCorrection {
            wavelengths_nm: vec![760.0],
            values: vec![10.0],
            ..NodalCorrection::default()
        },
        ..ReflectanceCalibration::default()
    };
    let mut sigma = [0.1, 0.1, 0.1];
    calibration::apply_reflectance_calibration_error_sigma(
        &calibration_error,
        &[760.0, 761.0, 762.0],
        &[0.5, 0.5, 0.5],
        &mut sigma,
        &mut scratch,
    )
    .unwrap();
    assert!((sigma[0] - (0.0125_f64).sqrt()).abs() < 1.0e-14);
}
