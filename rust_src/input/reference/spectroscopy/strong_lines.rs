use crate::input::{hitran_partition_tables, reference_data::SpectroscopyLine};

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
