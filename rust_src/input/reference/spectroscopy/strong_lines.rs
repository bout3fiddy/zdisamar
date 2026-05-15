use super::{
    HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K, HITRAN_HC_OVER_KB_CM_K,
    HITRAN_O2_LINE_MIXING_HC_OVER_KB_CM_K, HITRAN_PI, HITRAN_REFERENCE_TEMPERATURE_K,
    MAX_STRONG_LINE_SIDECARS, MIN_SPECTROSCOPY_PRESSURE_ATM, physics_core,
};
use crate::input::{
    hitran_partition_tables,
    reference_data::{
        RelaxationMatrix, SpectroscopyEvaluation, SpectroscopyLine, SpectroscopyStrongLine,
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct StrongLineConvTpState {
    pub line_count: usize,
    pub sig_moy_cm1: f64,
    pub population_t: Vec<f64>,
    pub dipole_t: Vec<f64>,
    pub mod_sig_cm1: Vec<f64>,
    pub half_width_cm1_at_t: Vec<f64>,
    pub line_mixing_coefficients: Vec<f64>,
    pub relaxation_weights: Vec<f64>,
}

impl StrongLineConvTpState {
    fn new(line_count: usize) -> Self {
        Self {
            line_count,
            sig_moy_cm1: 0.0,
            population_t: vec![0.0; line_count],
            dipole_t: vec![0.0; line_count],
            mod_sig_cm1: vec![0.0; line_count],
            half_width_cm1_at_t: vec![0.0; line_count],
            line_mixing_coefficients: vec![0.0; line_count],
            relaxation_weights: vec![0.0; line_count * line_count],
        }
    }

    pub fn weight_at(&self, row: usize, col: usize) -> f64 {
        self.relaxation_weights[row * self.line_count + col]
    }

    fn set_weight(&mut self, row: usize, col: usize, value: f64) {
        self.relaxation_weights[row * self.line_count + col] = value;
    }
}

pub fn strong_line_contribution(
    wavelength_nm: f64,
    _strong_lines: &[SpectroscopyStrongLine],
    strong_index: usize,
    convtp_state: &StrongLineConvTpState,
    temperature_k: f64,
    pressure_scale: f64,
) -> SpectroscopyEvaluation {
    let safe_temperature = temperature_k.max(150.0);
    let safe_pressure = pressure_scale.max(MIN_SPECTROSCOPY_PRESSURE_ATM);
    let evaluation_wavenumber_cm1 = physics_core::wavelength_to_wavenumber_cm1(wavelength_nm);
    let sig_moy_cm1 = convtp_state.sig_moy_cm1.max(1.0e-6);
    let gam_d = physics_core::doppler_width_cm1(
        safe_temperature,
        sig_moy_cm1,
        o2_strong_line_molecular_weight(),
    )
    .max(1.0e-6);
    let cte = std::f64::consts::LN_2.sqrt() / gam_d;
    let cte1 = cte / HITRAN_PI.sqrt();
    let cpf = physics_core::complex_probability_function(
        (convtp_state.mod_sig_cm1[strong_index] - evaluation_wavenumber_cm1) * cte,
        convtp_state.half_width_cm1_at_t[strong_index] * safe_pressure * cte,
    );
    let cte2 = evaluation_wavenumber_cm1
        * (1.0 - (-HITRAN_HC_OVER_KB_CM_K * evaluation_wavenumber_cm1 / safe_temperature).exp())
            .max(0.0);
    let base_absorption = cte1
        * safe_pressure
        * convtp_state.population_t[strong_index]
        * convtp_state.dipole_t[strong_index]
        * convtp_state.dipole_t[strong_index]
        * cte2;
    let number_density =
        1013.25 * safe_pressure / safe_temperature / HITRAN_BOLTZMANN_CONSTANT_CM3_HPA_PER_K;
    let line_sigma = (base_absorption * cpf.wr / number_density).max(0.0);
    let line_mixing_sigma =
        (-base_absorption * convtp_state.line_mixing_coefficients[strong_index] * cpf.wi)
            / number_density;
    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: 0.0,
        strong_line_sigma_cm2_per_molecule: line_sigma,
        line_sigma_cm2_per_molecule: line_sigma,
        line_mixing_sigma_cm2_per_molecule: line_mixing_sigma,
        total_sigma_cm2_per_molecule: (line_sigma + line_mixing_sigma).max(0.0),
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

pub fn prepare_strong_line_convtp_state(
    strong_lines: &[SpectroscopyStrongLine],
    relaxation_matrix: &RelaxationMatrix,
    temperature_k: f64,
    pressure_atm: f64,
) -> StrongLineConvTpState {
    let safe_temperature = temperature_k.max(150.0);
    let temperature_ratio = HITRAN_REFERENCE_TEMPERATURE_K / safe_temperature;
    let partition_ratio = hitran_partition_tables::ratio_t0_over_t(
        66,
        safe_temperature,
        HITRAN_REFERENCE_TEMPERATURE_K,
    )
    .unwrap_or(temperature_ratio);
    let line_count = strong_lines
        .len()
        .min(relaxation_matrix.line_count)
        .min(MAX_STRONG_LINE_SIDECARS);
    let mut state = StrongLineConvTpState::new(line_count);
    if line_count == 0 {
        return state;
    }

    for (row_index, strong_line) in strong_lines.iter().copied().enumerate().take(line_count) {
        state.population_t[row_index] = strong_line.population_t0
            * partition_ratio
            * (HITRAN_O2_LINE_MIXING_HC_OVER_KB_CM_K
                * strong_line.lower_state_energy_cm1
                * ((1.0 / HITRAN_REFERENCE_TEMPERATURE_K) - (1.0 / safe_temperature)))
                .exp();
        state.dipole_t[row_index] = strong_line.dipole_t0 * temperature_ratio.sqrt();
        state.mod_sig_cm1[row_index] =
            strong_line.center_wavenumber_cm1 + pressure_atm * strong_line.pressure_shift_cm1;
        state.half_width_cm1_at_t[row_index] = strong_line.air_half_width_cm1
            * temperature_ratio.powf(strong_line.temperature_exponent);

        for column_index in 0..line_count {
            state.set_weight(
                row_index,
                column_index,
                relaxation_matrix.weight_at(row_index, column_index)
                    * temperature_ratio
                        .powf(relaxation_matrix.temperature_exponent_at(row_index, column_index)),
            );
        }
    }

    for row_index in 0..line_count {
        for column_index in 0..line_count {
            if strong_lines[column_index].lower_state_energy_cm1
                < strong_lines[row_index].lower_state_energy_cm1
            {
                continue;
            }
            state.set_weight(
                column_index,
                row_index,
                state.weight_at(row_index, column_index) * state.population_t[column_index]
                    / state.population_t[row_index].max(1.0e-24),
            );
        }
    }

    for index in 0..line_count {
        state.set_weight(index, index, state.half_width_cm1_at_t[index]);
    }

    let mut weighted_center_sum = 0.0;
    let mut weighted_center_norm = 0.0;
    for line_index in 0..line_count {
        let weight = state.population_t[line_index]
            * state.dipole_t[line_index]
            * state.dipole_t[line_index];
        weighted_center_sum += state.mod_sig_cm1[line_index] * weight;
        weighted_center_norm += weight;
    }
    state.sig_moy_cm1 = if weighted_center_norm > 0.0 {
        weighted_center_sum / weighted_center_norm
    } else {
        state.mod_sig_cm1[0]
    };

    for column_index in 0..line_count {
        let mut upper_sum = 0.0;
        let mut lower_sum = 0.0;
        for (row_index, strong_line) in strong_lines.iter().take(line_count).enumerate() {
            if row_index <= column_index {
                upper_sum += strong_line.dipole_ratio * state.weight_at(row_index, column_index);
            } else {
                lower_sum += strong_line.dipole_ratio * state.weight_at(row_index, column_index);
            }
        }
        let rotational_gate =
            1.0 - f64::from(strong_lines[column_index].rotational_index_m1).abs() / 36.0;
        let renormalization_anchor =
            strong_lines[column_index].dipole_ratio * rotational_gate * rotational_gate * 0.04;

        for row_index in 0..line_count {
            if row_index <= column_index {
                continue;
            }
            let renormalized = -state.weight_at(row_index, column_index)
                * (upper_sum - renormalization_anchor)
                / lower_sum;
            state.set_weight(row_index, column_index, renormalized);
            state.set_weight(
                column_index,
                row_index,
                renormalized * state.population_t[column_index] / state.population_t[row_index],
            );
        }
    }

    for line_index in 0..line_count {
        let mut mixing_sum = 0.0;
        for other_index in 0..line_count {
            if other_index == line_index {
                continue;
            }
            let delta_sig = state.mod_sig_cm1[line_index] - state.mod_sig_cm1[other_index];
            if delta_sig == 0.0 {
                continue;
            }
            mixing_sum += 2.0 * state.dipole_t[other_index] / state.dipole_t[line_index]
                * state.weight_at(other_index, line_index)
                / delta_sig;
        }
        state.line_mixing_coefficients[line_index] = pressure_atm * mixing_sum;
    }

    state
}

fn o2_strong_line_molecular_weight() -> f64 {
    31.989830
}

pub fn partition_ratio_t0_over_t(
    line: &SpectroscopyLine,
    temperature_k: f64,
    reference_temperature_k: f64,
) -> f64 {
    let safe_temperature = temperature_k.max(150.0);
    let isotopologue_code = derive_isotopologue_code(line.gas_index, line.isotope_number);
    if let Some(ratio) = hitran_partition_tables::ratio_t0_over_t(
        isotopologue_code,
        safe_temperature,
        reference_temperature_k,
    ) {
        return ratio;
    }
    let exponent = match isotopologue_code {
        66 | 68 | 67 | 101 | 102 => 1.0,
        626 | 636 | 628 | 627 | 638 | 637 => 1.35,
        161 | 181 | 171 | 162 | 182 | 172 => 1.10,
        _ => 1.0 + 0.04 * f64::from(line.isotope_number.max(1) - 1),
    };
    (reference_temperature_k / safe_temperature).powf(exponent)
}

pub fn derive_isotopologue_code(gas_index: u16, isotope_number: u8) -> i32 {
    match gas_index {
        1 => match isotope_number {
            1 => 161,
            2 => 181,
            3 => 171,
            4 => 162,
            5 => 182,
            6 => 172,
            _ => 160 + i32::from(isotope_number),
        },
        7 => match isotope_number {
            1 => 66,
            2 => 68,
            3 => 67,
            4 => 69,
            _ => 70 + i32::from(isotope_number),
        },
        2 => match isotope_number {
            1 => 626,
            2 => 636,
            3 => 628,
            4 => 627,
            5 => 638,
            6 => 637,
            _ => 620 + i32::from(isotope_number),
        },
        5 => match isotope_number {
            1 => 26,
            2 => 36,
            3 => 28,
            4 => 27,
            5 => 38,
            6 => 37,
            _ => 20 + i32::from(isotope_number),
        },
        6 => match isotope_number {
            1 => 211,
            2 => 311,
            3 => 212,
            _ => 210 + i32::from(isotope_number),
        },
        11 => match isotope_number {
            1 => 4111,
            2 => 5111,
            _ => 4100 + i32::from(isotope_number),
        },
        _ => i32::from(gas_index) * 100 + i32::from(isotope_number),
    }
}

pub fn molecular_weight_for_line(line: &SpectroscopyLine) -> f64 {
    match derive_isotopologue_code(line.gas_index, line.isotope_number) {
        161 => 18.010565,
        181 => 20.014811,
        171 => 19.014780,
        162 => 19.016740,
        182 => 21.020985,
        172 => 20.020956,
        626 => 43.989830,
        636 => 44.993185,
        628 => 45.994076,
        627 => 44.994045,
        638 => 46.997431,
        637 => 45.997400,
        26 => 27.994915,
        36 => 28.998270,
        28 => 29.999161,
        27 => 28.999130,
        38 => 31.002516,
        37 => 30.002485,
        211 => 16.031300,
        311 => 17.034655,
        212 => 17.037475,
        66 => 31.989830,
        68 => 33.994076,
        67 => 32.994045,
        4111 => 17.026549,
        5111 => 18.023583,
        _ => match line.gas_index {
            1 => 18.01528,
            2 => 44.0095,
            5 => 28.0101,
            6 => 16.0425,
            7 => 31.9988,
            10 => 46.0055,
            11 => 17.0305,
            _ => 28.97,
        },
    }
}
