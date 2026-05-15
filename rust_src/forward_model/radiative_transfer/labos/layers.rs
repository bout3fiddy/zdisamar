use std::vec::Vec as StdVec;

use super::{
    matrix,
    phase_basis::{FourierPlmBasis, PhaseKernel, fill_zplus_zmin_from_basis_limited},
    types::{Geometry, LayerRt, MAX_NMUTOT, MAX_PHASE_COEF, Mat, Vec as LabosVec},
};
use crate::forward_model::{
    optical_properties::shared::phase_functions,
    radiative_transfer::common_types::LayerInput,
    radiative_transfer::common_types::{RadiativeTransferControls, ScatteringMode},
};

fn locate_lower_index(values: &[f64], target: f64) -> usize {
    if values.len() <= 1 {
        return 0;
    }
    let mut index = 0;
    while index + 1 < values.len() && values[index + 1] < target {
        index += 1;
    }
    index
}

pub fn zero_fourier_integral(
    zplus: &Mat,
    zmin: &Mat,
    geometry: &Geometry,
    column_index: usize,
) -> f64 {
    let column_weight = geometry.w[column_index].max(1.0e-30);
    let mut integral = 0.0;
    for imu in 0..geometry.n_gauss {
        let row_weight = geometry.w[imu].max(1.0e-30);
        integral += geometry.wg[imu]
            * ((zplus.get(imu, column_index) + zmin.get(imu, column_index))
                / (row_weight * column_weight));
    }
    integral
}

pub fn renormalize_zero_fourier_phase_kernel(geometry: &Geometry, zplus: &mut Mat, zmin: &mut Mat) {
    if geometry.n_gauss == 0 || geometry.nmutot == 0 {
        return;
    }

    let mut zplus_unweighted = [[0.0; MAX_NMUTOT]; MAX_NMUTOT];
    for imu0 in 0..geometry.nmutot {
        let column_weight = geometry.w[imu0].max(1.0e-30);
        for (imu, row) in zplus_unweighted
            .iter_mut()
            .enumerate()
            .take(geometry.nmutot)
        {
            let row_weight = geometry.w[imu].max(1.0e-30);
            row[imu0] = zplus.data[imu * zplus.n + imu0] / (row_weight * column_weight);
        }
    }

    for imu0 in 0..geometry.n_gauss {
        let mut integral = 0.0;
        for (imu, row) in zplus_unweighted.iter().enumerate().take(geometry.n_gauss) {
            integral += geometry.wg[imu]
                * (row[imu0]
                    + zmin.data[imu * zmin.n + imu0]
                        / (geometry.w[imu].max(1.0e-30) * geometry.w[imu0].max(1.0e-30)));
        }
        let denominator = zplus_unweighted[imu0][imu0] * geometry.wg[imu0];
        if denominator.abs() <= 1.0e-30 {
            continue;
        }
        let fraction = (2.0 - integral) / denominator;
        zplus_unweighted[imu0][imu0] *= 1.0 + fraction;
    }

    for imu0 in geometry.n_gauss..geometry.nmutot {
        let target_mu = geometry.u[imu0];
        let mut integral = 0.0;
        for (imu, row) in zplus_unweighted.iter().enumerate().take(geometry.n_gauss) {
            integral += geometry.wg[imu]
                * (row[imu0]
                    + zmin.data[imu * zmin.n + imu0]
                        / (geometry.w[imu].max(1.0e-30) * geometry.w[imu0].max(1.0e-30)));
        }
        let delta = 2.0 - integral;

        if target_mu > geometry.ug[0] && target_mu < geometry.ug[geometry.n_gauss - 1] {
            let low = locate_lower_index(&geometry.ug[..geometry.n_gauss], target_mu)
                .min(geometry.n_gauss - 2);
            let high = low + 1;
            let span = geometry.ug[high] - geometry.ug[low];
            if span <= 0.0 {
                continue;
            }
            let low_weight = (target_mu - geometry.ug[low]) / span;
            let high_weight = (geometry.ug[high] - target_mu) / span;
            let low_denominator = zplus_unweighted[imu0][low] * geometry.wg[low];
            let high_denominator = zplus_unweighted[imu0][high] * geometry.wg[high];
            if low_denominator.abs() > 1.0e-30 {
                let fraction = low_weight * delta / low_denominator;
                zplus_unweighted[imu0][low] *= 1.0 + fraction;
                zplus_unweighted[low][imu0] = zplus_unweighted[imu0][low];
            }
            if high_denominator.abs() > 1.0e-30 {
                let fraction = high_weight * delta / high_denominator;
                zplus_unweighted[imu0][high] *= 1.0 + fraction;
                zplus_unweighted[high][imu0] = zplus_unweighted[imu0][high];
            }
            continue;
        }

        let edge = if target_mu < geometry.ug[0] {
            0
        } else {
            geometry.n_gauss - 1
        };
        let denominator = zplus_unweighted[imu0][edge] * geometry.wg[edge];
        if denominator.abs() <= 1.0e-30 {
            continue;
        }
        let fraction = delta / denominator;
        zplus_unweighted[imu0][edge] *= 1.0 + fraction;
        zplus_unweighted[edge][imu0] = zplus_unweighted[imu0][edge];
    }

    for imu0 in 0..geometry.nmutot {
        let column_weight = geometry.w[imu0];
        for (imu, row) in zplus_unweighted.iter().enumerate().take(geometry.nmutot) {
            zplus.data[imu * zplus.n + imu0] = row[imu0] * geometry.w[imu] * column_weight;
        }
    }
}

