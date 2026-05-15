use super::{
    PreparedOpticalState, PreparedSublayer, SharedRtmLevelGeometry,
    continuum_carrier_density_at_altitude, continuum_carrier_density_at_sublayer,
    interpolate_prepared_scalar_at_altitude, line_spectroscopy_carrier_density,
    line_spectroscopy_carrier_density_at_sublayer, zero_spectroscopy_evaluation,
};
use crate::{
    common::errors,
    forward_model::optical_properties::shared::{
        particle_profiles,
        phase_functions::{self, PHASE_COEFFICIENT_COUNT, PhaseCoefficients},
    },
    input::{
        atmospheric_types::AbsorberSpecies,
        reference::rayleigh,
        reference_data::{SpectroscopyEvaluation, interpolate_cross_section_sigma},
    },
};

const CENTIMETERS_PER_KILOMETER: f64 = 1.0e5;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SharedOpticalCarrier {
    pub gas_absorption_optical_depth_per_km: f64,
    pub gas_scattering_optical_depth_per_km: f64,
    pub cia_optical_depth_per_km: f64,
    pub aerosol_optical_depth_per_km: f64,
    pub aerosol_scattering_optical_depth_per_km: f64,
    pub cloud_optical_depth_per_km: f64,
    pub cloud_scattering_optical_depth_per_km: f64,
    pub aerosol_phase_coefficients: PhaseCoefficients,
    pub phase_coefficients: PhaseCoefficients,
}

impl Default for SharedOpticalCarrier {
    fn default() -> Self {
        Self {
            gas_absorption_optical_depth_per_km: 0.0,
            gas_scattering_optical_depth_per_km: 0.0,
            cia_optical_depth_per_km: 0.0,
            aerosol_optical_depth_per_km: 0.0,
            aerosol_scattering_optical_depth_per_km: 0.0,
            cloud_optical_depth_per_km: 0.0,
            cloud_scattering_optical_depth_per_km: 0.0,
            aerosol_phase_coefficients: phase_functions::zero_phase_coefficients(),
            phase_coefficients: phase_functions::zero_phase_coefficients(),
        }
    }
}

impl SharedOpticalCarrier {
    pub fn total_scattering_optical_depth_per_km(self) -> f64 {
        self.gas_scattering_optical_depth_per_km
            + self.aerosol_scattering_optical_depth_per_km
            + self.cloud_scattering_optical_depth_per_km
    }

