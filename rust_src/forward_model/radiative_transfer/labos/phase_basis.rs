use crate::forward_model::optical_properties::shared::phase_functions::{self, PhaseCoefficients};

use super::types::{Geometry, MAX_NMUTOT, MAX_PHASE_COEF, Mat};

#[derive(Debug, Clone, Copy, PartialEq)]
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
    pub fn init(i_fourier: usize, max_phase_index: usize, geo: &Geometry) -> Self {
        let bounded_max_phase_index = max_phase_index.min(MAX_PHASE_COEF - 1);
        let mut result = Self {
            i_fourier,
            max_phase_index: bounded_max_phase_index,
            plus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
            minus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
        };
        if bounded_max_phase_index < i_fourier {
            return result;
        }

        let mut sqlm = [0.0; MAX_PHASE_COEF];
        for (l, value) in sqlm
            .iter_mut()
            .enumerate()
            .take(bounded_max_phase_index + 1)
            .skip(i_fourier + 1)
        {
            let lf = l as f64;
            let mf = i_fourier as f64;
            *value = (lf * lf - mf * mf).sqrt();
        }

        let mut p_lm1_plus = [0.0; MAX_NMUTOT];
        let mut p_l_plus = starting_plm(i_fourier, geo);
        let mut p_lm1_minus = [0.0; MAX_NMUTOT];
        let mut p_l_minus = p_l_plus;

        result.store_weighted(i_fourier, &p_l_plus, &p_l_minus, geo);
        if bounded_max_phase_index == i_fourier {
            return result;
        }

        for l in i_fourier..bounded_max_phase_index {
            let a_coef = sqlm[l + 1];
            let c_coef = -sqlm[l];
            for imu in 0..geo.nmutot {
                let b_plus = (2.0 * l as f64 + 1.0) * geo.u[imu];
                let p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
                p_lm1_plus[imu] = p_l_plus[imu];
                p_l_plus[imu] = p_lp1;

                let b_minus = -(2.0 * l as f64 + 1.0) * geo.u[imu];
                let p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
                p_lm1_minus[imu] = p_l_minus[imu];
                p_l_minus[imu] = p_lp1_m;
            }
            result.store_weighted(l + 1, &p_l_plus, &p_l_minus, geo);
        }

        result
    }

    fn store_weighted(
        &mut self,
        coef_idx: usize,
        p_l_plus: &[f64; MAX_NMUTOT],
        p_l_minus: &[f64; MAX_NMUTOT],
        geo: &Geometry,
    ) {
        for imu in 0..geo.nmutot {
            self.plus[coef_idx][imu] = p_l_plus[imu] * geo.w[imu];
            self.minus[coef_idx][imu] = p_l_minus[imu] * geo.w[imu];
        }
    }
}

fn starting_plm(i_fourier: usize, geo: &Geometry) -> [f64; MAX_NMUTOT] {
    let mut values = [0.0; MAX_NMUTOT];
    for (imu, value) in values.iter_mut().enumerate().take(geo.nmutot) {
        let u = geo.u[imu];
        let one_minus_uu = 1.0 - u * u;
        let squu = one_minus_uu.max(0.0).sqrt();
        *value = match i_fourier {
            0 => 1.0,
            1 => squu / 2.0_f64.sqrt(),
            2 => 0.25 * 6.0_f64.sqrt() * one_minus_uu,
            _ => {
                let mut f = 0.375 * one_minus_uu * one_minus_uu;
                for m_idx in 3..=i_fourier {
                    let mf = m_idx as f64;
                    f *= one_minus_uu * (mf - 0.5) / mf;
                }
                f.max(0.0).sqrt()
            }
        };
    }
    values
}

