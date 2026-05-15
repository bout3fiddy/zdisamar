use std::{hash::Hasher, vec::Vec as StdVec};

use wyhash::WyHash;

use super::{
    attenuation::{DynamicAttenArray, fill_attenuation_dynamic_with_grid},
    orders::OrdersWorkspace,
    phase_basis::{FourierPlmBasis, PhaseKernel},
    reflectance::fill_adjacent_layer_phase_max_indices,
    types::{Geometry, LayerRt, MAX_NMUTOT, MAX_PHASE_COEF, Mat},
};
use crate::forward_model::{
    optical_properties::shared::phase_functions::PhaseCoefficients,
    radiative_transfer::common_types::{LayerInput, PseudoSphericalGrid},
};

#[derive(Debug, Clone, PartialEq)]
pub struct Workspace {
    pub attenuation_data: StdVec<f64>,
    pub attenuation_layer_transmittance: StdVec<f64>,
    pub rt_layers: StdVec<LayerRt>,
    pub layer_phase_max_indices: StdVec<usize>,
    pub layer_effective_scattering_suffix: StdVec<f64>,
    pub source_phase_max_indices: StdVec<usize>,
    pub orders: Option<OrdersWorkspace>,
    pub layer_phase_kernels: StdVec<PhaseKernel>,
    pub layer_phase_kernel_valid: StdVec<bool>,
    pub plm_basis_cache: StdVec<FourierPlmBasis>,
    pub plm_basis_cache_valid: StdVec<bool>,
    pub previous_layer_phase_signatures: StdVec<u64>,
    pub previous_layer_phase_signature_valid: StdVec<bool>,
    pub cached_geometry: Option<Geometry>,
}

impl Workspace {
    pub fn new() -> Self {
        Self {
            attenuation_data: StdVec::new(),
            attenuation_layer_transmittance: StdVec::new(),
            rt_layers: StdVec::new(),
            layer_phase_max_indices: StdVec::new(),
            layer_effective_scattering_suffix: StdVec::new(),
            source_phase_max_indices: StdVec::new(),
            orders: None,
            layer_phase_kernels: StdVec::new(),
            layer_phase_kernel_valid: StdVec::new(),
            plm_basis_cache: StdVec::new(),
            plm_basis_cache_valid: StdVec::new(),
            previous_layer_phase_signatures: StdVec::new(),
            previous_layer_phase_signature_valid: StdVec::new(),
            cached_geometry: None,
        }
    }

    pub fn attenuation(
        &mut self,
        layers: &[LayerInput],
        pseudo_spherical_grid: &PseudoSphericalGrid,
        geometry: &Geometry,
        use_spherical_correction: bool,
    ) -> DynamicAttenArray {
        let nlevel = layers.len() + 1;
        self.attenuation_data
            .resize(geometry.nmutot * nlevel * nlevel, 0.0);
        self.attenuation_layer_transmittance
            .resize(geometry.nmutot * layers.len(), 0.0);
        fill_attenuation_dynamic_with_grid(
            layers,
            pseudo_spherical_grid,
            geometry,
            use_spherical_correction,
        )
    }

    pub fn geometry(&mut self, n_gauss: usize, mu0: f64, muv: f64) -> &Geometry {
        self.geometry_with_status(n_gauss, mu0, muv).geometry
    }

