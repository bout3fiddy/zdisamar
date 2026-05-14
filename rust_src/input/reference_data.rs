use crate::input::{BindingKind, Scene};

const BUNDLED_O2A_SOLAR_WAVELENGTHS_NM: [f64; 7] =
    [755.0, 758.0, 760.01, 761.99, 764.99, 770.0, 776.0];
const BUNDLED_O2A_SOLAR_IRRADIANCE: [f64; 7] = [
    4.805854615e14,
    4.879049767e14,
    4.858697784e14,
    4.615924814e14,
    4.832478218e14,
    4.60914094e14,
    4.759839792e14,
];

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct ClimatologyPoint {
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub air_number_density_cm3: f64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct ClimatologyProfile {
    pub rows: Vec<ClimatologyPoint>,
}

impl ClimatologyProfile {
    pub fn mean_number_density(&self) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        self.rows
            .iter()
            .map(|row| row.air_number_density_cm3)
            .sum::<f64>()
            / self.rows.len() as f64
    }

    pub fn interpolate_density(&self, altitude_km: f64) -> f64 {
        self.interpolate_altitude_value(altitude_km, |row| row.air_number_density_cm3)
    }

    pub fn interpolate_temperature(&self, altitude_km: f64) -> f64 {
        self.interpolate_altitude_value(altitude_km, |row| row.temperature_k)
    }

    pub fn interpolate_pressure(&self, altitude_km: f64) -> f64 {
        self.interpolate_altitude_value(altitude_km, |row| row.pressure_hpa)
    }

    pub fn interpolate_pressure_log_linear(&self, altitude_km: f64) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        if altitude_km <= self.rows[0].altitude_km {
            return self.rows[0].pressure_hpa;
        }
        for window in self.rows.windows(2) {
            let left = window[0];
            let right = window[1];
            if altitude_km <= right.altitude_km {
                let span = right.altitude_km - left.altitude_km;
                if span == 0.0 {
                    return right.pressure_hpa;
                }
                let weight = (altitude_km - left.altitude_km) / span;
                let left_log = left.pressure_hpa.max(1.0e-9).ln();
                let right_log = right.pressure_hpa.max(1.0e-9).ln();
                return (left_log + weight * (right_log - left_log)).exp();
            }
        }
        self.rows[self.rows.len() - 1].pressure_hpa
    }

    pub fn interpolate_temperature_for_pressure_log_linear(&self, pressure_hpa: f64) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        let safe_pressure_hpa = pressure_hpa.max(1.0e-9);
        let first_pressure_hpa = self.rows[0].pressure_hpa;
        let last_pressure_hpa = self.rows[self.rows.len() - 1].pressure_hpa;
        let descending = first_pressure_hpa >= last_pressure_hpa;
        if (descending && safe_pressure_hpa >= first_pressure_hpa)
            || (!descending && safe_pressure_hpa <= first_pressure_hpa)
        {
            return self.rows[0].temperature_k;
        }
        if (descending && safe_pressure_hpa <= last_pressure_hpa)
            || (!descending && safe_pressure_hpa >= last_pressure_hpa)
        {
            return self.rows[self.rows.len() - 1].temperature_k;
        }

        let log_pressure = safe_pressure_hpa.ln();
        for window in self.rows.windows(2) {
            let left = window[0];
            let right = window[1];
            let in_segment = if descending {
                safe_pressure_hpa <= left.pressure_hpa && safe_pressure_hpa >= right.pressure_hpa
            } else {
                safe_pressure_hpa >= left.pressure_hpa && safe_pressure_hpa <= right.pressure_hpa
            };
            if !in_segment {
                continue;
            }
            let left_log = left.pressure_hpa.max(1.0e-9).ln();
            let right_log = right.pressure_hpa.max(1.0e-9).ln();
            let span = right_log - left_log;
            if span == 0.0 {
                return right.temperature_k;
            }
            let weight = (log_pressure - left_log) / span;
            return left.temperature_k + weight * (right.temperature_k - left.temperature_k);
        }
        self.rows[self.rows.len() - 1].temperature_k
    }

    pub fn max_altitude(&self) -> f64 {
        self.rows.last().map(|row| row.altitude_km).unwrap_or(0.0)
    }

    pub fn interpolate_altitude_for_pressure(&self, pressure_hpa: f64) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        let safe_pressure_hpa = pressure_hpa.max(1.0e-9);
        let first_pressure_hpa = self.rows[0].pressure_hpa;
        let last_pressure_hpa = self.rows[self.rows.len() - 1].pressure_hpa;
        let descending = first_pressure_hpa >= last_pressure_hpa;
        if (descending && safe_pressure_hpa >= first_pressure_hpa)
            || (!descending && safe_pressure_hpa <= first_pressure_hpa)
        {
            return self.rows[0].altitude_km;
        }
        if (descending && safe_pressure_hpa <= last_pressure_hpa)
            || (!descending && safe_pressure_hpa >= last_pressure_hpa)
        {
            return self.rows[self.rows.len() - 1].altitude_km;
        }

        let log_pressure = safe_pressure_hpa.ln();
        for window in self.rows.windows(2) {
            let left = window[0];
            let right = window[1];
            let in_segment = if descending {
                safe_pressure_hpa <= left.pressure_hpa && safe_pressure_hpa >= right.pressure_hpa
            } else {
                safe_pressure_hpa >= left.pressure_hpa && safe_pressure_hpa <= right.pressure_hpa
            };
            if !in_segment {
                continue;
            }
            let left_log = left.pressure_hpa.max(1.0e-9).ln();
            let right_log = right.pressure_hpa.max(1.0e-9).ln();
            let span = right_log - left_log;
            if span == 0.0 {
                return right.altitude_km;
            }
            let weight = (log_pressure - left_log) / span;
            return left.altitude_km + weight * (right.altitude_km - left.altitude_km);
        }
        self.rows[self.rows.len() - 1].altitude_km
    }

    fn interpolate_altitude_value(
        &self,
        altitude_km: f64,
        value: impl Fn(ClimatologyPoint) -> f64,
    ) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        if altitude_km <= self.rows[0].altitude_km {
            return value(self.rows[0]);
        }
        for window in self.rows.windows(2) {
            let left = window[0];
            let right = window[1];
            if altitude_km <= right.altitude_km {
                let span = right.altitude_km - left.altitude_km;
                if span == 0.0 {
                    return value(right);
                }
                let weight = (altitude_km - left.altitude_km) / span;
                return value(left) + weight * (value(right) - value(left));
            }
        }
        value(self.rows[self.rows.len() - 1])
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CrossSectionPoint {
    pub wavelength_nm: f64,
    pub sigma_cm2_per_molecule: f64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CrossSectionTable {
    pub points: Vec<CrossSectionPoint>,
}

impl CrossSectionTable {
    pub fn mean_sigma_in_range(&self, start_nm: f64, end_nm: f64) -> f64 {
        let mut total = 0.0;
        let mut count = 0;
        for point in &self.points {
            if point.wavelength_nm < start_nm || point.wavelength_nm > end_nm {
                continue;
            }
            total += point.sigma_cm2_per_molecule;
            count += 1;
        }
        if count > 0 {
            return total / count as f64;
        }
        self.interpolate_sigma((start_nm + end_nm) * 0.5)
    }

    pub fn interpolate_sigma(&self, wavelength_nm: f64) -> f64 {
        if self.points.is_empty() {
            return 0.0;
        }
        if wavelength_nm <= self.points[0].wavelength_nm {
            return self.points[0].sigma_cm2_per_molecule;
        }
        if wavelength_nm >= self.points[self.points.len() - 1].wavelength_nm {
            return self.points[self.points.len() - 1].sigma_cm2_per_molecule;
        }
        let Some((left_index, right_index)) = self.bracket_for_wavelength(wavelength_nm) else {
            return self.points[self.points.len() - 1].sigma_cm2_per_molecule;
        };
        let left = self.points[left_index];
        let right = self.points[right_index];
        let span = right.wavelength_nm - left.wavelength_nm;
        if span == 0.0 {
            return right.sigma_cm2_per_molecule;
        }
        let weight = (wavelength_nm - left.wavelength_nm) / span;
        left.sigma_cm2_per_molecule
            + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule)
    }

    pub fn sigma_at_high_resolution(&self, wavelength_nm: f64) -> f64 {
        self.interpolate_sigma(wavelength_nm)
    }

    pub fn bracket_for_wavelength(&self, wavelength_nm: f64) -> Option<(usize, usize)> {
        if self.points.len() < 2 {
            return None;
        }
        let mut low = 0;
        let mut high = self.points.len() - 1;
        while low + 1 < high {
            let middle = low + (high - low) / 2;
            if self.points[middle].wavelength_nm <= wavelength_nm {
                low = middle;
            } else {
                high = middle;
            }
        }
        Some((low, high))
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct CollisionInducedAbsorptionPoint {
    pub wavelength_nm: f64,
    pub a0: f64,
    pub a1: f64,
    pub a2: f64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct CollisionInducedAbsorptionTable {
    pub scale_factor_cm5_per_molecule2: f64,
    pub points: Vec<CollisionInducedAbsorptionPoint>,
}

impl CollisionInducedAbsorptionTable {
    pub fn sigma_at(&self, wavelength_nm: f64, temperature_k: f64) -> f64 {
        let coefficients = self.interpolate_coefficients(wavelength_nm);
        let temperature_c = temperature_k - 273.15;
        let raw_sigma = coefficients.a0
            + coefficients.a1 * temperature_c
            + coefficients.a2 * temperature_c * temperature_c;
        self.scale_factor_cm5_per_molecule2 * raw_sigma.max(0.0)
    }

    pub fn d_sigma_d_temperature_at(&self, wavelength_nm: f64, temperature_k: f64) -> f64 {
        let coefficients = self.interpolate_coefficients(wavelength_nm);
        let temperature_c = temperature_k - 273.15;
        let raw_sigma = coefficients.a0
            + coefficients.a1 * temperature_c
            + coefficients.a2 * temperature_c * temperature_c;
        if raw_sigma <= 0.0 {
            return 0.0;
        }
        self.scale_factor_cm5_per_molecule2
            * (coefficients.a1 + 2.0 * coefficients.a2 * temperature_c)
    }

    pub fn mean_sigma_in_range(&self, start_nm: f64, end_nm: f64, temperature_k: f64) -> f64 {
        let mut total = 0.0;
        let mut count = 0;
        for point in &self.points {
            if point.wavelength_nm < start_nm || point.wavelength_nm > end_nm {
                continue;
            }
            total += self.sigma_at(point.wavelength_nm, temperature_k);
            count += 1;
        }
        if count > 0 {
            return total / count as f64;
        }
        self.sigma_at((start_nm + end_nm) * 0.5, temperature_k)
    }

    pub fn interpolate_coefficients(&self, wavelength_nm: f64) -> CollisionInducedAbsorptionPoint {
        if self.points.is_empty() {
            return CollisionInducedAbsorptionPoint {
                wavelength_nm,
                a0: 0.0,
                a1: 0.0,
                a2: 0.0,
            };
        }
        if wavelength_nm <= self.points[0].wavelength_nm {
            return self.points[0];
        }
        if wavelength_nm >= self.points[self.points.len() - 1].wavelength_nm {
            return self.points[self.points.len() - 1];
        }
        let right_index = self
            .points
            .partition_point(|point| point.wavelength_nm < wavelength_nm);
        interpolate_cia_coefficients_linear(
            self.points[right_index - 1],
            self.points[right_index],
            wavelength_nm,
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct AirmassFactorPoint {
    pub solar_zenith_deg: f64,
    pub view_zenith_deg: f64,
    pub relative_azimuth_deg: f64,
    pub airmass_factor: f64,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct MiePhasePoint {
    pub wavelength_nm: f64,
    pub extinction_scale: f64,
    pub single_scatter_albedo: f64,
    pub phase_coefficients: [f64; 4],
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct MiePhaseTable {
    pub points: Vec<MiePhasePoint>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct AirmassFactorLut {
    pub points: Vec<AirmassFactorPoint>,
}

impl AirmassFactorLut {
    pub fn nearest(
        &self,
        solar_zenith_deg: f64,
        view_zenith_deg: f64,
        relative_azimuth_deg: f64,
    ) -> f64 {
        if self.points.is_empty() {
            return 1.0;
        }
        let mut best_distance = f64::INFINITY;
        let mut best_value = self.points[0].airmass_factor;
        for point in &self.points {
            let delta_sza = point.solar_zenith_deg - solar_zenith_deg;
            let delta_vza = point.view_zenith_deg - view_zenith_deg;
            let delta_raa = point.relative_azimuth_deg - relative_azimuth_deg;
            let distance = delta_sza * delta_sza + delta_vza * delta_vza + delta_raa * delta_raa;
            if distance < best_distance {
                best_distance = distance;
                best_value = point.airmass_factor;
            }
        }
        best_value
    }

    pub fn provides_support_only(&self) -> bool {
        true
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct SpectroscopyLine {
    pub gas_index: u16,
    pub isotope_number: u8,
    pub abundance_fraction: f64,
    pub vendor_filter_metadata_from_source: bool,
    pub center_wavelength_nm: f64,
    pub center_wavenumber_cm1: f64,
    pub line_strength_cm2_per_molecule: f64,
    pub air_half_width_nm: f64,
    pub air_half_width_cm1: f64,
    pub temperature_exponent: f64,
    pub lower_state_energy_cm1: f64,
    pub pressure_shift_nm: f64,
    pub pressure_shift_cm1: f64,
    pub line_mixing_coefficient: f64,
    pub branch_ic1: Option<u8>,
    pub branch_ic2: Option<u8>,
    pub rotational_nf: Option<u8>,
}

impl Default for SpectroscopyLine {
    fn default() -> Self {
        Self {
            gas_index: 0,
            isotope_number: 1,
            abundance_fraction: 1.0,
            vendor_filter_metadata_from_source: false,
            center_wavelength_nm: 0.0,
            center_wavenumber_cm1: f64::NAN,
            line_strength_cm2_per_molecule: 0.0,
            air_half_width_nm: 0.0,
            air_half_width_cm1: f64::NAN,
            temperature_exponent: 0.0,
            lower_state_energy_cm1: 0.0,
            pressure_shift_nm: 0.0,
            pressure_shift_cm1: f64::NAN,
            line_mixing_coefficient: 0.0,
            branch_ic1: None,
            branch_ic2: None,
            rotational_nf: None,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectroscopyStrongLine {
    pub center_wavenumber_cm1: f64,
    pub center_wavelength_nm: f64,
    pub population_t0: f64,
    pub dipole_ratio: f64,
    pub dipole_t0: f64,
    pub lower_state_energy_cm1: f64,
    pub air_half_width_cm1: f64,
    pub air_half_width_nm: f64,
    pub temperature_exponent: f64,
    pub pressure_shift_cm1: f64,
    pub pressure_shift_nm: f64,
    pub rotational_index_m1: i32,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectroscopyStrongLineSet {
    pub lines: Vec<SpectroscopyStrongLine>,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct RelaxationMatrix {
    pub line_count: usize,
    pub wt0: Vec<f64>,
    pub bw: Vec<f64>,
}

impl RelaxationMatrix {
    pub fn weight_at(&self, row: usize, col: usize) -> f64 {
        self.wt0[row * self.line_count + col]
    }

    pub fn temperature_exponent_at(&self, row: usize, col: usize) -> f64 {
        self.bw[row * self.line_count + col]
    }
}

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct SpectroscopyEvaluation {
    pub weak_line_sigma_cm2_per_molecule: f64,
    pub strong_line_sigma_cm2_per_molecule: f64,
    pub line_sigma_cm2_per_molecule: f64,
    pub line_mixing_sigma_cm2_per_molecule: f64,
    pub total_sigma_cm2_per_molecule: f64,
    pub d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectroscopyRuntimeControls {
    pub gas_index: Option<u16>,
    pub active_isotopes: Vec<u8>,
    pub threshold_line_scale: Option<f64>,
    pub cutoff_cm1: Option<f64>,
    pub cutoff_grid_wavelengths_nm: Vec<f64>,
    pub cutoff_grid_wavenumbers_cm1: Vec<f64>,
    pub line_mixing_factor: f64,
}

impl SpectroscopyRuntimeControls {
    pub fn threshold_strength(&self, lines: &[SpectroscopyLine]) -> Option<f64> {
        let scale = self.threshold_line_scale?;
        if lines.is_empty() {
            return None;
        }
        let max_strength = lines
            .iter()
            .map(|line| line.line_strength_cm2_per_molecule)
            .fold(0.0, f64::max);
        Some(max_strength * scale)
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct SpectroscopyLineList {
    pub lines: Vec<SpectroscopyLine>,
    pub strong_lines: Option<Vec<SpectroscopyStrongLine>>,
    pub relaxation_matrix: Option<RelaxationMatrix>,
    pub strong_line_tolerance_nm: f64,
    pub lines_sorted_ascending: bool,
    pub preserve_anchor_weak_lines: bool,
    pub vendor_strong_line_partition: bool,
    pub strong_line_match_by_line: Option<Vec<Option<u16>>>,
    pub runtime_controls: SpectroscopyRuntimeControls,
}

impl SpectroscopyLineList {
    pub fn has_strong_line_sidecars(&self) -> bool {
        self.strong_lines.is_some() && self.relaxation_matrix.is_some()
    }
}

pub fn weighted_mean_samples(samples: &[f64], weights: &[f64]) -> f64 {
    if samples.is_empty() || samples.len() != weights.len() {
        return 0.0;
    }
    let mut numerator = 0.0;
    let mut denominator = 0.0;
    for (&sample, &weight) in samples.iter().zip(weights) {
        numerator += sample * weight;
        denominator += weight;
    }
    numerator / denominator.max(1.0e-12)
}

pub fn solar_irradiance_at_wavelength(scene: &Scene, wavelength_nm: f64) -> f64 {
    let operational_band_support = scene.observation_model.primary_operational_band_support();
    let source_irradiance = if operational_band_support
        .operational_solar_spectrum
        .enabled()
    {
        operational_band_support
            .operational_solar_spectrum
            .interpolate_irradiance(wavelength_nm)
    } else if scene.observation_model.solar_spectrum_source.kind() == BindingKind::BundleDefault {
        bundled_solar_irradiance(wavelength_nm)
            .unwrap_or_else(|| default_solar_continuum_irradiance(wavelength_nm))
    } else {
        default_solar_continuum_irradiance(wavelength_nm)
    };
    source_irradiance.max(1.0e-6)
}

fn bundled_solar_irradiance(wavelength_nm: f64) -> Option<f64> {
    if wavelength_nm < BUNDLED_O2A_SOLAR_WAVELENGTHS_NM[0]
        || wavelength_nm
            > BUNDLED_O2A_SOLAR_WAVELENGTHS_NM[BUNDLED_O2A_SOLAR_WAVELENGTHS_NM.len() - 1]
    {
        return None;
    }
    if wavelength_nm <= BUNDLED_O2A_SOLAR_WAVELENGTHS_NM[0] {
        return Some(BUNDLED_O2A_SOLAR_IRRADIANCE[0]);
    }
    for index in 0..BUNDLED_O2A_SOLAR_WAVELENGTHS_NM.len() - 1 {
        let left_nm = BUNDLED_O2A_SOLAR_WAVELENGTHS_NM[index];
        let right_nm = BUNDLED_O2A_SOLAR_WAVELENGTHS_NM[index + 1];
        let left_irradiance = BUNDLED_O2A_SOLAR_IRRADIANCE[index];
        let right_irradiance = BUNDLED_O2A_SOLAR_IRRADIANCE[index + 1];
        if wavelength_nm <= right_nm {
            let span = right_nm - left_nm;
            if span == 0.0 {
                return Some(right_irradiance);
            }
            let blend = (wavelength_nm - left_nm) / span;
            return Some(left_irradiance + blend * (right_irradiance - left_irradiance));
        }
    }
    Some(BUNDLED_O2A_SOLAR_IRRADIANCE[BUNDLED_O2A_SOLAR_IRRADIANCE.len() - 1])
}

fn default_solar_continuum_irradiance(wavelength_nm: f64) -> f64 {
    let reference_wavelength_nm = 760.0;
    let reference_irradiance = 4.87401e14;
    reference_irradiance * planck_continuum_shape(wavelength_nm, 5778.0)
        / planck_continuum_shape(reference_wavelength_nm, 5778.0)
}

fn planck_continuum_shape(wavelength_nm: f64, temperature_k: f64) -> f64 {
    let h = 6.62607015e-34;
    let c = 2.99792458e8;
    let k = 1.380649e-23;
    let wavelength_m = wavelength_nm.max(1.0) * 1.0e-9;
    let exponent = h * c / (wavelength_m * k * temperature_k.max(1.0));
    let denominator = exponent.exp_m1().max(1.0e-12);
    (2.0 * h * c * c) / wavelength_m.powf(5.0) / denominator
}

fn interpolate_cia_coefficients_linear(
    left: CollisionInducedAbsorptionPoint,
    right: CollisionInducedAbsorptionPoint,
    wavelength_nm: f64,
) -> CollisionInducedAbsorptionPoint {
    let span = right.wavelength_nm - left.wavelength_nm;
    if span == 0.0 {
        return right;
    }
    let weight = (wavelength_nm - left.wavelength_nm) / span;
    CollisionInducedAbsorptionPoint {
        wavelength_nm,
        a0: left.a0 + weight * (right.a0 - left.a0),
        a1: left.a1 + weight * (right.a1 - left.a1),
        a2: left.a2 + weight * (right.a2 - left.a2),
    }
}
