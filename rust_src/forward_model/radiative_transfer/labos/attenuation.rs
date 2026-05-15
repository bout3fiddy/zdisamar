use std::vec::Vec as StdVec;

use super::types::{Geometry, MAX_NMUTOT};
use crate::forward_model::radiative_transfer::common_types::{LayerInput, PseudoSphericalGrid};

#[derive(Debug, Clone, PartialEq)]
pub struct AttenArray {
    pub data: [[[f64; Self::MAX_LEVELS]; Self::MAX_LEVELS]; MAX_NMUTOT],
    pub nmutot: usize,
    pub nlayer: usize,
}

impl AttenArray {
    pub const MAX_LEVELS: usize = 65;

    pub fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.data[imu][from][to]
    }

    fn set(&mut self, imu: usize, from: usize, to: usize, value: f64) {
        self.data[imu][from][to] = value;
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DynamicAttenArray {
    pub data: StdVec<f64>,
    pub nmutot: usize,
    pub nlevel: usize,
}

impl DynamicAttenArray {
    pub fn new(nmutot: usize, nlevel: usize) -> Self {
        Self {
            data: vec![1.0; nmutot * nlevel * nlevel],
            nmutot,
            nlevel,
        }
    }

    fn index(&self, imu: usize, from: usize, to: usize) -> usize {
        (imu * self.nlevel + from) * self.nlevel + to
    }

    pub fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.data[self.index(imu, from, to)]
    }

    pub fn set(&mut self, imu: usize, from: usize, to: usize, value: f64) {
        let index = self.index(imu, from, to);
        self.data[index] = value;
    }
}

fn layer_transmittance_index(nlayer: usize, imu: usize, layer_index: usize) -> usize {
    imu * nlayer + layer_index
}

fn fill_layer_transmittance(
    layer_transmittance: &mut [f64],
    layers: &[LayerInput],
    geometry: &Geometry,
) {
    let nlayer = layers.len();
    debug_assert!(layer_transmittance.len() >= geometry.nmutot * nlayer);
    for imu in 0..geometry.nmutot {
        let u = geometry.u[imu].max(1.0e-6);
        for (layer_index, layer) in layers.iter().enumerate() {
            layer_transmittance[layer_transmittance_index(nlayer, imu, layer_index)] =
                (-layer.optical_depth / u).exp();
        }
    }
}

fn pseudo_spherical_direction_cosine(geometry: &Geometry, layer: &LayerInput, imu: usize) -> f64 {
    if imu == geometry.view_idx() {
        return layer.view_mu;
    }
    if imu == geometry.n_gauss + 1 {
        return layer.solar_mu;
    }
    geometry.u[imu]
}

fn apply_pseudo_spherical_top_level_attenuation(
    attenuation: &mut AttenArray,
    layers: &[LayerInput],
    geometry: &Geometry,
) {
    let top_level = layers.len();
    for imu in 0..geometry.nmutot {
        let mut cumulative = 1.0;
        attenuation.set(imu, top_level, top_level, 1.0);
        let mut level = top_level;
        while level > 0 {
            level -= 1;
            let u = pseudo_spherical_direction_cosine(geometry, &layers[level], imu).max(1.0e-6);
            cumulative *= (-layers[level].optical_depth / u).exp();
            attenuation.set(imu, top_level, level, cumulative);
        }
    }
}

fn apply_pseudo_spherical_top_level_attenuation_dynamic(
    attenuation: &mut DynamicAttenArray,
    layers: &[LayerInput],
    geometry: &Geometry,
) {
    let top_level = layers.len();
    for imu in 0..geometry.nmutot {
        let mut cumulative = 1.0;
        attenuation.set(imu, top_level, top_level, 1.0);
        let mut level = top_level;
        while level > 0 {
            level -= 1;
            let u = pseudo_spherical_direction_cosine(geometry, &layers[level], imu).max(1.0e-6);
            cumulative *= (-layers[level].optical_depth / u).exp();
            attenuation.set(imu, top_level, level, cumulative);
        }
    }
}

fn level_altitude_from_pseudo_spherical_grid(
    pseudo_spherical_grid: &PseudoSphericalGrid,
    level: usize,
) -> f64 {
    if !pseudo_spherical_grid.level_altitudes_km.is_empty() {
        return pseudo_spherical_grid.level_altitudes_km[level];
    }
    if level == 0 {
        let first = pseudo_spherical_grid.samples[0];
        return (first.altitude_km - 0.5 * first.thickness_km).max(0.0);
    }

    let start_index = pseudo_spherical_grid.level_sample_starts[level];
    if start_index >= pseudo_spherical_grid.samples.len() {
        let last = pseudo_spherical_grid.samples[pseudo_spherical_grid.samples.len() - 1];
        return (last.altitude_km + 0.5 * last.thickness_km).max(0.0);
    }

    let sample = pseudo_spherical_grid.samples[start_index];
    (sample.altitude_km - 0.5 * sample.thickness_km).max(0.0)
}

