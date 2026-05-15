use super::types::{Geometry, MAX_NMUTOT, MAX_PHASE_COEF, Mat};
use crate::forward_model::optical_properties::shared::phase_functions::{
    PhaseCoefficients, max_phase_coefficient_index,
};

struct PlmArrays {
    plus: [f64; MAX_NMUTOT],
    minus: [f64; MAX_NMUTOT],
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PhaseKernel {
    pub zplus: Mat,
    pub zmin: Mat,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PhaseKernelRow {
    pub zplus: [f64; MAX_NMUTOT],
    pub zmin: [f64; MAX_NMUTOT],
    pub n: usize,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct FourierPlmBasis {
    pub i_fourier: usize,
    pub max_phase_index: usize,
    pub plus: [[f64; MAX_NMUTOT]; MAX_PHASE_COEF],
    pub minus: [[f64; MAX_NMUTOT]; MAX_PHASE_COEF],
}

impl FourierPlmBasis {
    pub fn init(i_fourier: usize, max_phase_index: usize, geometry: &Geometry) -> Self {
        let mut result = Self {
            i_fourier,
            max_phase_index,
            plus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
            minus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
        };
        if max_phase_index < i_fourier {
            return result;
        }

        let mut sqlm = [0.0; MAX_PHASE_COEF];
        for (l, value) in sqlm
            .iter_mut()
            .enumerate()
            .take(max_phase_index + 1)
            .skip(i_fourier + 1)
        {
            let lf = l as f64;
            let mf = i_fourier as f64;
            *value = (lf * lf - mf * mf).sqrt();
        }

        let mut p_lm1_plus = [0.0; MAX_NMUTOT];
        let mut p_l_plus = start_plm(i_fourier, geometry);
        let mut p_lm1_minus = [0.0; MAX_NMUTOT];
        let mut p_l_minus = p_l_plus;

        result.store_weighted(i_fourier, &p_l_plus, &p_l_minus, geometry);
        if max_phase_index == i_fourier {
            return result;
        }

        for l in i_fourier..max_phase_index {
            let a_coef = sqlm[l + 1];
            let c_coef = -sqlm[l];
            for imu in 0..geometry.nmutot {
                let b_plus = (2.0 * l as f64 + 1.0) * geometry.u[imu];
                let p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
                p_lm1_plus[imu] = p_l_plus[imu];
                p_l_plus[imu] = p_lp1;

                let b_minus = -(2.0 * l as f64 + 1.0) * geometry.u[imu];
                let p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
                p_lm1_minus[imu] = p_l_minus[imu];
                p_l_minus[imu] = p_lp1_m;
            }
            result.store_weighted(l + 1, &p_l_plus, &p_l_minus, geometry);
        }

        result
    }

    fn store_weighted(
        &mut self,
        coef_idx: usize,
        p_l_plus: &[f64; MAX_NMUTOT],
        p_l_minus: &[f64; MAX_NMUTOT],
        geometry: &Geometry,
    ) {
        for imu in 0..geometry.nmutot {
            self.plus[coef_idx][imu] = p_l_plus[imu] * geometry.w[imu];
            self.minus[coef_idx][imu] = p_l_minus[imu] * geometry.w[imu];
        }
    }
}

fn start_plm(i_fourier: usize, geometry: &Geometry) -> [f64; MAX_NMUTOT] {
    let mut values = [0.0; MAX_NMUTOT];
    for (imu, value) in values.iter_mut().enumerate().take(geometry.nmutot) {
        let u = geometry.u[imu];
        let one_minus_uu = 1.0 - u * u;
        let squu = one_minus_uu.max(0.0).sqrt();
        *value = match i_fourier {
            0 => 1.0,
            1 => squu / 2.0_f64.sqrt(),
            2 => 0.25 * 6.0_f64.sqrt() * one_minus_uu,
            _ => {
                let mut factor = 0.375 * one_minus_uu * one_minus_uu;
                for m_idx in 3..i_fourier + 1 {
                    let mf = m_idx as f64;
                    factor *= one_minus_uu * (mf - 0.5) / mf;
                }
                factor.max(0.0).sqrt()
            }
        };
    }
    values
}

fn compute_plm(i_fourier: usize, coef_idx: usize, geometry: &Geometry) -> PlmArrays {
    if coef_idx < i_fourier {
        return PlmArrays {
            plus: [0.0; MAX_NMUTOT],
            minus: [0.0; MAX_NMUTOT],
        };
    }

    let mut sqlm = [0.0; MAX_PHASE_COEF];
    for (l, value) in sqlm
        .iter_mut()
        .enumerate()
        .take(coef_idx + 1)
        .skip(i_fourier + 1)
    {
        let lf = l as f64;
        let mf = i_fourier as f64;
        *value = (lf * lf - mf * mf).sqrt();
    }

    let mut p_lm1_plus = [0.0; MAX_NMUTOT];
    let mut p_l_plus = start_plm(i_fourier, geometry);
    let mut p_lm1_minus = [0.0; MAX_NMUTOT];
    let mut p_l_minus = p_l_plus;

    if coef_idx != i_fourier {
        for l in i_fourier..coef_idx {
            let a_coef = sqlm[l + 1];
            let c_coef = -sqlm[l];
            for imu in 0..geometry.nmutot {
                let b_plus = (2.0 * l as f64 + 1.0) * geometry.u[imu];
                let p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
                p_lm1_plus[imu] = p_l_plus[imu];
                p_l_plus[imu] = p_lp1;

                let b_minus = -(2.0 * l as f64 + 1.0) * geometry.u[imu];
                let p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
                p_lm1_minus[imu] = p_l_minus[imu];
                p_l_minus[imu] = p_lp1_m;
            }
        }
    }

    let mut plus = [0.0; MAX_NMUTOT];
    let mut minus = [0.0; MAX_NMUTOT];
    for imu in 0..geometry.nmutot {
        plus[imu] = p_l_plus[imu] * geometry.w[imu];
        minus[imu] = p_l_minus[imu] * geometry.w[imu];
    }
    PlmArrays { plus, minus }
}

pub fn fill_zplus_zmin_from_basis(
    i_fourier: usize,
    phase_coefficients: PhaseCoefficients,
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> PhaseKernel {
    fill_zplus_zmin_from_basis_limited(
        i_fourier,
        phase_coefficients,
        max_phase_coefficient_index(&phase_coefficients),
        geometry,
        plm_basis,
    )
}

pub fn fill_zplus_zmin_from_basis_limited(
    i_fourier: usize,
    phase_coefficients: PhaseCoefficients,
    max_phase_index: usize,
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> PhaseKernel {
    let n = geometry.nmutot;
    let bounded_max_phase_index = max_phase_index.min(MAX_PHASE_COEF - 1);
    if i_fourier > bounded_max_phase_index {
        return PhaseKernel {
            zplus: Mat::zero(n),
            zmin: Mat::zero(n),
        };
    }

    let mut zplus = Mat::zero(n);
    let mut zmin = Mat::zero(n);
    for (l, alpha) in phase_coefficients
        .iter()
        .enumerate()
        .take(bounded_max_phase_index + 1)
        .skip(i_fourier)
    {
        if *alpha == 0.0 {
            continue;
        }
        let (plus_l, minus_l) = if l <= plm_basis.max_phase_index {
            (plm_basis.plus[l], plm_basis.minus[l])
        } else {
            let plm = compute_plm(i_fourier, l, geometry);
            (plm.plus, plm.minus)
        };
        add_phase_term(n, *alpha, &plus_l, &minus_l, &mut zplus, &mut zmin);
    }

    PhaseKernel { zplus, zmin }
}

pub fn fill_zplus_zmin_row_from_basis_limited(
    i_fourier: usize,
    phase_coefficients: PhaseCoefficients,
    max_phase_index: usize,
    geometry: &Geometry,
    plm_basis: &FourierPlmBasis,
    row_index: usize,
) -> PhaseKernelRow {
    let n = geometry.nmutot;
    let bounded_max_phase_index = max_phase_index.min(MAX_PHASE_COEF - 1);
    if row_index >= n || i_fourier > bounded_max_phase_index {
        return PhaseKernelRow {
            zplus: [0.0; MAX_NMUTOT],
            zmin: [0.0; MAX_NMUTOT],
            n,
        };
    }

    let mut row = PhaseKernelRow {
        zplus: [0.0; MAX_NMUTOT],
        zmin: [0.0; MAX_NMUTOT],
        n,
    };
    for (l, alpha) in phase_coefficients
        .iter()
        .enumerate()
        .take(bounded_max_phase_index + 1)
        .skip(i_fourier)
    {
        if *alpha == 0.0 {
            continue;
        }
        let (plus_l, minus_l) = if l <= plm_basis.max_phase_index {
            (plm_basis.plus[l], plm_basis.minus[l])
        } else {
            let plm = compute_plm(i_fourier, l, geometry);
            (plm.plus, plm.minus)
        };
        let scaled_plus_row = *alpha * plus_l[row_index];
        let scaled_minus_row = *alpha * minus_l[row_index];
        for (j, plus_value) in plus_l.iter().enumerate().take(n) {
            row.zplus[j] += scaled_plus_row * plus_value;
            row.zmin[j] += scaled_minus_row * plus_value;
        }
    }
    row
}

pub fn fill_zplus_zmin(
    i_fourier: usize,
    phase_coefficients: PhaseCoefficients,
    geometry: &Geometry,
) -> PhaseKernel {
    let max_phase_index = max_phase_coefficient_index(&phase_coefficients);
    let plm_basis = FourierPlmBasis::init(i_fourier, max_phase_index, geometry);
    fill_zplus_zmin_from_basis(i_fourier, phase_coefficients, geometry, &plm_basis)
}

fn add_phase_term(
    n: usize,
    alpha: f64,
    plus_l: &[f64; MAX_NMUTOT],
    minus_l: &[f64; MAX_NMUTOT],
    zplus: &mut Mat,
    zmin: &mut Mat,
) {
    for i in 0..n {
        let scaled_plus_i = alpha * plus_l[i];
        let scaled_minus_i = alpha * minus_l[i];
        let row = i * n;
        for (j, plus_value) in plus_l.iter().enumerate().take(n) {
            zplus.data[row + j] += scaled_plus_i * plus_value;
            zmin.data[row + j] += scaled_minus_i * plus_value;
        }
    }
}
