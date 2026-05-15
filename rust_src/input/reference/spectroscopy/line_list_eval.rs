use super::{
    HITRAN_REFERENCE_TEMPERATURE_K, VENDOR_CUTOFF_PREWINDOW_MARGIN_CM1,
    physics_core::{
        prepare_weak_line_wavelength_state, wavelength_to_wavenumber_cm1,
        wavenumber_cm1_to_wavelength_nm, weak_line_contribution_with_wavelength_state,
    },
};
use crate::input::reference_data::{
    SpectroscopyEvaluation, SpectroscopyLine, SpectroscopyLineList,
};

pub fn evaluate_at(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> SpectroscopyEvaluation {
    let total = total_sigma_at(line_list, wavelength_nm, temperature_k, pressure_hpa);
    let delta_t = 0.5;
    let upper = total_sigma_at(
        line_list,
        wavelength_nm,
        temperature_k + delta_t,
        pressure_hpa,
    );
    let lower = total_sigma_at(
        line_list,
        wavelength_nm,
        (temperature_k - delta_t).max(150.0),
        pressure_hpa,
    );
    SpectroscopyEvaluation {
        d_sigma_d_temperature_cm2_per_molecule_per_k: (upper.total_sigma_cm2_per_molecule
            - lower.total_sigma_cm2_per_molecule)
            / (2.0 * delta_t),
        ..total
    }
}

pub fn total_sigma_at(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> SpectroscopyEvaluation {
    if line_list.lines.is_empty() {
        return SpectroscopyEvaluation::default();
    }

    let safe_temperature = temperature_k.max(150.0);
    let pressure_scale = (pressure_hpa / 1013.25).max(super::MIN_SPECTROSCOPY_PRESSURE_ATM);
    let relevant_window = relevant_line_window_for_wavelength(line_list, wavelength_nm);
    let wavelength_state =
        prepare_weak_line_wavelength_state(wavelength_nm, &line_list.runtime_controls);
    let mut line_sigma = 0.0;

    for line in relevant_window.lines {
        let contribution = weak_line_contribution_with_wavelength_state(
            wavelength_nm,
            line,
            safe_temperature,
            pressure_scale,
            HITRAN_REFERENCE_TEMPERATURE_K,
            &line_list.runtime_controls,
            wavelength_state,
        );
        line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: line_sigma,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_sigma_cm2_per_molecule: line_sigma,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: line_sigma,
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

struct RelevantLineWindow<'a> {
    lines: &'a [SpectroscopyLine],
}

fn relevant_line_window_for_wavelength<'a>(
    line_list: &'a SpectroscopyLineList,
    wavelength_nm: f64,
) -> RelevantLineWindow<'a> {
    if !line_list.lines_sorted_ascending {
        return RelevantLineWindow {
            lines: &line_list.lines,
        };
    }
    let Some(cutoff_cm1) = line_list.runtime_controls.cutoff_cm1 else {
        return RelevantLineWindow {
            lines: &line_list.lines,
        };
    };

    let vendor_discrete_cutoff_cm1 = cutoff_cm1 + VENDOR_CUTOFF_PREWINDOW_MARGIN_CM1;
    let evaluation_wavenumber_cm1 = wavelength_to_wavenumber_cm1(wavelength_nm);
    let minimum_wavenumber_cm1 =
        (evaluation_wavenumber_cm1 - vendor_discrete_cutoff_cm1).max(1.0e-6);
    let maximum_wavenumber_cm1 = evaluation_wavenumber_cm1 + vendor_discrete_cutoff_cm1;
    let minimum_wavelength_nm = wavenumber_cm1_to_wavelength_nm(maximum_wavenumber_cm1);
    let maximum_wavelength_nm = wavenumber_cm1_to_wavelength_nm(minimum_wavenumber_cm1);
    let lower = lower_bound_line_index(&line_list.lines, minimum_wavelength_nm);
    let upper = upper_bound_line_index(&line_list.lines, maximum_wavelength_nm);
    RelevantLineWindow {
        lines: &line_list.lines[lower..upper],
    }
}

fn lower_bound_line_index(lines: &[SpectroscopyLine], wavelength_nm: f64) -> usize {
    let mut low = 0;
    let mut high = lines.len();
    while low < high {
        let middle = low + (high - low) / 2;
        if lines[middle].center_wavelength_nm < wavelength_nm {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    low
}

fn upper_bound_line_index(lines: &[SpectroscopyLine], wavelength_nm: f64) -> usize {
    let mut low = 0;
    let mut high = lines.len();
    while low < high {
        let middle = low + (high - low) / 2;
        if lines[middle].center_wavelength_nm <= wavelength_nm {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    low
}
