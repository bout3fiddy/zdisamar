use super::state_types::{
    ActiveCrossSectionAbsorber, ActiveLineAbsorber, CrossSectionRepresentationKind,
    PreparedCrossSectionAbsorber, PreparedCrossSectionRepresentation, PreparedLineAbsorber,
};
use crate::{
    common::errors,
    input::{
        absorber::{
            Absorber, AbsorptionRepresentation, SpectroscopyMode, resolved_absorber_species,
        },
        atmospheric_types::AbsorberSpecies,
        instrument::OperationalCrossSectionLut,
        reference_data::{CrossSectionTable, SpectroscopyLine, SpectroscopyLineList},
        scene::Scene,
    },
};

pub const DEFAULT_O2_VOLUME_MIXING_RATIO: f64 = 0.20946;

pub fn collect_active_line_absorbers(scene: &Scene) -> Vec<ActiveLineAbsorber> {
    scene
        .absorbers
        .items
        .iter()
        .filter_map(|absorber| {
            let species = resolved_absorber_species(absorber)?;
            if !species.is_line_absorbing()
                || absorber.spectroscopy.mode != SpectroscopyMode::LineByLine
            {
                return None;
            }
            Some(ActiveLineAbsorber {
                species,
                controls: absorber.spectroscopy.line_gas_controls.clone(),
                volume_mixing_ratio_profile_ppmv: absorber.volume_mixing_ratio_profile_ppmv.clone(),
            })
        })
        .collect()
}

pub fn collect_active_cross_section_absorbers<'a>(
    scene: &'a Scene,
    fallback_cross_sections: &'a CrossSectionTable,
) -> Vec<ActiveCrossSectionAbsorber<'a>> {
    let any_strong_absorption_band = scene.bands.items.iter().enumerate().any(|(band_index, _)| {
        scene
            .observation_model
            .cross_section_fit
            .strong_absorption_for_band(band_index)
    });
    let use_effective_cross_section = scene
        .observation_model
        .cross_section_fit
        .use_effective_cross_section_oe
        || scene
            .observation_model
            .cross_section_fit
            .use_polynomial_expansion
        || any_strong_absorption_band;
    let polynomial_order = scene
        .observation_model
        .cross_section_fit
        .maximum_polynomial_order();

    scene
        .absorbers
        .items
        .iter()
        .filter_map(|absorber| {
            let species = resolved_absorber_species(absorber)?;
            if absorber.spectroscopy.mode != SpectroscopyMode::CrossSections {
                return None;
            }

            let representation = match absorber.spectroscopy.resolved_absorption_representation() {
                AbsorptionRepresentation::XsecTable(table) => {
                    AbsorptionRepresentation::XsecTable(table)
                }
                AbsorptionRepresentation::XsecLut(lut) => AbsorptionRepresentation::XsecLut(lut),
                AbsorptionRepresentation::LineAbs(_) | AbsorptionRepresentation::None => {
                    // Some legacy scenes provide the O2-O2 table at the scene level, not on
                    // the absorber. Resolve that once so later state-build code does not need
                    // a second fallback path.
                    AbsorptionRepresentation::XsecTable(fallback_cross_sections)
                }
            };

            Some(ActiveCrossSectionAbsorber {
                species,
                representation,
                volume_mixing_ratio_profile_ppmv: &absorber.volume_mixing_ratio_profile_ppmv,
                use_effective_cross_section,
                polynomial_order,
            })
        })
        .collect()
}

