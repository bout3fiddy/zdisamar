use crate::common::math::interpolation::spline;

#[derive(Debug, Default, Clone, Copy, PartialEq)]
pub struct SpectroscopyLine {
    pub gas_index: u8,
    pub isotope_number: u8,
    pub center_wavelength_nm: f64,
    pub line_strength_cm2_per_molecule: f64,
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct SpectroscopyLineList {
    pub lines: Vec<SpectroscopyLine>,
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
