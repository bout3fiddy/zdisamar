use crate::forward_model::{
    jacobian::{self, State},
    optical_properties::shared::phase_functions,
    radiative_transfer::{LayerInput, RadiativeTransferControls, ScatteringMode},
};

use super::{
    FourierPlmBasis, PhaseKernel, fill_zplus_zmin_from_basis_limited, matrix,
    types::{Geometry, LayerRt, MAX_NMUTOT, MAX_PHASE_COEF, Mat, Vec as LabosVec},
};

fn phase_odd_reciprocal(index: usize) -> f64 {
    1.0 / (2.0 * index as f64 + 1.0)
}

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

pub fn zero_fourier_integral(zplus: &Mat, zmin: &Mat, geo: &Geometry, column_index: usize) -> f64 {
    let column_weight = geo.w[column_index].max(1.0e-30);
    let mut integral = 0.0;
    for imu in 0..geo.n_gauss {
        let row_weight = geo.w[imu].max(1.0e-30);
        integral += geo.wg[imu]
            * ((zplus.get(imu, column_index) + zmin.get(imu, column_index))
                / (row_weight * column_weight));
    }
    integral
}

pub fn renormalize_zero_fourier_phase_kernel(geo: &Geometry, zplus: &mut Mat, zmin: &mut Mat) {
    if geo.n_gauss == 0 || geo.nmutot == 0 {
        return;
    }

    let mut zp = [[0.0; MAX_NMUTOT]; MAX_NMUTOT];
    for imu0 in 0..geo.nmutot {
        let column_weight = geo.w[imu0].max(1.0e-30);
        for (imu, row) in zp.iter_mut().enumerate().take(geo.nmutot) {
            let row_weight = geo.w[imu].max(1.0e-30);
            row[imu0] = zplus.data[imu * zplus.n + imu0] / (row_weight * column_weight);
        }
    }

    for imu0 in 0..geo.n_gauss {
        let mut integral = 0.0;
        for (imu, row) in zp.iter().enumerate().take(geo.n_gauss) {
            integral += geo.wg[imu]
                * (row[imu0]
                    + zmin.data[imu * zmin.n + imu0]
                        / (geo.w[imu].max(1.0e-30) * geo.w[imu0].max(1.0e-30)));
        }
        let denominator = zp[imu0][imu0] * geo.wg[imu0];
        if denominator.abs() <= 1.0e-30 {
            continue;
        }
        let fraction = (2.0 - integral) / denominator;
        zp[imu0][imu0] *= 1.0 + fraction;
    }

    for imu0 in geo.n_gauss..geo.nmutot {
        let target_mu = geo.u[imu0];
        let mut integral = 0.0;
        for (imu, row) in zp.iter().enumerate().take(geo.n_gauss) {
            integral += geo.wg[imu]
                * (row[imu0]
                    + zmin.data[imu * zmin.n + imu0]
                        / (geo.w[imu].max(1.0e-30) * geo.w[imu0].max(1.0e-30)));
        }
        let delta = 2.0 - integral;

        if target_mu > geo.ug[0] && target_mu < geo.ug[geo.n_gauss - 1] {
            let low = locate_lower_index(&geo.ug[..geo.n_gauss], target_mu).min(geo.n_gauss - 2);
            let high = low + 1;
            let span = geo.ug[high] - geo.ug[low];
            if span <= 0.0 {
                continue;
            }
            let low_weight = (target_mu - geo.ug[low]) / span;
            let high_weight = (geo.ug[high] - target_mu) / span;
            let low_denominator = zp[imu0][low] * geo.wg[low];
            let high_denominator = zp[imu0][high] * geo.wg[high];
            if low_denominator.abs() > 1.0e-30 {
                let fraction = low_weight * delta / low_denominator;
                zp[imu0][low] *= 1.0 + fraction;
                zp[low][imu0] = zp[imu0][low];
            }
            if high_denominator.abs() > 1.0e-30 {
                let fraction = high_weight * delta / high_denominator;
                zp[imu0][high] *= 1.0 + fraction;
                zp[high][imu0] = zp[imu0][high];
            }
            continue;
        }

        let edge = if target_mu < geo.ug[0] {
            0
        } else {
            geo.n_gauss - 1
        };
        let denominator = zp[imu0][edge] * geo.wg[edge];
        if denominator.abs() <= 1.0e-30 {
            continue;
        }
        let fraction = delta / denominator;
        zp[imu0][edge] *= 1.0 + fraction;
        zp[edge][imu0] = zp[imu0][edge];
    }

    for imu0 in 0..geo.nmutot {
        let column_weight = geo.w[imu0];
        for (imu, row) in zp.iter().enumerate().take(geo.nmutot) {
            zplus.data[imu * zplus.n + imu0] = row[imu0] * geo.w[imu] * column_weight;
        }
    }
}

