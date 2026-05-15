use super::{
    ActiveCrossSectionAbsorber, ActiveLineAbsorber, PreparationContext,
    PreparedCrossSectionAbsorber, PreparedLineAbsorber,
    spectroscopy::{
        collect_active_cross_section_absorbers, collect_active_line_absorbers,
        prepare_cross_section_absorbers, prepare_line_absorber_line_list, prepare_line_absorbers,
        resolve_active_line_species, resolve_continuum_owner_species, sort_line_list,
    },
};
use crate::{
    common::errors,
    input::{
        atmospheric_types::AbsorberSpecies,
        reference_data::{SpectroscopyLineList, StrongLinePreparedState, WeakLinePreparedState},
    },
};

#[derive(Debug, Clone, PartialEq)]
pub struct AbsorberBuildState<'a> {
    pub active_line_absorbers: Vec<ActiveLineAbsorber>,
    pub active_cross_section_absorbers: Vec<ActiveCrossSectionAbsorber<'a>>,
    pub single_active_line_absorber: Option<ActiveLineAbsorber>,
    pub owned_cross_section_absorbers: Vec<PreparedCrossSectionAbsorber>,
    pub owned_line_absorbers: Vec<PreparedLineAbsorber>,
    pub strong_line_states: Vec<StrongLinePreparedState>,
    pub profile_strong_line_states: Vec<StrongLinePreparedState>,
    pub profile_weak_line_states: Vec<WeakLinePreparedState>,
    pub owned_lines: Option<SpectroscopyLineList>,
    pub active_line_species: Option<AbsorberSpecies>,
    pub continuum_owner_species: Option<AbsorberSpecies>,
    pub mean_sigma: f64,
    pub midpoint_continuum_sigma: f64,
    pub air_mass_factor: f64,
    pub has_line_absorbers: bool,
}

impl<'a> Default for AbsorberBuildState<'a> {
    fn default() -> Self {
        Self {
            active_line_absorbers: Vec::new(),
            active_cross_section_absorbers: Vec::new(),
            single_active_line_absorber: None,
            owned_cross_section_absorbers: Vec::new(),
            owned_line_absorbers: Vec::new(),
            strong_line_states: Vec::new(),
            profile_strong_line_states: Vec::new(),
            profile_weak_line_states: Vec::new(),
            owned_lines: None,
            active_line_species: None,
            continuum_owner_species: None,
            mean_sigma: 0.0,
            midpoint_continuum_sigma: 0.0,
            air_mass_factor: 0.0,
            has_line_absorbers: false,
        }
    }
}

pub fn build_absorbers<'a>(
    context: &mut PreparationContext<'a>,
) -> Result<AbsorberBuildState<'a>, errors::Error> {
    let mut owned_lines = context.spectroscopy_lines.take();
    let scene = context.scene;
    let operational_o2_lut = context.operational_o2_lut.clone();
    let active_line_absorbers = collect_active_line_absorbers(scene);
    let active_cross_section_absorbers =
        collect_active_cross_section_absorbers(scene, context.cross_sections);
    let single_active_line_absorber = if active_line_absorbers.len() == 1 {
        Some(active_line_absorbers[0].clone())
    } else {
        None
    };
    let sublayer_count = context.vertical_grid.sublayer_mid_altitudes_km.len();

    let mut state = AbsorberBuildState {
        active_line_absorbers,
        active_cross_section_absorbers,
        single_active_line_absorber,
        ..AbsorberBuildState::default()
    };

    state.owned_cross_section_absorbers =
        prepare_cross_section_absorbers(&state.active_cross_section_absorbers, sublayer_count)?;

    build_line_absorbers(
        &mut state,
        &mut owned_lines,
        sublayer_count,
        &operational_o2_lut,
    )?;
    prepare_profile_line_states(context, &mut state, &operational_o2_lut)?;

    state.active_line_species = if state.owned_line_absorbers.is_empty() {
        resolve_active_line_species(
            state.single_active_line_absorber.as_ref(),
            state.owned_lines.as_ref(),
            &operational_o2_lut,
        )?
    } else {
        None
    };
    state.continuum_owner_species = resolve_continuum_owner_species(
        state.active_line_species,
        &state.owned_line_absorbers,
        &operational_o2_lut,
    );
    state.has_line_absorbers =
        state.single_active_line_absorber.is_some() || !state.owned_line_absorbers.is_empty();
    if state.owned_cross_section_absorbers.is_empty() {
        state.mean_sigma = context.cross_sections.mean_sigma_in_range(
            context.scene.spectral_grid.start_nm,
            context.scene.spectral_grid.end_nm,
        );
        state.midpoint_continuum_sigma = context
            .cross_sections
            .interpolate_sigma(context.midpoint_nm);
    }
    state.air_mass_factor = context.lut.nearest(
        scene.geometry.solar_zenith_deg,
        scene.geometry.viewing_zenith_deg,
        scene.geometry.relative_azimuth_deg,
    );

    Ok(state)
}

