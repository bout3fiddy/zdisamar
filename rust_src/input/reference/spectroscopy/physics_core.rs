use super::{
    HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K, HITRAN_BOLTZMANN_CONSTANT_J_PER_K,
    HITRAN_GAS_CONSTANT_J_PER_MOL_K, HITRAN_HC_OVER_KB_CM_K, HITRAN_PI,
    HITRAN_SPEED_OF_LIGHT_M_PER_S, MIN_SPECTROSCOPY_PRESSURE_ATM,
    VENDOR_CUTOFF_BOUNDARY_MARGIN_CM1, strong_lines,
};
use crate::input::reference_data::{
    SpectroscopyEvaluation, SpectroscopyLine, SpectroscopyRuntimeControls,
    WeakLinePreparedLineState,
};

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ComplexProbability {
    pub wr: f64,
    pub wi: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct WeakLineWavelengthState {
    pub evaluation_wavenumber_cm1: f64,
    pub cutoff_grid_index: Option<usize>,
}

pub fn complex_probability_function(x: f64, y: f64) -> ComplexProbability {
    const T: [f64; 6] = [
        0.314240376,
        0.947788391,
        1.59768264,
        2.27950708,
        3.02063703,
        3.8897249,
    ];
    const U: [f64; 6] = [
        1.01172805,
        -0.75197147,
        1.2557727e-2,
        1.00220082e-2,
        -2.42068135e-4,
        5.00848061e-7,
    ];
    const S: [f64; 6] = [
        1.393237,
        0.231152406,
        -0.155351466,
        6.21836624e-3,
        9.19082986e-5,
        -6.27525958e-7,
    ];

    let mut wr = 0.0;
    let mut wi = 0.0;
    let y1 = y + 1.5;
    let y2 = y1 * y1;

    if y > 0.85 || x.abs() < (18.1 * y + 1.65) {
        for index in 0..T.len() {
            let mut r = x - T[index];
            let mut d = 1.0 / (r * r + y2);
            let d1 = y1 * d;
            let d2 = r * d;
            r = x + T[index];
            d = 1.0 / (r * r + y2);
            let d3 = y1 * d;
            let d4 = r * d;
            wr += U[index] * (d1 + d3) - S[index] * (d2 - d4);
            wi += U[index] * (d2 + d4) + S[index] * (d1 - d3);
        }
    } else {
        if x.abs() < 12.0 {
            wr = (-x * x).exp();
        }
        let y3 = y + 3.0;
        for index in 0..T.len() {
            let mut r = x - T[index];
            let mut r2 = r * r;
            let mut d = 1.0 / (r2 + y2);
            let d1 = y1 * d;
            let d2 = r * d;
            wr += y * (U[index] * (r * d2 - 1.5 * d1) + S[index] * y3 * d2) / (r2 + 2.25);

            r = x + T[index];
            r2 = r * r;
            d = 1.0 / (r2 + y2);
            let d3 = y1 * d;
            let d4 = r * d;
            wr += y * (U[index] * (r * d4 - 1.5 * d3) - S[index] * y3 * d4) / (r2 + 2.25);
            wi += U[index] * (d2 + d4) + S[index] * (d1 - d3);
        }
    }

    ComplexProbability { wr, wi }
}

pub fn wavelength_to_wavenumber_cm1(wavelength_nm: f64) -> f64 {
    1.0e7 / wavelength_nm.max(1.0e-9)
}

pub fn wavenumber_cm1_to_wavelength_nm(wavenumber_cm1: f64) -> f64 {
    1.0e7 / wavenumber_cm1.max(1.0e-9)
}

pub fn spectral_width_nm_to_cm1(width_nm: f64, center_wavenumber_cm1: f64) -> f64 {
    let safe_center = center_wavenumber_cm1.max(1.0);
    width_nm * safe_center * safe_center / 1.0e7
}

pub fn doppler_width_cm1(
    temperature_k: f64,
    wavenumber_cm1: f64,
    molecular_weight_g_per_mol: f64,
) -> f64 {
    let prefactor = (2.0 * std::f64::consts::LN_2 * HITRAN_GAS_CONSTANT_J_PER_MOL_K
        / (HITRAN_SPEED_OF_LIGHT_M_PER_S * HITRAN_SPEED_OF_LIGHT_M_PER_S))
        .sqrt();
    prefactor * temperature_k.max(1.0).sqrt()
        / (molecular_weight_g_per_mol / 1.0e3).max(1.0e-12).sqrt()
        * wavenumber_cm1
}

pub fn prepare_weak_line_wavelength_state(
    wavelength_nm: f64,
    runtime_controls: &SpectroscopyRuntimeControls,
) -> WeakLineWavelengthState {
    let evaluation_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelength_nm);
    let cutoff_grid_index = if runtime_controls.cutoff_grid_wavenumbers_cm1.len()
        == runtime_controls.cutoff_grid_wavelengths_nm.len()
        && runtime_controls.cutoff_grid_wavenumbers_cm1.len() >= 2
    {
        Some(nearest_wavenumber_grid_index_from_wavenumbers(
            &runtime_controls.cutoff_grid_wavenumbers_cm1,
            evaluation_wavenumber_cm1,
        ))
    } else if runtime_controls.cutoff_grid_wavelengths_nm.len() >= 2 {
        Some(nearest_wavenumber_grid_index(
            &runtime_controls.cutoff_grid_wavelengths_nm,
            evaluation_wavenumber_cm1,
        ))
    } else {
        None
    };
    WeakLineWavelengthState {
        evaluation_wavenumber_cm1,
        cutoff_grid_index,
    }
}