fn single_scatter_r(a: f64, e: &LabosVec, zmin: &Mat, geo: &Geometry) -> Mat {
    let n = geo.nmutot;
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            let eer = e.data[i] * ej;
            result.data[idx] = a * zmin.data[idx] * (1.0 - eer) * geo.dmu_plus[idx];
            idx += n;
        }
    }
    result
}

fn single_scatter_t(a: f64, b: f64, e: &LabosVec, zplus: &Mat, geo: &Geometry) -> Mat {
    let n = geo.nmutot;
    let mut result = Mat::zero(n);
    for j in 0..n {
        let ej = e.data[j];
        let mut idx = j;
        for i in 0..n {
            let eet = if geo.dmu_same[idx] {
                b * e.data[i]
            } else {
                e.data[i] - ej
            };
            result.data[idx] = a * zplus.data[idx] * eet * geo.dmu_min[idx];
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
    geo: &Geometry,
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

        let mut rd = Mat::zero(n);
        let rd_nonzero = matrix::smul_into_known_traces_if_nonzero(
            &mut rd,
            n,
            n_gauss,
            threshold_mul,
            trace_r,
            trace_d,
            r,
            &d,
        );

        let u = if rd_nonzero {
            matrix::semul_add(n, r, e, &rd)
        } else {
            matrix::semul(n, r, e)
        };
        let trace_u = gauss_trace(n, n_gauss, &u);

        let mut tu = Mat::zero(n);
        let tu_nonzero = matrix::smul_into_known_traces_if_nonzero(
            &mut tu,
            n,
            n_gauss,
            threshold_mul,
            trace_t,
            trace_u,
            t,
            &u,
        );

        let r_new = if tu_nonzero {
            matrix::mat_add_esmul3(n, r, e, &u, &tu)
        } else {
            matrix::mat_add_esmul(n, r, e, &u)
        };

        let mut td = Mat::zero(n);
        let td_nonzero = matrix::smul_into_known_traces_if_nonzero(
            &mut td,
            n,
            n_gauss,
            threshold_mul,
            trace_t,
            trace_d,
            t,
            &d,
        );

        let t_new = if td_nonzero {
            matrix::esmul_semul_add(n, e, &d, t, &td)
        } else {
            matrix::esmul_semul(n, e, &d, t)
        };

        // Both new operators must use the pre-step R/T values, matching DISAMAR's whole-array update.
        *r = r_new;
        *t = t_new;

        b *= 2.0;
        if b < 0.001 {
            for imu in 0..geo.nmutot {
                e.data[imu] = (-b / geo.u[imu].max(1.0e-12)).exp();
            }
        } else {
            square_attenuation(n, e);
        }
    }
}

fn max_layer_phase_coefficient_index(layers: &[LayerInput]) -> usize {
    layers
        .iter()
        .map(|layer| phase_functions::max_phase_coefficient_index(layer.phase_coefficients))
        .max()
        .unwrap_or(0)
}

pub fn fill_layer_phase_max_indices(layer_phase_max_indices: &mut [usize], layers: &[LayerInput]) {
    assert!(layer_phase_max_indices.len() >= layers.len());
    for (layer, max_index) in layers.iter().zip(layer_phase_max_indices.iter_mut()) {
        *max_index = phase_functions::max_phase_coefficient_index(layer.phase_coefficients);
    }
}

pub fn fill_layer_effective_scattering_suffixes(
    suffixes: &mut [f64],
    layers: &[LayerInput],
    layer_phase_max_indices: &[usize],
) {
    assert!(layer_phase_max_indices.len() >= layers.len());
    assert!(suffixes.len() >= layers.len() * MAX_PHASE_COEF);
    for (layer_idx, (layer, max_phase_index)) in layers
        .iter()
        .zip(layer_phase_max_indices.iter().copied())
        .enumerate()
    {
        let layer_suffixes =
            &mut suffixes[layer_idx * MAX_PHASE_COEF..(layer_idx + 1) * MAX_PHASE_COEF];
        layer_suffixes.fill(0.0);
        let mut suffix: f64 = 0.0;
        let mut reverse_index = max_phase_index.min(MAX_PHASE_COEF - 1) + 1;
        while reverse_index > 0 {
            reverse_index -= 1;
            let beta_eff =
                layer.phase_coefficients[reverse_index].abs() * phase_odd_reciprocal(reverse_index);
            suffix = suffix.max(beta_eff);
            layer_suffixes[reverse_index] = suffix;
        }
    }
}

#[allow(clippy::too_many_arguments)]
pub fn calc_rt_layers_into_with_basis(
    rt: &mut [LayerRt],
    layers: &[LayerInput],
    i_fourier: usize,
    geo: &Geometry,
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
    rt[0] = zero_layer_rt(geo.nmutot);
    if let Some(active) = rt_active.as_deref_mut() {
        active[0] = false;
    }
    if let Some(valid) = phase_kernel_valid.as_deref_mut() {
        valid.fill(false);
    }

    for (layer_idx, layer) in layers.iter().copied().enumerate() {
        let rt_idx = layer_idx + 1;
        if i_fourier >= MAX_PHASE_COEF {
            if let Some(active) = rt_active.as_deref_mut() {
                active[rt_idx] = false;
            }
            rt[rt_idx] = zero_layer_rt(geo.nmutot);
            continue;
        }

        let max_phase_index = layer_phase_max_indices
            .map(|indices| indices[layer_idx])
            .unwrap_or_else(|| {
                phase_functions::max_phase_coefficient_index(layer.phase_coefficients)
            });
        if i_fourier > max_phase_index {
            if let Some(active) = rt_active.as_deref_mut() {
                active[rt_idx] = false;
            }
            rt[rt_idx] = zero_layer_rt(geo.nmutot);
            continue;
        }
        if layer.optical_depth < 1.0e-20
            || layer.scattering_optical_depth <= 0.0
            || layer.single_scatter_albedo <= 0.0
        {
            if let Some(active) = rt_active.as_deref_mut() {
                active[rt_idx] = false;
            }
            rt[rt_idx] = zero_layer_rt(geo.nmutot);
            continue;
        }

        let mut z = fill_zplus_zmin_from_basis_limited(
            i_fourier,
            &layer.phase_coefficients,
            max_phase_index,
            geo,
            plm_basis,
        );
        if let Some(cache) = phase_kernel_cache.as_deref_mut() {
            cache[rt_idx] = z;
        }
        if let Some(valid) = phase_kernel_valid.as_deref_mut() {
            valid[rt_idx] = true;
        }

        let b = layer.optical_depth;
        let a = layer.single_scatter_albedo;
        let bounded_max_phase_index = max_phase_index.min(MAX_PHASE_COEF - 1);
        let max_beta_eff = if let Some(suffixes) = layer_effective_scattering_suffixes {
            assert!(suffixes.len() >= layers.len() * MAX_PHASE_COEF);
            suffixes[layer_idx * MAX_PHASE_COEF + i_fourier]
        } else {
            layer
                .phase_coefficients
                .iter()
                .copied()
                .enumerate()
                .take(bounded_max_phase_index + 1)
                .skip(i_fourier)
                .map(|(index, coefficient)| coefficient.abs() * phase_odd_reciprocal(index))
                .fold(0.0, f64::max)
        };
        let a_eff = a * max_beta_eff;

        let mut use_doubling = false;
        let mut b_start = b;
        let mut ndouble = 0;
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

        let mut e = LabosVec::zero(geo.nmutot);
        for imu in 0..geo.nmutot {
            e.data[imu] = (-b_start / geo.u[imu].max(1.0e-12)).exp();
        }

        let mut r = single_scatter_r(a, &e, &z.zmin, geo);
        let mut t = single_scatter_t(a, b_start, &e, &z.zplus, geo);

        if use_doubling {
            if i_fourier == 0 && controls.renorm_phase_function {
                renormalize_zero_fourier_phase_kernel(geo, &mut z.zplus, &mut z.zmin);
                r = single_scatter_r(a, &e, &z.zmin, geo);
                t = single_scatter_t(a, b_start, &e, &z.zplus, geo);
            }
            do_double(
                ndouble,
                geo.nmutot,
                geo.n_gauss,
                controls.performance_thresholds.threshold_mul,
                geo,
                b_start,
                &mut r,
                &mut t,
                &mut e,
            );
        }

        rt[rt_idx] = LayerRt { r, t };
        if let Some(active) = rt_active.as_deref_mut() {
            active[rt_idx] = a != 0.0;
        }
    }
}

pub fn calc_rt_layers_tangent_into_with_basis(
    rt_tangent: &mut [LayerRt],
    layers: &[LayerInput],
    state: State,
    i_fourier: usize,
    geo: &Geometry,
    controls: RadiativeTransferControls,
    plm_basis: &FourierPlmBasis,
) {
    let nlevel = layers.len() + 1;
    assert!(rt_tangent.len() >= nlevel);
    for layer_rt in rt_tangent.iter_mut().take(nlevel) {
        *layer_rt = zero_layer_rt(geo.nmutot);
    }

    let eps = 1.0e-5;
    let inv_span = 0.5 / eps;
    for (layer_idx, layer) in layers.iter().copied().enumerate() {
        let d_optical_depth = jacobian::get(layer.optical_depth_jacobian, state);
        let d_scattering_optical_depth =
            jacobian::get(layer.scattering_optical_depth_jacobian, state);
        let d_single_scatter_albedo = jacobian::get(layer.single_scatter_albedo_jacobian, state);
        if d_optical_depth == 0.0
            && d_scattering_optical_depth == 0.0
            && d_single_scatter_albedo == 0.0
        {
            continue;
        }

        let mut plus_layer = layer;
        plus_layer.optical_depth = (layer.optical_depth + eps * d_optical_depth).max(0.0);
        plus_layer.scattering_optical_depth =
            (layer.scattering_optical_depth + eps * d_scattering_optical_depth).max(0.0);
        plus_layer.single_scatter_albedo =
            (layer.single_scatter_albedo + eps * d_single_scatter_albedo).clamp(0.0, 1.0);

        let mut minus_layer = layer;
        minus_layer.optical_depth = (layer.optical_depth - eps * d_optical_depth).max(0.0);
        minus_layer.scattering_optical_depth =
            (layer.scattering_optical_depth - eps * d_scattering_optical_depth).max(0.0);
        minus_layer.single_scatter_albedo =
            (layer.single_scatter_albedo - eps * d_single_scatter_albedo).clamp(0.0, 1.0);

        let mut plus_rt = [zero_layer_rt(geo.nmutot); 2];
        let mut minus_rt = [zero_layer_rt(geo.nmutot); 2];
        calc_rt_layers_into_with_basis(
            &mut plus_rt,
            &[plus_layer],
            i_fourier,
            geo,
            controls,
            plm_basis,
            None,
            None,
            None,
            None,
            None,
        );
        calc_rt_layers_into_with_basis(
            &mut minus_rt,
            &[minus_layer],
            i_fourier,
            geo,
            controls,
            plm_basis,
            None,
            None,
            None,
            None,
            None,
        );
        rt_tangent[layer_idx + 1] = layer_rt_difference_scaled(plus_rt[1], minus_rt[1], inv_span);
    }
}

fn layer_rt_difference_scaled(plus: LayerRt, minus: LayerRt, scale: f64) -> LayerRt {
    LayerRt {
        r: mat_difference_scaled(plus.r, minus.r, scale),
        t: mat_difference_scaled(plus.t, minus.t, scale),
    }
}

fn mat_difference_scaled(plus: Mat, minus: Mat, scale: f64) -> Mat {
    let mut result = Mat::zero(plus.n);
    for index in 0..plus.n * plus.n {
        result.data[index] = (plus.data[index] - minus.data[index]) * scale;
    }
    result
}

fn zero_layer_rt(n: usize) -> LayerRt {
    LayerRt {
        r: Mat::zero(n),
        t: Mat::zero(n),
    }
}

pub fn calc_rt_layers_into(
    rt: &mut [LayerRt],
    layers: &[LayerInput],
    i_fourier: usize,
    geo: &Geometry,
    controls: RadiativeTransferControls,
) {
    let plm_basis =
        FourierPlmBasis::init(i_fourier, max_layer_phase_coefficient_index(layers), geo);
    calc_rt_layers_into_with_basis(
        rt, layers, i_fourier, geo, controls, &plm_basis, None, None, None, None, None,
    );
}

pub fn calc_rt_layers(
    layers: &[LayerInput],
    i_fourier: usize,
    geo: &Geometry,
    controls: RadiativeTransferControls,
) -> std::vec::Vec<LayerRt> {
    let mut rt = vec![zero_layer_rt(geo.nmutot); layers.len() + 1];
    calc_rt_layers_into(&mut rt, layers, i_fourier, geo, controls);
    rt
}

pub fn fill_surface(i_fourier: usize, albedo: f64, geo: &Geometry) -> LayerRt {
    let n = geo.nmutot;
    let mut result = zero_layer_rt(n);
    if i_fourier == 0 {
        for j in 0..n {
            for i in 0..n {
                result.r.set(i, j, geo.w[i] * albedo * geo.w[j]);
            }
        }
    }
    result
}
