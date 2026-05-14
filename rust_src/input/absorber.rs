use crate::{
    common::errors,
    input::{
        atmospheric_types::AbsorberSpecies,
        binding::Binding,
        instrument::OperationalCrossSectionLut,
        reference_data::{
            CollisionInducedAbsorptionTable, CrossSectionTable, SpectroscopyLineList,
        },
    },
};

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum SpectroscopyMode {
    #[default]
    None,
    LineByLine,
    Cia,
    CrossSections,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum SpectroscopyStage {
    #[default]
    None,
    Simulation,
    Retrieval,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum AbsorptionRepresentation<'a> {
    None,
    LineAbs(&'a SpectroscopyLineList),
    XsecTable(&'a CrossSectionTable),
    XsecLut(&'a OperationalCrossSectionLut),
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct LineGasControls {
    pub factor_lm_sim: Option<f64>,
    pub factor_lm_retr: Option<f64>,
    pub isotopes_sim: Vec<u8>,
    pub isotopes_retr: Vec<u8>,
    pub threshold_line_sim: Option<f64>,
    pub threshold_line_retr: Option<f64>,
    pub cutoff_sim_cm1: Option<f64>,
    pub cutoff_retr_cm1: Option<f64>,
    pub active_stage: SpectroscopyStage,
}

impl LineGasControls {
    pub fn validate(&self) -> Result<(), errors::Error> {
        validate_optional_finite(self.factor_lm_sim)?;
        validate_optional_finite(self.factor_lm_retr)?;
        validate_optional_nonnegative(self.threshold_line_sim)?;
        validate_optional_nonnegative(self.threshold_line_retr)?;
        validate_optional_positive(self.cutoff_sim_cm1)?;
        validate_optional_positive(self.cutoff_retr_cm1)?;
        validate_isotope_selection(&self.isotopes_sim)?;
        validate_isotope_selection(&self.isotopes_retr)
    }

    pub fn configured(&self) -> bool {
        self.factor_lm_sim.is_some()
            || self.factor_lm_retr.is_some()
            || !self.isotopes_sim.is_empty()
            || !self.isotopes_retr.is_empty()
            || self.threshold_line_sim.is_some()
            || self.threshold_line_retr.is_some()
            || self.cutoff_sim_cm1.is_some()
            || self.cutoff_retr_cm1.is_some()
    }

    pub fn active_line_mixing_factor(&self) -> f64 {
        match self.active_stage {
            SpectroscopyStage::Simulation => self.factor_lm_sim.unwrap_or(1.0),
            SpectroscopyStage::Retrieval => self.factor_lm_retr.unwrap_or(1.0),
            SpectroscopyStage::None => self.factor_lm_sim.or(self.factor_lm_retr).unwrap_or(1.0),
        }
    }

    pub fn active_isotopes(&self) -> &[u8] {
        match self.active_stage {
            SpectroscopyStage::Simulation => &self.isotopes_sim,
            SpectroscopyStage::Retrieval => &self.isotopes_retr,
            SpectroscopyStage::None => {
                if self.isotopes_sim.is_empty() {
                    &self.isotopes_retr
                } else {
                    &self.isotopes_sim
                }
            }
        }
    }

    pub fn active_threshold_line(&self) -> Option<f64> {
        match self.active_stage {
            SpectroscopyStage::Simulation => self.threshold_line_sim,
            SpectroscopyStage::Retrieval => self.threshold_line_retr,
            SpectroscopyStage::None => self.threshold_line_sim.or(self.threshold_line_retr),
        }
    }

    pub fn active_cutoff_cm1(&self) -> Option<f64> {
        match self.active_stage {
            SpectroscopyStage::Simulation => self.cutoff_sim_cm1,
            SpectroscopyStage::Retrieval => self.cutoff_retr_cm1,
            SpectroscopyStage::None => self.cutoff_sim_cm1.or(self.cutoff_retr_cm1),
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Spectroscopy {
    pub mode: SpectroscopyMode,
    pub provider: String,
    pub line_list: Binding,
    pub line_mixing: Binding,
    pub strong_lines: Binding,
    pub cia_table: Binding,
    pub cross_section_table: Binding,
    pub operational_lut: Binding,
    pub line_gas_controls: LineGasControls,
    pub resolved_line_list: Option<SpectroscopyLineList>,
    pub resolved_cia_table: Option<CollisionInducedAbsorptionTable>,
    pub resolved_cross_section_table: Option<CrossSectionTable>,
    pub resolved_cross_section_lut: Option<OperationalCrossSectionLut>,
}

impl Spectroscopy {
    pub fn validate(&self) -> Result<(), errors::Error> {
        self.line_list.validate()?;
        self.line_mixing.validate()?;
        self.strong_lines.validate()?;
        self.cia_table.validate()?;
        self.cross_section_table.validate()?;
        self.operational_lut.validate()?;
        self.line_gas_controls.validate()?;

        if self.mode == SpectroscopyMode::None
            && (!self.provider.is_empty()
                || self.line_list.enabled()
                || self.line_mixing.enabled()
                || self.strong_lines.enabled()
                || self.cia_table.enabled()
                || self.cross_section_table.enabled()
                || self.operational_lut.enabled()
                || self.line_gas_controls.configured()
                || self.resolved_line_list.is_some()
                || self.resolved_cia_table.is_some()
                || self.resolved_cross_section_table.is_some()
                || self.resolved_cross_section_lut.is_some())
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.resolved_line_list.is_some() && self.mode != SpectroscopyMode::LineByLine {
            return Err(errors::Error::InvalidRequest);
        }
        if self.resolved_cia_table.is_some() && self.mode != SpectroscopyMode::Cia {
            return Err(errors::Error::InvalidRequest);
        }
        if self.resolved_cross_section_table.is_some()
            && self.mode != SpectroscopyMode::CrossSections
        {
            return Err(errors::Error::InvalidRequest);
        }
        if self.resolved_cross_section_lut.is_some() && !self.operational_lut.enabled() {
            return Err(errors::Error::InvalidRequest);
        }

        let has_cross_section_table =
            self.cross_section_table.enabled() || self.resolved_cross_section_table.is_some();
        let has_cross_section_lut =
            self.operational_lut.enabled() || self.resolved_cross_section_lut.is_some();
        if self.mode == SpectroscopyMode::CrossSections
            && has_cross_section_table
            && has_cross_section_lut
        {
            return Err(errors::Error::InvalidRequest);
        }
        Ok(())
    }

    pub fn resolved_absorption_representation(&self) -> AbsorptionRepresentation<'_> {
        if let Some(lut) = &self.resolved_cross_section_lut {
            return AbsorptionRepresentation::XsecLut(lut);
        }
        if let Some(table) = &self.resolved_cross_section_table {
            return AbsorptionRepresentation::XsecTable(table);
        }
        if let Some(line_list) = &self.resolved_line_list {
            return AbsorptionRepresentation::LineAbs(line_list);
        }
        AbsorptionRepresentation::None
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct Absorber {
    pub id: String,
    pub species: String,
    pub resolved_species: Option<AbsorberSpecies>,
    pub profile_source: Binding,
    pub volume_mixing_ratio_profile_ppmv: Vec<[f64; 2]>,
    pub spectroscopy: Spectroscopy,
}

impl Absorber {
    pub fn validate(&self) -> Result<(), errors::Error> {
        if self.id.is_empty() || self.species.is_empty() {
            return Err(errors::Error::InvalidRequest);
        }
        if resolved_absorber_species(self).is_none() {
            return Err(errors::Error::InvalidRequest);
        }
        self.profile_source.validate()?;
        validate_volume_mixing_ratio_profile(&self.volume_mixing_ratio_profile_ppmv)?;
        self.spectroscopy.validate()
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct AbsorberSet {
    pub items: Vec<Absorber>,
}

impl AbsorberSet {
    pub fn validate(&self) -> Result<(), errors::Error> {
        for (index, absorber) in self.items.iter().enumerate() {
            absorber.validate()?;
            for other in &self.items[index + 1..] {
                if absorber.id == other.id {
                    return Err(errors::Error::InvalidRequest);
                }
            }
        }
        Ok(())
    }
}

pub fn resolve_absorber_species_name(species_name: &str) -> Option<AbsorberSpecies> {
    match species_name {
        "o2" => Some(AbsorberSpecies::O2),
        "o2_o2" => Some(AbsorberSpecies::O2O2),
        _ => {
            let lower = species_name.to_ascii_lowercase();
            match lower.as_str() {
                "o2_o2" | "o2o2" | "o2-o2" => Some(AbsorberSpecies::O2O2),
                _ => None,
            }
        }
    }
}

pub fn resolved_absorber_species(absorber: &Absorber) -> Option<AbsorberSpecies> {
    absorber
        .resolved_species
        .or_else(|| resolve_absorber_species_name(&absorber.species))
}

pub fn validate_volume_mixing_ratio_profile(
    profile_ppmv: &[[f64; 2]],
) -> Result<(), errors::Error> {
    let mut previous_pressure_hpa = None;
    let mut descending = None;
    for entry in profile_ppmv {
        if !entry[0].is_finite() || !entry[1].is_finite() || entry[0] <= 0.0 || entry[1] < 0.0 {
            return Err(errors::Error::InvalidRequest);
        }
        if let Some(previous) = previous_pressure_hpa {
            if entry[0] == previous {
                return Err(errors::Error::InvalidRequest);
            }
            let entry_descending = entry[0] < previous;
            if let Some(expected_descending) = descending {
                if entry_descending != expected_descending {
                    return Err(errors::Error::InvalidRequest);
                }
            } else {
                descending = Some(entry_descending);
            }
        }
        previous_pressure_hpa = Some(entry[0]);
    }
    Ok(())
}

fn validate_isotope_selection(isotopes: &[u8]) -> Result<(), errors::Error> {
    for (index, isotope) in isotopes.iter().copied().enumerate() {
        if isotope == 0 || isotopes[index + 1..].contains(&isotope) {
            return Err(errors::Error::InvalidRequest);
        }
    }
    Ok(())
}

fn validate_optional_finite(value: Option<f64>) -> Result<(), errors::Error> {
    if value.is_some_and(|value| !value.is_finite()) {
        return Err(errors::Error::InvalidRequest);
    }
    Ok(())
}

fn validate_optional_nonnegative(value: Option<f64>) -> Result<(), errors::Error> {
    if value.is_some_and(|value| !value.is_finite() || value < 0.0) {
        return Err(errors::Error::InvalidRequest);
    }
    Ok(())
}

fn validate_optional_positive(value: Option<f64>) -> Result<(), errors::Error> {
    if value.is_some_and(|value| !value.is_finite() || value <= 0.0) {
        return Err(errors::Error::InvalidRequest);
    }
    Ok(())
}