    pub fn total_optical_depth_per_km(self) -> f64 {
        self.gas_absorption_optical_depth_per_km
            + self.gas_scattering_optical_depth_per_km
            + self.cia_optical_depth_per_km
            + self.aerosol_optical_depth_per_km
            + self.cloud_optical_depth_per_km
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PreparedQuadratureCarrier {
    pub ksca: f64,
    pub aerosol_scattering_optical_depth_per_km: f64,
    pub aerosol_phase_coefficients: PhaseCoefficients,
    pub phase_coefficients: PhaseCoefficients,
}

impl Default for PreparedQuadratureCarrier {
    fn default() -> Self {
        Self {
            ksca: 0.0,
            aerosol_scattering_optical_depth_per_km: 0.0,
            aerosol_phase_coefficients: phase_functions::zero_phase_coefficients(),
            phase_coefficients: phase_functions::zero_phase_coefficients(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SharedBoundaryCarrier {
    pub gas_scattering_optical_depth_per_km: f64,
    pub particle_scattering_optical_depth_above_per_km: f64,
    pub particle_scattering_optical_depth_below_per_km: f64,
    pub aerosol_scattering_optical_depth_above_per_km: f64,
    pub aerosol_scattering_optical_depth_below_per_km: f64,
    pub ksca_above: f64,
    pub ksca_below: f64,
    pub gas_phase_coefficients: PhaseCoefficients,
    pub aerosol_phase_coefficients_above: PhaseCoefficients,
    pub aerosol_phase_coefficients_below: PhaseCoefficients,
    pub phase_coefficients_above: PhaseCoefficients,
    pub phase_coefficients_below: PhaseCoefficients,
}

impl Default for SharedBoundaryCarrier {
    fn default() -> Self {
        Self {
            gas_scattering_optical_depth_per_km: 0.0,
            particle_scattering_optical_depth_above_per_km: 0.0,
            particle_scattering_optical_depth_below_per_km: 0.0,
            aerosol_scattering_optical_depth_above_per_km: 0.0,
            aerosol_scattering_optical_depth_below_per_km: 0.0,
            ksca_above: 0.0,
            ksca_below: 0.0,
            gas_phase_coefficients: phase_functions::gas_phase_coefficients(),
            aerosol_phase_coefficients_above: phase_functions::zero_phase_coefficients(),
            aerosol_phase_coefficients_below: phase_functions::zero_phase_coefficients(),
            phase_coefficients_above: phase_functions::zero_phase_coefficients(),
            phase_coefficients_below: phase_functions::zero_phase_coefficients(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
struct ParticleBoundaryCarrier {
    aerosol_optical_depth_per_km: f64,
    aerosol_scattering_optical_depth_per_km: f64,
    cloud_optical_depth_per_km: f64,
    cloud_scattering_optical_depth_per_km: f64,
    aerosol_phase_coefficients: PhaseCoefficients,
    cloud_phase_coefficients: PhaseCoefficients,
}

impl Default for ParticleBoundaryCarrier {
    fn default() -> Self {
        Self {
            aerosol_optical_depth_per_km: 0.0,
            aerosol_scattering_optical_depth_per_km: 0.0,
            cloud_optical_depth_per_km: 0.0,
            cloud_scattering_optical_depth_per_km: 0.0,
            aerosol_phase_coefficients: phase_functions::zero_phase_coefficients(),
            cloud_phase_coefficients: phase_functions::zero_phase_coefficients(),
        }
    }
}

impl ParticleBoundaryCarrier {
    fn total_scattering_optical_depth_per_km(self) -> f64 {
        self.aerosol_scattering_optical_depth_per_km + self.cloud_scattering_optical_depth_per_km
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct InterpolatedQuadratureState {
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub number_density_cm3: f64,
    pub oxygen_number_density_cm3: f64,
    pub cia_pair_density_cm6: f64,
    pub absorber_number_density_cm3: f64,
    pub aerosol_optical_depth_per_km: f64,
    pub cloud_optical_depth_per_km: f64,
    pub aerosol_single_scatter_albedo: f64,
    pub cloud_single_scatter_albedo: f64,
    pub aerosol_phase_coefficients: PhaseCoefficients,
    pub cloud_phase_coefficients: PhaseCoefficients,
}

impl InterpolatedQuadratureState {
    fn cia_pair_density_cm6_value(self) -> f64 {
        if self.cia_pair_density_cm6 > 0.0 {
            self.cia_pair_density_cm6
        } else {
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3
        }
    }
}

fn optical_depth_per_kilometer(optical_depth: f64, path_length_cm: f64) -> f64 {
    let span_km = (path_length_cm / CENTIMETERS_PER_KILOMETER).max(0.0);
    if span_km > 0.0 {
        optical_depth / span_km
    } else {
        0.0
    }
}

fn particle_boundary_carrier_at_support_row(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
) -> ParticleBoundaryCarrier {
    let aerosol_optical_depth_per_km = particle_profiles::scale_optical_depth(
        optical_depth_per_kilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    let cloud_optical_depth_per_km = particle_profiles::scale_optical_depth(
        optical_depth_per_kilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        wavelength_nm,
    );
    ParticleBoundaryCarrier {
        aerosol_optical_depth_per_km,
        aerosol_scattering_optical_depth_per_km: aerosol_optical_depth_per_km
            * sublayer.aerosol_single_scatter_albedo,
        cloud_optical_depth_per_km,
        cloud_scattering_optical_depth_per_km: cloud_optical_depth_per_km
            * sublayer.cloud_single_scatter_albedo,
        aerosol_phase_coefficients: sublayer.aerosol_phase_coefficients,
        cloud_phase_coefficients: sublayer.cloud_phase_coefficients,
    }
}

fn particle_boundary_carrier_from_index(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    support_row_index: u32,
) -> ParticleBoundaryCarrier {
    if support_row_index == u32::MAX {
        return ParticleBoundaryCarrier::default();
    }
    let row_index = support_row_index as usize;
    sublayers
        .get(row_index)
        .map(|&sublayer| {
            particle_boundary_carrier_at_support_row(prepared, wavelength_nm, sublayer)
        })
        .unwrap_or_default()
}

pub fn shared_boundary_carrier_at_level(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    level_geometry: SharedRtmLevelGeometry,
) -> Result<SharedBoundaryCarrier, errors::Error> {
    let boundary_row_index = level_geometry.support_row_index as usize;
    let Some(&boundary_sublayer) = sublayers.get(boundary_row_index) else {
        return Ok(SharedBoundaryCarrier::default());
    };
    let gas_carrier = shared_optical_carrier_at_support_row(
        prepared,
        wavelength_nm,
        boundary_sublayer,
        boundary_row_index,
    )?;
    let particle_above = particle_boundary_carrier_from_index(
        prepared,
        wavelength_nm,
        sublayers,
        level_geometry.particle_above_support_row_index,
    );
    let particle_below = particle_boundary_carrier_from_index(
        prepared,
        wavelength_nm,
        sublayers,
        level_geometry.particle_below_support_row_index,
    );
    let gas_scattering = gas_carrier.gas_scattering_optical_depth_per_km;
    let rayleigh2 = phase_functions::rayleigh_phase_coefficient2_at_wavelength(wavelength_nm);
    Ok(SharedBoundaryCarrier {
        gas_scattering_optical_depth_per_km: gas_scattering,
        particle_scattering_optical_depth_above_per_km: particle_above
            .total_scattering_optical_depth_per_km(),
        particle_scattering_optical_depth_below_per_km: particle_below
            .total_scattering_optical_depth_per_km(),
        aerosol_scattering_optical_depth_above_per_km: particle_above
            .aerosol_scattering_optical_depth_per_km,
        aerosol_scattering_optical_depth_below_per_km: particle_below
            .aerosol_scattering_optical_depth_per_km,
        ksca_above: gas_scattering + particle_above.total_scattering_optical_depth_per_km(),
        ksca_below: gas_scattering + particle_below.total_scattering_optical_depth_per_km(),
        gas_phase_coefficients: phase_functions::gas_phase_coefficients_from_rayleigh2(rayleigh2),
        aerosol_phase_coefficients_above: particle_above.aerosol_phase_coefficients,
        aerosol_phase_coefficients_below: particle_below.aerosol_phase_coefficients,
        phase_coefficients_above: phase_functions::combine_phase_coefficients_with_rayleigh2(
            rayleigh2,
            gas_scattering,
            particle_above.aerosol_scattering_optical_depth_per_km,
            particle_above.cloud_scattering_optical_depth_per_km,
            &particle_above.aerosol_phase_coefficients,
            &particle_above.cloud_phase_coefficients,
        ),
        phase_coefficients_below: phase_functions::combine_phase_coefficients_with_rayleigh2(
            rayleigh2,
            gas_scattering,
            particle_below.aerosol_scattering_optical_depth_per_km,
            particle_below.cloud_scattering_optical_depth_per_km,
            &particle_below.aerosol_phase_coefficients,
            &particle_below.cloud_phase_coefficients,
        ),
    })
}

pub fn shared_active_carrier_at_level(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    level_geometry: SharedRtmLevelGeometry,
) -> Result<SharedOpticalCarrier, errors::Error> {
    let boundary_row_index = level_geometry.support_row_index as usize;
    let Some(&boundary_sublayer) = sublayers.get(boundary_row_index) else {
        return Ok(SharedOpticalCarrier::default());
    };
    let gas_carrier = shared_optical_carrier_at_support_row(
        prepared,
        wavelength_nm,
        boundary_sublayer,
        boundary_row_index,
    )?;

    let below_index = level_geometry.particle_below_support_row_index;
    let above_index = level_geometry.particle_above_support_row_index;
    if below_index == u32::MAX && above_index == u32::MAX {
        return Ok(gas_carrier);
    }
    if below_index == u32::MAX {
        let Some(&above_row) = sublayers.get(above_index as usize) else {
            return Ok(gas_carrier);
        };
        let particle = particle_boundary_carrier_at_support_row(prepared, wavelength_nm, above_row);
        return Ok(compose_shared_active_carrier(
            wavelength_nm,
            gas_carrier,
            particle,
            particle,
            0.0,
        ));
    }
    if above_index == u32::MAX {
        let Some(&below_row) = sublayers.get(below_index as usize) else {
            return Ok(gas_carrier);
        };
        let particle = particle_boundary_carrier_at_support_row(prepared, wavelength_nm, below_row);
        return Ok(compose_shared_active_carrier(
            wavelength_nm,
            gas_carrier,
            particle,
            particle,
            0.0,
        ));
    }

    let Some(&below_row) = sublayers.get(below_index as usize) else {
        return Ok(gas_carrier);
    };
    let Some(&above_row) = sublayers.get(above_index as usize) else {
        return Ok(gas_carrier);
    };
    let altitude_span_km = above_row.altitude_km - below_row.altitude_km;
    let fraction = if altitude_span_km > 0.0 {
        ((level_geometry.altitude_km - below_row.altitude_km) / altitude_span_km).clamp(0.0, 1.0)
    } else {
        0.5
    };
    Ok(compose_shared_active_carrier(
        wavelength_nm,
        gas_carrier,
        particle_boundary_carrier_at_support_row(prepared, wavelength_nm, below_row),
        particle_boundary_carrier_at_support_row(prepared, wavelength_nm, above_row),
        fraction,
    ))
}

fn compose_shared_active_carrier(
    wavelength_nm: f64,
    gas_carrier: SharedOpticalCarrier,
    particle_below: ParticleBoundaryCarrier,
    particle_above: ParticleBoundaryCarrier,
    fraction: f64,
) -> SharedOpticalCarrier {
    let clamped_fraction = fraction.clamp(0.0, 1.0);
    let left_weight = 1.0 - clamped_fraction;
    let right_weight = clamped_fraction;
    let aerosol_optical_depth_per_km = left_weight * particle_below.aerosol_optical_depth_per_km
        + right_weight * particle_above.aerosol_optical_depth_per_km;
    let aerosol_scattering_optical_depth_per_km = left_weight
        * particle_below.aerosol_scattering_optical_depth_per_km
        + right_weight * particle_above.aerosol_scattering_optical_depth_per_km;
    let cloud_optical_depth_per_km = left_weight * particle_below.cloud_optical_depth_per_km
        + right_weight * particle_above.cloud_optical_depth_per_km;
    let cloud_scattering_optical_depth_per_km = left_weight
        * particle_below.cloud_scattering_optical_depth_per_km
        + right_weight * particle_above.cloud_scattering_optical_depth_per_km;
    let aerosol_phase_coefficients = interpolate_phase_coefficients_by_scattering(
        particle_below.aerosol_scattering_optical_depth_per_km,
        particle_above.aerosol_scattering_optical_depth_per_km,
        &particle_below.aerosol_phase_coefficients,
        &particle_above.aerosol_phase_coefficients,
        clamped_fraction,
    );
    let cloud_phase_coefficients = interpolate_phase_coefficients_by_scattering(
        particle_below.cloud_scattering_optical_depth_per_km,
        particle_above.cloud_scattering_optical_depth_per_km,
        &particle_below.cloud_phase_coefficients,
        &particle_above.cloud_phase_coefficients,
        clamped_fraction,
    );
    SharedOpticalCarrier {
        gas_absorption_optical_depth_per_km: gas_carrier.gas_absorption_optical_depth_per_km,
        gas_scattering_optical_depth_per_km: gas_carrier.gas_scattering_optical_depth_per_km,
        cia_optical_depth_per_km: gas_carrier.cia_optical_depth_per_km,
        aerosol_optical_depth_per_km,
        aerosol_scattering_optical_depth_per_km,
        cloud_optical_depth_per_km,
        cloud_scattering_optical_depth_per_km,
        aerosol_phase_coefficients,
        phase_coefficients: phase_functions::combine_phase_coefficients(
            wavelength_nm,
            gas_carrier.gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            &aerosol_phase_coefficients,
            &cloud_phase_coefficients,
        ),
    }
}

fn interpolate_phase_coefficients_by_scattering(
    left_scattering_per_km: f64,
    right_scattering_per_km: f64,
    left_phase_coefficients: &PhaseCoefficients,
    right_phase_coefficients: &PhaseCoefficients,
    fraction: f64,
) -> PhaseCoefficients {
    let clamped_fraction = fraction.clamp(0.0, 1.0);
    let left_weight = 1.0 - clamped_fraction;
    let right_weight = clamped_fraction;
    let interpolated_scattering_per_km =
        left_weight * left_scattering_per_km + right_weight * right_scattering_per_km;

    let mut coefficients = phase_functions::zero_phase_coefficients();
    for index in 1..PHASE_COEFFICIENT_COUNT {
        coefficients[index] = if interpolated_scattering_per_km > 0.0 {
            (left_weight * left_scattering_per_km * left_phase_coefficients[index]
                + right_weight * right_scattering_per_km * right_phase_coefficients[index])
                / interpolated_scattering_per_km
        } else {
            left_weight * left_phase_coefficients[index]
                + right_weight * right_phase_coefficients[index]
        };
    }
    coefficients
}

fn interpolate_quadrature_state_between_sublayers(
    left: PreparedSublayer,
    right: PreparedSublayer,
    altitude_km: f64,
) -> InterpolatedQuadratureState {
    let interpolation_span_km = right.altitude_km - left.altitude_km;
    let fraction = if interpolation_span_km > 0.0 {
        (altitude_km - left.altitude_km) / interpolation_span_km
    } else {
        0.0
    };
    let clamped_fraction = fraction.clamp(0.0, 1.0);
    let left_weight = 1.0 - clamped_fraction;
    let right_weight = clamped_fraction;

    let left_aerosol_per_km =
        optical_depth_per_kilometer(left.aerosol_optical_depth, left.path_length_cm);
    let right_aerosol_per_km =
        optical_depth_per_kilometer(right.aerosol_optical_depth, right.path_length_cm);
    let left_cloud_per_km =
        optical_depth_per_kilometer(left.cloud_optical_depth, left.path_length_cm);
    let right_cloud_per_km =
        optical_depth_per_kilometer(right.cloud_optical_depth, right.path_length_cm);
    let left_aerosol_scattering_per_km = left_aerosol_per_km * left.aerosol_single_scatter_albedo;
    let right_aerosol_scattering_per_km =
        right_aerosol_per_km * right.aerosol_single_scatter_albedo;
    let left_cloud_scattering_per_km = left_cloud_per_km * left.cloud_single_scatter_albedo;
    let right_cloud_scattering_per_km = right_cloud_per_km * right.cloud_single_scatter_albedo;

    InterpolatedQuadratureState {
        pressure_hpa: (left_weight * left.pressure_hpa + right_weight * right.pressure_hpa)
            .max(0.0),
        temperature_k: (left_weight * left.temperature_k + right_weight * right.temperature_k)
            .max(0.0),
        number_density_cm3: (left_weight * left.number_density_cm3
            + right_weight * right.number_density_cm3)
            .max(0.0),
        oxygen_number_density_cm3: (left_weight * left.oxygen_number_density_cm3
            + right_weight * right.oxygen_number_density_cm3)
            .max(0.0),
        cia_pair_density_cm6: (left_weight * left.cia_pair_density_cm6_value()
            + right_weight * right.cia_pair_density_cm6_value())
        .max(0.0),
        absorber_number_density_cm3: (left_weight * left.absorber_number_density_cm3
            + right_weight * right.absorber_number_density_cm3)
            .max(0.0),
        aerosol_optical_depth_per_km: (left_weight * left_aerosol_per_km
            + right_weight * right_aerosol_per_km)
            .max(0.0),
        cloud_optical_depth_per_km: (left_weight * left_cloud_per_km
            + right_weight * right_cloud_per_km)
            .max(0.0),
        aerosol_single_scatter_albedo: (left_weight * left.aerosol_single_scatter_albedo
            + right_weight * right.aerosol_single_scatter_albedo)
            .clamp(0.0, 1.0),
        cloud_single_scatter_albedo: (left_weight * left.cloud_single_scatter_albedo
            + right_weight * right.cloud_single_scatter_albedo)
            .clamp(0.0, 1.0),
        aerosol_phase_coefficients: interpolate_phase_coefficients_by_scattering(
            left_aerosol_scattering_per_km,
            right_aerosol_scattering_per_km,
            &left.aerosol_phase_coefficients,
            &right.aerosol_phase_coefficients,
            clamped_fraction,
        ),
        cloud_phase_coefficients: interpolate_phase_coefficients_by_scattering(
            left_cloud_scattering_per_km,
            right_cloud_scattering_per_km,
            &left.cloud_phase_coefficients,
            &right.cloud_phase_coefficients,
            clamped_fraction,
        ),
    }
}

pub fn interpolate_quadrature_state_at_altitude(
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
) -> Option<InterpolatedQuadratureState> {
    if sublayers.is_empty() {
        return None;
    }
    if sublayers.len() == 1 {
        let sublayer = sublayers[0];
        return Some(InterpolatedQuadratureState {
            pressure_hpa: sublayer.pressure_hpa,
            temperature_k: sublayer.temperature_k,
            number_density_cm3: sublayer.number_density_cm3,
            oxygen_number_density_cm3: sublayer.oxygen_number_density_cm3,
            cia_pair_density_cm6: sublayer.cia_pair_density_cm6_value(),
            absorber_number_density_cm3: sublayer.absorber_number_density_cm3,
            aerosol_optical_depth_per_km: optical_depth_per_kilometer(
                sublayer.aerosol_optical_depth,
                sublayer.path_length_cm,
            ),
            cloud_optical_depth_per_km: optical_depth_per_kilometer(
                sublayer.cloud_optical_depth,
                sublayer.path_length_cm,
            ),
            aerosol_single_scatter_albedo: sublayer.aerosol_single_scatter_albedo,
            cloud_single_scatter_albedo: sublayer.cloud_single_scatter_albedo,
            aerosol_phase_coefficients: sublayer.aerosol_phase_coefficients,
            cloud_phase_coefficients: sublayer.cloud_phase_coefficients,
        });
    }

    let first = sublayers[0];
    let last = sublayers[sublayers.len() - 1];
    if altitude_km <= first.altitude_km {
        return Some(interpolate_quadrature_state_between_sublayers(
            first,
            sublayers[1],
            altitude_km,
        ));
    }
    if altitude_km >= last.altitude_km {
        return Some(interpolate_quadrature_state_between_sublayers(
            sublayers[sublayers.len() - 2],
            last,
            altitude_km,
        ));
    }
    for pair in sublayers.windows(2) {
        let left = pair[0];
        let right = pair[1];
        if altitude_km <= right.altitude_km {
            return Some(interpolate_quadrature_state_between_sublayers(
                left,
                right,
                altitude_km,
            ));
        }
    }
    None
}

pub fn quadrature_carrier_at_altitude(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
) -> Result<PreparedQuadratureCarrier, errors::Error> {
    let carrier =
        shared_optical_carrier_at_altitude(prepared, wavelength_nm, sublayers, altitude_km)?;
    Ok(PreparedQuadratureCarrier {
        ksca: carrier.total_scattering_optical_depth_per_km(),
        aerosol_scattering_optical_depth_per_km: carrier.aerosol_scattering_optical_depth_per_km,
        aerosol_phase_coefficients: carrier.aerosol_phase_coefficients,
        phase_coefficients: carrier.phase_coefficients,
    })
}

fn add_weighted_evaluation(
    weighted: &mut SpectroscopyEvaluation,
    evaluation: SpectroscopyEvaluation,
    weight: f64,
) {
    weighted.weak_line_sigma_cm2_per_molecule +=
        evaluation.weak_line_sigma_cm2_per_molecule * weight;
    weighted.strong_line_sigma_cm2_per_molecule +=
        evaluation.strong_line_sigma_cm2_per_molecule * weight;
    weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
    weighted.line_mixing_sigma_cm2_per_molecule +=
        evaluation.line_mixing_sigma_cm2_per_molecule * weight;
    weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
        evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
}

fn divide_evaluation(weighted: &mut SpectroscopyEvaluation, total_weight: f64) {
    weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
    weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_sigma_cm2_per_molecule /= total_weight;
    weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
    weighted.total_sigma_cm2_per_molecule /= total_weight;
    weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
}

fn weighted_spectroscopy_evaluation_at_support_row(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    let mut total_weight = 0.0;
    let mut weighted = zero_spectroscopy_evaluation();

    if prepared.operational_o2_lut.enabled() && sublayer.oxygen_number_density_cm3 > 0.0 {
        let o2_evaluation = super::operational_o2_evaluation_at_wavelength(
            &prepared.operational_o2_lut,
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
        total_weight += sublayer.oxygen_number_density_cm3;
        add_weighted_evaluation(
            &mut weighted,
            o2_evaluation,
            sublayer.oxygen_number_density_cm3,
        );
    }

    for line_absorber in &prepared.line_absorbers {
        if prepared.operational_o2_lut.enabled() && line_absorber.species == AbsorberSpecies::O2 {
            continue;
        }
        let weight = line_absorber
            .number_densities_cm3
            .get(global_sublayer_index)
            .copied()
            .unwrap_or(0.0);
        if weight <= 0.0 {
            continue;
        }
        let evaluation = line_absorber.line_list.evaluate_at(
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        );
        total_weight += weight;
        add_weighted_evaluation(&mut weighted, evaluation, weight);
    }

    if total_weight <= 0.0 {
        return Ok(weighted);
    }
    divide_evaluation(&mut weighted, total_weight);
    Ok(weighted)
}

fn weighted_spectroscopy_evaluation_at_altitude(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
    oxygen_number_density_cm3: f64,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    let mut total_weight = 0.0;
    let mut weighted = zero_spectroscopy_evaluation();

    if prepared.operational_o2_lut.enabled() && oxygen_number_density_cm3 > 0.0 {
        let o2_evaluation = super::operational_o2_evaluation_at_wavelength(
            &prepared.operational_o2_lut,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
        total_weight += oxygen_number_density_cm3;
        add_weighted_evaluation(&mut weighted, o2_evaluation, oxygen_number_density_cm3);
    }

    for line_absorber in &prepared.line_absorbers {
        if prepared.operational_o2_lut.enabled() && line_absorber.species == AbsorberSpecies::O2 {
            continue;
        }
        let weight = interpolate_prepared_scalar_at_altitude(
            sublayers,
            &line_absorber.number_densities_cm3,
            altitude_km,
        );
        if weight <= 0.0 {
            continue;
        }
        let evaluation =
            line_absorber
                .line_list
                .evaluate_at(wavelength_nm, temperature_k, pressure_hpa);
        total_weight += weight;
        add_weighted_evaluation(&mut weighted, evaluation, weight);
    }

    if total_weight <= 0.0 {
        return Ok(weighted);
    }
    divide_evaluation(&mut weighted, total_weight);
    Ok(weighted)
}

pub fn shared_optical_carrier_at_support_row(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayer: PreparedSublayer,
    global_sublayer_index: usize,
) -> Result<SharedOpticalCarrier, errors::Error> {
    let continuum_sigma = if prepared.cross_section_absorbers.is_empty() {
        interpolate_cross_section_sigma(&prepared.continuum_points, wavelength_nm)
    } else {
        0.0
    };
    let spectroscopy_eval = if !prepared.line_absorbers.is_empty() {
        weighted_spectroscopy_evaluation_at_support_row(
            prepared,
            wavelength_nm,
            sublayer,
            global_sublayer_index,
        )?
    } else {
        super::weighted_spectroscopy_evaluation_at_wavelength(
            prepared,
            wavelength_nm,
            sublayer.temperature_k,
            sublayer.pressure_hpa,
        )?
    };

    let mut cross_section_absorption_optical_depth_per_km = 0.0;
    for absorber in &prepared.cross_section_absorbers {
        let absorber_density_cm3 = absorber
            .number_densities_cm3
            .get(global_sublayer_index)
            .copied()
            .unwrap_or(0.0);
        if absorber_density_cm3 <= 0.0 {
            continue;
        }
        cross_section_absorption_optical_depth_per_km +=
            absorber.sigma_at(wavelength_nm, sublayer.temperature_k, sublayer.pressure_hpa)
                * absorber_density_cm3
                * CENTIMETERS_PER_KILOMETER;
    }

    let line_absorber_density_cm3 =
        line_spectroscopy_carrier_density_at_sublayer(prepared, sublayer, global_sublayer_index);
    let continuum_density_cm3 = if prepared.cross_section_absorbers.is_empty() {
        continuum_carrier_density_at_sublayer(prepared, sublayer, global_sublayer_index)
    } else {
        0.0
    };
    let gas_absorption_optical_depth_per_km =
        continuum_sigma * continuum_density_cm3 * CENTIMETERS_PER_KILOMETER
            + cross_section_absorption_optical_depth_per_km
            + spectroscopy_eval.total_sigma_cm2_per_molecule
                * line_absorber_density_cm3
                * CENTIMETERS_PER_KILOMETER;
    let gas_scattering_optical_depth_per_km = rayleigh::cross_section_cm2(wavelength_nm)
        * sublayer.number_density_cm3
        * CENTIMETERS_PER_KILOMETER;
    let cia_optical_depth_per_km = super::cia_sigma_at_wavelength(
        prepared,
        wavelength_nm,
        sublayer.temperature_k,
        sublayer.pressure_hpa,
    ) * sublayer.cia_pair_density_cm6_value()
        * CENTIMETERS_PER_KILOMETER;
    let aerosol_optical_depth_per_km = particle_profiles::scale_optical_depth(
        optical_depth_per_kilometer(sublayer.aerosol_optical_depth, sublayer.path_length_cm),
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    let cloud_optical_depth_per_km = particle_profiles::scale_optical_depth(
        optical_depth_per_kilometer(sublayer.cloud_optical_depth, sublayer.path_length_cm),
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        wavelength_nm,
    );
    let aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * sublayer.aerosol_single_scatter_albedo;
    let cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * sublayer.cloud_single_scatter_albedo;
    let rayleigh2 = phase_functions::rayleigh_phase_coefficient2_at_wavelength(wavelength_nm);

    Ok(SharedOpticalCarrier {
        gas_absorption_optical_depth_per_km,
        gas_scattering_optical_depth_per_km,
        cia_optical_depth_per_km,
        aerosol_optical_depth_per_km,
        aerosol_scattering_optical_depth_per_km,
        cloud_optical_depth_per_km,
        cloud_scattering_optical_depth_per_km,
        aerosol_phase_coefficients: sublayer.aerosol_phase_coefficients,
        phase_coefficients: phase_functions::combine_phase_coefficients_with_rayleigh2(
            rayleigh2,
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            &sublayer.aerosol_phase_coefficients,
            &sublayer.cloud_phase_coefficients,
        ),
    })
}

pub fn shared_optical_carrier_at_altitude(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    sublayers: &[PreparedSublayer],
    altitude_km: f64,
) -> Result<SharedOpticalCarrier, errors::Error> {
    let Some(state) = interpolate_quadrature_state_at_altitude(sublayers, altitude_km) else {
        return Ok(SharedOpticalCarrier::default());
    };
    let continuum_sigma = if prepared.cross_section_absorbers.is_empty() {
        interpolate_cross_section_sigma(&prepared.continuum_points, wavelength_nm)
    } else {
        0.0
    };
    let spectroscopy_sigma = if !prepared.line_absorbers.is_empty() {
        weighted_spectroscopy_evaluation_at_altitude(
            prepared,
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
            sublayers,
            altitude_km,
            state.oxygen_number_density_cm3,
        )?
        .total_sigma_cm2_per_molecule
    } else {
        super::weighted_spectroscopy_evaluation_at_wavelength(
            prepared,
            wavelength_nm,
            state.temperature_k,
            state.pressure_hpa,
        )?
        .total_sigma_cm2_per_molecule
    };

    let mut cross_section_density_cm3 = 0.0;
    let mut cross_section_absorption_optical_depth_per_km = 0.0;
    for absorber in &prepared.cross_section_absorbers {
        let absorber_density_cm3 = interpolate_prepared_scalar_at_altitude(
            sublayers,
            &absorber.number_densities_cm3,
            altitude_km,
        );
        if absorber_density_cm3 <= 0.0 {
            continue;
        }
        cross_section_density_cm3 += absorber_density_cm3;
        cross_section_absorption_optical_depth_per_km +=
            absorber.sigma_at(wavelength_nm, state.temperature_k, state.pressure_hpa)
                * absorber_density_cm3
                * CENTIMETERS_PER_KILOMETER;
    }

    let line_absorber_density_cm3 = line_spectroscopy_carrier_density(
        prepared,
        state.absorber_number_density_cm3,
        state.oxygen_number_density_cm3,
        cross_section_density_cm3,
    );
    let continuum_density_cm3 = if prepared.cross_section_absorbers.is_empty() {
        continuum_carrier_density_at_altitude(
            prepared,
            sublayers,
            altitude_km,
            state.absorber_number_density_cm3,
            state.oxygen_number_density_cm3,
        )
    } else {
        0.0
    };
    let gas_absorption_optical_depth_per_km =
        continuum_sigma * continuum_density_cm3 * CENTIMETERS_PER_KILOMETER
            + cross_section_absorption_optical_depth_per_km
            + spectroscopy_sigma * line_absorber_density_cm3 * CENTIMETERS_PER_KILOMETER;
    let gas_scattering_optical_depth_per_km = rayleigh::cross_section_cm2(wavelength_nm)
        * state.number_density_cm3
        * CENTIMETERS_PER_KILOMETER;
    let cia_optical_depth_per_km = super::cia_sigma_at_wavelength(
        prepared,
        wavelength_nm,
        state.temperature_k,
        state.pressure_hpa,
    ) * state.cia_pair_density_cm6_value()
        * CENTIMETERS_PER_KILOMETER;
    let aerosol_optical_depth_per_km = particle_profiles::scale_optical_depth(
        state.aerosol_optical_depth_per_km,
        prepared.aerosol_reference_wavelength_nm,
        prepared.aerosol_angstrom_exponent,
        wavelength_nm,
    );
    let cloud_optical_depth_per_km = particle_profiles::scale_optical_depth(
        state.cloud_optical_depth_per_km,
        prepared.cloud_reference_wavelength_nm,
        prepared.cloud_angstrom_exponent,
        wavelength_nm,
    );
    let aerosol_scattering_optical_depth_per_km =
        aerosol_optical_depth_per_km * state.aerosol_single_scatter_albedo;
    let cloud_scattering_optical_depth_per_km =
        cloud_optical_depth_per_km * state.cloud_single_scatter_albedo;

    Ok(SharedOpticalCarrier {
        gas_absorption_optical_depth_per_km,
        gas_scattering_optical_depth_per_km,
        cia_optical_depth_per_km,
        aerosol_optical_depth_per_km,
        aerosol_scattering_optical_depth_per_km,
        cloud_optical_depth_per_km,
        cloud_scattering_optical_depth_per_km,
        aerosol_phase_coefficients: state.aerosol_phase_coefficients,
        phase_coefficients: phase_functions::combine_phase_coefficients(
            wavelength_nm,
            gas_scattering_optical_depth_per_km,
            aerosol_scattering_optical_depth_per_km,
            cloud_scattering_optical_depth_per_km,
            &state.aerosol_phase_coefficients,
            &state.cloud_phase_coefficients,
        ),
    })
}
