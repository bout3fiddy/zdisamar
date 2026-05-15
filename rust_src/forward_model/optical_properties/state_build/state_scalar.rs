use super::state_types::PreparedSublayer;
use crate::{
    forward_model::optical_properties::shared::particle_profiles,
    input::atmosphere::FractionControl,
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
