use crate::input::{binding::BindingKind, scene::Scene};

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

pub fn irradiance_at_wavelength(scene: &Scene, wavelength_nm: f64) -> f64 {
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

pub fn bundled_solar_irradiance(wavelength_nm: f64) -> Option<f64> {
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
        if wavelength_nm <= right_nm {
            let left_irradiance = BUNDLED_O2A_SOLAR_IRRADIANCE[index];
            let right_irradiance = BUNDLED_O2A_SOLAR_IRRADIANCE[index + 1];
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

pub fn default_solar_continuum_irradiance(wavelength_nm: f64) -> f64 {
    let reference_wavelength_nm = 760.0;
    let reference_irradiance = 4.87401e14;
    reference_irradiance * planck_continuum_shape(wavelength_nm, 5778.0)
        / planck_continuum_shape(reference_wavelength_nm, 5778.0)
}

fn planck_continuum_shape(wavelength_nm: f64, temperature_k: f64) -> f64 {
    let h = 6.626_070_15e-34;
    let c = 2.997_924_58e8;
    let k = 1.380_649e-23;
    let wavelength_m = wavelength_nm.max(1.0) * 1.0e-9;
    let exponent = h * c / (wavelength_m * k * temperature_k.max(1.0));
    let denominator = exponent.exp_m1().max(1.0e-12);
    (2.0 * h * c * c) / wavelength_m.powi(5) / denominator
}
