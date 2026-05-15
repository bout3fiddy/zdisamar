#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub enum PhaseSupportKind {
    #[default]
    None,
    AnalyticHg,
    MieTable,
}

#[derive(Debug, Default, Clone, Copy, PartialEq)]
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

impl Default for MiePhasePoint {
    fn default() -> Self {
        Self {
            wavelength_nm: 0.0,
            extinction_scale: 1.0,
            single_scatter_albedo: 1.0,
            phase_coefficients: [1.0, 0.0, 0.0, 0.0],
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct MiePhaseTable {
    pub points: Vec<MiePhasePoint>,
}

impl MiePhaseTable {
    pub fn interpolate(&self, wavelength_nm: f64) -> MiePhasePoint {
        if self.points.is_empty() {
            return MiePhasePoint {
                wavelength_nm,
                ..MiePhasePoint::default()
            };
        }
        if wavelength_nm <= self.points[0].wavelength_nm {
            return self.points[0];
        }

        for pair in self.points.windows(2) {
            let left = pair[0];
            let right = pair[1];
            if wavelength_nm > right.wavelength_nm {
                continue;
            }
            let span = right.wavelength_nm - left.wavelength_nm;
            if span == 0.0 {
                return right;
            }
            let weight = (wavelength_nm - left.wavelength_nm) / span;
            let mut phase_coefficients = [0.0; 4];
            for (index, slot) in phase_coefficients.iter_mut().enumerate() {
                *slot = left.phase_coefficients[index]
                    + weight * (right.phase_coefficients[index] - left.phase_coefficients[index]);
            }
            phase_coefficients[0] = 1.0;
            return MiePhasePoint {
                wavelength_nm,
                extinction_scale: left.extinction_scale
                    + weight * (right.extinction_scale - left.extinction_scale),
                single_scatter_albedo: left.single_scatter_albedo
                    + weight * (right.single_scatter_albedo - left.single_scatter_albedo),
                phase_coefficients,
            };
        }
        *self.points.last().expect("non-empty Mie phase table")
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Error {
    ShapeMismatch,
}

pub fn spectral_profile_from_optical_depth(
    wavelengths_nm: &[f64],
    mean_airmass_factor: f64,
    optical_depth_proxy: &[f64],
) -> Result<Vec<f64>, Error> {
    if wavelengths_nm.len() != optical_depth_proxy.len() {
        return Err(Error::ShapeMismatch);
    }
    if wavelengths_nm.is_empty() {
        return Ok(Vec::new());
    }

    let proxy_sum: f64 = optical_depth_proxy.iter().map(|value| value.max(0.0)).sum();
    let proxy_mean = proxy_sum / (optical_depth_proxy.len() as f64).max(1.0e-9);
    let safe_mean_airmass = if mean_airmass_factor.is_finite() && mean_airmass_factor > 0.0 {
        mean_airmass_factor
    } else {
        1.0
    };
    let midpoint_nm = 0.5 * (wavelengths_nm[0] + wavelengths_nm[wavelengths_nm.len() - 1]);
    let half_span_nm =
        (0.5 * (wavelengths_nm[wavelengths_nm.len() - 1] - wavelengths_nm[0])).max(1.0e-9);

    let mut profile = Vec::with_capacity(wavelengths_nm.len());
    for (wavelength_nm, proxy) in wavelengths_nm.iter().zip(optical_depth_proxy.iter()) {
        let normalized_proxy = if proxy_mean > 0.0 {
            proxy.max(0.0) / proxy_mean
        } else {
            1.0
        };
        let coordinate = (wavelength_nm - midpoint_nm) / half_span_nm;
        // The small tilt keeps generated support profiles from becoming flat,
        // then the final normalization restores the requested mean.
        let geometric_tilt = 1.0 + 0.05 * coordinate;
        profile.push(safe_mean_airmass * normalized_proxy * geometric_tilt);
    }

    let current_mean = profile.iter().sum::<f64>() / (profile.len() as f64).max(1.0e-9);
    let renormalization = safe_mean_airmass / current_mean.max(1.0e-9);
    for value in &mut profile {
        *value *= renormalization;
    }
    Ok(profile)
}
