use crate::forward_model::instrument_grid::spectral_math::sampling;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
    InvalidNoiseScaleFactor,
    InvalidInputNoiseSigma,
    MissingInputNoiseSigma,
    MissingReferenceSignal,
    InvalidReferenceSignal,
    SingularWhiteningWeight,
    UnsupportedS5OperationalRange,
}

pub fn shot_noise_std(
    signal: &[f64],
    electrons_per_count: f64,
    output: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    if !electrons_per_count.is_finite() || electrons_per_count <= 0.0 {
        return Err(Error::InvalidNoiseScaleFactor);
    }
    for (&sample, slot) in signal.iter().zip(output) {
        let electrons = (sample * electrons_per_count).max(0.0);
        *slot = electrons.sqrt() / electrons_per_count;
    }
    Ok(())
}

pub fn whiten_residuals(residual: &[f64], sigma: &[f64], output: &mut [f64]) -> Result<(), Error> {
    if residual.len() != sigma.len() || residual.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    for ((&value, &sigma_value), slot) in residual.iter().zip(sigma).zip(output) {
        if !sigma_value.is_finite() || sigma_value <= 0.0 {
            return Err(Error::SingularWhiteningWeight);
        }
        *slot = value / sigma_value;
    }
    Ok(())
}

pub fn copy_input_sigma(input_sigma: &[f64], output: &mut [f64]) -> Result<(), Error> {
    if input_sigma.is_empty() {
        return Err(Error::MissingInputNoiseSigma);
    }
    if input_sigma.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    for (&sigma_value, slot) in input_sigma.iter().zip(output) {
        if !sigma_value.is_finite() || sigma_value <= 0.0 {
            return Err(Error::InvalidInputNoiseSigma);
        }
        *slot = sigma_value;
    }
    Ok(())
}

pub fn scale_sigma_from_reference(
    reference_signal: &[f64],
    reference_sigma: &[f64],
    current_signal: &[f64],
    reference_bin_width_nm: f64,
    current_bin_width_nm: f64,
    output: &mut [f64],
) -> Result<(), Error> {
    if reference_signal.is_empty() {
        return Err(Error::MissingReferenceSignal);
    }
    if reference_signal.len() != reference_sigma.len()
        || reference_signal.len() != current_signal.len()
        || reference_signal.len() != output.len()
    {
        return Err(Error::ShapeMismatch);
    }
    if !reference_bin_width_nm.is_finite()
        || reference_bin_width_nm <= 0.0
        || !current_bin_width_nm.is_finite()
        || current_bin_width_nm <= 0.0
    {
        return Err(Error::InvalidNoiseScaleFactor);
    }

    let bin_width_scale = (reference_bin_width_nm / current_bin_width_nm).sqrt();
    for (((&reference_value, &sigma_value), &signal_value), slot) in reference_signal
        .iter()
        .zip(reference_sigma)
        .zip(current_signal)
        .zip(output)
    {
        if !reference_value.is_finite() || reference_value <= 0.0 {
            return Err(Error::InvalidReferenceSignal);
        }
        if !signal_value.is_finite() || signal_value < 0.0 {
            return Err(Error::InvalidReferenceSignal);
        }
        if !sigma_value.is_finite() || sigma_value <= 0.0 {
            return Err(Error::InvalidInputNoiseSigma);
        }

        *slot = sigma_value * (signal_value / reference_value).sqrt() * bin_width_scale;
    }
    Ok(())
}

