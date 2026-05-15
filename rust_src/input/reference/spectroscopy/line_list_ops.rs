use super::{VENDOR_CUTOFF_PREWINDOW_MARGIN_CM1, physics_core, support};
use crate::input::reference_data::{SpectroscopyLine, SpectroscopyLineList};

pub struct RelevantLineWindow<'a> {
    pub lines: &'a [SpectroscopyLine],
    pub start_index: usize,
}

pub fn relevant_line_window_for_wavelength<'a>(
    line_list: &'a SpectroscopyLineList,
    wavelength_nm: f64,
) -> RelevantLineWindow<'a> {
    if !line_list.lines_sorted_ascending {
        return RelevantLineWindow {
            lines: &line_list.lines,
            start_index: 0,
        };
    }
    let Some(cutoff_cm1) = line_list.runtime_controls.cutoff_cm1 else {
        return RelevantLineWindow {
            lines: &line_list.lines,
            start_index: 0,
        };
    };

    let vendor_discrete_cutoff_cm1 = cutoff_cm1 + VENDOR_CUTOFF_PREWINDOW_MARGIN_CM1;
    let evaluation_wavenumber_cm1 = physics_core::wavelength_to_wavenumber_cm1(wavelength_nm);
    let minimum_wavenumber_cm1 =
        (evaluation_wavenumber_cm1 - vendor_discrete_cutoff_cm1).max(1.0e-6);
    let maximum_wavenumber_cm1 = evaluation_wavenumber_cm1 + vendor_discrete_cutoff_cm1;
    let minimum_wavelength_nm =
        physics_core::wavenumber_cm1_to_wavelength_nm(maximum_wavenumber_cm1);
    let maximum_wavelength_nm =
        physics_core::wavenumber_cm1_to_wavelength_nm(minimum_wavenumber_cm1);
    let lower = lower_bound_line_index(&line_list.lines, minimum_wavelength_nm);
    let upper = upper_bound_line_index(&line_list.lines, maximum_wavelength_nm);
    RelevantLineWindow {
        lines: &line_list.lines[lower..upper],
        start_index: lower,
    }
}

pub fn select_strong_line_anchors(
    line_list: &SpectroscopyLineList,
    relevant_lines: &[SpectroscopyLine],
    start_index: usize,
) -> Vec<Option<usize>> {
    let Some(strong_lines) = &line_list.strong_lines else {
        return Vec::new();
    };
    let mut anchors = vec![None; strong_lines.len()];
    if uses_vendor_strong_line_partition(line_list) {
        return anchors;
    }

    let mut deltas = vec![f64::INFINITY; strong_lines.len()];
    for (line_index, line) in relevant_lines.iter().enumerate() {
        let Some(strong_index) =
            matched_strong_index_for_relevant_line(line_list, start_index, line, line_index)
        else {
            continue;
        };
        if strong_index >= strong_lines.len() {
            continue;
        }
        let delta =
            (strong_lines[strong_index].center_wavelength_nm - line.center_wavelength_nm).abs();
        if delta > deltas[strong_index] {
            continue;
        }
        if delta == deltas[strong_index]
            && let Some(anchor_index) = anchors[strong_index]
        {
            let incumbent = relevant_lines[anchor_index];
            if incumbent.line_strength_cm2_per_molecule >= line.line_strength_cm2_per_molecule {
                continue;
            }
        }
        anchors[strong_index] = Some(line_index);
        deltas[strong_index] = delta;
    }
    anchors
}

pub fn matched_strong_index_for_relevant_line(
    line_list: &SpectroscopyLineList,
    start_index: usize,
    line: &SpectroscopyLine,
    line_index: usize,
) -> Option<usize> {
    if let Some(matches) = &line_list.strong_line_match_by_line {
        let global_index = start_index + line_index;
        if global_index < matches.len() {
            return matches[global_index].map(usize::from);
        }
    }
    if uses_vendor_strong_line_partition(line_list)
        && !support::is_vendor_o2a_strong_candidate_from_source(line)
    {
        return None;
    }
    find_strong_line_match(line_list, line.center_wavelength_nm)
}

pub fn should_exclude_weak_line(
    line_list: &SpectroscopyLineList,
    start_index: usize,
    line: &SpectroscopyLine,
    line_index: usize,
    strong_line_anchors: &[Option<usize>],
) -> bool {
    if uses_vendor_strong_line_partition(line_list) {
        if line_list.preserve_anchor_weak_lines {
            return false;
        }
        if !support::is_vendor_o2a_strong_candidate_from_source(line) {
            return false;
        }
        return matched_strong_index_for_relevant_line(line_list, start_index, line, line_index)
            .is_some();
    }
    let Some(strong_index) =
        matched_strong_index_for_relevant_line(line_list, start_index, line, line_index)
    else {
        return false;
    };
    if line_list.preserve_anchor_weak_lines {
        return false;
    }
    strong_line_anchors.get(strong_index).copied().flatten() == Some(line_index)
}

pub fn uses_vendor_strong_line_partition(line_list: &SpectroscopyLineList) -> bool {
    line_list.has_strong_line_sidecars() && line_list.vendor_strong_line_partition
}

pub fn detect_vendor_strong_line_partition(line_list: &SpectroscopyLineList) -> bool {
    if !line_list.has_strong_line_sidecars() {
        return false;
    }
    if line_list
        .runtime_controls
        .gas_index
        .is_some_and(|gas_index| gas_index != 7)
    {
        return false;
    }
    line_list
        .lines
        .iter()
        .any(|line| line.gas_index == 7 && support::line_has_vendor_strong_line_metadata(line))
}

pub fn find_strong_line_match(
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
) -> Option<usize> {
    let strong_lines = line_list.strong_lines.as_ref()?;

    let mut best_index = None;
    let mut best_delta = f64::INFINITY;
    for (index, strong_line) in strong_lines.iter().enumerate() {
        let delta = (strong_line.center_wavelength_nm - wavelength_nm).abs();
        let tolerance_nm = line_list
            .strong_line_tolerance_nm
            .max(strong_line.air_half_width_nm * 4.0);
        if delta > tolerance_nm || delta >= best_delta {
            continue;
        }
        best_index = Some(index);
        best_delta = delta;
    }
    best_index
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
