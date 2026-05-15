use crate::{
    forward_model::instrument_grid::spectral_math::sampling,
    input::instrument::{
        NodalCorrection, ReflectanceCalibration, RingControls, SimpleOffsets, SinusoidalFeatures,
    },
};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Calibration {
    pub gain: f64,
    pub offset: f64,
    pub wavelength_shift_nm: f64,
    pub stray_light: f64,
}

impl Default for Calibration {
    fn default() -> Self {
        Self {
            gain: 1.0,
            offset: 0.0,
            wavelength_shift_nm: 0.0,
            stray_light: 0.0,
        }
    }
}

pub fn apply_signal(
    calibration: Calibration,
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    if signal.is_empty() {
        return Ok(());
    }

    let mean_signal = spectral_mean(signal);
    for (&sample, slot) in signal.iter().zip(output) {
        let stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        *slot = calibration.gain * stray_mixed + calibration.offset;
    }
    Ok(())
}

pub fn apply_signal_derivative(
    calibration: Calibration,
    signal: &[f64],
    output: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != output.len() {
        return Err(Error::ShapeMismatch);
    }
    if signal.is_empty() {
        return Ok(());
    }

    let mean_signal = spectral_mean(signal);
    for (&sample, slot) in signal.iter().zip(output) {
        let stray_mixed = sample + calibration.stray_light * (mean_signal - sample);
        *slot = calibration.gain * stray_mixed;
    }
    Ok(())
}

pub fn shifted_wavelength(calibration: Calibration, wavelength_nm: f64) -> f64 {
    wavelength_nm + calibration.wavelength_shift_nm
}

pub fn apply_simple_offsets(offsets: SimpleOffsets, signal: &mut [f64]) {
    if signal.is_empty() {
        return;
    }
    let reference = signal[0];
    for sample in signal {
        *sample *= 1.0 + 0.01 * offsets.multiplicative_percent;
        *sample += 0.01 * offsets.additive_percent_of_first * reference;
    }
}

pub fn apply_simple_offset_derivatives(offsets: SimpleOffsets, signal: &mut [f64]) {
    apply_simple_offsets(offsets, signal);
}

pub fn apply_spectral_features(
    features: SinusoidalFeatures,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != signal.len() {
        return Err(Error::ShapeMismatch);
    }
    if signal.is_empty() {
        return Ok(());
    }

    let first_wavelength = wavelengths_nm[0];
    let reference_signal = signal[0];
    for (&wavelength_nm, sample) in wavelengths_nm.iter().zip(signal) {
        let delta_nm = wavelength_nm - first_wavelength;
        let mut additive_term = 0.0;
        let mut multiplicative_term = 0.0;
        if features.additive_amplitude_percent != 0.0 {
            additive_term = reference_signal
                * 0.01
                * features.additive_amplitude_percent
                * ((delta_nm * 2.0 * std::f64::consts::PI / features.additive_period_nm)
                    + features.additive_phase_deg.to_radians())
                .sin();
        }
        if features.multiplicative_amplitude_percent != 0.0 {
            multiplicative_term = 0.01
                * features.multiplicative_amplitude_percent
                * ((delta_nm * 2.0 * std::f64::consts::PI / features.multiplicative_period_nm)
                    + features.multiplicative_phase_deg.to_radians())
                .sin();
        }
        *sample = *sample * (1.0 + multiplicative_term) + additive_term;
    }
    Ok(())
}

pub fn apply_spectral_feature_derivatives(
    features: SinusoidalFeatures,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
) -> Result<(), Error> {
    apply_spectral_features(features, wavelengths_nm, signal)
}

pub fn apply_smear(
    percent_smear: f64,
    signal: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    if signal.len() != scratch.len() {
        return Err(Error::ShapeMismatch);
    }
    if signal.len() < 2 {
        return Ok(());
    }

    scratch.copy_from_slice(signal);
    let first = signal[0];
    for index in 0..signal.len() - 1 {
        let smear = 0.01 * percent_smear * scratch[index];
        scratch[index] -= smear;
        scratch[index + 1] += smear;
    }
    scratch[0] = first;
    signal.copy_from_slice(scratch);
    Ok(())
}