pub fn sigma_from_interpolated_signal_to_noise(
    wavelengths_nm: &[f64],
    snr_wavelengths_nm: &[f64],
    snr_values: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != signal.len() || signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    if snr_wavelengths_nm.is_empty() || snr_wavelengths_nm.len() != snr_values.len() {
        return Err(Error::InvalidNoiseScaleFactor);
    }
    if snr_wavelengths_nm.len() == 1 {
        let snr_value = snr_values[0];
        if !snr_value.is_finite() || snr_value <= 0.0 {
            return Err(Error::InvalidNoiseScaleFactor);
        }
        for (&signal_value, slot) in signal.iter().zip(output) {
            if !signal_value.is_finite() || signal_value < 0.0 {
                return Err(Error::InvalidReferenceSignal);
            }
            *slot = signal_value / snr_value;
        }
        return Ok(());
    }
    for ((&wavelength_nm, &signal_value), slot) in wavelengths_nm.iter().zip(signal).zip(output) {
        if !signal_value.is_finite() || signal_value < 0.0 {
            return Err(Error::InvalidReferenceSignal);
        }
        let snr_value = sampling::sample_linear_clamped_assume_valid(
            snr_wavelengths_nm,
            snr_values,
            wavelength_nm,
        );
        if !snr_value.is_finite() || snr_value <= 0.0 {
            return Err(Error::InvalidNoiseScaleFactor);
        }
        *slot = signal_value / snr_value;
    }
    Ok(())
}

pub fn sigma_from_lab_operational(
    signal: &[f64],
    a: f64,
    b: f64,
    output: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    if !a.is_finite() || a <= 0.0 || !b.is_finite() || b < 0.0 {
        return Err(Error::InvalidNoiseScaleFactor);
    }
    for (&signal_value, slot) in signal.iter().zip(output) {
        if !signal_value.is_finite() || signal_value < 0.0 {
            return Err(Error::InvalidReferenceSignal);
        }
        *slot = (a * signal_value + b * b).sqrt() / a;
    }
    Ok(())
}

pub fn sigma_from_s5_operational(
    wavelengths_nm: &[f64],
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != signal.len() || signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }

    for ((&wavelength_nm, &signal_value), slot) in wavelengths_nm.iter().zip(signal).zip(output) {
        if !wavelength_nm.is_finite() || !signal_value.is_finite() || signal_value < 0.0 {
            return Err(Error::InvalidReferenceSignal);
        }
        let coefficients = s5_operational_coefficients(wavelength_nm)?;
        *slot = (coefficients.a * signal_value + coefficients.b).sqrt() / coefficients.a;
    }
    Ok(())
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct S5Coefficients {
    a: f64,
    b: f64,
}

fn s5_operational_coefficients(wavelength_nm: f64) -> Result<S5Coefficients, Error> {
    let a_1 = 4.70194461239e-05;
    let b_1 = 3449239.8849;
    let a0_4 = 4.67913725e-06;
    let a1_4 = -1.26105546e-05;
    let a2_4 = 1.39147643e-05;
    let a3_4 = -5.39067088e-06;
    let b0_4 = -407188.40771951;
    let b1_4 = 1161526.66109376;
    let a0_2 = 3.03796420e-07;
    let a1_2 = -6.81549664e-07;
    let a2_2 = 6.78226603e-07;
    let a3_2 = -2.70807116e-07;
    let b0_2 = 131105.24706965;
    let b1_2 = 15500.79117382;
    let a_3 = 3.7839338322e-07;
    let b_3 = 787116.299872;

    if !(270.0..=500.0).contains(&wavelength_nm) || (wavelength_nm > 300.0 && wavelength_nm < 303.0)
    {
        return Err(Error::UnsupportedS5OperationalRange);
    }
    if wavelength_nm <= 300.0 {
        return Ok(S5Coefficients { a: a_1, b: b_1 });
    }
    if (303.0..=310.0).contains(&wavelength_nm) {
        let d = (wavelength_nm - 302.0) / 8.0;
        return Ok(S5Coefficients {
            a: a0_4 + a1_4 * d + a2_4 * d * d + a3_4 * d * d * d,
            b: b0_4 + b1_4 / d,
        });
    }
    if wavelength_nm > 310.0 && wavelength_nm < 330.0 {
        let d = (wavelength_nm - 309.0) / 21.0;
        return Ok(S5Coefficients {
            a: a0_2 + a1_2 * d + a2_2 * d * d + a3_2 * d * d * d,
            b: b0_2 + b1_2 / d,
        });
    }
    Ok(S5Coefficients { a: a_3, b: b_3 })
}
