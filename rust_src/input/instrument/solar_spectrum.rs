use crate::common::errors::{Error, Result};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct OperationalSolarSpectrum {
    pub wavelengths_nm: Vec<f64>,
    pub irradiance: Vec<f64>,
    pub spline_second_derivatives: Vec<f64>,
}

impl OperationalSolarSpectrum {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty()
    }

    pub fn validate(&self) -> Result<()> {
        if !self.enabled() {
            if !self.irradiance.is_empty() || !self.spline_second_derivatives.is_empty() {
                return Err(Error::InvalidRequest);
            }
            return Ok(());
        }
        if self.irradiance.len() != self.wavelengths_nm.len() {
            return Err(Error::InvalidRequest);
        }
        if !self.spline_second_derivatives.is_empty()
            && self.spline_second_derivatives.len() != self.wavelengths_nm.len()
        {
            return Err(Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        for (&wavelength_nm, &irradiance) in self.wavelengths_nm.iter().zip(&self.irradiance) {
            if !wavelength_nm.is_finite() || !irradiance.is_finite() || irradiance < 0.0 {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_wavelength
                && wavelength_nm <= previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
        }
        for second_derivative in &self.spline_second_derivatives {
            if !second_derivative.is_finite() {
                return Err(Error::InvalidRequest);
            }
        }
        Ok(())
    }

    pub fn prepare_interpolation(&mut self) -> Result<()> {
        self.validate()?;
        if !self.enabled() || self.wavelengths_nm.len() < 3 {
            self.spline_second_derivatives.clear();
            return Ok(());
        }

        let len = self.wavelengths_nm.len();
        let mut second_derivatives = vec![0.0; len];
        let mut slopes = vec![0.0; len];
        let mut c3 = vec![0.0; len];
        let mut c4 = vec![0.0; len];

        let first_span_nm = self.wavelengths_nm[1] - self.wavelengths_nm[0];
        let last_span_nm = self.wavelengths_nm[len - 1] - self.wavelengths_nm[len - 2];
        if first_span_nm <= 0.0 || last_span_nm <= 0.0 {
            return Err(Error::InvalidRequest);
        }

        slopes[0] = (self.irradiance[1] - self.irradiance[0]) / first_span_nm;
        slopes[len - 1] = (self.irradiance[len - 1] - self.irradiance[len - 2]) / last_span_nm;

        for index in 1..len {
            c3[index] = self.wavelengths_nm[index] - self.wavelengths_nm[index - 1];
            if c3[index] <= 0.0 {
                return Err(Error::InvalidRequest);
            }
            c4[index] = (self.irradiance[index] - self.irradiance[index - 1]) / c3[index];
        }

        // Match the DISAMAR solar spline mode: first derivatives specified at both ends.
        c4[0] = 1.0;
        c3[0] = 0.0;

        for index in 1..len - 1 {
            let g = -c3[index + 1] / c4[index - 1];
            slopes[index] = g * slopes[index - 1]
                + 3.0 * (c3[index] * c4[index + 1] + c3[index + 1] * c4[index]);
            c4[index] = g * c3[index - 1] + 2.0 * (c3[index] + c3[index + 1]);
        }

        for index in (1..len).rev() {
            slopes[index - 1] = (slopes[index - 1] - c3[index - 1] * slopes[index]) / c4[index - 1];
        }

        for index in 1..len {
            let dtau_nm = c3[index];
            let first_divided_difference =
                (self.irradiance[index] - self.irradiance[index - 1]) / dtau_nm;
            let third_divided_difference =
                slopes[index - 1] + slopes[index] - (2.0 * first_divided_difference);
            c3[index - 1] = 2.0
                * (first_divided_difference - slopes[index - 1] - third_divided_difference)
                / dtau_nm;
            c4[index - 1] = 6.0 * third_divided_difference / (dtau_nm * dtau_nm);
        }

        second_derivatives[0] = -0.5 * c3[1];
        second_derivatives[1..(len - 1)].copy_from_slice(&c3[1..(len - 1)]);
        second_derivatives[len - 1] = -0.5 * c3[len - 2];
        self.spline_second_derivatives = second_derivatives;
        Ok(())
    }

    pub fn interpolate_irradiance(&self, wavelength_nm: f64) -> f64 {
        self.interpolate_irradiance_within_bounds(wavelength_nm)
            .unwrap_or_else(|| {
                if !self.enabled() {
                    return 0.0;
                }
                if wavelength_nm <= self.wavelengths_nm[0] {
                    self.irradiance[0]
                } else {
                    self.irradiance[self.irradiance.len() - 1]
                }
            })
    }

    pub fn interpolate_irradiance_linear(&self, wavelength_nm: f64) -> f64 {
        self.interpolate_irradiance_linear_within_bounds(wavelength_nm)
            .unwrap_or_else(|| {
                if !self.enabled() {
                    return 0.0;
                }
                if wavelength_nm <= self.wavelengths_nm[0] {
                    self.irradiance[0]
                } else {
                    self.irradiance[self.irradiance.len() - 1]
                }
            })
    }

    pub fn covers_range(&self, lower_wavelength_nm: f64, upper_wavelength_nm: f64) -> bool {
        self.enabled()
            && lower_wavelength_nm >= self.wavelengths_nm[0]
            && upper_wavelength_nm <= self.wavelengths_nm[self.wavelengths_nm.len() - 1]
    }

    pub fn interpolate_irradiance_within_bounds(&self, wavelength_nm: f64) -> Option<f64> {
        if !self.enabled()
            || wavelength_nm < self.wavelengths_nm[0]
            || wavelength_nm > self.wavelengths_nm[self.wavelengths_nm.len() - 1]
        {
            return None;
        }
        if self.spline_ready() {
            return self.interpolate_prepared_spline_within_bounds(wavelength_nm);
        }
        self.interpolate_irradiance_linear_within_bounds(wavelength_nm)
    }

    pub fn interpolate_irradiance_linear_within_bounds(&self, wavelength_nm: f64) -> Option<f64> {
        if !self.enabled()
            || wavelength_nm < self.wavelengths_nm[0]
            || wavelength_nm > self.wavelengths_nm[self.wavelengths_nm.len() - 1]
        {
            return None;
        }
        if wavelength_nm == self.wavelengths_nm[0] {
            return Some(self.irradiance[0]);
        }
        for index in 0..self.wavelengths_nm.len() - 1 {
            let left_nm = self.wavelengths_nm[index];
            let right_nm = self.wavelengths_nm[index + 1];
            if wavelength_nm <= right_nm {
                let span = right_nm - left_nm;
                if span == 0.0 {
                    return Some(self.irradiance[index + 1]);
                }
                let weight = (wavelength_nm - left_nm) / span;
                return Some(
                    self.irradiance[index]
                        + weight * (self.irradiance[index + 1] - self.irradiance[index]),
                );
            }
        }
        Some(self.irradiance[self.irradiance.len() - 1])
    }

    pub fn interpolate_onto(&self, wavelengths_nm: &[f64]) -> Vec<f64> {
        wavelengths_nm
            .iter()
            .map(|wavelength_nm| self.interpolate_irradiance(*wavelength_nm))
            .collect()
    }

    pub fn correct_measured_spectrum_onto(
        &self,
        source_wavelengths_nm: &[f64],
        measured_values: &[f64],
        target_wavelengths_nm: &[f64],
    ) -> Result<Vec<f64>> {
        if source_wavelengths_nm.len() != measured_values.len()
            || measured_values.len() != target_wavelengths_nm.len()
        {
            return Err(Error::InvalidRequest);
        }

        let source_solar = self.interpolate_onto(source_wavelengths_nm);
        let target_solar = self.interpolate_onto(target_wavelengths_nm);
        let mut corrected = Vec::with_capacity(target_wavelengths_nm.len());
        for ((&measured_value, &source_irradiance), &target_irradiance) in
            measured_values.iter().zip(&source_solar).zip(&target_solar)
        {
            if !measured_value.is_finite() {
                return Err(Error::InvalidRequest);
            }
            corrected.push(measured_value * target_irradiance / source_irradiance.max(1.0e-12));
        }
        Ok(corrected)
    }

    fn spline_ready(&self) -> bool {
        self.spline_second_derivatives.len() == self.wavelengths_nm.len()
            && self.wavelengths_nm.len() >= 3
    }

    fn interpolate_prepared_spline_within_bounds(&self, wavelength_nm: f64) -> Option<f64> {
        if wavelength_nm == self.wavelengths_nm[0] {
            return Some(self.irradiance[0]);
        }
        if wavelength_nm == self.wavelengths_nm[self.wavelengths_nm.len() - 1] {
            return Some(self.irradiance[self.irradiance.len() - 1]);
        }

        let mut lower_index = 0;
        let mut upper_index = self.wavelengths_nm.len() - 1;
        while upper_index - lower_index > 1 {
            let middle_index = (upper_index + lower_index) / 2;
            if self.wavelengths_nm[middle_index] > wavelength_nm {
                upper_index = middle_index;
            } else {
                lower_index = middle_index;
            }
        }

        let span_nm = self.wavelengths_nm[upper_index] - self.wavelengths_nm[lower_index];
        if span_nm == 0.0 {
            return Some(self.irradiance[upper_index]);
        }

        let dx_nm = wavelength_nm - self.wavelengths_nm[lower_index];
        // Horner form keeps the same reduction order as the DISAMAR spline helper.
        let b = (self.irradiance[upper_index] - self.irradiance[lower_index]) / span_nm
            - (2.0 * self.spline_second_derivatives[lower_index]
                + self.spline_second_derivatives[upper_index])
                * span_nm
                / 6.0;
        let d = (self.spline_second_derivatives[upper_index]
            - self.spline_second_derivatives[lower_index])
            / (6.0 * span_nm);
        Some(
            self.irradiance[lower_index]
                + dx_nm
                    * (b + dx_nm * (self.spline_second_derivatives[lower_index] / 2.0 + dx_nm * d)),
        )
    }
}
