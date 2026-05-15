use crate::input::instrument::{BuiltinLineShapeKind, SlitIndex, SpectralResponse};

pub fn default_kernel_half_span_nm(fwhm_nm: f64) -> f64 {
    (3.0 * fwhm_nm.max(1.0e-4)).max(1.0e-4)
}

pub fn spectral_response_weight(response: &SpectralResponse, offset_nm: f64) -> f64 {
    let fwhm_nm = response.fwhm_nm.max(1.0e-4);
    match response.slit_index {
        SlitIndex::GaussianModulated => {
            let sigma_nm = fwhm_nm / 2.354_820_045;
            let gaussian = (-0.5 * (offset_nm / sigma_nm).powi(2)).exp();
            let phase_rad = response.phase_deg.to_radians();
            let modulation = 1.0
                + response.amplitude
                    * (response.scale * offset_nm / fwhm_nm + phase_rad)
                        .sin()
                        .powi(2);
            (gaussian * modulation).max(0.0)
        }
        SlitIndex::FlatTopN4 => flat_top_n4_weight(fwhm_nm, offset_nm),
        SlitIndex::TripleFlatTopN4 => {
            flat_top_n4_weight(fwhm_nm, offset_nm)
                + flat_top_n4_weight(fwhm_nm, offset_nm - 0.1)
                + flat_top_n4_weight(fwhm_nm, offset_nm + 0.1)
        }
        SlitIndex::Table => {
            builtin_line_shape_weight(response.builtin_line_shape, fwhm_nm, offset_nm)
        }
    }
}

pub fn builtin_line_shape_weight(shape: BuiltinLineShapeKind, fwhm_nm: f64, offset_nm: f64) -> f64 {
    let safe_fwhm_nm = fwhm_nm.max(1.0e-4);
    match shape {
        BuiltinLineShapeKind::Gaussian => {
            let sigma_nm = safe_fwhm_nm / 2.354_820_045;
            (-0.5 * (offset_nm / sigma_nm).powi(2)).exp()
        }
        BuiltinLineShapeKind::FlatTopN4 => flat_top_n4_weight(safe_fwhm_nm, offset_nm),
        BuiltinLineShapeKind::TripleFlatTopN4 => {
            flat_top_n4_weight(safe_fwhm_nm, offset_nm)
                + flat_top_n4_weight(safe_fwhm_nm, offset_nm - 0.1)
                + flat_top_n4_weight(safe_fwhm_nm, offset_nm + 0.1)
        }
    }
}

pub fn flat_top_n4_weight(fwhm_nm: f64, offset_nm: f64) -> f64 {
    let width_nm = fwhm_nm / 1.681_793;
    2.0_f64.powf(-2.0 * (offset_nm / width_nm.max(1.0e-6)).powi(4))
}