pub fn apply_multiplicative_nodes(
    correction: &NodalCorrection,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != signal.len() || signal.len() != scratch.len() {
        return Err(Error::ShapeMismatch);
    }
    if !correction.enabled() {
        return Ok(());
    }

    for ((&wavelength_nm, &sample), slot) in
        wavelengths_nm.iter().zip(signal.iter()).zip(&mut *scratch)
    {
        let percent = sample_correction(correction, &correction.values, wavelength_nm)?;
        *slot = sample + (0.01 * percent * sample);
    }
    signal.copy_from_slice(scratch);
    Ok(())
}

pub fn apply_stray_light_nodes(
    correction: &NodalCorrection,
    wavelengths_nm: &[f64],
    source_signal: &[f64],
    signal: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != source_signal.len()
        || source_signal.len() != signal.len()
        || signal.len() != scratch.len()
    {
        return Err(Error::ShapeMismatch);
    }
    if !correction.enabled() {
        return Ok(());
    }
    if correction.values.len() > 64 {
        return Err(Error::ShapeMismatch);
    }

    let mut node_values = [0.0; 64];
    for (index, node_value) in node_values
        .iter_mut()
        .enumerate()
        .take(correction.values.len())
    {
        let base = sample_linear(
            wavelengths_nm,
            source_signal,
            correction.wavelengths_nm[index],
        )?;
        let bias = correction
            .characteristic_bias
            .get(index)
            .copied()
            .unwrap_or(1.0);
        *node_value = 0.01 * correction.values[index] * base * bias;
    }

    for ((&wavelength_nm, &sample), slot) in
        wavelengths_nm.iter().zip(signal.iter()).zip(&mut *scratch)
    {
        let additive = sample_correction(
            correction,
            &node_values[..correction.values.len()],
            wavelength_nm,
        )?;
        *slot = sample + additive;
    }
    signal.copy_from_slice(scratch);
    Ok(())
}

pub fn apply_ring_spectrum(
    ring: &RingControls,
    wavelengths_nm: &[f64],
    irradiance: &[f64],
    radiance: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != irradiance.len()
        || irradiance.len() != radiance.len()
        || radiance.len() != scratch.len()
    {
        return Err(Error::ShapeMismatch);
    }
    if !ring.enabled || radiance.is_empty() {
        return Ok(());
    }
    if !ring.spectrum.is_empty() && ring.spectrum.len() != radiance.len() {
        return Err(Error::ShapeMismatch);
    }

    let effective_coefficient = ring.coefficient * ring.fraction_raman_lines;
    let mean_irradiance = if ring.spectrum.is_empty() && !ring.differential {
        spectral_mean(irradiance)
    } else {
        0.0
    };
    for index in 0..radiance.len() {
        let basis = if ring.spectrum.len() == radiance.len() {
            ring.spectrum[index]
        } else if ring.differential {
            synthesized_differential_ring(irradiance, index)
        } else {
            synthesized_full_ring(mean_irradiance, irradiance[index])
        };
        scratch[index] = radiance[index] + effective_coefficient * basis * irradiance[index];
    }
    radiance.copy_from_slice(scratch);
    Ok(())
}

pub fn apply_polarization_scrambler_bias(
    use_polarization_scrambler: bool,
    depolarization_factor: f64,
    wavelengths_nm: &[f64],
    signal: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != signal.len() {
        return Err(Error::ShapeMismatch);
    }
    if use_polarization_scrambler
        || signal.is_empty()
        || !depolarization_factor.is_finite()
        || depolarization_factor <= 0.0
        || signal.len() == 1
    {
        return Ok(());
    }

    let start_nm = wavelengths_nm[0];
    let end_nm = wavelengths_nm[wavelengths_nm.len() - 1];
    let center_nm = 0.5 * (start_nm + end_nm);
    let half_span_nm = (0.5 * (end_nm - start_nm)).max(1.0e-9);
    let leakage_scale = 0.35 * depolarization_factor;

    for (&wavelength_nm, sample) in wavelengths_nm.iter().zip(signal) {
        let normalized_offset = (wavelength_nm - center_nm) / half_span_nm;
        *sample *= 1.0 + (leakage_scale * normalized_offset);
    }
    Ok(())
}