pub fn fill_layer_phase_max_indices(layer_phase_max_indices: &mut [usize], layers: &[LayerInput]) {
    assert!(layer_phase_max_indices.len() >= layers.len());
    for (layer, max_index) in layers.iter().zip(layer_phase_max_indices.iter_mut()) {
        *max_index = phase_functions::max_phase_coefficient_index(&layer.phase_coefficients);
    }
}

pub fn fill_layer_effective_scattering_suffixes(
    suffixes: &mut [f64],
    layers: &[LayerInput],
    layer_phase_max_indices: &[usize],
) {
    assert!(layer_phase_max_indices.len() >= layers.len());
    assert!(suffixes.len() >= layers.len() * MAX_PHASE_COEF);
    for (layer_idx, layer) in layers.iter().enumerate() {
        let max_phase_index = layer_phase_max_indices[layer_idx];
        let layer_suffixes =
            &mut suffixes[layer_idx * MAX_PHASE_COEF..(layer_idx + 1) * MAX_PHASE_COEF];
        layer_suffixes.fill(0.0);
        let mut suffix: f64 = 0.0;
        let mut reverse_index = (max_phase_index + 1).min(MAX_PHASE_COEF);
        while reverse_index > 0 {
            reverse_index -= 1;
            let idx_f = reverse_index as f64;
            let beta_eff = layer.phase_coefficients[reverse_index].abs() / (2.0 * idx_f + 1.0);
            suffix = suffix.max(beta_eff);
            layer_suffixes[reverse_index] = suffix;
        }
    }
}

pub fn fill_surface(i_fourier: usize, albedo: f64, geometry: &Geometry) -> LayerRt {
    let n = geometry.nmutot;
    let mut result = LayerRt {
        r: Mat::zero(n),
        t: Mat::zero(n),
    };

    if i_fourier == 0 {
        for j in 0..n {
            for i in 0..n {
                result.r.set(i, j, geometry.w[i] * albedo * geometry.w[j]);
            }
        }
    }

    result
}

fn single_scatter_r(a: f64, e: &LabosVec, zmin: &Mat, geometry: &Geometry) -> Mat {
    let n = geometry.nmutot;
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            let eer = e.data[i] * ej;
            result.data[idx] = a * zmin.data[idx] * (1.0 - eer) * geometry.dmu_plus[idx];
            idx += n;
        }
    }
    result
}

fn single_scatter_t(a: f64, b: f64, e: &LabosVec, zplus: &Mat, geometry: &Geometry) -> Mat {
    let n = geometry.nmutot;
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            let eet = if geometry.dmu_same[idx] {
                b * e.data[i]
            } else {
                e.data[i] - ej
            };
            result.data[idx] = a * zplus.data[idx] * eet * geometry.dmu_min[idx];
            idx += n;
        }
    }
    result
}

fn gauss_trace(n: usize, n_gauss: usize, mat: &Mat) -> f64 {
    let mut trace = 0.0;
    for k in 0..n_gauss {
        trace += mat.data[k * n + k];
    }
    trace
}

