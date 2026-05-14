use crate::input::instrument::{
    constants::{
        MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS,
        MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS,
    },
    cross_section_lut::OperationalCrossSectionLut,
    cross_section_lut_basis,
};

pub struct Evaluation {
    pub sigma: f64,
    pub d_sigma_d_temperature: f64,
}

pub fn evaluate(
    lut: &OperationalCrossSectionLut,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> Evaluation {
    if !lut.enabled() {
        return Evaluation {
            sigma: 0.0,
            d_sigma_d_temperature: 0.0,
        };
    }

    let temperature_count = usize::from(lut.temperature_coefficient_count);
    let pressure_count = usize::from(lut.pressure_coefficient_count);
    let mut legendre_lnt = [0.0; MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS];
    let mut derivative_legendre_lnt = [0.0; MAX_OPERATIONAL_REFSPEC_TEMPERATURE_COEFFICIENTS];
    let mut legendre_lnp = [0.0; MAX_OPERATIONAL_REFSPEC_PRESSURE_COEFFICIENTS];

    let scaled_lnt =
        scaled_log_coordinate(temperature_k, lut.min_temperature_k, lut.max_temperature_k);
    let scaled_lnp =
        scaled_log_coordinate(pressure_hpa, lut.min_pressure_hpa, lut.max_pressure_hpa);

    cross_section_lut_basis::fill_legendre_values(
        &mut legendre_lnt[..temperature_count],
        scaled_lnt,
    );
    cross_section_lut_basis::fill_legendre_values(&mut legendre_lnp[..pressure_count], scaled_lnp);
    cross_section_lut_basis::fill_legendre_temperature_derivative(
        &mut derivative_legendre_lnt[..temperature_count],
        &legendre_lnt[..temperature_count],
        scaled_lnt,
        temperature_k,
        lut.min_temperature_k,
        lut.max_temperature_k,
    );

    let bracket = wavelength_bracket(lut, wavelength_nm);
    let left_sigma = evaluate_at_index(
        lut,
        bracket.left_index,
        &legendre_lnt[..temperature_count],
        &legendre_lnp[..pressure_count],
    );
    let right_sigma = if bracket.left_index == bracket.right_index {
        left_sigma
    } else {
        evaluate_at_index(
            lut,
            bracket.right_index,
            &legendre_lnt[..temperature_count],
            &legendre_lnp[..pressure_count],
        )
    };
    let left_derivative = evaluate_at_index(
        lut,
        bracket.left_index,
        &derivative_legendre_lnt[..temperature_count],
        &legendre_lnp[..pressure_count],
    );
    let right_derivative = if bracket.left_index == bracket.right_index {
        left_derivative
    } else {
        evaluate_at_index(
            lut,
            bracket.right_index,
            &derivative_legendre_lnt[..temperature_count],
            &legendre_lnp[..pressure_count],
        )
    };

    Evaluation {
        sigma: (left_sigma + bracket.weight * (right_sigma - left_sigma)).max(0.0),
        d_sigma_d_temperature: left_derivative
            + bracket.weight * (right_derivative - left_derivative),
    }
}

fn evaluate_at_index(
    lut: &OperationalCrossSectionLut,
    wavelength_index: usize,
    legendre_lnt: &[f64],
    legendre_lnp: &[f64],
) -> f64 {
    let mut sigma = 0.0;
    for (pressure_index, &pressure_basis) in legendre_lnp.iter().enumerate() {
        for (temperature_index, &temperature_basis) in legendre_lnt.iter().enumerate() {
            sigma += coefficient_at(lut, temperature_index, pressure_index, wavelength_index)
                * temperature_basis
                * pressure_basis;
        }
    }
    sigma
}

fn coefficient_at(
    lut: &OperationalCrossSectionLut,
    temperature_index: usize,
    pressure_index: usize,
    wavelength_index: usize,
) -> f64 {
    let wavelength_stride = usize::from(lut.temperature_coefficient_count)
        * usize::from(lut.pressure_coefficient_count);
    let offset = wavelength_index * wavelength_stride
        + pressure_index * usize::from(lut.temperature_coefficient_count)
        + temperature_index;
    lut.coefficients[offset]
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

struct WavelengthBracket {
    left_index: usize,
    right_index: usize,
    weight: f64,
}

fn wavelength_bracket(lut: &OperationalCrossSectionLut, wavelength_nm: f64) -> WavelengthBracket {
    if lut.wavelengths_nm.is_empty() || wavelength_nm <= lut.wavelengths_nm[0] {
        return WavelengthBracket {
            left_index: 0,
            right_index: 0,
            weight: 0.0,
        };
    }

    for index in 0..lut.wavelengths_nm.len() - 1 {
        let left_nm = lut.wavelengths_nm[index];
        let right_nm = lut.wavelengths_nm[index + 1];
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

    let last_index = lut.wavelengths_nm.len() - 1;
    WavelengthBracket {
        left_index: last_index,
        right_index: last_index,
        weight: 0.0,
    }
}
