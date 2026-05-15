use super::types::{Geometry, LayerRt, MAX_NMUTOT, MAX_PHASE_COEF, Mat};
use crate::forward_model::{
    optical_properties::shared::phase_functions, radiative_transfer::common_types::LayerInput,
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
