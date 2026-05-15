use super::{
    HITRAN_REFERENCE_TEMPERATURE_K, line_list_ops,
    physics_core::{
        prepare_weak_line_wavelength_state, weak_line_contribution_prepared,
        weak_line_contribution_with_wavelength_state,
    },
    strong_lines,
};
use crate::input::reference_data::{
    SpectroscopyEvaluation, SpectroscopyLineList, StrongLinePreparedState, WeakLinePreparedState,
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
    if line_list.has_strong_line_sidecars() {
        return total_sigma_with_strong_line_sidecars(
            line_list,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
    }
    total_sigma_from_line_list_only(line_list, wavelength_nm, temperature_k, pressure_hpa)
}

pub fn total_sigma_from_line_list_only(
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
    let relevant_window =
        line_list_ops::relevant_line_window_for_wavelength(line_list, wavelength_nm);
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

pub fn total_sigma_with_strong_line_sidecars(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> SpectroscopyEvaluation {
    if line_list.lines.is_empty() {
        return SpectroscopyEvaluation::default();
    }

    let Some(strong_lines) = &line_list.strong_lines else {
        return SpectroscopyEvaluation::default();
    };
    let Some(relaxation_matrix) = &line_list.relaxation_matrix else {
        return SpectroscopyEvaluation::default();
    };

    let pressure_scale = (pressure_hpa / 1013.25).max(super::MIN_SPECTROSCOPY_PRESSURE_ATM);
    let safe_temperature = temperature_k.max(150.0);
    let convtp_state = strong_lines::prepare_strong_line_convtp_state(
        strong_lines,
        relaxation_matrix,
        safe_temperature,
        pressure_scale,
    );
    let relevant_window =
        line_list_ops::relevant_line_window_for_wavelength(line_list, wavelength_nm);
    let strong_line_anchors = line_list_ops::select_strong_line_anchors(
        line_list,
        relevant_window.lines,
        relevant_window.start_index,
    );

    let mut weak_line_sigma = 0.0;
    let mut strong_line_sigma = 0.0;
    let mut line_mixing_sigma = 0.0;
    let weak_line_wavelength_state =
        prepare_weak_line_wavelength_state(wavelength_nm, &line_list.runtime_controls);

    for (line_index, line) in relevant_window.lines.iter().enumerate() {
        if line_list_ops::should_exclude_weak_line(
            line_list,
            relevant_window.start_index,
            line,
            line_index,
            &strong_line_anchors,
        ) {
            continue;
        }
        let contribution = weak_line_contribution_with_wavelength_state(
            wavelength_nm,
            line,
            safe_temperature,
            pressure_scale,
            HITRAN_REFERENCE_TEMPERATURE_K,
            &line_list.runtime_controls,
            weak_line_wavelength_state,
        );
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    for strong_index in 0..convtp_state.line_count {
        let contribution = strong_lines::strong_line_contribution(
            wavelength_nm,
            strong_lines,
            strong_index,
            &convtp_state,
            safe_temperature,
            pressure_scale,
        );
        strong_line_sigma += contribution.strong_line_sigma_cm2_per_molecule;
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule
            * line_list.runtime_controls.line_mixing_factor;
    }

    let total_line_sigma = weak_line_sigma + strong_line_sigma;
    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: weak_line_sigma,
        strong_line_sigma_cm2_per_molecule: strong_line_sigma,
        line_sigma_cm2_per_molecule: total_line_sigma,
        line_mixing_sigma_cm2_per_molecule: line_mixing_sigma,
        total_sigma_cm2_per_molecule: (total_line_sigma + line_mixing_sigma).max(0.0),
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

pub fn total_sigma_with_prepared_profile_state(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_strong_state: Option<&StrongLinePreparedState>,
    prepared_weak_state: Option<&WeakLinePreparedState>,
) -> SpectroscopyEvaluation {
    if line_list.has_strong_line_sidecars()
        && let Some(prepared_strong_state) = prepared_strong_state
    {
        return total_sigma_with_prepared_strong_line_state(
            line_list,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            prepared_strong_state,
            prepared_weak_state,
        );
    }
    total_sigma_from_prepared_weak_state(
        line_list,
        wavelength_nm,
        temperature_k,
        pressure_hpa,
        prepared_weak_state,
    )
}

pub fn total_sigma_with_prepared_strong_line_state(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_strong_state: &StrongLinePreparedState,
    prepared_weak_state: Option<&WeakLinePreparedState>,
) -> SpectroscopyEvaluation {
    if line_list.lines.is_empty() {
        return SpectroscopyEvaluation::default();
    }
    let Some(strong_lines) = &line_list.strong_lines else {
        return SpectroscopyEvaluation::default();
    };

    let pressure_scale = (pressure_hpa / 1013.25).max(super::MIN_SPECTROSCOPY_PRESSURE_ATM);
    let safe_temperature = temperature_k.max(150.0);
    let relevant_window =
        line_list_ops::relevant_line_window_for_wavelength(line_list, wavelength_nm);
    let strong_line_anchors = line_list_ops::select_strong_line_anchors(
        line_list,
        relevant_window.lines,
        relevant_window.start_index,
    );
    let weak_line_wavelength_state =
        prepare_weak_line_wavelength_state(wavelength_nm, &line_list.runtime_controls);

    let mut weak_line_sigma = 0.0;
    for (line_index, line) in relevant_window.lines.iter().enumerate() {
        if line_list_ops::should_exclude_weak_line(
            line_list,
            relevant_window.start_index,
            line,
            line_index,
            &strong_line_anchors,
        ) {
            continue;
        }
        let global_index = relevant_window.start_index + line_index;
        let contribution = if let Some(prepared_weak_state) = prepared_weak_state {
            if global_index < prepared_weak_state.lines.len() {
                weak_line_contribution_prepared(
                    weak_line_wavelength_state,
                    prepared_weak_state.lines[global_index],
                    &line_list.runtime_controls,
                )
            } else {
                weak_line_contribution_with_wavelength_state(
                    wavelength_nm,
                    line,
                    safe_temperature,
                    pressure_scale,
                    HITRAN_REFERENCE_TEMPERATURE_K,
                    &line_list.runtime_controls,
                    weak_line_wavelength_state,
                )
            }
        } else {
            weak_line_contribution_with_wavelength_state(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                HITRAN_REFERENCE_TEMPERATURE_K,
                &line_list.runtime_controls,
                weak_line_wavelength_state,
            )
        };
        weak_line_sigma += contribution.line_sigma_cm2_per_molecule;
    }

    let mut strong_line_sigma = 0.0;
    let mut line_mixing_sigma = 0.0;
    for strong_index in 0..prepared_strong_state.line_count {
        let contribution = strong_lines::strong_line_contribution(
            wavelength_nm,
            strong_lines,
            strong_index,
            prepared_strong_state,
            safe_temperature,
            pressure_scale,
        );
        strong_line_sigma += contribution.strong_line_sigma_cm2_per_molecule;
        line_mixing_sigma += contribution.line_mixing_sigma_cm2_per_molecule
            * line_list.runtime_controls.line_mixing_factor;
    }

    let total_line_sigma = weak_line_sigma + strong_line_sigma;
    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: weak_line_sigma,
        strong_line_sigma_cm2_per_molecule: strong_line_sigma,
        line_sigma_cm2_per_molecule: total_line_sigma,
        line_mixing_sigma_cm2_per_molecule: line_mixing_sigma,
        total_sigma_cm2_per_molecule: (total_line_sigma + line_mixing_sigma).max(0.0),
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
}

fn total_sigma_from_prepared_weak_state(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    prepared_weak_state: Option<&WeakLinePreparedState>,
) -> SpectroscopyEvaluation {
    let Some(prepared_weak_state) = prepared_weak_state else {
        return total_sigma_from_line_list_only(
            line_list,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
    };
    if line_list.lines.is_empty() {
        return SpectroscopyEvaluation::default();
    }

    let safe_temperature = temperature_k.max(150.0);
    let pressure_scale = (pressure_hpa / 1013.25).max(super::MIN_SPECTROSCOPY_PRESSURE_ATM);
    let relevant_window =
        line_list_ops::relevant_line_window_for_wavelength(line_list, wavelength_nm);
    let wavelength_state =
        prepare_weak_line_wavelength_state(wavelength_nm, &line_list.runtime_controls);
    let mut line_sigma = 0.0;

    for (line_index, line) in relevant_window.lines.iter().enumerate() {
        let global_index = relevant_window.start_index + line_index;
        let contribution = if global_index < prepared_weak_state.lines.len() {
            weak_line_contribution_prepared(
                wavelength_state,
                prepared_weak_state.lines[global_index],
                &line_list.runtime_controls,
            )
        } else {
            weak_line_contribution_with_wavelength_state(
                wavelength_nm,
                line,
                safe_temperature,
                pressure_scale,
                HITRAN_REFERENCE_TEMPERATURE_K,
                &line_list.runtime_controls,
                wavelength_state,
            )
        };
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
