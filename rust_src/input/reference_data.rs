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