pub fn prepare_cross_section_absorbers(
    active_absorbers: &[ActiveCrossSectionAbsorber<'_>],
    sublayer_count: usize,
) -> Result<Vec<PreparedCrossSectionAbsorber>, errors::Error> {
    active_absorbers
        .iter()
        .map(|absorber| {
            let representation_kind = representation_kind_for(absorber)?;
            let representation = match absorber.representation {
                AbsorptionRepresentation::XsecTable(table) => {
                    PreparedCrossSectionRepresentation::Table(table.clone())
                }
                AbsorptionRepresentation::XsecLut(lut) => {
                    PreparedCrossSectionRepresentation::Lut(lut.clone())
                }
                AbsorptionRepresentation::LineAbs(_) | AbsorptionRepresentation::None => {
                    return Err(errors::Error::InvalidRequest);
                }
            };

            Ok(PreparedCrossSectionAbsorber {
                species: absorber.species,
                representation_kind,
                polynomial_order: absorber.polynomial_order,
                representation,
                number_densities_cm3: vec![0.0; sublayer_count],
                column_density_factor: 0.0,
            })
        })
        .collect()
}

pub fn prepare_line_absorber(
    active_absorber: &ActiveLineAbsorber,
    line_list: &SpectroscopyLineList,
    sublayer_count: usize,
    use_operational_o2_lut: bool,
) -> Result<PreparedLineAbsorber, errors::Error> {
    let line_list =
        prepare_line_absorber_line_list(active_absorber, line_list, use_operational_o2_lut)?;
    Ok(PreparedLineAbsorber {
        species: active_absorber.species,
        line_list,
        number_densities_cm3: vec![0.0; sublayer_count],
        strong_line_states: Vec::new(),
        column_density_factor: 0.0,
    })
}

pub fn prepare_line_absorbers(
    active_absorbers: &[ActiveLineAbsorber],
    line_list: &SpectroscopyLineList,
    sublayer_count: usize,
    operational_o2_lut: &OperationalCrossSectionLut,
) -> Result<Vec<PreparedLineAbsorber>, errors::Error> {
    active_absorbers
        .iter()
        .map(|active_absorber| {
            let use_operational_o2_lut =
                operational_o2_lut.enabled() && active_absorber.species == AbsorberSpecies::O2;
            prepare_line_absorber(
                active_absorber,
                line_list,
                sublayer_count,
                use_operational_o2_lut,
            )
        })
        .collect()
}

pub fn prepare_line_absorber_strong_line_states(
    line_absorber: &mut PreparedLineAbsorber,
    sublayers: &[super::state_types::PreparedSublayer],
) -> Result<(), errors::Error> {
    if !line_absorber.line_list.has_strong_line_sidecars() {
        line_absorber.strong_line_states.clear();
        return Ok(());
    }

    let mut states = Vec::with_capacity(sublayers.len());
    for sublayer in sublayers {
        let Some(state) = line_absorber
            .line_list
            .prepare_strong_line_state(sublayer.temperature_k, sublayer.pressure_hpa)
        else {
            return Err(errors::Error::InvalidRequest);
        };
        states.push(Some(state));
    }
    line_absorber.strong_line_states = states;
    Ok(())
}

pub fn prepare_line_absorber_line_list(
    active_absorber: &ActiveLineAbsorber,
    line_list: &SpectroscopyLineList,
    use_operational_o2_lut: bool,
) -> Result<SpectroscopyLineList, errors::Error> {
    let mut prepared = line_list.clone();
    apply_runtime_controls_for_absorber(&mut prepared, active_absorber)?;
    if !use_operational_o2_lut && prepared.lines.is_empty() {
        return Err(errors::Error::InvalidRequest);
    }
    sort_line_list(&mut prepared);
    if !use_operational_o2_lut {
        prepared.build_strong_line_match_index()?;
    }
    Ok(prepared)
}

fn representation_kind_for(
    absorber: &ActiveCrossSectionAbsorber<'_>,
) -> Result<CrossSectionRepresentationKind, errors::Error> {
    match absorber.representation {
        AbsorptionRepresentation::XsecTable(_) if absorber.use_effective_cross_section => {
            Ok(CrossSectionRepresentationKind::EffectiveTable)
        }
        AbsorptionRepresentation::XsecTable(_) => Ok(CrossSectionRepresentationKind::Table),
        AbsorptionRepresentation::XsecLut(_) if absorber.use_effective_cross_section => {
            Ok(CrossSectionRepresentationKind::EffectiveLut)
        }
        AbsorptionRepresentation::XsecLut(_) => Ok(CrossSectionRepresentationKind::Lut),
        AbsorptionRepresentation::LineAbs(_) | AbsorptionRepresentation::None => {
            Err(errors::Error::InvalidRequest)
        }
    }
}

pub fn resolve_active_line_species(
    active_line_absorber: Option<&ActiveLineAbsorber>,
    line_list: Option<&SpectroscopyLineList>,
    operational_o2_lut: &OperationalCrossSectionLut,
) -> Result<Option<AbsorberSpecies>, errors::Error> {
    if let Some(line_absorber) = active_line_absorber {
        return Ok(Some(line_absorber.species));
    }
    if operational_o2_lut.enabled() {
        return Ok(Some(AbsorberSpecies::O2));
    }
    let Some(spectroscopy_lines) = line_list else {
        return Ok(None);
    };
    if let Some(gas_index) = spectroscopy_lines.runtime_controls.gas_index {
        return species_for_hitran_index(gas_index)
            .ok_or(errors::Error::InvalidRequest)
            .map(Some);
    }
    infer_line_species(&spectroscopy_lines.lines)
}

pub fn resolve_continuum_owner_species(
    active_line_species: Option<AbsorberSpecies>,
    line_absorbers: &[PreparedLineAbsorber],
    operational_o2_lut: &OperationalCrossSectionLut,
) -> Option<AbsorberSpecies> {
    if operational_o2_lut.enabled() {
        return Some(AbsorberSpecies::O2);
    }
    if let Some(species) = active_line_species {
        return Some(species);
    }
    if line_absorbers.len() == 1 {
        return Some(line_absorbers[0].species);
    }
    line_absorbers
        .iter()
        .find(|line_absorber| line_absorber.species == AbsorberSpecies::O2)
        .map(|line_absorber| line_absorber.species)
}

pub fn species_mixing_ratio_at_pressure(
    scene: &Scene,
    species: AbsorberSpecies,
    explicit_profile_ppmv: &[[f64; 2]],
    pressure_hpa: f64,
    default_fraction: Option<f64>,
) -> Option<f64> {
    let profile_ppmv = if explicit_profile_ppmv.is_empty() {
        find_absorber_by_species(scene, species)
            .map(|absorber| absorber.volume_mixing_ratio_profile_ppmv.as_slice())
            .unwrap_or(&[])
    } else {
        explicit_profile_ppmv
    };
    if !profile_ppmv.is_empty() {
        return Some(interpolate_mixing_ratio_profile_fraction(
            profile_ppmv,
            pressure_hpa,
        ));
    }
    default_fraction.or_else(|| default_volume_mixing_ratio_for_scene(scene, species))
}

pub fn default_volume_mixing_ratio(species: AbsorberSpecies) -> Option<f64> {
    match species {
        AbsorberSpecies::O2 | AbsorberSpecies::O2O2 => None,
    }
}

pub fn sort_line_list(line_list: &mut SpectroscopyLineList) {
    line_list.lines.sort_by(|left, right| {
        left.center_wavelength_nm
            .total_cmp(&right.center_wavelength_nm)
    });
    line_list.lines_sorted_ascending = true;
}

fn apply_runtime_controls_for_absorber(
    line_list: &mut SpectroscopyLineList,
    active_absorber: &ActiveLineAbsorber,
) -> Result<(), errors::Error> {
    line_list.apply_runtime_controls(
        active_absorber.species.hitran_index().map(u16::from),
        active_absorber.controls.active_isotopes(),
        active_absorber.controls.active_threshold_line(),
        active_absorber.controls.active_cutoff_cm1(),
        if active_absorber.species == AbsorberSpecies::O2 {
            active_absorber.controls.active_line_mixing_factor()
        } else {
            0.0
        },
    )
}

fn default_volume_mixing_ratio_for_scene(_scene: &Scene, species: AbsorberSpecies) -> Option<f64> {
    default_volume_mixing_ratio(species)
}

fn infer_line_species(
    lines: &[SpectroscopyLine],
) -> Result<Option<AbsorberSpecies>, errors::Error> {
    let Some(first_line) = lines.first() else {
        return Ok(None);
    };
    if first_line.gas_index == 0 {
        return Ok(None);
    }
    if lines
        .iter()
        .skip(1)
        .any(|line| line.gas_index != first_line.gas_index)
    {
        return Ok(None);
    }
    species_for_hitran_index(first_line.gas_index)
        .ok_or(errors::Error::InvalidRequest)
        .map(Some)
}

fn species_for_hitran_index(gas_index: u16) -> Option<AbsorberSpecies> {
    match gas_index {
        7 => Some(AbsorberSpecies::O2),
        _ => None,
    }
}

fn find_absorber_by_species(scene: &Scene, species: AbsorberSpecies) -> Option<&Absorber> {
    scene
        .absorbers
        .items
        .iter()
        .find(|absorber| resolved_absorber_species(absorber) == Some(species))
}

fn interpolate_mixing_ratio_profile_fraction(profile_ppmv: &[[f64; 2]], pressure_hpa: f64) -> f64 {
    if profile_ppmv.is_empty() {
        return 0.0;
    }
    let safe_pressure_hpa = pressure_hpa.max(0.0);
    if profile_ppmv.len() == 1 {
        return ppmv_to_fraction(profile_ppmv[0][1]);
    }

    let first_pressure_hpa = profile_ppmv[0][0];
    let last_pressure_hpa = profile_ppmv[profile_ppmv.len() - 1][0];
    // Input profiles can be stored surface-to-top or top-to-surface. Keep the
    // original order and interpolate within it so both vendor conventions work.
    let descending = first_pressure_hpa >= last_pressure_hpa;
    if (descending && safe_pressure_hpa >= first_pressure_hpa)
        || (!descending && safe_pressure_hpa <= first_pressure_hpa)
    {
        return ppmv_to_fraction(profile_ppmv[0][1]);
    }
    if (descending && safe_pressure_hpa <= last_pressure_hpa)
        || (!descending && safe_pressure_hpa >= last_pressure_hpa)
    {
        return ppmv_to_fraction(profile_ppmv[profile_ppmv.len() - 1][1]);
    }

    for pair in profile_ppmv.windows(2) {
        let left = pair[0];
        let right = pair[1];
        let in_segment = if descending {
            safe_pressure_hpa <= left[0] && safe_pressure_hpa >= right[0]
        } else {
            safe_pressure_hpa >= left[0] && safe_pressure_hpa <= right[0]
        };
        if !in_segment {
            continue;
        }

        let span = right[0] - left[0];
        if span == 0.0 {
            return ppmv_to_fraction(right[1]);
        }
        let weight = (safe_pressure_hpa - left[0]) / span;
        return ppmv_to_fraction(left[1] + weight * (right[1] - left[1]));
    }

    ppmv_to_fraction(profile_ppmv[profile_ppmv.len() - 1][1])
}

fn ppmv_to_fraction(value_ppmv: f64) -> f64 {
    value_ppmv.max(0.0) * 1.0e-6
}