pub fn prepare_weak_line_prepared_line_state(
    line: &SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
) -> WeakLinePreparedLineState {
    let safe_temperature = temperature_k.max(150.0);
    let safe_pressure = pressure_atm.max(MIN_SPECTROSCOPY_PRESSURE_ATM);
    let center_wavenumber_cm1 = line_center_wavenumber_cm1(line);
    let temperature_ratio = reference_temperature_k / safe_temperature;
    let shifted_center_wavenumber_cm1 =
        (center_wavenumber_cm1 + line_pressure_shift_cm1(line) * safe_pressure).max(1.0);
    let half_width_cm1_at_t = (line_air_half_width_cm1(line)
        * temperature_ratio.powf(line.temperature_exponent))
    .max(1.0e-6);
    let doppler_width_cm1 = doppler_width_cm1(
        safe_temperature,
        shifted_center_wavenumber_cm1,
        strong_lines::molecular_weight_for_line(line),
    )
    .max(1.0e-6);
    let cte = std::f64::consts::LN_2.sqrt() / doppler_width_cm1;

    let mut converted_strength = line.line_strength_cm2_per_molecule
        * strong_lines::partition_ratio_t0_over_t(line, safe_temperature, reference_temperature_k)
        * (HITRAN_HC_OVER_KB_CM_K
            * line.lower_state_energy_cm1
            * ((1.0 / reference_temperature_k) - (1.0 / safe_temperature)))
            .exp()
        / shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013
        / HITRAN_BOLTZMANN_CONSTANT_J_PER_K
        / safe_temperature
        / (1.0
            - (-HITRAN_HC_OVER_KB_CM_K * shifted_center_wavenumber_cm1 / reference_temperature_k)
                .exp())
        .max(1.0e-12);

    WeakLinePreparedLineState {
        shifted_center_wavenumber_cm1,
        cte,
        line_shape_y: half_width_cm1_at_t * safe_pressure * cte,
        prefactor_base: std::f64::consts::LN_2.sqrt() / doppler_width_cm1 / HITRAN_PI.sqrt()
            * safe_pressure
            * converted_strength,
        safe_temperature,
        safe_pressure,
    }
}

pub fn weak_line_contribution(
    wavelength_nm: f64,
    line: &SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    runtime_controls: &SpectroscopyRuntimeControls,
) -> SpectroscopyEvaluation {
    let wavelength_state = prepare_weak_line_wavelength_state(wavelength_nm, runtime_controls);
    weak_line_contribution_with_wavelength_state(
        wavelength_nm,
        line,
        temperature_k,
        pressure_atm,
        reference_temperature_k,
        runtime_controls,
        wavelength_state,
    )
}

