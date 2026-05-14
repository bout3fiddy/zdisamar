use crate::common::errors::{Error, Result};

use super::constants::{
    MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS, MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS,
};

#[derive(Debug, Clone, Default, PartialEq)]
pub struct OperationalCrossSectionLut {
    pub wavelengths_nm: Vec<f64>,
    pub coefficients: Vec<f64>,
    pub temperature_coefficient_count: u8,
    pub pressure_coefficient_count: u8,
    pub min_temperature_k: f64,
    pub max_temperature_k: f64,
    pub min_pressure_hpa: f64,
    pub max_pressure_hpa: f64,
}

impl OperationalCrossSectionLut {
    pub fn enabled(&self) -> bool {
        !self.wavelengths_nm.is_empty()
    }

    pub fn validate(&self) -> Result<()> {
        if !self.enabled() {
            if !self.coefficients.is_empty()
                || self.temperature_coefficient_count != 0
                || self.pressure_coefficient_count != 0
            {
                return Err(Error::InvalidRequest);
            }
            return Ok(());
        }

        if self.temperature_coefficient_count == 0
            || usize::from(self.temperature_coefficient_count)
                > MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS
            || self.pressure_coefficient_count == 0
            || usize::from(self.pressure_coefficient_count)
                > MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS
        {
            return Err(Error::InvalidRequest);
        }
        if !self.min_temperature_k.is_finite()
            || !self.max_temperature_k.is_finite()
            || !self.min_pressure_hpa.is_finite()
            || !self.max_pressure_hpa.is_finite()
            || self.min_temperature_k <= 0.0
            || self.max_temperature_k <= self.min_temperature_k
            || self.min_pressure_hpa <= 0.0
            || self.max_pressure_hpa <= self.min_pressure_hpa
        {
            return Err(Error::InvalidRequest);
        }

        let mut previous_wavelength = None;
        for &wavelength_nm in &self.wavelengths_nm {
            if !wavelength_nm.is_finite() {
                return Err(Error::InvalidRequest);
            }
            if let Some(previous) = previous_wavelength
                && wavelength_nm <= previous
            {
                return Err(Error::InvalidRequest);
            }
            previous_wavelength = Some(wavelength_nm);
        }

        let expected_coefficient_count = self.wavelengths_nm.len()
            * usize::from(self.temperature_coefficient_count)
            * usize::from(self.pressure_coefficient_count);
        if self.coefficients.len() != expected_coefficient_count {
            return Err(Error::InvalidRequest);
        }
        if self
            .coefficients
            .iter()
            .any(|coefficient| !coefficient.is_finite())
        {
            return Err(Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn sigma_at(&self, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) -> f64 {
        self.evaluate(wavelength_nm, temperature_k, pressure_hpa)
            .sigma
    }

    pub fn d_sigma_d_temperature_at(
        &self,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) -> f64 {
        self.evaluate(wavelength_nm, temperature_k, pressure_hpa)
            .d_sigma_d_temperature
    }

    fn evaluate(&self, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) -> Evaluation {
        if !self.enabled() {
            return Evaluation::default();
        }

        let t_count = usize::from(self.temperature_coefficient_count);
        let p_count = usize::from(self.pressure_coefficient_count);
        let scaled_lnt = scaled_log_coordinate(
            temperature_k,
            self.min_temperature_k,
            self.max_temperature_k,
        );
        let scaled_lnp =
            scaled_log_coordinate(pressure_hpa, self.min_pressure_hpa, self.max_pressure_hpa);
        let mut legendre_lnt = vec![0.0; t_count];
        let mut legendre_lnp = vec![0.0; p_count];
        let mut derivative_legendre_lnt = vec![0.0; t_count];
        fill_legendre_values(&mut legendre_lnt, scaled_lnt);
        fill_legendre_values(&mut legendre_lnp, scaled_lnp);
        fill_legendre_temperature_derivative(
            &mut derivative_legendre_lnt,
            &legendre_lnt,
            scaled_lnt,
            temperature_k,
            self.min_temperature_k,
            self.max_temperature_k,
        );

        let bracket = self.wavelength_bracket(wavelength_nm);
        let left_sigma = self.evaluate_at_index(bracket.left_index, &legendre_lnt, &legendre_lnp);
        let right_sigma = if bracket.left_index == bracket.right_index {
            left_sigma
        } else {
            self.evaluate_at_index(bracket.right_index, &legendre_lnt, &legendre_lnp)
        };
        let left_derivative =
            self.evaluate_at_index(bracket.left_index, &derivative_legendre_lnt, &legendre_lnp);
        let right_derivative = if bracket.left_index == bracket.right_index {
            left_derivative
        } else {
            self.evaluate_at_index(bracket.right_index, &derivative_legendre_lnt, &legendre_lnp)
        };

        Evaluation {
            sigma: (left_sigma + bracket.weight * (right_sigma - left_sigma)).max(0.0),
            d_sigma_d_temperature: left_derivative
                + bracket.weight * (right_derivative - left_derivative),
        }
    }

    fn evaluate_at_index(
        &self,
        wavelength_index: usize,
        legendre_lnt: &[f64],
        legendre_lnp: &[f64],
    ) -> f64 {
        let mut sigma = 0.0;
        for (pressure_index, &pressure_basis) in legendre_lnp
            .iter()
            .enumerate()
            .take(usize::from(self.pressure_coefficient_count))
        {
            for (temperature_index, &temperature_basis) in legendre_lnt
                .iter()
                .enumerate()
                .take(usize::from(self.temperature_coefficient_count))
            {
                sigma += self.coefficient_at(temperature_index, pressure_index, wavelength_index)
                    * temperature_basis
                    * pressure_basis;
            }
        }
        sigma
    }

    fn coefficient_at(
        &self,
        temperature_index: usize,
        pressure_index: usize,
        wavelength_index: usize,
    ) -> f64 {
        let wavelength_stride = usize::from(self.temperature_coefficient_count)
            * usize::from(self.pressure_coefficient_count);
        let offset = wavelength_index * wavelength_stride
            + pressure_index * usize::from(self.temperature_coefficient_count)
            + temperature_index;
        self.coefficients[offset]
    }

    fn wavelength_bracket(&self, wavelength_nm: f64) -> WavelengthBracket {
        if self.wavelengths_nm.is_empty() || wavelength_nm <= self.wavelengths_nm[0] {
            return WavelengthBracket {
                left_index: 0,
                right_index: 0,
                weight: 0.0,
            };
        }

        for index in 0..self.wavelengths_nm.len() - 1 {
            let left_nm = self.wavelengths_nm[index];
            let right_nm = self.wavelengths_nm[index + 1];
            if wavelength_nm <= right_nm {
                let span = right_nm - left_nm;
                return WavelengthBracket {
                    left_index: index,
                    right_index: index + 1,
                    weight: if span == 0.0 {
                        0.0
                    } else {
                        (wavelength_nm - left_nm) / span
                    },
                };
            }
        }

        let last_index = self.wavelengths_nm.len() - 1;
        WavelengthBracket {
            left_index: last_index,
            right_index: last_index,
            weight: 0.0,
        }
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
struct Evaluation {
    sigma: f64,
    d_sigma_d_temperature: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct WavelengthBracket {
    left_index: usize,
    right_index: usize,
    weight: f64,
}

fn fill_legendre_values(values: &mut [f64], scaled_coordinate: f64) {
    if values.is_empty() {
        return;
    }
    values[0] = 1.0;
    if values.len() == 1 {
        return;
    }
    values[1] = scaled_coordinate;
    for index in 2..values.len() {
        let order = (index - 1) as f64;
        values[index] = (((2.0 * order) + 1.0) * scaled_coordinate * values[index - 1]
            - order * values[index - 2])
            / (order + 1.0);
    }
}

fn fill_legendre_temperature_derivative(
    derivative_values: &mut [f64],
    legendre_values: &[f64],
    scaled_coordinate: f64,
    temperature_k: f64,
    minimum_temperature_k: f64,
    maximum_temperature_k: f64,
) {
    derivative_values.fill(0.0);
    if derivative_values.len() <= 1 {
        return;
    }
    let scale = maximum_temperature_k.ln() - minimum_temperature_k.ln();
    if scale == 0.0 || temperature_k <= 0.0 {
        return;
    }

    let d_scaled_d_temperature = 2.0 / (scale * temperature_k);
    derivative_values[1] = 1.0;
    for index in 2..derivative_values.len() {
        derivative_values[index] = (scaled_coordinate * derivative_values[index - 1])
            + (index as f64 * legendre_values[index - 1]);
    }
    for derivative_value in &mut derivative_values[1..] {
        *derivative_value *= d_scaled_d_temperature;
    }
}

fn scaled_log_coordinate(value: f64, minimum: f64, maximum: f64) -> f64 {
    if minimum <= 0.0 || maximum <= 0.0 {
        return 0.0;
    }
    let ln_max = maximum.ln();
    let ln_min = minimum.ln();
    let scale = ln_max - ln_min;
    if scale == 0.0 {
        return 0.0;
    }
    let safe_value = if value > 0.0 { value } else { minimum };
    -((ln_max + ln_min) / scale) + (2.0 * safe_value.ln() / scale)
}
