use crate::{
    common::{
        errors,
        math::{interpolation::spline, quadrature::gauss_legendre},
    },
    input::reference::spectroscopy::line_list_ops,
};

const MAX_SPLINE_PROFILE_ROWS: usize = spline::MAX_SPLINE_POINT_COUNT;

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct ClimatologyPoint {
    pub altitude_km: f64,
    pub pressure_hpa: f64,
    pub temperature_k: f64,
    pub air_number_density_cm3: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct ClimatologyProfile {
    pub rows: Vec<ClimatologyPoint>,
}

impl ClimatologyProfile {
    pub fn densify_vendor_pressure_grid(
        &self,
        surface_pressure_hpa: f64,
    ) -> Result<Self, errors::Error> {
        if self.rows.len() < 2 {
            return Ok(self.clone());
        }

        let scale_height_guess_km = 8.0;
        let mut dense_row_count = 1;
        for pair in self.rows.windows(2) {
            let lower = pair[0];
            let upper = pair[1];
            let safe_lower_pressure = lower.pressure_hpa.max(1.0e-9);
            let safe_upper_pressure = upper.pressure_hpa.max(1.0e-9);
            let delta_z_guess =
                scale_height_guess_km * (safe_lower_pressure / safe_upper_pressure).ln();
            let additional_levels = delta_z_guess.max(0.0).floor() as usize;
            dense_row_count += additional_levels + 1;
        }

        let mut dense_pressures_hpa = vec![0.0; dense_row_count];
        let mut dense_temperatures_k = vec![0.0; dense_row_count];
        let mut dense_altitudes_km = vec![0.0; dense_row_count];
        let mut dense_altitudes_gp_km = vec![0.0; (dense_row_count - 1) * 2];

        // DISAMAR's layer setup is pressure-driven. Densifying in log-pressure keeps
        // the vertical grid stable where the atmosphere thins quickly.
        let mut dense_index = 0;
        dense_pressures_hpa[dense_index] = self.rows[0].pressure_hpa;
        for pair in self.rows.windows(2) {
            let lower = pair[0];
            let upper = pair[1];
            let safe_lower_pressure = lower.pressure_hpa.max(1.0e-9);
            let safe_upper_pressure = upper.pressure_hpa.max(1.0e-9);
            let delta_z_guess =
                scale_height_guess_km * (safe_lower_pressure / safe_upper_pressure).ln();
            let additional_levels = delta_z_guess.max(0.0).floor() as usize;
            if additional_levels > 0 {
                let delta_nodes_lnp = (safe_lower_pressure / safe_upper_pressure).ln();
                let delta_lnp = delta_nodes_lnp / (additional_levels + 1) as f64;
                for _ in 0..additional_levels {
                    dense_index += 1;
                    dense_pressures_hpa[dense_index] =
                        dense_pressures_hpa[dense_index - 1] * (-delta_lnp).exp();
                }
            }
            dense_index += 1;
            dense_pressures_hpa[dense_index] = upper.pressure_hpa;
        }
        debug_assert_eq!(dense_index + 1, dense_row_count);

        for (index, pressure_hpa) in dense_pressures_hpa.iter().copied().enumerate() {
            dense_temperatures_k[index] =
                self.interpolate_temperature_for_pressure_spline(pressure_hpa);
        }

        let mut gauss_nodes_01 = [0.0; 2];
        let mut gauss_weights_01 = [0.0; 2];
        gauss_legendre::fill_disamar_div_points_01(2, &mut gauss_nodes_01, &mut gauss_weights_01)
            .map_err(|_| errors::Error::InvalidRequest)?;

        let universal_gas_constant = 8.3144621;
        let mean_molecular_weight_air = 28.964e-3;
        let safe_surface_pressure_hpa = surface_pressure_hpa.max(1.0e-9);
        let mut dense_log_pressures = vec![0.0; dense_row_count];
        for (index, pressure_hpa) in dense_pressures_hpa.iter().copied().enumerate() {
            dense_log_pressures[index] = pressure_hpa.max(1.0e-9).ln();
            dense_altitudes_km[index] = scale_height_guess_km
                * (safe_surface_pressure_hpa.ln() - dense_log_pressures[index]);
        }

        for interval_index in 0..dense_row_count - 1 {
            let dlnp =
                dense_log_pressures[interval_index] - dense_log_pressures[interval_index + 1];
            for (gauss_index, &gauss_node) in gauss_nodes_01.iter().enumerate() {
                let gp_index = interval_index * 2 + gauss_index;
                dense_altitudes_gp_km[gp_index] = scale_height_guess_km
                    * (safe_surface_pressure_hpa.ln()
                        - (dense_log_pressures[interval_index + 1] + dlnp * gauss_node));
            }
        }

        let mut previous_altitudes_km = dense_altitudes_km.clone();
        for _ in 0..6 {
            dense_altitudes_km[0] = 0.0;
            for pressure_index in 1..dense_row_count {
                let gp_start = (pressure_index - 1) * 2;
                let dlnp =
                    dense_log_pressures[pressure_index - 1] - dense_log_pressures[pressure_index];
                let mut interval_altitude_increment_km = 0.0;
                for (gauss_index, (&gauss_node, &gauss_weight)) in
                    gauss_nodes_01.iter().zip(&gauss_weights_01).enumerate()
                {
                    let gp_index = gp_start + gauss_index;
                    let pressure_gp_hpa =
                        (dense_log_pressures[pressure_index] + dlnp * gauss_node).exp();
                    let temperature_gp_k =
                        self.interpolate_temperature_for_pressure_spline(pressure_gp_hpa);
                    let gravity = gravitational_acceleration_meters_per_second_squared(
                        45.0,
                        dense_altitudes_gp_km[gp_index],
                    );
                    let scale_height_km = 1.0e-3 * universal_gas_constant * temperature_gp_k
                        / mean_molecular_weight_air
                        / gravity;
                    interval_altitude_increment_km += gauss_weight * dlnp * scale_height_km;
                }
                dense_altitudes_km[pressure_index] =
                    dense_altitudes_km[pressure_index - 1] + interval_altitude_increment_km;
            }

            // The altitude grid depends on gravity at the grid-point altitude, so
            // Zig iterates a few times instead of assuming one fixed scale height.
            let chi2 = dense_altitudes_km
                .iter()
                .zip(&previous_altitudes_km)
                .map(|(&altitude_km, &previous_altitude_km)| {
                    let delta = altitude_km - previous_altitude_km;
                    delta * delta
                })
                .sum::<f64>();
            if chi2 < 1.0e-6 {
                break;
            }
            previous_altitudes_km.copy_from_slice(&dense_altitudes_km);
        }

        // The vendor profile can start below the requested surface pressure. Shift
        // the generated altitude axis so the active surface is exactly zero.
        let surface_altitude_shift_km = linear_sample_descending(
            &dense_pressures_hpa,
            &dense_altitudes_km,
            safe_surface_pressure_hpa,
        );

        let rows = dense_pressures_hpa
            .iter()
            .zip(&dense_temperatures_k)
            .zip(&dense_altitudes_km)
            .map(
                |((&pressure_hpa, &temperature_k), &altitude_km)| ClimatologyPoint {
                    altitude_km: altitude_km - surface_altitude_shift_km,
                    pressure_hpa,
                    temperature_k,
                    air_number_density_cm3: pressure_hpa / temperature_k.max(1.0e-9) / 1.380658e-19,
                },
            )
            .collect();

        Ok(Self { rows })
    }

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
        interpolate_by_altitude(&self.rows, altitude_km, |row| row.air_number_density_cm3)
    }

    pub fn interpolate_temperature(&self, altitude_km: f64) -> f64 {
        interpolate_by_altitude(&self.rows, altitude_km, |row| row.temperature_k)
    }

    pub fn interpolate_temperature_spline(&self, altitude_km: f64) -> f64 {
        if self.rows.len() < 3 || self.rows.len() > MAX_SPLINE_PROFILE_ROWS {
            return self.interpolate_temperature(altitude_km);
        }
        if altitude_km <= self.rows[0].altitude_km {
            return self.rows[0].temperature_k;
        }
        if altitude_km >= self.rows[self.rows.len() - 1].altitude_km {
            return self.rows[self.rows.len() - 1].temperature_k;
        }

        let altitudes_km = self
            .rows
            .iter()
            .map(|row| row.altitude_km)
            .collect::<Vec<_>>();
        let temperatures_k = self
            .rows
            .iter()
            .map(|row| row.temperature_k)
            .collect::<Vec<_>>();
        spline::sample_endpoint_secant(&altitudes_km, &temperatures_k, altitude_km)
            .unwrap_or_else(|_| self.interpolate_temperature(altitude_km))
    }

    pub fn interpolate_temperature_for_pressure_log_linear(&self, pressure_hpa: f64) -> f64 {
        interpolate_by_log_pressure(&self.rows, pressure_hpa, |row| row.temperature_k)
    }

    pub fn interpolate_temperature_for_pressure_spline(&self, pressure_hpa: f64) -> f64 {
        sample_by_log_pressure_spline(&self.rows, pressure_hpa, |row| row.temperature_k)
            .unwrap_or_else(|| self.interpolate_temperature_for_pressure_log_linear(pressure_hpa))
    }

    pub fn interpolate_pressure(&self, altitude_km: f64) -> f64 {
        interpolate_by_altitude(&self.rows, altitude_km, |row| row.pressure_hpa)
    }

    pub fn interpolate_pressure_log_linear(&self, altitude_km: f64) -> f64 {
        if self.rows.is_empty() {
            return 0.0;
        }
        if altitude_km <= self.rows[0].altitude_km {
            return self.rows[0].pressure_hpa;
        }
        for pair in self.rows.windows(2) {
            let left = pair[0];
            let right = pair[1];
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

    pub fn interpolate_pressure_log_spline(&self, altitude_km: f64) -> f64 {
        if self.rows.len() < 3 || self.rows.len() > MAX_SPLINE_PROFILE_ROWS {
            return self.interpolate_pressure_log_linear(altitude_km);
        }
        if altitude_km <= self.rows[0].altitude_km {
            return self.rows[0].pressure_hpa;
        }
        if altitude_km >= self.rows[self.rows.len() - 1].altitude_km {
            return self.rows[self.rows.len() - 1].pressure_hpa;
        }

        let altitudes_km = self
            .rows
            .iter()
            .map(|row| row.altitude_km)
            .collect::<Vec<_>>();
        let log_pressures = self
            .rows
            .iter()
            .map(|row| row.pressure_hpa.max(1.0e-9).ln())
            .collect::<Vec<_>>();
        spline::sample_endpoint_secant(&altitudes_km, &log_pressures, altitude_km)
            .map(f64::exp)
            .unwrap_or_else(|_| self.interpolate_pressure_log_linear(altitude_km))
    }

    pub fn max_altitude(&self) -> f64 {
        self.rows.last().map_or(0.0, |row| row.altitude_km)
    }

    pub fn interpolate_altitude_for_pressure(&self, pressure_hpa: f64) -> f64 {
        interpolate_by_log_pressure(&self.rows, pressure_hpa, |row| row.altitude_km)
    }

    pub fn interpolate_altitude_for_pressure_spline(&self, pressure_hpa: f64) -> f64 {
        sample_by_log_pressure_spline(&self.rows, pressure_hpa, |row| row.altitude_km)
            .unwrap_or_else(|| self.interpolate_altitude_for_pressure(pressure_hpa))
    }
}

fn interpolate_by_altitude(
    rows: &[ClimatologyPoint],
    altitude_km: f64,
    value: impl Fn(ClimatologyPoint) -> f64,
) -> f64 {
    if rows.is_empty() {
        return 0.0;
    }
    if altitude_km <= rows[0].altitude_km {
        return value(rows[0]);
    }
    for pair in rows.windows(2) {
        let left = pair[0];
        let right = pair[1];
        if altitude_km <= right.altitude_km {
            let span = right.altitude_km - left.altitude_km;
            if span == 0.0 {
                return value(right);
            }
            let weight = (altitude_km - left.altitude_km) / span;
            return value(left) + weight * (value(right) - value(left));
        }
    }
    value(rows[rows.len() - 1])
}

fn interpolate_by_log_pressure(
    rows: &[ClimatologyPoint],
    pressure_hpa: f64,
    value: impl Fn(ClimatologyPoint) -> f64,
) -> f64 {
    if rows.is_empty() {
        return 0.0;
    }

    let safe_pressure_hpa = pressure_hpa.max(1.0e-9);
    let first_pressure_hpa = rows[0].pressure_hpa;
    let last_pressure_hpa = rows[rows.len() - 1].pressure_hpa;
    let descending = first_pressure_hpa >= last_pressure_hpa;

    if (descending && safe_pressure_hpa >= first_pressure_hpa)
        || (!descending && safe_pressure_hpa <= first_pressure_hpa)
    {
        return value(rows[0]);
    }
    if (descending && safe_pressure_hpa <= last_pressure_hpa)
        || (!descending && safe_pressure_hpa >= last_pressure_hpa)
    {
        return value(rows[rows.len() - 1]);
    }

    let log_pressure = safe_pressure_hpa.ln();
    for pair in rows.windows(2) {
        let left = pair[0];
        let right = pair[1];
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
            return value(right);
        }
        let weight = (log_pressure - left_log) / span;
        return value(left) + weight * (value(right) - value(left));
    }
    value(rows[rows.len() - 1])
}

fn sample_by_log_pressure_spline(
    rows: &[ClimatologyPoint],
    pressure_hpa: f64,
    value: impl Fn(ClimatologyPoint) -> f64,
) -> Option<f64> {
    if rows.len() < 3 || rows.len() > MAX_SPLINE_PROFILE_ROWS {
        return None;
    }

    let safe_pressure_hpa = pressure_hpa.max(1.0e-9);
    let first_pressure_hpa = rows[0].pressure_hpa;
    let last_pressure_hpa = rows[rows.len() - 1].pressure_hpa;
    let descending = first_pressure_hpa >= last_pressure_hpa;

    if (descending && safe_pressure_hpa >= first_pressure_hpa)
        || (!descending && safe_pressure_hpa <= first_pressure_hpa)
    {
        return Some(value(rows[0]));
    }
    if (descending && safe_pressure_hpa <= last_pressure_hpa)
        || (!descending && safe_pressure_hpa >= last_pressure_hpa)
    {
        return Some(value(rows[rows.len() - 1]));
    }

    let ordered = if descending {
        rows.iter().rev().copied().collect::<Vec<_>>()
    } else {
        rows.to_vec()
    };
    let log_pressures = ordered
        .iter()
        .map(|row| row.pressure_hpa.max(1.0e-9).ln())
        .collect::<Vec<_>>();
    let values = ordered.iter().map(|&row| value(row)).collect::<Vec<_>>();
    spline::sample_endpoint_secant(&log_pressures, &values, safe_pressure_hpa.ln()).ok()
}

fn linear_sample_descending(x_desc: &[f64], y: &[f64], target_x: f64) -> f64 {
    debug_assert_eq!(x_desc.len(), y.len());
    debug_assert!(!x_desc.is_empty());
    if target_x >= x_desc[0] {
        return y[0];
    }
    if target_x <= x_desc[x_desc.len() - 1] {
        return y[y.len() - 1];
    }

    for index in 0..x_desc.len() - 1 {
        let left_x = x_desc[index];
        let right_x = x_desc[index + 1];
        if target_x > left_x || target_x < right_x {
            continue;
        }
        let span = right_x - left_x;
        if span == 0.0 {
            return y[index + 1];
        }
        let weight = (target_x - left_x) / span;
        return y[index] + weight * (y[index + 1] - y[index]);
    }
    y[y.len() - 1]
}

fn gravitational_acceleration_meters_per_second_squared(
    latitude_deg: f64,
    altitude_km: f64,
) -> f64 {
    let geodetic_flattening_term = 0.993_306_f32 as f64;
    let geodetic_latitude_rad = (latitude_deg.to_radians().tan()
        / (geodetic_flattening_term + 1.049583e-6 * altitude_km))
        .atan();
    let sin_latitude = geodetic_latitude_rad.sin();
    let gravity_at_mean_sea_level = 9.78031 + 0.05186 * sin_latitude * sin_latitude;
    gravity_at_mean_sea_level - 3.086e-3 * altitude_km
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct SpectroscopyLine {
    pub gas_index: u16,
    pub isotope_number: u8,
    pub abundance_fraction: f64,
    pub vendor_filter_metadata_from_source: bool,
    pub center_wavelength_nm: f64,
    pub center_wavenumber_cm1: Option<f64>,
    pub line_strength_cm2_per_molecule: f64,
    pub air_half_width_nm: f64,
    pub air_half_width_cm1: Option<f64>,
    pub temperature_exponent: f64,
    pub lower_state_energy_cm1: f64,
    pub pressure_shift_nm: f64,
    pub pressure_shift_cm1: Option<f64>,
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
            center_wavenumber_cm1: None,
            line_strength_cm2_per_molecule: 0.0,
            air_half_width_nm: 0.0,
            air_half_width_cm1: None,
            temperature_exponent: 0.0,
            lower_state_energy_cm1: 0.0,
            pressure_shift_nm: 0.0,
            pressure_shift_cm1: None,
            line_mixing_coefficient: 0.0,
            branch_ic1: None,
            branch_ic2: None,
            rotational_nf: None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
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

    pub fn apply_runtime_controls(
        &mut self,
        gas_index: Option<u16>,
        active_isotopes: &[u8],
        threshold_line_scale: Option<f64>,
        cutoff_cm1: Option<f64>,
        line_mixing_factor: f64,
    ) -> Result<(), errors::Error> {
        line_list_ops::apply_runtime_controls(
            self,
            gas_index,
            active_isotopes,
            threshold_line_scale,
            cutoff_cm1,
            line_mixing_factor,
        )
    }

    pub fn build_strong_line_match_index(&mut self) -> Result<(), errors::Error> {
        line_list_ops::build_strong_line_match_index(self)
    }

    pub fn prepare_strong_line_state(
        &self,
        temperature_k: f64,
        pressure_hpa: f64,
    ) -> Option<StrongLinePreparedState> {
        line_list_ops::prepare_strong_line_state(self, temperature_k, pressure_hpa)
    }

    pub fn prepare_weak_line_state(
        &self,
        temperature_k: f64,
        pressure_hpa: f64,
    ) -> WeakLinePreparedState {
        line_list_ops::prepare_weak_line_state(self, temperature_k, pressure_hpa)
    }

    pub fn sigma_at(&self, wavelength_nm: f64, temperature_k: f64, pressure_hpa: f64) -> f64 {
        self.evaluate_at(wavelength_nm, temperature_k, pressure_hpa)
            .total_sigma_cm2_per_molecule
    }

    pub fn sigma_at_with_prepared_profile_state(
        &self,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_strong_state: Option<&StrongLinePreparedState>,
        prepared_weak_state: Option<&WeakLinePreparedState>,
    ) -> f64 {
        crate::input::reference::spectroscopy::line_list_eval::total_sigma_with_prepared_profile_state(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            prepared_strong_state,
            prepared_weak_state,
        )
        .total_sigma_cm2_per_molecule
    }

    pub fn evaluate_at(
        &self,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) -> SpectroscopyEvaluation {
        crate::input::reference::spectroscopy::line_list_eval::evaluate_at(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        )
    }
}

impl Default for SpectroscopyLineList {
    fn default() -> Self {
        Self {
            lines: Vec::new(),
            strong_lines: None,
            relaxation_matrix: None,
            strong_line_tolerance_nm: 0.01,
            lines_sorted_ascending: false,
            preserve_anchor_weak_lines: false,
            vendor_strong_line_partition: false,
            strong_line_match_by_line: None,
            runtime_controls: SpectroscopyRuntimeControls::default(),
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

impl Default for SpectroscopyStrongLine {
    fn default() -> Self {
        Self {
            center_wavenumber_cm1: 0.0,
            center_wavelength_nm: 0.0,
            population_t0: 0.0,
            dipole_ratio: 0.0,
            dipole_t0: 0.0,
            lower_state_energy_cm1: 0.0,
            air_half_width_cm1: 0.0,
            air_half_width_nm: 0.0,
            temperature_exponent: 0.0,
            pressure_shift_cm1: 0.0,
            pressure_shift_nm: 0.0,
            rotational_index_m1: 0,
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
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

pub type StrongLinePreparedState =
    crate::input::reference::spectroscopy::strong_lines::StrongLineConvTpState;

#[derive(Debug, Clone, PartialEq)]
pub struct SpectroscopyRuntimeControls {
    pub gas_index: Option<u16>,
    pub active_isotopes: Vec<u8>,
    pub threshold_line_scale: Option<f64>,
    pub cutoff_cm1: Option<f64>,
    pub cutoff_grid_wavelengths_nm: Vec<f64>,
    pub cutoff_grid_wavenumbers_cm1: Vec<f64>,
    pub line_mixing_factor: f64,
}

impl Default for SpectroscopyRuntimeControls {
    fn default() -> Self {
        Self {
            gas_index: None,
            active_isotopes: Vec::new(),
            threshold_line_scale: None,
            cutoff_cm1: None,
            cutoff_grid_wavelengths_nm: Vec::new(),
            cutoff_grid_wavenumbers_cm1: Vec::new(),
            line_mixing_factor: 1.0,
        }
    }
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct SpectroscopyEvaluation {
    pub weak_line_sigma_cm2_per_molecule: f64,
    pub strong_line_sigma_cm2_per_molecule: f64,
    pub line_sigma_cm2_per_molecule: f64,
    pub line_mixing_sigma_cm2_per_molecule: f64,
    pub total_sigma_cm2_per_molecule: f64,
    pub d_sigma_d_temperature_cm2_per_molecule_per_k: f64,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct WeakLinePreparedLineState {
    pub shifted_center_wavenumber_cm1: f64,
    pub cte: f64,
    pub line_shape_y: f64,
    pub prefactor_base: f64,
    pub safe_temperature: f64,
    pub safe_pressure: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct WeakLinePreparedState {
    pub line_count: usize,
    pub lines: Vec<WeakLinePreparedLineState>,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct CrossSectionPoint {
    pub wavelength_nm: f64,
    pub sigma_cm2_per_molecule: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
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
        interpolate_cross_section_sigma(&self.points, wavelength_nm)
    }

    pub fn sigma_at_high_resolution(&self, wavelength_nm: f64) -> f64 {
        self.interpolate_sigma(wavelength_nm)
    }

    pub fn bracket_for_wavelength(&self, wavelength_nm: f64) -> Option<(usize, usize)> {
        cross_section_bracket_for_wavelength(&self.points, wavelength_nm)
    }
}

pub fn interpolate_cross_section_sigma(points: &[CrossSectionPoint], wavelength_nm: f64) -> f64 {
    if points.is_empty() {
        return 0.0;
    }
    if wavelength_nm <= points[0].wavelength_nm {
        return points[0].sigma_cm2_per_molecule;
    }
    if wavelength_nm >= points[points.len() - 1].wavelength_nm {
        return points[points.len() - 1].sigma_cm2_per_molecule;
    }

    let Some((left_index, right_index)) =
        cross_section_bracket_for_wavelength(points, wavelength_nm)
    else {
        return points[points.len() - 1].sigma_cm2_per_molecule;
    };
    let left = points[left_index];
    let right = points[right_index];
    let span = right.wavelength_nm - left.wavelength_nm;
    if span == 0.0 {
        return right.sigma_cm2_per_molecule;
    }
    let weight = (wavelength_nm - left.wavelength_nm) / span;
    left.sigma_cm2_per_molecule
        + weight * (right.sigma_cm2_per_molecule - left.sigma_cm2_per_molecule)
}

fn cross_section_bracket_for_wavelength(
    points: &[CrossSectionPoint],
    wavelength_nm: f64,
) -> Option<(usize, usize)> {
    if points.len() < 2 {
        return None;
    }

    let mut low = 0;
    let mut high = points.len() - 1;
    while low + 1 < high {
        let middle = low + (high - low) / 2;
        if points[middle].wavelength_nm <= wavelength_nm {
            low = middle;
        } else {
            high = middle;
        }
    }
    Some((low, high))
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct CollisionInducedAbsorptionPoint {
    pub wavelength_nm: f64,
    pub a0: f64,
    pub a1: f64,
    pub a2: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct CollisionInducedAbsorptionTable {
    pub points: Vec<CollisionInducedAbsorptionPoint>,
    pub scale_factor_cm5_per_molecule2: f64,
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

        let right_index = lower_bound_cia_point_index(&self.points, wavelength_nm);
        let window = spline_window(self.points.len(), right_index);
        if window.count >= 3 {
            let points = &self.points[window.start..window.start + window.count];
            return CollisionInducedAbsorptionPoint {
                wavelength_nm,
                a0: sample_cia_coefficient_spline(points, wavelength_nm, CiaCoefficientKind::A0),
                a1: sample_cia_coefficient_spline(points, wavelength_nm, CiaCoefficientKind::A1),
                a2: sample_cia_coefficient_spline(points, wavelength_nm, CiaCoefficientKind::A2),
            };
        }
        interpolate_cia_coefficients_linear(
            self.points[right_index - 1],
            self.points[right_index],
            wavelength_nm,
        )
    }
}

#[derive(Debug, Clone, Copy)]
enum CiaCoefficientKind {
    A0,
    A1,
    A2,
}

struct CiaSplineWindow {
    start: usize,
    count: usize,
}

fn spline_window(point_count: usize, right_index: usize) -> CiaSplineWindow {
    let count = point_count.min(spline::MAX_SPLINE_POINT_COUNT);
    if point_count <= spline::MAX_SPLINE_POINT_COUNT {
        return CiaSplineWindow { start: 0, count };
    }

    let half_window = spline::MAX_SPLINE_POINT_COUNT / 2;
    let mut start = right_index.saturating_sub(half_window);
    if start + count > point_count {
        start = point_count - count;
    }
    CiaSplineWindow { start, count }
}

fn sample_cia_coefficient_spline(
    points: &[CollisionInducedAbsorptionPoint],
    wavelength_nm: f64,
    coefficient_kind: CiaCoefficientKind,
) -> f64 {
    let x = points
        .iter()
        .map(|point| point.wavelength_nm)
        .collect::<Vec<_>>();
    let y = points
        .iter()
        .map(|point| match coefficient_kind {
            CiaCoefficientKind::A0 => point.a0,
            CiaCoefficientKind::A1 => point.a1,
            CiaCoefficientKind::A2 => point.a2,
        })
        .collect::<Vec<_>>();
    spline::sample_endpoint_secant(&x, &y, wavelength_nm).unwrap_or(0.0)
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

fn lower_bound_cia_point_index(
    points: &[CollisionInducedAbsorptionPoint],
    wavelength_nm: f64,
) -> usize {
    let mut low = 0;
    let mut high = points.len();
    while low < high {
        let middle = low + (high - low) / 2;
        if points[middle].wavelength_nm < wavelength_nm {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    low
}