pub fn weak_line_contribution_with_wavelength_state(
    wavelength_nm: f64,
    line: &SpectroscopyLine,
    temperature_k: f64,
    pressure_atm: f64,
    reference_temperature_k: f64,
    runtime_controls: &SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) -> SpectroscopyEvaluation {
    if !weak_line_inside_vendor_cutoff(line, pressure_atm, runtime_controls, wavelength_state) {
        return SpectroscopyEvaluation::default();
    }

    let safe_temperature = temperature_k.max(150.0);
    let safe_pressure = pressure_atm.max(MIN_SPECTROSCOPY_PRESSURE_ATM);
    let evaluation_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelength_nm);
    let center_wavenumber_cm1 = line_center_wavenumber_cm1(line);
    let temperature_ratio = reference_temperature_k / safe_temperature;
    let shifted_center_wavenumber_cm1 =
        (center_wavenumber_cm1 + line_pressure_shift_cm1(line) * safe_pressure).max(1.0);
    let half_width_cm1_at_t = (line_air_half_width_cm1(line)
        * temperature_ratio.powf(line.temperature_exponent))
    .max(1.0e-6);
    let doppler_width_cm1 = doppler_width_cm1(
        safe_temperature,
        shifted_center_wavenumber_cm1,
        strong_lines::molecular_weight_for_line(line),
    )
    .max(1.0e-6);
    let cte = std::f64::consts::LN_2.sqrt() / doppler_width_cm1;
    let cpf = complex_probability_function(
        (shifted_center_wavenumber_cm1 - evaluation_wavenumber_cm1) * cte,
        half_width_cm1_at_t * safe_pressure * cte,
    );

    let mut converted_strength = line.line_strength_cm2_per_molecule
        * strong_lines::partition_ratio_t0_over_t(line, safe_temperature, reference_temperature_k)
        * (HITRAN_HC_OVER_KB_CM_K
            * line.lower_state_energy_cm1
            * ((1.0 / reference_temperature_k) - (1.0 / safe_temperature)))
            .exp()
        / shifted_center_wavenumber_cm1;
    converted_strength *= 0.1013
        / HITRAN_BOLTZMANN_CONSTANT_J_PER_K
        / safe_temperature
        / (1.0
            - (-HITRAN_HC_OVER_KB_CM_K * shifted_center_wavenumber_cm1 / reference_temperature_k)
                .exp())
        .max(1.0e-12);

    let stimulated_emission_scale = evaluation_wavenumber_cm1
        * (1.0 - (-HITRAN_HC_OVER_KB_CM_K * evaluation_wavenumber_cm1 / safe_temperature).exp());
    let prefactor = std::f64::consts::LN_2.sqrt() / doppler_width_cm1 / HITRAN_PI.sqrt()
        * safe_pressure
        * converted_strength
        * stimulated_emission_scale
        * safe_temperature
        * HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K
        / safe_pressure
        / 1013.25;
    let line_sigma = (prefactor * cpf.wr).max(0.0);

    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: line_sigma,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_sigma_cm2_per_molecule: line_sigma,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: line_sigma,
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