fn build_line_absorbers(
    state: &mut AbsorberBuildState<'_>,
    owned_lines: &mut Option<SpectroscopyLineList>,
    sublayer_count: usize,
    operational_o2_lut: &crate::input::instrument::OperationalCrossSectionLut,
) -> Result<(), errors::Error> {
    let Some(mut line_list) = owned_lines.take() else {
        return Ok(());
    };

    if state.active_line_absorbers.len() > 1
        || (operational_o2_lut.enabled() && !state.active_line_absorbers.is_empty())
    {
        state.owned_line_absorbers = prepare_line_absorbers(
            &state.active_line_absorbers,
            &line_list,
            sublayer_count,
            operational_o2_lut,
        )?;
        return Ok(());
    }

    if let Some(line_absorber) = &state.single_active_line_absorber {
        let use_operational_o2_lut =
            operational_o2_lut.enabled() && line_absorber.species == AbsorberSpecies::O2;
        line_list =
            prepare_line_absorber_line_list(line_absorber, &line_list, use_operational_o2_lut)?;
    } else {
        sort_line_list(&mut line_list);
        if !operational_o2_lut.enabled() {
            line_list.build_strong_line_match_index()?;
        }
    }
    state.owned_lines = Some(line_list);
    Ok(())
}

fn prepare_profile_line_states(
    context: &PreparationContext<'_>,
    state: &mut AbsorberBuildState<'_>,
    operational_o2_lut: &crate::input::instrument::OperationalCrossSectionLut,
) -> Result<(), errors::Error> {
    if !state.owned_line_absorbers.is_empty() || operational_o2_lut.enabled() {
        return Ok(());
    }
    let Some(line_list) = &state.owned_lines else {
        return Ok(());
    };
    if !line_list.has_strong_line_sidecars() {
        return Ok(());
    }
    if context.spectroscopy_profile_temperatures_k.len()
        != context.spectroscopy_profile_pressures_hpa.len()
    {
        return Err(errors::Error::InvalidRequest);
    }

    if context.spectroscopy_profile_temperatures_k.is_empty() {
        // Keep this storage empty until sublayer temperatures are known.
        state.strong_line_states = Vec::new();
        return Ok(());
    }

    for (&temperature_k, &pressure_hpa) in context
        .spectroscopy_profile_temperatures_k
        .iter()
        .zip(&context.spectroscopy_profile_pressures_hpa)
    {
        state
            .profile_weak_line_states
            .push(line_list.prepare_weak_line_state(temperature_k, pressure_hpa));
        let Some(strong_state) = line_list.prepare_strong_line_state(temperature_k, pressure_hpa)
        else {
            return Err(errors::Error::InvalidRequest);
        };
        state.profile_strong_line_states.push(strong_state);
    }
    Ok(())
}
