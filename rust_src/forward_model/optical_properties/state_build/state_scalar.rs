use super::{prepared_state::PreparedOpticalState, state_types::PreparedSublayer};
use crate::{
    forward_model::optical_properties::shared::particle_profiles,
    input::{atmosphere::FractionControl, atmospheric_types::AbsorberSpecies},
};

pub fn prepared_scalar_for_sublayer(values: &[f64], sublayer: PreparedSublayer) -> f64 {
    let index = sublayer.global_sublayer_index as usize;
    values.get(index).copied().unwrap_or(0.0)
}

fn interpolate_prepared_scalar_between_sublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    values: &[f64],
    altitude_km: f64,
) -> f64 {
    let left_value = prepared_scalar_for_sublayer(values, left);
    let right_value = prepared_scalar_for_sublayer(values, right);
    let span = right.altitude_km - left.altitude_km;
    if span <= 0.0 {
        return right_value;
    }
    let fraction = ((altitude_km - left.altitude_km) / span).clamp(0.0, 1.0);
    left_value + (right_value - left_value) * fraction
}

pub fn interpolate_prepared_scalar_at_altitude(
    sublayers: &[PreparedSublayer],
    values: &[f64],
    altitude_km: f64,
) -> f64 {
    if sublayers.is_empty() {
        return 0.0;
    }
    if sublayers.len() == 1 {
        return prepared_scalar_for_sublayer(values, sublayers[0]);
    }

    let first = sublayers[0];
    let last = sublayers[sublayers.len() - 1];
    if altitude_km <= first.altitude_km {
        return interpolate_prepared_scalar_between_sublayers(
            first,
            sublayers[1],
            values,
            altitude_km,
        );
    }
    if altitude_km >= last.altitude_km {
        return interpolate_prepared_scalar_between_sublayers(
            sublayers[sublayers.len() - 2],
            last,
            values,
            altitude_km,
        );
    }
    for pair in sublayers.windows(2) {
        let left = pair[0];
        let right = pair[1];
        if altitude_km <= right.altitude_km {
            return interpolate_prepared_scalar_between_sublayers(left, right, values, altitude_km);
        }
    }
    prepared_scalar_for_sublayer(values, last)
}

fn line_absorber_density_for_species_at_sublayer(
    prepared: &PreparedOpticalState,
    species: AbsorberSpecies,
    global_sublayer_index: usize,
) -> f64 {
    for line_absorber in &prepared.line_absorbers {
        if line_absorber.species != species {
            continue;
        }
        return line_absorber
            .number_densities_cm3
            .get(global_sublayer_index)
            .copied()
            .unwrap_or(0.0);
    }
    0.0
}

fn line_absorber_density_for_species_at_altitude(
    prepared: &PreparedOpticalState,
    species: AbsorberSpecies,
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
) -> f64 {
    for line_absorber in &prepared.line_absorbers {
        if line_absorber.species != species {
            continue;
        }
        return interpolate_prepared_scalar_at_altitude(
            sublayers,
            &line_absorber.number_densities_cm3,
            altitude_km,
        );
    }
    0.0
}

pub fn continuum_carrier_density_at_sublayer(
    prepared: &PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) -> f64 {
    if prepared.line_absorbers.is_empty() {
        return sublayer.absorber_number_density_cm3;
    }

    let Some(owner_species) = prepared.continuum_owner_species else {
        return sublayer.absorber_number_density_cm3;
    };
    if prepared.operational_o2_lut.enabled() && owner_species == AbsorberSpecies::O2 {
        return sublayer.oxygen_number_density_cm3;
    }
    line_absorber_density_for_species_at_sublayer(prepared, owner_species, global_sublayer_index)
}

fn cross_section_carrier_density_at_sublayer(
    prepared: &PreparedOpticalState,
    global_sublayer_index: usize,
) -> f64 {
    prepared
        .cross_section_absorbers
        .iter()
        .filter_map(|absorber| absorber.number_densities_cm3.get(global_sublayer_index))
        .copied()
        .sum()
}

pub fn line_spectroscopy_carrier_density(
    prepared: &PreparedOpticalState,
    absorber_density_cm3: f64,
    oxygen_density_cm3: f64,
    cross_section_density_cm3: f64,
) -> f64 {
    if prepared.operational_o2_lut.enabled() {
        return oxygen_density_cm3;
    }
    if cross_section_density_cm3 <= 0.0 {
        return absorber_density_cm3;
    }
    (absorber_density_cm3 - cross_section_density_cm3).max(0.0)
}

pub fn line_spectroscopy_carrier_density_at_sublayer(
    prepared: &PreparedOpticalState,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) -> f64 {
    line_spectroscopy_carrier_density(
        prepared,
        sublayer.absorber_number_density_cm3,
        sublayer.oxygen_number_density_cm3,
        if prepared.cross_section_absorbers.is_empty() {
            0.0
        } else {
            cross_section_carrier_density_at_sublayer(prepared, global_sublayer_index)
        },
    )
}

pub fn continuum_carrier_density_at_altitude(
    prepared: &PreparedOpticalState,
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
    absorber_density_cm3: f64,
    oxygen_density_cm3: f64,
) -> f64 {
    if prepared.line_absorbers.is_empty() {
        return absorber_density_cm3;
    }

    let Some(owner_species) = prepared.continuum_owner_species else {
        return absorber_density_cm3;
    };
    if prepared.operational_o2_lut.enabled() && owner_species == AbsorberSpecies::O2 {
        return oxygen_density_cm3;
    }
    line_absorber_density_for_species_at_altitude(prepared, owner_species, sublayers, altitude_km)
}

fn fraction_at_wavelength(control: &FractionControl, wavelength_nm: f64) -> f64 {
    if !control.enabled {
        return 1.0;
    }
    control.value_at_wavelength(wavelength_nm)
}

pub fn particle_optical_depth_at_wavelength(
    effective_reference_optical_depth: f64,
    base_reference_optical_depth: f64,
    reference_wavelength_nm: f64,
    angstrom_exponent: f64,
    control: &FractionControl,
    wavelength_nm: f64,
) -> f64 {
    if base_reference_optical_depth > 0.0 {
        return particle_profiles::scale_optical_depth(
            base_reference_optical_depth,
            reference_wavelength_nm,
            angstrom_exponent,
            wavelength_nm,
        ) * fraction_at_wavelength(control, wavelength_nm);
    }

    let effective_optical_depth = particle_profiles::scale_optical_depth(
        effective_reference_optical_depth,
        reference_wavelength_nm,
        angstrom_exponent,
        wavelength_nm,
    );
    if !control.enabled {
        return effective_optical_depth;
    }

    let reference_fraction = control.value_at_wavelength(reference_wavelength_nm);
    if reference_fraction <= 0.0 {
        return 0.0;
    }
    effective_optical_depth * fraction_at_wavelength(control, wavelength_nm) / reference_fraction
}