fn square_attenuation(n: usize, e: &mut LabosVec) {
    for value in e.data.iter_mut().take(n) {
        *value *= *value;
    }
}

#[allow(clippy::too_many_arguments)]
fn do_double(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    geometry: &Geometry,
    b_start: f64,
    r: &mut Mat,
    t: &mut Mat,
    e: &mut LabosVec,
) {
    let mut b = b_start;
    for _ in 0..ndouble {
        let trace_r = gauss_trace(n, n_gauss, r);
        let trace_t = gauss_trace(n, n_gauss, t);
        let q_is_zero = (trace_r * trace_r).abs() <= threshold_mul;

        let d = if q_is_zero {
            *t
        } else {
            let q = matrix::qseries_known_nonzero_product(n, n_gauss, r, r);
            matrix::smul_add_semul3_known_right_trace(n, n_gauss, threshold_mul, &q, e, t, trace_t)
        };
        let trace_d = if q_is_zero {
            trace_t
        } else {
            gauss_trace(n, n_gauss, &d)
        };

        let u = if let Some(rd) =
            matrix::smul_known_traces_if_nonzero(n, n_gauss, threshold_mul, trace_r, trace_d, r, &d)
        {
            matrix::semul_add(n, r, e, &rd)
        } else {
            matrix::semul(n, r, e)
        };
        let trace_u = gauss_trace(n, n_gauss, &u);

        let r_new = if let Some(tu) =
            matrix::smul_known_traces_if_nonzero(n, n_gauss, threshold_mul, trace_t, trace_u, t, &u)
        {
            matrix::mat_add_esmul3(n, r, e, &u, &tu)
        } else {
            matrix::mat_add_esmul(n, r, e, &u)
        };

        let t_new = if let Some(td) =
            matrix::smul_known_traces_if_nonzero(n, n_gauss, threshold_mul, trace_t, trace_d, t, &d)
        {
            matrix::esmul_semul_add(n, e, &d, t, &td)
        } else {
            matrix::esmul_semul(n, e, &d, t)
        };

        *r = r_new;
        *t = t_new;

        b *= 2.0;
        if b < 0.001 {
            for imu in 0..geometry.nmutot {
                e.data[imu] = (-b / geometry.u[imu].max(1.0e-12)).exp();
            }
        } else {
            square_attenuation(n, e);
        }
    }
}

fn max_layer_phase_coefficient_index(layers: &[LayerInput]) -> usize {
    layers
        .iter()
        .map(|layer| phase_functions::max_phase_coefficient_index(&layer.phase_coefficients))
        .max()
        .unwrap_or(0)
}

fn zero_layer_rt(n: usize) -> LayerRt {
    LayerRt {
        r: Mat::zero(n),
        t: Mat::zero(n),
    }
}

