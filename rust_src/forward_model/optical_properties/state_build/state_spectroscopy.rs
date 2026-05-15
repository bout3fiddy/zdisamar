use super::{PreparedOpticalState, operational_o2_evaluation_at_wavelength};
use crate::{
    common::{errors, math::interpolation::spline},
    input::{
        reference::spectroscopy::line_list_eval,
        reference_data::{SpectroscopyEvaluation, interpolate_cross_section_sigma},
    },
};

#[derive(Debug, Default, Clone, PartialEq)]
pub struct ProfileNodeSpectroscopyCache {
    altitudes_km: Vec<f64>,
    weak_values: Vec<f64>,
    strong_values: Vec<f64>,
    line_values: Vec<f64>,
    line_mixing_values: Vec<f64>,
    total_values: Vec<f64>,
    weak_second: Vec<f64>,
    strong_second: Vec<f64>,
    line_second: Vec<f64>,
    line_mixing_second: Vec<f64>,
    total_second: Vec<f64>,
}

impl ProfileNodeSpectroscopyCache {
    pub fn new(prepared: &PreparedOpticalState, wavelength_nm: f64) -> Self {
        let Some(line_list) = &prepared.spectroscopy_lines else {
            return Self::default();
        };
        if !prepared.line_absorbers.is_empty() || prepared.operational_o2_lut.enabled() {
            return Self::default();
        }

        let node_count = prepared.spectroscopy_profile_altitudes_km.len();
        if !(3..=spline::MAX_SPLINE_POINT_COUNT).contains(&node_count)
            || prepared.spectroscopy_profile_pressures_hpa.len() != node_count
            || prepared.spectroscopy_profile_temperatures_k.len() != node_count
        {
            return Self::default();
        }

        let strong_states = (prepared.spectroscopy_profile_strong_line_states.len() == node_count)
            .then_some(prepared.spectroscopy_profile_strong_line_states.as_slice());
        let weak_states = (prepared.spectroscopy_profile_weak_line_states.len() == node_count)
            .then_some(prepared.spectroscopy_profile_weak_line_states.as_slice());

        let mut cache = Self {
            altitudes_km: prepared.spectroscopy_profile_altitudes_km.clone(),
            weak_values: Vec::with_capacity(node_count),
            strong_values: Vec::with_capacity(node_count),
            line_values: Vec::with_capacity(node_count),
            line_mixing_values: Vec::with_capacity(node_count),
            total_values: Vec::with_capacity(node_count),
            weak_second: Vec::new(),
            strong_second: Vec::new(),
            line_second: Vec::new(),
            line_mixing_second: Vec::new(),
            total_second: Vec::new(),
        };

        for index in 0..node_count {
            let evaluation = line_list_eval::total_sigma_with_prepared_profile_state(
                line_list,
                wavelength_nm,
                prepared.spectroscopy_profile_temperatures_k[index],
                prepared.spectroscopy_profile_pressures_hpa[index],
                strong_states.map(|states| &states[index]),
                weak_states.map(|states| &states[index]),
            );
            cache
                .weak_values
                .push(evaluation.weak_line_sigma_cm2_per_molecule);
            cache
                .strong_values
                .push(evaluation.strong_line_sigma_cm2_per_molecule);
            cache
                .line_values
                .push(evaluation.line_sigma_cm2_per_molecule);
            cache
                .line_mixing_values
                .push(evaluation.line_mixing_sigma_cm2_per_molecule);
            cache
                .total_values
                .push(evaluation.total_sigma_cm2_per_molecule);
        }

        if cache.fill_second_derivatives().is_err() {
            return Self::default();
        }
        cache
    }

    pub fn evaluation_at_altitude(&self, altitude_km: f64) -> Option<SpectroscopyEvaluation> {
        if self.altitudes_km.len() < 3
            || altitude_km < self.altitudes_km[0]
            || altitude_km > self.altitudes_km[self.altitudes_km.len() - 1]
        {
            return None;
        }

        Some(SpectroscopyEvaluation {
            weak_line_sigma_cm2_per_molecule: self.sample(
                &self.weak_values,
                &self.weak_second,
                altitude_km,
            )?,
            strong_line_sigma_cm2_per_molecule: self.sample(
                &self.strong_values,
                &self.strong_second,
                altitude_km,
            )?,
            line_sigma_cm2_per_molecule: self.sample(
                &self.line_values,
                &self.line_second,
                altitude_km,
            )?,
            line_mixing_sigma_cm2_per_molecule: self.sample(
                &self.line_mixing_values,
                &self.line_mixing_second,
                altitude_km,
            )?,
            total_sigma_cm2_per_molecule: self
                .sample(&self.total_values, &self.total_second, altitude_km)?
                .max(0.0),
            d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
        })
    }

    fn fill_second_derivatives(&mut self) -> Result<(), spline::Error> {
        self.weak_second =
            spline::endpoint_secant_second_derivatives(&self.altitudes_km, &self.weak_values)?;
        self.strong_second =
            spline::endpoint_secant_second_derivatives(&self.altitudes_km, &self.strong_values)?;
        self.line_second =
            spline::endpoint_secant_second_derivatives(&self.altitudes_km, &self.line_values)?;
        self.line_mixing_second = spline::endpoint_secant_second_derivatives(
            &self.altitudes_km,
            &self.line_mixing_values,
        )?;
        self.total_second =
            spline::endpoint_secant_second_derivatives(&self.altitudes_km, &self.total_values)?;
        Ok(())
    }