pub fn apply_reflectance_calibration_error_sigma(
    calibration_error: &ReflectanceCalibration,
    wavelengths_nm: &[f64],
    reflectance: &[f64],
    sigma: &mut [f64],
    scratch: &mut [f64],
) -> Result<(), Error> {
    if wavelengths_nm.len() != reflectance.len()
        || reflectance.len() != sigma.len()
        || sigma.len() != scratch.len()
    {
        return Err(Error::ShapeMismatch);
    }
    if !calibration_error.multiplicative_error.enabled()
        && !calibration_error.additive_error.enabled()
    {
        return Ok(());
    }

    scratch.fill(0.0);
    if calibration_error.multiplicative_error.enabled() {
        for ((&wavelength_nm, &reflectance_value), slot) in wavelengths_nm
            .iter()
            .zip(reflectance)
            .zip(scratch.iter_mut())
        {
            let percent = sample_correction(
                &calibration_error.multiplicative_error,
                &calibration_error.multiplicative_error.values,
                wavelength_nm,
            )?;
            *slot += (reflectance_value * percent / 100.0).powi(2);
        }
    }
    if calibration_error.additive_error.enabled() {
        if calibration_error.additive_error.values.len() > 64 {
            return Err(Error::ShapeMismatch);
        }
        let mut node_values = [0.0; 64];
        for (index, node_value) in node_values
            .iter_mut()
            .enumerate()
            .take(calibration_error.additive_error.values.len())
        {
            let reflectance_at_node = sample_linear(
                wavelengths_nm,
                reflectance,
                calibration_error.additive_error.wavelengths_nm[index],
            )?;
            *node_value =
                reflectance_at_node * calibration_error.additive_error.values[index] / 100.0;
        }
        for (&wavelength_nm, slot) in wavelengths_nm.iter().zip(scratch.iter_mut()) {
            let additive_sigma = sample_correction(
                &calibration_error.additive_error,
                &node_values[..calibration_error.additive_error.values.len()],
                wavelength_nm,
            )?;
            *slot += additive_sigma * additive_sigma;
        }
    }

    for (sigma_value, &systematic_variance) in sigma.iter_mut().zip(scratch.iter()) {
        *sigma_value = ((*sigma_value * *sigma_value) + systematic_variance).sqrt();
    }
    Ok(())
}

fn sample_correction(
    correction: &NodalCorrection,
    values: &[f64],
    wavelength_nm: f64,
) -> Result<f64, Error> {
    if correction.wavelengths_nm.is_empty() || values.is_empty() {
        return Ok(0.0);
    }
    if correction.wavelengths_nm.len() != values.len() {
        return Err(Error::ShapeMismatch);
    }
    if values.len() == 1 {
        return Ok(values[0]);
    }
    if correction.use_linear_interpolation {
        return sample_linear(&correction.wavelengths_nm, values, wavelength_nm);
    }
    sample_polynomial(&correction.wavelengths_nm, values, wavelength_nm)
}

fn sample_linear(x: &[f64], y: &[f64], target_x: f64) -> Result<f64, Error> {
    sampling::sample_linear_clamped(x, y, target_x).map_err(|_| Error::ShapeMismatch)
}

fn sample_polynomial(x: &[f64], y: &[f64], target_x: f64) -> Result<f64, Error> {
    if x.len() != y.len() || x.is_empty() {
        return Err(Error::ShapeMismatch);
    }
    if x.len() == 1 {
        return Ok(y[0]);
    }

    let mut total = 0.0;
    for (i, (&xi, &yi)) in x.iter().zip(y).enumerate() {
        let mut basis = 1.0;
        for (j, &xj) in x.iter().enumerate() {
            if i == j {
                continue;
            }
            basis *= (target_x - xj) / (xi - xj);
        }
        total += yi * basis;
    }
    Ok(total)
}

fn synthesized_differential_ring(irradiance: &[f64], index: usize) -> f64 {
    if irradiance.len() == 1 {
        return 0.0;
    }
    let left = if index == 0 {
        irradiance[0]
    } else {
        irradiance[index - 1]
    };
    let right = if index + 1 >= irradiance.len() {
        irradiance[irradiance.len() - 1]
    } else {
        irradiance[index + 1]
    };
    (left - right) / irradiance[index].max(1.0e-12)
}

fn synthesized_full_ring(mean_irradiance: f64, irradiance: f64) -> f64 {
    (mean_irradiance - irradiance) / mean_irradiance.max(1.0e-12)
}

fn spectral_mean(values: &[f64]) -> f64 {
    values.iter().sum::<f64>() / values.len() as f64
}
