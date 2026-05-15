use crate::{
    common::math::quadrature::gauss_legendre,
    forward_model::optical_properties::shared::phase_functions::PHASE_COEFFICIENT_COUNT,
};

pub const MAX_GAUSS: usize = 10;
pub const MAX_EXTRA: usize = 2;
pub const MAX_NMUTOT: usize = MAX_GAUSS + MAX_EXTRA;
pub const MAX_N2: usize = MAX_NMUTOT * MAX_NMUTOT;
pub const MAX_PHASE_COEF: usize = PHASE_COEFFICIENT_COUNT;

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Mat {
    pub data: [f64; MAX_N2],
    pub n: usize,
}

impl Mat {
    pub fn zero(n: usize) -> Self {
        Self {
            data: [0.0; MAX_N2],
            n,
        }
    }

    pub fn identity(n: usize) -> Self {
        let mut matrix = Self::zero(n);
        for i in 0..n {
            matrix.set(i, i, 1.0);
        }
        matrix
    }

    pub fn get(&self, i: usize, j: usize) -> f64 {
        self.data[i * self.n + j]
    }

    pub fn set(&mut self, i: usize, j: usize, val: f64) {
        self.data[i * self.n + j] = val;
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec {
    pub data: [f64; MAX_NMUTOT],
    pub n: usize,
}

impl Vec {
    pub fn zero(n: usize) -> Self {
        Self {
            data: [0.0; MAX_NMUTOT],
            n,
        }
    }

    pub fn get(&self, i: usize) -> f64 {
        self.data[i]
    }

    pub fn set(&mut self, i: usize, val: f64) {
        self.data[i] = val;
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Vec2 {
    pub col: [Vec; 2],
    pub n: usize,
}

impl Vec2 {
    pub fn zero(n: usize) -> Self {
        Self {
            col: [Vec::zero(n), Vec::zero(n)],
            n,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LayerRt {
    pub r: Mat,
    pub t: Mat,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UdField {
    pub e: Vec,
    pub u: Vec2,
    pub d: Vec2,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct UdLocal {
    pub u: Vec2,
    pub d: Vec2,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct Geometry {
    pub n_gauss: usize,
    pub nmutot: usize,
    pub u: [f64; MAX_NMUTOT],
    pub w: [f64; MAX_NMUTOT],
    pub ug: [f64; MAX_GAUSS],
    pub wg: [f64; MAX_GAUSS],
    pub dmu_plus: [f64; MAX_N2],
    pub dmu_min: [f64; MAX_N2],
    pub dmu_same: [bool; MAX_N2],
    pub mu0: f64,
    pub muv: f64,
}

impl Geometry {
    pub fn init(n_gauss: usize, mu0: f64, muv: f64) -> Self {
        let mut nodes_01 = [0.0; MAX_GAUSS];
        let mut weights_01 = [0.0; MAX_GAUSS];
        gauss_legendre::fill_disamar_div_points_01(n_gauss as u32, &mut nodes_01, &mut weights_01)
            .expect("LABOS geometry requires a supported Gauss order");

        let mut geometry = Self {
            n_gauss,
            nmutot: n_gauss + MAX_EXTRA,
            u: [0.0; MAX_NMUTOT],
            w: [0.0; MAX_NMUTOT],
            ug: [0.0; MAX_GAUSS],
            wg: [0.0; MAX_GAUSS],
            dmu_plus: [0.0; MAX_N2],
            dmu_min: [0.0; MAX_N2],
            dmu_same: [false; MAX_N2],
            mu0,
            muv,
        };

        for i in 0..n_gauss {
            let ug = nodes_01[i];
            let wg = weights_01[i];
            geometry.u[i] = ug;
            geometry.w[i] = (2.0 * ug * wg).sqrt();
            geometry.ug[i] = ug;
            geometry.wg[i] = wg;
        }
        // LABOS treats the user view and direct solar cosines as two extra
        // directions after the Gauss streams, so fixed arrays can serve both
        // matrix transport and source terms without reallocating.
        geometry.u[n_gauss] = muv;
        geometry.w[n_gauss] = 1.0;
        geometry.u[n_gauss + 1] = mu0;
        geometry.w[n_gauss + 1] = 1.0;

        for j in 0..geometry.nmutot {
            let uj = geometry.u[j];
            for i in 0..geometry.nmutot {
                let ui = geometry.u[i];
                let idx = i * geometry.nmutot + j;
                geometry.dmu_plus[idx] = 0.25 / (ui + uj).max(1.0e-12);
                let du = ui - uj;
                if du.abs() < 1.0e-6 {
                    geometry.dmu_same[idx] = true;
                    geometry.dmu_min[idx] = 0.25 / (ui * uj).max(1.0e-12);
                } else {
                    geometry.dmu_min[idx] = 0.25 / du;
                }
            }
        }
        geometry
    }

    pub fn view_idx(&self) -> usize {
        self.n_gauss
    }
}