    pub fn geometry_with_status(
        &mut self,
        n_gauss: usize,
        mu0: f64,
        muv: f64,
    ) -> GeometryCacheStatus<'_> {
        let hit = self.cached_geometry.is_some_and(|geometry| {
            geometry.n_gauss == n_gauss && geometry.mu0 == mu0 && geometry.muv == muv
        });
        if !hit {
            self.cached_geometry = Some(Geometry::init(n_gauss, mu0, muv));
            self.plm_basis_cache_valid.fill(false);
            self.previous_layer_phase_signature_valid.fill(false);
        }
        GeometryCacheStatus {
            geometry: self
                .cached_geometry
                .as_ref()
                .expect("geometry cache is initialized"),
            hit,
        }
    }

    pub fn layer_rt(&mut self, nlevel: usize) -> &mut [LayerRt] {
        self.rt_layers.resize(nlevel, zero_layer_rt());
        &mut self.rt_layers[..nlevel]
    }

    pub fn layer_phase_max_indices(&mut self, nlayer: usize) -> &mut [usize] {
        self.layer_phase_max_indices.resize(nlayer, 0);
        &mut self.layer_phase_max_indices[..nlayer]
    }

    pub fn layer_effective_scattering_suffix(&mut self, nlayer: usize) -> &mut [f64] {
        let required_len = nlayer * MAX_PHASE_COEF;
        self.layer_effective_scattering_suffix
            .resize(required_len, 0.0);
        &mut self.layer_effective_scattering_suffix[..required_len]
    }

    pub fn source_phase_max_indices(&mut self, nlevel: usize) -> &mut [usize] {
        self.source_phase_max_indices.resize(nlevel, 0);
        &mut self.source_phase_max_indices[..nlevel]
    }

    pub fn fill_source_phase_max_indices_from_layers(
        &mut self,
        layer_phase_max_indices: &[usize],
    ) -> &mut [usize] {
        let nlevel = layer_phase_max_indices.len() + 1;
        let source_phase_max_indices = self.source_phase_max_indices(nlevel);
        fill_adjacent_layer_phase_max_indices(source_phase_max_indices, layer_phase_max_indices);
        source_phase_max_indices
    }

    pub fn orders_workspace(&mut self, nlevel: usize) -> &mut OrdersWorkspace {
        let needs_replace = self
            .orders
            .as_ref()
            .is_none_or(|orders| orders.ud.len() < nlevel);
        if needs_replace {
            self.orders = Some(OrdersWorkspace::new(nlevel));
        }
        self.orders
            .as_mut()
            .expect("orders workspace is initialized")
    }

    pub fn phase_kernel_cache(&mut self, nlevel: usize) -> &mut [PhaseKernel] {
        self.layer_phase_kernels.resize(nlevel, zero_phase_kernel());
        &mut self.layer_phase_kernels[..nlevel]
    }

    pub fn phase_kernel_valid(&mut self, nlevel: usize) -> &mut [bool] {
        self.layer_phase_kernel_valid.resize(nlevel, false);
        &mut self.layer_phase_kernel_valid[..nlevel]
    }

    pub fn fourier_plm_basis(
        &mut self,
        i_fourier: usize,
        max_phase_index: usize,
        geometry: &Geometry,
    ) -> &FourierPlmBasis {
        self.fourier_plm_basis_with_status(i_fourier, max_phase_index, geometry)
            .plm_basis
    }

    pub fn fourier_plm_basis_with_status(
        &mut self,
        i_fourier: usize,
        max_phase_index: usize,
        geometry: &Geometry,
    ) -> PlmBasisCacheStatus<'_> {
        assert!(i_fourier < MAX_PHASE_COEF);
        let previous_cache_len = self.plm_basis_cache.len();
        let previous_valid_len = self.plm_basis_cache_valid.len();
        self.plm_basis_cache
            .resize_with(MAX_PHASE_COEF, empty_plm_basis);
        self.plm_basis_cache_valid.resize(MAX_PHASE_COEF, false);
        if previous_cache_len < MAX_PHASE_COEF || previous_valid_len < MAX_PHASE_COEF {
            self.plm_basis_cache_valid.fill(false);
        }

        let was_valid = self.plm_basis_cache_valid[i_fourier];
        let needs_extend =
            was_valid && self.plm_basis_cache[i_fourier].max_phase_index < max_phase_index;
        if !was_valid || needs_extend {
            self.plm_basis_cache[i_fourier] =
                FourierPlmBasis::init(i_fourier, max_phase_index, geometry);
            self.plm_basis_cache_valid[i_fourier] = true;
        }

        PlmBasisCacheStatus {
            plm_basis: &self.plm_basis_cache[i_fourier],
            hit: was_valid && !needs_extend,
            extended: needs_extend,
        }
    }

    pub fn probe_layer_phase_signatures(
        &mut self,
        layers: &[LayerInput],
        layer_phase_max_indices: &[usize],
        fourier_max: usize,
    ) -> LayerPhaseSignatureProbe {
        assert!(layer_phase_max_indices.len() >= layers.len());
        self.previous_layer_phase_signatures.resize(layers.len(), 0);
        let previous_valid_len = self.previous_layer_phase_signature_valid.len();
        self.previous_layer_phase_signature_valid
            .resize(layers.len(), false);
        if previous_valid_len < layers.len() {
            self.previous_layer_phase_signature_valid.fill(false);
        }

        let mut probe = LayerPhaseSignatureProbe {
            layer_count: layers.len(),
            ..LayerPhaseSignatureProbe::default()
        };
        for (layer_idx, layer) in layers.iter().enumerate() {
            let max_index = layer_phase_max_indices[layer_idx];
            let signature = layer_phase_signature(&layer.phase_coefficients, max_index);
            let possible_templates = max_index.min(fourier_max) + 1;
            probe.possible_fourier_layer_templates += possible_templates;

            if self.previous_layer_phase_signature_valid[layer_idx] {
                let previous_signature = self.previous_layer_phase_signatures[layer_idx];
                if signature_max_index(previous_signature) == max_index {
                    probe.max_index_matches += 1;
                }
                if previous_signature == signature {
                    probe.signature_matches += 1;
                    probe.reusable_fourier_layer_templates += possible_templates;
                }
            }

            self.previous_layer_phase_signatures[layer_idx] = signature;
            self.previous_layer_phase_signature_valid[layer_idx] = true;
        }
        probe
    }
}

impl Default for Workspace {
    fn default() -> Self {
        Self::new()
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct GeometryCacheStatus<'a> {
    pub geometry: &'a Geometry,
    pub hit: bool,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct PlmBasisCacheStatus<'a> {
    pub plm_basis: &'a FourierPlmBasis,
    pub hit: bool,
    pub extended: bool,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct LayerPhaseSignatureProbe {
    pub layer_count: usize,
    pub max_index_matches: usize,
    pub signature_matches: usize,
    pub reusable_fourier_layer_templates: usize,
    pub possible_fourier_layer_templates: usize,
}

fn zero_layer_rt() -> LayerRt {
    LayerRt {
        r: Mat::zero(0),
        t: Mat::zero(0),
    }
}

fn zero_phase_kernel() -> PhaseKernel {
    PhaseKernel {
        zplus: Mat::zero(0),
        zmin: Mat::zero(0),
    }
}

fn empty_plm_basis() -> FourierPlmBasis {
    FourierPlmBasis {
        i_fourier: 0,
        max_phase_index: 0,
        plus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
        minus: [[0.0; MAX_NMUTOT]; MAX_PHASE_COEF],
    }
}

fn layer_phase_signature(phase_coefficients: &PhaseCoefficients, max_index: usize) -> u64 {
    let mut hasher = WyHash::with_seed(0x9e37_79b9_7f4a_7c15);
    hasher.write(&max_index.to_ne_bytes());
    for coefficient in phase_coefficients.iter().take(max_index + 1) {
        let bits = coefficient.to_bits();
        hasher.write(&bits.to_ne_bytes());
    }
    ((max_index as u64) << 56) ^ (hasher.finish() & 0x00ff_ffff_ffff_ffff)
}

fn signature_max_index(signature: u64) -> usize {
    (signature >> 56) as usize
}
