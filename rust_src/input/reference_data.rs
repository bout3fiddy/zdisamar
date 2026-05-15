use crate::{
    common::{errors, math::interpolation::spline},
    input::reference::spectroscopy::line_list_ops,
};

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