fn compute_plm(i_fourier: usize, coef_idx: usize, geo: &Geometry) -> PlmArrays {
    let bounded_coef_idx = coef_idx.min(MAX_PHASE_COEF - 1);
    if bounded_coef_idx < i_fourier {
        return PlmArrays {
            plus: [0.0; MAX_NMUTOT],
            minus: [0.0; MAX_NMUTOT],
        };
    }

    let mut sqlm = [0.0; MAX_PHASE_COEF];
    for (l, value) in sqlm
        .iter_mut()
        .enumerate()
        .take(bounded_coef_idx + 1)
        .skip(i_fourier + 1)
    {
        let lf = l as f64;
        let mf = i_fourier as f64;
        *value = (lf * lf - mf * mf).sqrt();
    }

    let mut p_lm1_plus = [0.0; MAX_NMUTOT];
    let mut p_l_plus = starting_plm(i_fourier, geo);
    let mut p_lm1_minus = [0.0; MAX_NMUTOT];
    let mut p_l_minus = p_l_plus;

    if bounded_coef_idx == i_fourier {
        return weighted_plm(&p_l_plus, &p_l_minus, geo);
    }

    for l in i_fourier..bounded_coef_idx {
        let a_coef = sqlm[l + 1];
        let c_coef = -sqlm[l];
        for imu in 0..geo.nmutot {
            let b_plus = (2.0 * l as f64 + 1.0) * geo.u[imu];
            let p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
            p_lm1_plus[imu] = p_l_plus[imu];
            p_l_plus[imu] = p_lp1;

            let b_minus = -(2.0 * l as f64 + 1.0) * geo.u[imu];
            let p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
            p_lm1_minus[imu] = p_l_minus[imu];
            p_l_minus[imu] = p_lp1_m;
        }
    }

    weighted_plm(&p_l_plus, &p_l_minus, geo)
}

fn weighted_plm(
    p_l_plus: &[f64; MAX_NMUTOT],
    p_l_minus: &[f64; MAX_NMUTOT],
    geo: &Geometry,
) -> PlmArrays {
    let mut plus = [0.0; MAX_NMUTOT];
    let mut minus = [0.0; MAX_NMUTOT];
    for imu in 0..geo.nmutot {
        plus[imu] = p_l_plus[imu] * geo.w[imu];
        minus[imu] = p_l_minus[imu] * geo.w[imu];
    }
    PlmArrays { plus, minus }
}