#[allow(clippy::too_many_arguments)]
pub fn calc_rt_layers_into_with_basis(
    rt: &mut [LayerRt],
    layers: &[LayerInput],
    i_fourier: usize,
    geometry: &Geometry,
    controls: RadiativeTransferControls,
    plm_basis: &FourierPlmBasis,
    layer_phase_max_indices: Option<&[usize]>,
    layer_effective_scattering_suffixes: Option<&[f64]>,
    mut phase_kernel_cache: Option<&mut [PhaseKernel]>,
    mut phase_kernel_valid: Option<&mut [bool]>,
    mut rt_active: Option<&mut [bool]>,
) {
    let nlayer = layers.len();
    assert!(rt.len() > nlayer);
    rt[0] = zero_layer_rt(geometry.nmutot);
    if let Some(active) = rt_active.as_deref_mut() {
        active[0] = false;
    }
    if let Some(valid) = phase_kernel_valid.as_deref_mut() {
        valid.fill(false);
    }

    for (layer_idx, layer) in layers.iter().enumerate() {
        let rt_idx = layer_idx + 1;
        if i_fourier >= MAX_PHASE_COEF {
            if let Some(active) = rt_active.as_deref_mut() {
                active[rt_idx] = false;
            }
            rt[rt_idx] = zero_layer_rt(geometry.nmutot);
            continue;
        }

        let phase_coefficients = layer.phase_coefficients;
        let max_phase_index = layer_phase_max_indices
            .map(|indices| indices[layer_idx])
            .unwrap_or_else(|| phase_functions::max_phase_coefficient_index(&phase_coefficients));
        if i_fourier > max_phase_index
            || layer.optical_depth < 1.0e-20
            || layer.scattering_optical_depth <= 0.0
            || layer.single_scatter_albedo <= 0.0
        {
            if let Some(active) = rt_active.as_deref_mut() {
                active[rt_idx] = false;
            }
            rt[rt_idx] = zero_layer_rt(geometry.nmutot);
            continue;
        }

        let mut phase_kernel = fill_zplus_zmin_from_basis_limited(
            i_fourier,
            phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
        );
        if let Some(cache) = phase_kernel_cache.as_deref_mut() {
            cache[rt_idx] = phase_kernel;
            if let Some(valid) = phase_kernel_valid.as_deref_mut() {
                valid[rt_idx] = true;
            }
        }

        let b = layer.optical_depth;
        let a = layer.single_scatter_albedo;
        let max_beta_eff = if let Some(suffixes) = layer_effective_scattering_suffixes {
            suffixes[layer_idx * MAX_PHASE_COEF + i_fourier]
        } else {
            let mut suffix: f64 = 0.0;
            for (coefficient_index, coefficient) in phase_coefficients
                .iter()
                .enumerate()
                .take(max_phase_index + 1)
                .skip(i_fourier)
            {
                let idx_f = coefficient_index as f64;
                let beta_eff = coefficient.abs() / (2.0 * idx_f + 1.0);
                suffix = suffix.max(beta_eff);
            }
            suffix
        };
        let a_eff = a * max_beta_eff;

        let mut use_doubling = false;
        let mut b_start = b;
        let mut ndouble = 0usize;
        if controls.scattering == ScatteringMode::Multiple
            && a_eff * b > controls.performance_thresholds.threshold_doubl
        {
            use_doubling = true;
            let mut bd = b;
            for _ in 0..60 {
                bd /= 2.0;
                ndouble += 1;
                if a_eff * bd < controls.performance_thresholds.threshold_doubl {
                    break;
                }
            }
            b_start = bd;
        }

        let mut e = LabosVec::zero(geometry.nmutot);
        for imu in 0..geometry.nmutot {
            e.data[imu] = (-b_start / geometry.u[imu].max(1.0e-12)).exp();
        }

        let mut r = single_scatter_r(a, &e, &phase_kernel.zmin, geometry);
        let mut t = single_scatter_t(a, b_start, &e, &phase_kernel.zplus, geometry);

        if use_doubling {
            if i_fourier == 0 && controls.renorm_phase_function {
                renormalize_zero_fourier_phase_kernel(
                    geometry,
                    &mut phase_kernel.zplus,
                    &mut phase_kernel.zmin,
                );
                r = single_scatter_r(a, &e, &phase_kernel.zmin, geometry);
                t = single_scatter_t(a, b_start, &e, &phase_kernel.zplus, geometry);
            }
            do_double(
                ndouble,
                geometry.nmutot,
                geometry.n_gauss,
                controls.performance_thresholds.threshold_mul,
                geometry,
                b_start,
                &mut r,
                &mut t,
                &mut e,
            );
        }

        rt[rt_idx].r = r;
        rt[rt_idx].t = t;
        if let Some(active) = rt_active.as_deref_mut() {
            active[rt_idx] = a != 0.0;
        }
    }
}

pub fn calc_rt_layers_into(
    rt: &mut [LayerRt],
    layers: &[LayerInput],
    i_fourier: usize,
    geometry: &Geometry,
    controls: RadiativeTransferControls,
) {
    let plm_basis = FourierPlmBasis::init(
        i_fourier,
        max_layer_phase_coefficient_index(layers),
        geometry,
    );
    calc_rt_layers_into_with_basis(
        rt, layers, i_fourier, geometry, controls, &plm_basis, None, None, None, None, None,
    );
}

pub fn calc_rt_layers(
    layers: &[LayerInput],
    i_fourier: usize,
    geometry: &Geometry,
    controls: RadiativeTransferControls,
) -> StdVec<LayerRt> {
    let mut rt = vec![zero_layer_rt(geometry.nmutot); layers.len() + 1];
    calc_rt_layers_into(&mut rt, layers, i_fourier, geometry, controls);
    rt
}
