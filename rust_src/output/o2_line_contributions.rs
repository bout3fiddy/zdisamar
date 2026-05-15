use crate::{
    common::errors,
    forward_model::optical_properties::state_build::PreparedOpticalState,
    input::{
        atmospheric_types::AbsorberSpecies,
        reference::spectroscopy::{
            HITRAN_REFERENCE_TEMPERATURE_K, MIN_SPECTROSCOPY_PRESSURE_ATM, line_list_ops,
            physics_core, strong_lines,
        },
        reference_data::{
            SpectroscopyEvaluation, SpectroscopyLine, SpectroscopyLineList, SpectroscopyStrongLine,
        },
    },
};

pub const MISSING_INDEX: u32 = u32::MAX;

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum O2LineRowKind {
    #[default]
    WeakLine = 0,
    StrongLine = 1,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
#[repr(u32)]
pub enum O2LineStatus {
    #[default]
    WeakIncluded = 0,
    WeakExcludedByStrongLine = 1,
    StrongSidecar = 2,
    WeakZeroAfterCutoff = 3,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct O2LineContributionRow {
    pub wavelength_nm: f64,
    pub profile_node_index: u32,
    pub altitude_km: f64,
    pub row_kind: O2LineRowKind,
    pub status: O2LineStatus,
    pub line_index: u32,
    pub strong_line_index: u32,
    pub matched_strong_line_index: u32,
    pub gas_index: u16,
    pub isotope_number: u8,
    pub isotopologue_code: i32,
    pub center_wavelength_nm: f64,
    pub center_wavenumber_cm1: f64,
    pub shifted_center_wavenumber_cm1: f64,
    pub line_strength_cm2_per_molecule: f64,
    pub air_half_width_cm1: f64,
    pub pressure_shift_cm1: f64,
    pub lower_state_energy_cm1: f64,
    pub temperature_k: f64,
    pub pressure_hpa: f64,
    pub weak_line_sigma_cm2_per_molecule: f64,
    pub strong_line_sigma_cm2_per_molecule: f64,
    pub line_mixing_sigma_cm2_per_molecule: f64,
    pub total_sigma_cm2_per_molecule: f64,
    pub abs_total_sigma_cm2_per_molecule: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct O2LineContributionTable {
    pub rows: Vec<O2LineContributionRow>,
    pub total_row_count: usize,
    pub truncated: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct ThermodynamicState {
    profile_node_index: u32,
    altitude_km: f64,
    temperature_k: f64,
    pressure_hpa: f64,
}

#[derive(Debug, Clone, Copy)]
struct RowContext<'a> {
    line_list: &'a SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
    temperature_k: f64,
    pressure_scale: f64,
    start_index: usize,
    strong_line_anchors: &'a [Option<usize>],
    relevant_lines: &'a [SpectroscopyLine],
}

pub fn build(
    prepared: &PreparedOpticalState,
    wavelengths_nm: &[f64],
    max_rows: usize,
) -> Result<O2LineContributionTable, errors::Error> {
    if wavelengths_nm.is_empty() || max_rows == 0 {
        return Err(errors::Error::InvalidRequest);
    }
    let Some(line_list) = primary_o2_line_list(prepared) else {
        return Err(errors::Error::InvalidRequest);
    };

    let mut rows =
        Vec::with_capacity(max_rows.min(line_list.lines.len() + strong_line_count(line_list)));
    let mut total_row_count = 0;
    for &wavelength_nm in wavelengths_nm {
        if let Some(node_count) = profile_node_count(prepared) {
            for node_index in 0..node_count {
                append_rows_for_wavelength(
                    &mut rows,
                    &mut total_row_count,
                    max_rows,
                    line_list,
                    wavelength_nm,
                    ThermodynamicState {
                        profile_node_index: node_index as u32,
                        altitude_km: prepared.spectroscopy_profile_altitudes_km[node_index],
                        temperature_k: prepared.spectroscopy_profile_temperatures_k[node_index],
                        pressure_hpa: prepared.spectroscopy_profile_pressures_hpa[node_index],
                    },
                );
            }
        } else {
            append_rows_for_wavelength(
                &mut rows,
                &mut total_row_count,
                max_rows,
                line_list,
                wavelength_nm,
                ThermodynamicState {
                    profile_node_index: MISSING_INDEX,
                    altitude_km: f64::NAN,
                    temperature_k: prepared.effective_temperature_k,
                    pressure_hpa: prepared.effective_pressure_hpa,
                },
            );
        }
    }

    Ok(O2LineContributionTable {
        rows,
        total_row_count,
        truncated: total_row_count > max_rows,
    })
}

fn primary_o2_line_list(prepared: &PreparedOpticalState) -> Option<&SpectroscopyLineList> {
    if let Some(line_list) = &prepared.spectroscopy_lines {
        return Some(line_list);
    }
    prepared
        .line_absorbers
        .iter()
        .find(|line_absorber| line_absorber.species == AbsorberSpecies::O2)
        .map(|line_absorber| &line_absorber.line_list)
}

fn profile_node_count(prepared: &PreparedOpticalState) -> Option<usize> {
    let node_count = prepared.spectroscopy_profile_altitudes_km.len();
    if node_count == 0
        || prepared.spectroscopy_profile_pressures_hpa.len() != node_count
        || prepared.spectroscopy_profile_temperatures_k.len() != node_count
    {
        return None;
    }
    Some(node_count)
}

fn strong_line_count(line_list: &SpectroscopyLineList) -> usize {
    let Some(strong_lines) = &line_list.strong_lines else {
        return 0;
    };
    if line_list.has_strong_line_sidecars() {
        strong_lines.len()
    } else {
        0
    }
}

fn append_rows_for_wavelength(
    rows: &mut Vec<O2LineContributionRow>,
    total_row_count: &mut usize,
    max_rows: usize,
    line_list: &SpectroscopyLineList,
    wavelength_nm: f64,
    thermodynamic_state: ThermodynamicState,
) {
    let pressure_scale =
        (thermodynamic_state.pressure_hpa / 1013.25).max(MIN_SPECTROSCOPY_PRESSURE_ATM);
    let safe_temperature = thermodynamic_state.temperature_k.max(150.0);
    let relevant_window =
        line_list_ops::relevant_line_window_for_wavelength(line_list, wavelength_nm);
    let strong_line_anchors = line_list_ops::select_strong_line_anchors(
        line_list,
        relevant_window.lines,
        relevant_window.start_index,
    );
    let row_context = RowContext {
        line_list,
        wavelength_nm,
        thermodynamic_state,
        temperature_k: safe_temperature,
        pressure_scale,
        start_index: relevant_window.start_index,
        strong_line_anchors: &strong_line_anchors,
        relevant_lines: relevant_window.lines,
    };

    for (line_index, line) in relevant_window.lines.iter().enumerate() {
        *total_row_count += 1;
        if rows.len() >= max_rows {
            continue;
        }
        rows.push(weak_line_row(row_context, *line, line_index));
    }

    if !line_list.has_strong_line_sidecars() {
        return;
    }
    let Some(strong_line_values) = &line_list.strong_lines else {
        return;
    };
    let Some(relaxation_matrix) = &line_list.relaxation_matrix else {
        return;
    };
    let strong_state = strong_lines::prepare_strong_line_convtp_state(
        strong_line_values,
        relaxation_matrix,
        safe_temperature,
        pressure_scale,
    );
    for (strong_index, strong_line) in strong_line_values
        .iter()
        .copied()
        .take(strong_state.line_count)
        .enumerate()
    {
        *total_row_count += 1;
        if rows.len() >= max_rows {
            continue;
        }
        rows.push(strong_line_row(
            row_context,
            strong_line_values,
            strong_line,
            strong_index,
            &strong_state,
        ));
    }
}

fn weak_line_row(
    context: RowContext<'_>,
    line: SpectroscopyLine,
    line_index: usize,
) -> O2LineContributionRow {
    let matched_strong_index = line_list_ops::matched_strong_index_for_relevant_line(
        context.line_list,
        context.start_index,
        &line,
        line_index,
    );
    let excluded = line_list_ops::should_exclude_weak_line(
        context.line_list,
        context.start_index,
        &line,
        line_index,
        context.strong_line_anchors,
    );
    let contribution = if excluded {
        SpectroscopyEvaluation::default()
    } else {
        physics_core::weak_line_contribution(
            context.wavelength_nm,
            &line,
            context.temperature_k,
            context.pressure_scale,
            HITRAN_REFERENCE_TEMPERATURE_K,
            &context.line_list.runtime_controls,
        )
    };
    let status = if excluded {
        O2LineStatus::WeakExcludedByStrongLine
    } else if contribution.total_sigma_cm2_per_molecule == 0.0 {
        O2LineStatus::WeakZeroAfterCutoff
    } else {
        O2LineStatus::WeakIncluded
    };

    O2LineContributionRow {
        wavelength_nm: context.wavelength_nm,
        profile_node_index: context.thermodynamic_state.profile_node_index,
        altitude_km: context.thermodynamic_state.altitude_km,
        row_kind: O2LineRowKind::WeakLine,
        status,
        line_index: (context.start_index + line_index) as u32,
        strong_line_index: MISSING_INDEX,
        matched_strong_line_index: optional_index(matched_strong_index),
        gas_index: line.gas_index,
        isotope_number: line.isotope_number,
        isotopologue_code: strong_lines::derive_isotopologue_code(
            line.gas_index,
            line.isotope_number,
        ),
        center_wavelength_nm: line.center_wavelength_nm,
        center_wavenumber_cm1: physics_core::line_center_wavenumber_cm1(&line),
        shifted_center_wavenumber_cm1: physics_core::shifted_line_center_wavenumber_cm1(
            &line,
            context.pressure_scale,
        ),
        line_strength_cm2_per_molecule: line.line_strength_cm2_per_molecule,
        air_half_width_cm1: physics_core::line_air_half_width_cm1(&line),
        pressure_shift_cm1: physics_core::line_pressure_shift_cm1(&line),
        lower_state_energy_cm1: line.lower_state_energy_cm1,
        temperature_k: context.temperature_k,
        pressure_hpa: context.thermodynamic_state.pressure_hpa,
        weak_line_sigma_cm2_per_molecule: contribution.weak_line_sigma_cm2_per_molecule,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: contribution.total_sigma_cm2_per_molecule,
        abs_total_sigma_cm2_per_molecule: contribution.total_sigma_cm2_per_molecule.abs(),
    }
}

fn strong_line_row(
    context: RowContext<'_>,
    strong_line_values: &[SpectroscopyStrongLine],
    strong_line: SpectroscopyStrongLine,
    strong_index: usize,
    strong_state: &strong_lines::StrongLineConvTpState,
) -> O2LineContributionRow {
    let contribution = strong_lines::strong_line_contribution(
        context.wavelength_nm,
        strong_line_values,
        strong_index,
        strong_state,
        context.temperature_k,
        context.pressure_scale,
    );
    let line_mixing_sigma = contribution.line_mixing_sigma_cm2_per_molecule
        * context.line_list.runtime_controls.line_mixing_factor;
    let total_sigma =
        (contribution.strong_line_sigma_cm2_per_molecule + line_mixing_sigma).max(0.0);
    let anchor = strong_anchor_line(
        context.strong_line_anchors,
        context.relevant_lines,
        context.start_index,
        strong_index,
    );

    O2LineContributionRow {
        wavelength_nm: context.wavelength_nm,
        profile_node_index: context.thermodynamic_state.profile_node_index,
        altitude_km: context.thermodynamic_state.altitude_km,
        row_kind: O2LineRowKind::StrongLine,
        status: O2LineStatus::StrongSidecar,
        line_index: anchor.map_or(MISSING_INDEX, |owned| owned.line_index),
        strong_line_index: strong_index as u32,
        matched_strong_line_index: strong_index as u32,
        gas_index: anchor.map_or(7, |owned| owned.line.gas_index),
        isotope_number: anchor.map_or(1, |owned| owned.line.isotope_number),
        isotopologue_code: anchor.map_or(66, |owned| {
            strong_lines::derive_isotopologue_code(owned.line.gas_index, owned.line.isotope_number)
        }),
        center_wavelength_nm: strong_line.center_wavelength_nm,
        center_wavenumber_cm1: strong_line.center_wavenumber_cm1,
        shifted_center_wavenumber_cm1: strong_state.mod_sig_cm1[strong_index],
        line_strength_cm2_per_molecule: anchor
            .map_or(f64::NAN, |owned| owned.line.line_strength_cm2_per_molecule),
        air_half_width_cm1: strong_line.air_half_width_cm1,
        pressure_shift_cm1: strong_line.pressure_shift_cm1,
        lower_state_energy_cm1: strong_line.lower_state_energy_cm1,
        temperature_k: context.temperature_k,
        pressure_hpa: context.thermodynamic_state.pressure_hpa,
        weak_line_sigma_cm2_per_molecule: 0.0,
        strong_line_sigma_cm2_per_molecule: contribution.strong_line_sigma_cm2_per_molecule,
        line_mixing_sigma_cm2_per_molecule: line_mixing_sigma,
        total_sigma_cm2_per_molecule: total_sigma,
        abs_total_sigma_cm2_per_molecule: total_sigma.abs(),
    }
}

#[derive(Debug, Clone, Copy)]
struct StrongAnchorLine {
    line: SpectroscopyLine,
    line_index: u32,
}

fn strong_anchor_line(
    strong_line_anchors: &[Option<usize>],
    relevant_lines: &[SpectroscopyLine],
    relevant_start_index: usize,
    strong_index: usize,
) -> Option<StrongAnchorLine> {
    let relevant_index = strong_line_anchors.get(strong_index).copied().flatten()?;
    let line = *relevant_lines.get(relevant_index)?;
    Some(StrongAnchorLine {
        line,
        line_index: (relevant_start_index + relevant_index) as u32,
    })
}

fn optional_index(index: Option<usize>) -> u32 {
    index.map_or(MISSING_INDEX, |value| value as u32)
}
