use crate::forward_model::{
    jacobian::{self, State},
    radiative_transfer::{LayerInput, PseudoSphericalGrid},
};

use super::types::{Geometry, MAX_NMUTOT};

pub const MAX_LEVELS: usize = 65;

#[derive(Debug, Clone, PartialEq)]
pub struct AttenArray {
    pub data: [f64; MAX_NMUTOT * MAX_LEVELS * MAX_LEVELS],
    pub nmutot: usize,
    pub nlayer: usize,
}

impl AttenArray {
    pub fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.data[self.index(imu, from, to)]
    }

    fn set(&mut self, imu: usize, from: usize, to: usize, value: f64) {
        let index = self.index(imu, from, to);
        self.data[index] = value;
    }

    fn index(&self, imu: usize, from: usize, to: usize) -> usize {
        (imu * MAX_LEVELS + from) * MAX_LEVELS + to
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct DynamicAttenArray {
    pub data: std::vec::Vec<f64>,
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

pub fn fill_attenuation(
    layers: &[LayerInput],
    geo: &Geometry,
    use_spherical_correction: bool,
) -> AttenArray {
    let nlayer = layers.len();
    let mut atten = AttenArray {
        data: [1.0; MAX_NMUTOT * MAX_LEVELS * MAX_LEVELS],
        nmutot: geo.nmutot,
        nlayer,
    };

    for il_to_0 in 0..nlayer {
        let il_to = il_to_0 + 1;
        for il_from_idx in (1..=il_to).rev() {
            let layer_idx = il_from_idx - 1;
            for imu in 0..geo.nmutot {
                let u = geo.u[imu].max(1.0e-6);
                let atten_lay = (-layers[layer_idx].optical_depth / u).exp();
                let value = atten.get(imu, il_from_idx, il_to) * atten_lay;
                atten.set(imu, il_from_idx - 1, il_to, value);
            }
        }
    }

    mirror_levels_static(&mut atten, nlayer + 1, geo.nmutot);
    if use_spherical_correction {
        apply_pseudo_spherical_top_level_attenuation(&mut atten, layers, geo);
    }
    atten
}

pub fn fill_attenuation_dynamic(
    layers: &[LayerInput],
    geo: &Geometry,
    use_spherical_correction: bool,
) -> DynamicAttenArray {
    fill_attenuation_dynamic_with_grid(
        layers,
        &PseudoSphericalGrid::default(),
        geo,
        use_spherical_correction,
    )
}

pub fn fill_attenuation_dynamic_with_grid(
    layers: &[LayerInput],
    pseudo_spherical_grid: &PseudoSphericalGrid,
    geo: &Geometry,
    use_spherical_correction: bool,
) -> DynamicAttenArray {
    let mut atten = DynamicAttenArray::new(geo.nmutot, layers.len() + 1);
    fill_attenuation_dynamic_in_place(
        &mut atten,
        layers,
        pseudo_spherical_grid,
        geo,
        use_spherical_correction,
    );
    atten
}

pub fn fill_attenuation_tangent_dynamic(
    layers: &[LayerInput],
    state: State,
    geo: &Geometry,
) -> DynamicAttenArray {
    let nlayer = layers.len();
    let nlevel = nlayer + 1;
    let mut atten = DynamicAttenArray {
        data: vec![0.0; geo.nmutot * nlevel * nlevel],
        nmutot: geo.nmutot,
        nlevel,
    };

    for il_to_0 in 0..nlayer {
        let il_to = il_to_0 + 1;
        for il_from_idx in (1..=il_to).rev() {
            let layer_idx = il_from_idx - 1;
            for imu in 0..geo.nmutot {
                let u = geo.u[imu].max(1.0e-6);
                let trans = (-layers[layer_idx].optical_depth / u).exp();
                let dtrans =
                    trans * (-jacobian::get(layers[layer_idx].optical_depth_jacobian, state) / u);
                let value = atten.get(imu, il_from_idx, il_to) * trans
                    + cumulative_base_transmittance(layers, geo, imu, il_from_idx, il_to) * dtrans;
                atten.set(imu, il_from_idx - 1, il_to, value);
            }
        }
    }

    mirror_levels_dynamic(&mut atten, nlevel, geo.nmutot);
    atten
}

fn fill_attenuation_dynamic_in_place(
    atten: &mut DynamicAttenArray,
    layers: &[LayerInput],
    pseudo_spherical_grid: &PseudoSphericalGrid,
    geo: &Geometry,
    use_spherical_correction: bool,
) {
    let nlayer = layers.len();
    let nlevel = nlayer + 1;
    atten.data.fill(1.0);
    for imu in 0..geo.nmutot {
        for level in 0..nlevel {
            atten.set(imu, level, level, 1.0);
        }
    }

    let mut layer_transmittance = vec![0.0; geo.nmutot * nlayer];
    fill_layer_transmittance(&mut layer_transmittance, layers, geo);
    for il_to_0 in 0..nlayer {
        let il_to = il_to_0 + 1;
        for il_from_idx in (1..=il_to).rev() {
            let layer_idx = il_from_idx - 1;
            for imu in 0..geo.nmutot {
                let atten_lay =
                    layer_transmittance[layer_transmittance_index(nlayer, imu, layer_idx)];
                let value = atten.get(imu, il_from_idx, il_to) * atten_lay;
                atten.set(imu, il_from_idx - 1, il_to, value);
            }
        }
    }

    mirror_levels_dynamic(atten, nlevel, geo.nmutot);
    if use_spherical_correction {
        if pseudo_spherical_grid.is_valid_for(nlayer) {
            apply_pseudo_spherical_top_level_attenuation_dynamic_with_grid(
                atten,
                pseudo_spherical_grid,
                geo,
            );
        } else {
            apply_pseudo_spherical_top_level_attenuation_dynamic(atten, layers, geo);
        }
    }
}

fn layer_transmittance_index(nlayer: usize, imu: usize, layer_index: usize) -> usize {
    imu * nlayer + layer_index
}

fn fill_layer_transmittance(
    layer_transmittance: &mut [f64],
    layers: &[LayerInput],
    geo: &Geometry,
) {
    let nlayer = layers.len();
    for imu in 0..geo.nmutot {
        let u = geo.u[imu].max(1.0e-6);
        for (layer_index, layer) in layers.iter().enumerate() {
            layer_transmittance[layer_transmittance_index(nlayer, imu, layer_index)] =
                (-layer.optical_depth / u).exp();
        }
    }
}

fn pseudo_spherical_direction_cosine(geo: &Geometry, layer: &LayerInput, imu: usize) -> f64 {
    if imu == geo.view_idx() {
        return layer.view_mu;
    }
    if imu == geo.n_gauss + 1 {
        return layer.solar_mu;
    }
    geo.u[imu]
}

fn apply_pseudo_spherical_top_level_attenuation(
    atten: &mut AttenArray,
    layers: &[LayerInput],
    geo: &Geometry,
) {
    let top_level = layers.len();
    for imu in 0..geo.nmutot {
        let mut cumulative = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        for level in (0..top_level).rev() {
            let u = pseudo_spherical_direction_cosine(geo, &layers[level], imu).max(1.0e-6);
            cumulative *= (-layers[level].optical_depth / u).exp();
            atten.set(imu, top_level, level, cumulative);
        }
    }
}

fn apply_pseudo_spherical_top_level_attenuation_dynamic(
    atten: &mut DynamicAttenArray,
    layers: &[LayerInput],
    geo: &Geometry,
) {
    let top_level = layers.len();
    for imu in 0..geo.nmutot {
        let mut cumulative = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        for level in (0..top_level).rev() {
            let u = pseudo_spherical_direction_cosine(geo, &layers[level], imu).max(1.0e-6);
            cumulative *= (-layers[level].optical_depth / u).exp();
            atten.set(imu, top_level, level, cumulative);
        }
    }
}

fn apply_pseudo_spherical_top_level_attenuation_dynamic_with_grid(
    atten: &mut DynamicAttenArray,
    pseudo_spherical_grid: &PseudoSphericalGrid,
    geo: &Geometry,
) {
    let rearth_km = 6371.0;
    let top_level = pseudo_spherical_grid.level_sample_starts.len() - 1;
    for imu in 0..geo.nmutot {
        let u = geo.u[imu].clamp(-1.0, 1.0);
        let sin2theta = (1.0 - u * u).max(0.0);
        atten.set(imu, top_level, top_level, 1.0);
        for level in (0..top_level).rev() {
            let level_radius =
                rearth_km + level_altitude_from_pseudo_spherical_grid(pseudo_spherical_grid, level);
            let sqrx_sin2theta = sin2theta * level_radius * level_radius;
            let mut sumkext = 0.0;
            for index in pseudo_spherical_grid.level_sample_starts[level]
                ..pseudo_spherical_grid.samples.len()
            {
                let sample = pseudo_spherical_grid.samples[index];
                if sample.optical_depth <= 0.0 {
                    continue;
                }
                let sample_radius = rearth_km + sample.altitude_km;
                let denominator = (sample_radius * sample_radius - sqrx_sin2theta)
                    .abs()
                    .sqrt();
                let numerator = sample.optical_depth * sample_radius;
                sumkext += numerator / denominator.max(1.0e-12);
            }
            atten.set(imu, top_level, level, (-sumkext).exp());
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

fn cumulative_base_transmittance(
    layers: &[LayerInput],
    geo: &Geometry,
    imu: usize,
    from_level: usize,
    to_level: usize,
) -> f64 {
    if from_level >= to_level {
        return 1.0;
    }
    let u = geo.u[imu].max(1.0e-6);
    let mut value = 1.0;
    for layer_idx in from_level..to_level {
        if layer_idx >= layers.len() {
            break;
        }
        value *= (-layers[layer_idx].optical_depth / u).exp();
    }
    value
}

fn mirror_levels_static(atten: &mut AttenArray, nlevel: usize, nmutot: usize) {
    for il_to in 0..nlevel {
        for il_from in il_to..nlevel {
            for imu in 0..nmutot {
                let value = atten.get(imu, il_to, il_from);
                atten.set(imu, il_from, il_to, value);
            }
        }
    }
}

fn mirror_levels_dynamic(atten: &mut DynamicAttenArray, nlevel: usize, nmutot: usize) {
    for il_to in 0..nlevel {
        for il_from in il_to..nlevel {
            for imu in 0..nmutot {
                let value = atten.get(imu, il_to, il_from);
                atten.set(imu, il_from, il_to, value);
            }
        }
    }
}