fn apply_pseudo_spherical_top_level_attenuation_dynamic_with_grid(
    attenuation: &mut DynamicAttenArray,
    pseudo_spherical_grid: &PseudoSphericalGrid,
    geometry: &Geometry,
) {
    let earth_radius_km = 6371.0;
    let top_level = pseudo_spherical_grid.level_sample_starts.len() - 1;
    for imu in 0..geometry.nmutot {
        let u = geometry.u[imu].clamp(-1.0, 1.0);
        let sin2theta = (1.0 - u * u).max(0.0);
        attenuation.set(imu, top_level, top_level, 1.0);
        let mut level = top_level;
        while level > 0 {
            level -= 1;
            let level_radius = earth_radius_km
                + level_altitude_from_pseudo_spherical_grid(pseudo_spherical_grid, level);
            let sqrx_sin2theta = sin2theta * level_radius * level_radius;
            let mut sumkext = 0.0;
            for index in pseudo_spherical_grid.level_sample_starts[level]
                ..pseudo_spherical_grid.samples.len()
            {
                let sample = pseudo_spherical_grid.samples[index];
                if sample.optical_depth <= 0.0 {
                    continue;
                }
                let sample_radius = earth_radius_km + sample.altitude_km;
                let denominator = (sample_radius * sample_radius - sqrx_sin2theta)
                    .abs()
                    .sqrt();
                let numerator = sample.optical_depth * sample_radius;
                sumkext += numerator / denominator.max(1.0e-12);
            }
            attenuation.set(imu, top_level, level, (-sumkext).exp());
        }
    }
}

pub fn fill_attenuation(
    layers: &[LayerInput],
    geometry: &Geometry,
    use_spherical_correction: bool,
) -> AttenArray {
    let nlayer = layers.len();
    let mut attenuation = AttenArray {
        data: [[[1.0; AttenArray::MAX_LEVELS]; AttenArray::MAX_LEVELS]; MAX_NMUTOT],
        nmutot: geometry.nmutot,
        nlayer,
    };

    for il_to_0 in 0..nlayer {
        let il_to = il_to_0 + 1;
        let mut il_from_idx = il_to;
        while il_from_idx >= 1 {
            let layer_idx = il_from_idx - 1;
            for imu in 0..geometry.nmutot {
                let u = geometry.u[imu].max(1.0e-6);
                let atten_lay = (-layers[layer_idx].optical_depth / u).exp();
                let value = attenuation.get(imu, il_from_idx, il_to) * atten_lay;
                attenuation.set(imu, il_from_idx - 1, il_to, value);
            }
            il_from_idx -= 1;
        }
    }

    for il_to in 0..nlayer + 1 {
        for il_from in il_to..nlayer + 1 {
            for imu in 0..geometry.nmutot {
                attenuation.set(imu, il_from, il_to, attenuation.get(imu, il_to, il_from));
            }
        }
    }

    if use_spherical_correction {
        apply_pseudo_spherical_top_level_attenuation(&mut attenuation, layers, geometry);
    }

    attenuation
}

pub fn fill_attenuation_dynamic(
    layers: &[LayerInput],
    geometry: &Geometry,
    use_spherical_correction: bool,
) -> DynamicAttenArray {
    fill_attenuation_dynamic_with_grid(
        layers,
        &PseudoSphericalGrid::default(),
        geometry,
        use_spherical_correction,
    )
}

pub fn fill_attenuation_dynamic_with_grid(
    layers: &[LayerInput],
    pseudo_spherical_grid: &PseudoSphericalGrid,
    geometry: &Geometry,
    use_spherical_correction: bool,
) -> DynamicAttenArray {
    let nlayer = layers.len();
    let nlevel = nlayer + 1;
    let mut layer_transmittance = vec![0.0; geometry.nmutot * nlayer];
    fill_layer_transmittance(&mut layer_transmittance, layers, geometry);
    let mut attenuation = DynamicAttenArray {
        data: vec![0.0; geometry.nmutot * nlevel * nlevel],
        nmutot: geometry.nmutot,
        nlevel,
    };
    for imu in 0..geometry.nmutot {
        for level in 0..nlevel {
            attenuation.set(imu, level, level, 1.0);
        }
    }

    for il_to_0 in 0..nlayer {
        let il_to = il_to_0 + 1;
        let mut il_from_idx = il_to;
        while il_from_idx >= 1 {
            let layer_idx = il_from_idx - 1;
            for imu in 0..geometry.nmutot {
                let atten_lay =
                    layer_transmittance[layer_transmittance_index(nlayer, imu, layer_idx)];
                let value = attenuation.get(imu, il_from_idx, il_to) * atten_lay;
                attenuation.set(imu, il_from_idx - 1, il_to, value);
            }
            il_from_idx -= 1;
        }
    }

    for il_to in 0..nlevel {
        for il_from in il_to..nlevel {
            for imu in 0..geometry.nmutot {
                attenuation.set(imu, il_from, il_to, attenuation.get(imu, il_to, il_from));
            }
        }
    }

    if use_spherical_correction {
        if pseudo_spherical_grid.is_valid_for(nlayer) {
            apply_pseudo_spherical_top_level_attenuation_dynamic_with_grid(
                &mut attenuation,
                pseudo_spherical_grid,
                geometry,
            );
        } else {
            apply_pseudo_spherical_top_level_attenuation_dynamic(
                &mut attenuation,
                layers,
                geometry,
            );
        }
    }

    attenuation
}