pub fn weak_line_contribution_prepared(
    wavelength_state: WeakLineWavelengthState,
    prepared_line: WeakLinePreparedLineState,
    runtime_controls: &SpectroscopyRuntimeControls,
) -> SpectroscopyEvaluation {
    if !prepared_weak_line_inside_vendor_cutoff(prepared_line, runtime_controls, wavelength_state) {
        return SpectroscopyEvaluation::default();
    }

    let cpf = complex_probability_function(
        (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1)
            * prepared_line.cte,
        prepared_line.line_shape_y,
    );
    let stimulated_emission_scale = wavelength_state.evaluation_wavenumber_cm1
        * (1.0
            - (-HITRAN_HC_OVER_KB_CM_K * wavelength_state.evaluation_wavenumber_cm1
                / prepared_line.safe_temperature)
                .exp());
    let prefactor = prepared_line.prefactor_base
        * stimulated_emission_scale
        * prepared_line.safe_temperature
        * HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K
        / prepared_line.safe_pressure
        / 1013.25;
    let line_sigma = (prefactor * cpf.wr).max(0.0);

    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: line_sigma,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_sigma_cm2_per_molecule: line_sigma,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: line_sigma,
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

fn line_center_wavenumber_cm1(line: &SpectroscopyLine) -> f64 {
    line.center_wavenumber_cm1
        .filter(|value| value.is_finite())
        .unwrap_or_else(|| wavelength_to_wavenumber_cm1(line.center_wavelength_nm))
}

fn line_air_half_width_cm1(line: &SpectroscopyLine) -> f64 {
    line.air_half_width_cm1
        .filter(|value| value.is_finite())
        .unwrap_or_else(|| {
            spectral_width_nm_to_cm1(line.air_half_width_nm, line_center_wavenumber_cm1(line))
        })
}

fn line_pressure_shift_cm1(line: &SpectroscopyLine) -> f64 {
    line.pressure_shift_cm1
        .filter(|value| value.is_finite())
        .unwrap_or_else(|| {
            -spectral_width_nm_to_cm1(line.pressure_shift_nm, line_center_wavenumber_cm1(line))
        })
}

fn shifted_line_center_wavenumber_cm1(line: &SpectroscopyLine, pressure_atm: f64) -> f64 {
    (line_center_wavenumber_cm1(line) + line_pressure_shift_cm1(line) * pressure_atm).max(1.0)
}

fn weak_line_inside_vendor_cutoff(
    line: &SpectroscopyLine,
    pressure_atm: f64,
    runtime_controls: &SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) -> bool {
    let Some(window_cm1) = runtime_controls.cutoff_cm1 else {
        return true;
    };
    let shifted_center_wavenumber_cm1 = shifted_line_center_wavenumber_cm1(line, pressure_atm);

    if runtime_controls.cutoff_grid_wavelengths_nm.len() >= 2 {
        let (lower_endpoint_index, upper_endpoint_index) =
            if runtime_controls.cutoff_grid_wavenumbers_cm1.len()
                == runtime_controls.cutoff_grid_wavelengths_nm.len()
                && runtime_controls.cutoff_grid_wavenumbers_cm1.len() >= 2
            {
                (
                    nearest_wavenumber_grid_index_from_wavenumbers(
                        &runtime_controls.cutoff_grid_wavenumbers_cm1,
                        shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearest_wavenumber_grid_index_from_wavenumbers(
                        &runtime_controls.cutoff_grid_wavenumbers_cm1,
                        shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                )
            } else {
                (
                    nearest_wavenumber_grid_index(
                        &runtime_controls.cutoff_grid_wavelengths_nm,
                        shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearest_wavenumber_grid_index(
                        &runtime_controls.cutoff_grid_wavelengths_nm,
                        shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                )
            };
        let Some(evaluation_index) = wavelength_state.cutoff_grid_index else {
            return false;
        };
        let start_index = lower_endpoint_index.min(upper_endpoint_index);
        let end_index = lower_endpoint_index.max(upper_endpoint_index);
        return evaluation_index >= start_index && evaluation_index <= end_index;
    }

    let fallback_cutoff_cm1 = window_cm1 + VENDOR_CUTOFF_BOUNDARY_MARGIN_CM1;
    (shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1).abs()
        <= fallback_cutoff_cm1
}

fn prepared_weak_line_inside_vendor_cutoff(
    prepared_line: WeakLinePreparedLineState,
    runtime_controls: &SpectroscopyRuntimeControls,
    wavelength_state: WeakLineWavelengthState,
) -> bool {
    let Some(window_cm1) = runtime_controls.cutoff_cm1 else {
        return true;
    };

    if runtime_controls.cutoff_grid_wavelengths_nm.len() >= 2 {
        let (lower_endpoint_index, upper_endpoint_index) =
            if runtime_controls.cutoff_grid_wavenumbers_cm1.len()
                == runtime_controls.cutoff_grid_wavelengths_nm.len()
                && runtime_controls.cutoff_grid_wavenumbers_cm1.len() >= 2
            {
                (
                    nearest_wavenumber_grid_index_from_wavenumbers(
                        &runtime_controls.cutoff_grid_wavenumbers_cm1,
                        prepared_line.shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearest_wavenumber_grid_index_from_wavenumbers(
                        &runtime_controls.cutoff_grid_wavenumbers_cm1,
                        prepared_line.shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                )
            } else {
                (
                    nearest_wavenumber_grid_index(
                        &runtime_controls.cutoff_grid_wavelengths_nm,
                        prepared_line.shifted_center_wavenumber_cm1 + window_cm1,
                    ),
                    nearest_wavenumber_grid_index(
                        &runtime_controls.cutoff_grid_wavelengths_nm,
                        prepared_line.shifted_center_wavenumber_cm1 - window_cm1,
                    ),
                )
            };
        let Some(evaluation_index) = wavelength_state.cutoff_grid_index else {
            return false;
        };
        let start_index = lower_endpoint_index.min(upper_endpoint_index);
        let end_index = lower_endpoint_index.max(upper_endpoint_index);
        return evaluation_index >= start_index && evaluation_index <= end_index;
    }

    let fallback_cutoff_cm1 = window_cm1 + VENDOR_CUTOFF_BOUNDARY_MARGIN_CM1;
    (prepared_line.shifted_center_wavenumber_cm1 - wavelength_state.evaluation_wavenumber_cm1).abs()
        <= fallback_cutoff_cm1
}

pub fn nearest_wavenumber_grid_index(wavelengths_nm: &[f64], target_wavenumber_cm1: f64) -> usize {
    debug_assert!(!wavelengths_nm.is_empty());
    if wavelengths_nm.len() == 1 {
        return 0;
    }

    let first_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelengths_nm[0]);
    let last_index = wavelengths_nm.len() - 1;
    let last_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelengths_nm[last_index]);
    let descending = first_wavenumber_cm1 >= last_wavenumber_cm1;

    if descending {
        if target_wavenumber_cm1 >= first_wavenumber_cm1 {
            return 0;
        }
        if target_wavenumber_cm1 <= last_wavenumber_cm1 {
            return last_index;
        }

        let mut lower_index = 0;
        let mut upper_index = last_index;
        while upper_index - lower_index > 1 {
            let midpoint = lower_index + (upper_index - lower_index) / 2;
            let midpoint_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelengths_nm[midpoint]);
            if midpoint_wavenumber_cm1 >= target_wavenumber_cm1 {
                lower_index = midpoint;
            } else {
                upper_index = midpoint;
            }
        }
        return nearest_of_two_wavenumber_grid_indices(
            wavelengths_nm,
            target_wavenumber_cm1,
            lower_index,
            upper_index,
        );
    }

    if target_wavenumber_cm1 <= first_wavenumber_cm1 {
        return 0;
    }
    if target_wavenumber_cm1 >= last_wavenumber_cm1 {
        return last_index;
    }

    let mut lower_index = 0;
    let mut upper_index = last_index;
    while upper_index - lower_index > 1 {
        let midpoint = lower_index + (upper_index - lower_index) / 2;
        let midpoint_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelengths_nm[midpoint]);
        if midpoint_wavenumber_cm1 <= target_wavenumber_cm1 {
            lower_index = midpoint;
        } else {
            upper_index = midpoint;
        }
    }
    nearest_of_two_wavenumber_grid_indices(
        wavelengths_nm,
        target_wavenumber_cm1,
        lower_index,
        upper_index,
    )
}

pub fn nearest_wavenumber_grid_index_from_wavenumbers(
    wavenumbers_cm1: &[f64],
    target_wavenumber_cm1: f64,
) -> usize {
    debug_assert!(!wavenumbers_cm1.is_empty());
    if wavenumbers_cm1.len() == 1 {
        return 0;
    }

    let last_index = wavenumbers_cm1.len() - 1;
    let descending = wavenumbers_cm1[0] >= wavenumbers_cm1[last_index];
    if descending {
        if target_wavenumber_cm1 >= wavenumbers_cm1[0] {
            return 0;
        }
        if target_wavenumber_cm1 <= wavenumbers_cm1[last_index] {
            return last_index;
        }
    } else {
        if target_wavenumber_cm1 <= wavenumbers_cm1[0] {
            return 0;
        }
        if target_wavenumber_cm1 >= wavenumbers_cm1[last_index] {
            return last_index;
        }
    }

    let mut lower_index = 0;
    let mut upper_index = last_index;
    while upper_index - lower_index > 1 {
        let midpoint = lower_index + (upper_index - lower_index) / 2;
        let midpoint_wavenumber_cm1 = wavenumbers_cm1[midpoint];
        if (descending && midpoint_wavenumber_cm1 >= target_wavenumber_cm1)
            || (!descending && midpoint_wavenumber_cm1 <= target_wavenumber_cm1)
        {
            lower_index = midpoint;
        } else {
            upper_index = midpoint;
        }
    }

    if (wavenumbers_cm1[lower_index] - target_wavenumber_cm1).abs()
        <= (wavenumbers_cm1[upper_index] - target_wavenumber_cm1).abs()
    {
        lower_index
    } else {
        upper_index
    }
}

fn nearest_of_two_wavenumber_grid_indices(
    wavelengths_nm: &[f64],
    target_wavenumber_cm1: f64,
    left_index: usize,
    right_index: usize,
) -> usize {
    let left_delta =
        (wavelength_to_wavenumber_cm1(wavelengths_nm[left_index]) - target_wavenumber_cm1).abs();
    let right_delta =
        (wavelength_to_wavenumber_cm1(wavelengths_nm[right_index]) - target_wavenumber_cm1).abs();
    if left_delta <= right_delta {
        left_index
    } else {
        right_index
    }
}