    fn sample(&self, values: &[f64], second: &[f64], altitude_km: f64) -> Option<f64> {
        spline::sample_with_second_derivatives(&self.altitudes_km, values, second, altitude_km).ok()
    }
}

pub fn total_cross_section_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<f64, errors::Error> {
    let continuum = if prepared.cross_section_absorbers.is_empty() {
        interpolate_cross_section_sigma(&prepared.continuum_points, wavelength_nm)
    } else {
        weighted_cross_section_sigma_at_wavelength(
            prepared,
            wavelength_nm,
            prepared.effective_temperature_k,
            prepared.effective_pressure_hpa,
        )
    };
    let line_sigma = effective_spectroscopy_evaluation_at_wavelength(prepared, wavelength_nm)?
        .total_sigma_cm2_per_molecule;
    Ok(continuum + line_sigma)
}

pub fn effective_spectroscopy_evaluation_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    weighted_spectroscopy_evaluation_at_wavelength(
        prepared,
        wavelength_nm,
        prepared.effective_temperature_k,
        prepared.effective_pressure_hpa,
    )
}

pub fn collision_induced_sigma_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
) -> f64 {
    cia_sigma_at_wavelength(
        prepared,
        wavelength_nm,
        prepared.effective_temperature_k,
        prepared.effective_pressure_hpa,
    )
}

pub fn cia_sigma_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> f64 {
    if prepared.operational_o2o2_lut.enabled() {
        return prepared
            .operational_o2o2_lut
            .sigma_at(wavelength_nm, temperature_k, pressure_hpa);
    }
    if let Some(cia_table) = &prepared.collision_induced_absorption {
        return cia_table.sigma_at(wavelength_nm, temperature_k);
    }
    0.0
}

pub fn weighted_cross_section_sigma_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> f64 {
    if prepared.cross_section_absorbers.is_empty() {
        return 0.0;
    }

    let mut total_weight = 0.0;
    let mut weighted_sigma = 0.0;
    for absorber in &prepared.cross_section_absorbers {
        let weight = if absorber.column_density_factor > 0.0 {
            absorber.column_density_factor
        } else {
            1.0
        };
        total_weight += weight;
        weighted_sigma += absorber.sigma_at(wavelength_nm, temperature_k, pressure_hpa) * weight;
    }
    if total_weight <= 0.0 {
        return 0.0;
    }
    weighted_sigma / total_weight
}

pub fn weighted_spectroscopy_evaluation_at_wavelength(
    prepared: &PreparedOpticalState,
    wavelength_nm: f64,
    temperature_k: f64,
    pressure_hpa: f64,
) -> Result<SpectroscopyEvaluation, errors::Error> {
    let mut total_weight = 0.0;
    let mut weighted = zero_spectroscopy_evaluation();

    if prepared.operational_o2_lut.enabled() && prepared.oxygen_column_density_factor > 0.0 {
        let evaluation = operational_o2_evaluation_at_wavelength(
            &prepared.operational_o2_lut,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
        add_weighted_evaluation(
            &mut weighted,
            evaluation,
            prepared.oxygen_column_density_factor,
        );
        total_weight += prepared.oxygen_column_density_factor;
    }

    for line_absorber in &prepared.line_absorbers {
        if prepared.operational_o2_lut.enabled()
            && line_absorber.species == crate::input::atmospheric_types::AbsorberSpecies::O2
        {
            continue;
        }
        if line_absorber.line_list.lines.is_empty() {
            continue;
        }
        let weight = line_absorber.column_density_factor;
        if weight <= 0.0 {
            continue;
        }
        let evaluation =
            line_absorber
                .line_list
                .evaluate_at(wavelength_nm, temperature_k, pressure_hpa);
        add_weighted_evaluation(&mut weighted, evaluation, weight);
        total_weight += weight;
    }

    let standalone_line_list =
        if !prepared.operational_o2_lut.enabled() && prepared.line_absorbers.is_empty() {
            prepared
                .spectroscopy_lines
                .as_ref()
                .filter(|line_list| !line_list.lines.is_empty())
        } else {
            None
        };
    if let Some(line_list) = standalone_line_list {
        let evaluation = line_list.evaluate_at(wavelength_nm, temperature_k, pressure_hpa);
        let weight = if prepared.column_density_factor > 0.0 {
            prepared.column_density_factor
        } else {
            1.0
        };
        add_weighted_evaluation(&mut weighted, evaluation, weight);
        total_weight += weight;
    }

    if total_weight <= 0.0 {
        if prepared.operational_o2_lut.enabled() {
            return Ok(operational_o2_evaluation_at_wavelength(
                &prepared.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            ));
        }
        return Ok(zero_spectroscopy_evaluation());
    }

    divide_evaluation(&mut weighted, total_weight);
    Ok(weighted)
}

pub fn zero_spectroscopy_evaluation() -> SpectroscopyEvaluation {
    SpectroscopyEvaluation {
        weak_line_sigma_cm2_per_molecule: 0.0,
        strong_line_sigma_cm2_per_molecule: 0.0,
        line_sigma_cm2_per_molecule: 0.0,
        line_mixing_sigma_cm2_per_molecule: 0.0,
        total_sigma_cm2_per_molecule: 0.0,
        d_sigma_d_temperature_cm2_per_molecule_per_k: 0.0,
    }
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