pub fn fill_zplus_zmin_from_basis(
    i_fourier: usize,
    phase_coefficients: &PhaseCoefficients,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> PhaseKernel {
    fill_zplus_zmin_from_basis_limited(
        i_fourier,
        phase_coefficients,
        phase_functions::max_phase_coefficient_index(*phase_coefficients),
        geo,
        plm_basis,
    )
}

pub fn fill_zplus_zmin_from_basis_limited(
    i_fourier: usize,
    phase_coefficients: &PhaseCoefficients,
    max_phase_index: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
) -> PhaseKernel {
    let n = geo.nmutot;
    let bounded_max_phase_index = max_phase_index.min(MAX_PHASE_COEF - 1);
    if i_fourier > bounded_max_phase_index {
        return PhaseKernel {
            zplus: Mat::zero(n),
            zmin: Mat::zero(n),
        };
    }

    let mut zplus = Mat::zero(n);
    let mut zmin = Mat::zero(n);
    let mut found_order = false;
    for (l, alpha1) in phase_coefficients
        .iter()
        .copied()
        .enumerate()
        .take(bounded_max_phase_index + 1)
        .skip(i_fourier)
    {
        if alpha1 == 0.0 {
            continue;
        }

        if l <= plm_basis.max_phase_index {
            add_phase_term(
                &mut zplus,
                &mut zmin,
                n,
                alpha1,
                &plm_basis.plus[l],
                &plm_basis.minus[l],
                found_order,
            );
        } else {
            let plm = compute_plm(i_fourier, l, geo);
            add_phase_term(
                &mut zplus,
                &mut zmin,
                n,
                alpha1,
                &plm.plus,
                &plm.minus,
                found_order,
            );
        }
        found_order = true;
    }

    if !found_order {
        return PhaseKernel {
            zplus: Mat::zero(n),
            zmin: Mat::zero(n),
        };
    }

    PhaseKernel { zplus, zmin }
}

pub fn fill_zplus_zmin_row_from_basis_limited(
    i_fourier: usize,
    phase_coefficients: &PhaseCoefficients,
    max_phase_index: usize,
    geo: &Geometry,
    plm_basis: &FourierPlmBasis,
    row_index: usize,
) -> PhaseKernelRow {
    let n = geo.nmutot;
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
    let mut found_order = false;
    for (l, alpha1) in phase_coefficients
        .iter()
        .copied()
        .enumerate()
        .take(bounded_max_phase_index + 1)
        .skip(i_fourier)
    {
        if alpha1 == 0.0 {
            continue;
        }

        if l <= plm_basis.max_phase_index {
            add_phase_row_term(
                &mut row,
                row_index,
                n,
                alpha1,
                &plm_basis.plus[l],
                &plm_basis.minus[l],
                found_order,
            );
        } else {
            let plm = compute_plm(i_fourier, l, geo);
            add_phase_row_term(
                &mut row,
                row_index,
                n,
                alpha1,
                &plm.plus,
                &plm.minus,
                found_order,
            );
        }
        found_order = true;
    }

    if !found_order {
        return PhaseKernelRow {
            zplus: [0.0; MAX_NMUTOT],
            zmin: [0.0; MAX_NMUTOT],
            n,
        };
    }

    row
}

fn add_phase_term(
    zplus: &mut Mat,
    zmin: &mut Mat,
    n: usize,
    alpha1: f64,
    plus_l: &[f64; MAX_NMUTOT],
    minus_l: &[f64; MAX_NMUTOT],
    add_to_existing: bool,
) {
    // Zig has a 12-wide specialization here. This keeps the parity path simple until the Rust layers are pinned by tests.
    for i in 0..n {
        let scaled_plus_i = alpha1 * plus_l[i];
        let scaled_minus_i = alpha1 * minus_l[i];
        let row = i * n;
        for (j, plus_j) in plus_l.iter().enumerate().take(n) {
            let idx = row + j;
            let plus_value = scaled_plus_i * plus_j;
            let min_value = scaled_minus_i * plus_j;
            if add_to_existing {
                zplus.data[idx] += plus_value;
                zmin.data[idx] += min_value;
            } else {
                zplus.data[idx] = plus_value;
                zmin.data[idx] = min_value;
            }
        }
    }
}

fn add_phase_row_term(
    row: &mut PhaseKernelRow,
    row_index: usize,
    n: usize,
    alpha1: f64,
    plus_l: &[f64; MAX_NMUTOT],
    minus_l: &[f64; MAX_NMUTOT],
    add_to_existing: bool,
) {
    let scaled_plus_row = alpha1 * plus_l[row_index];
    let scaled_minus_row = alpha1 * minus_l[row_index];
    for (j, plus_j) in plus_l.iter().enumerate().take(n) {
        let plus_value = scaled_plus_row * plus_j;
        let min_value = scaled_minus_row * plus_j;
        if add_to_existing {
            row.zplus[j] += plus_value;
            row.zmin[j] += min_value;
        } else {
            row.zplus[j] = plus_value;
            row.zmin[j] = min_value;
        }
    }
}

pub fn fill_zplus_zmin(
    i_fourier: usize,
    phase_coefficients: &PhaseCoefficients,
    geo: &Geometry,
) -> PhaseKernel {
    let max_phase_index = phase_functions::max_phase_coefficient_index(*phase_coefficients);
    let plm_basis = FourierPlmBasis::init(i_fourier, max_phase_index, geo);
    fill_zplus_zmin_from_basis(i_fourier, phase_coefficients, geo, &plm_basis)
}
