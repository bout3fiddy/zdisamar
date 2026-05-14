use zdisamar::forward_model::instrument_grid::spectral_math::{grid, noise, sampling};

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
