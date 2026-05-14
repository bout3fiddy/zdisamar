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
        let mut m = Self::zero(n);
        for i in 0..n {
            m.set(i, i, 1.0);
        }
        m
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
    pub fn init(n_gauss: usize, mu0: f64, muv: f64) -> Result<Self, gauss_legendre::Error> {
        let mut nodes_01 = [0.0; MAX_GAUSS];
        let mut weights_01 = [0.0; MAX_GAUSS];
        gauss_legendre::fill_disamar_div_points_01(n_gauss as u32, &mut nodes_01, &mut weights_01)?;

        let mut geo = Self {
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
            geo.u[i] = ug;
            // LABOS stores sqrt-weighted ordinates because later matrix assembly uses w_i w_j products often.
            geo.w[i] = (2.0 * ug * wg).sqrt();
            geo.ug[i] = ug;
            geo.wg[i] = wg;
        }
        geo.u[n_gauss] = muv;
        geo.w[n_gauss] = 1.0;
        geo.u[n_gauss + 1] = mu0;
        geo.w[n_gauss + 1] = 1.0;

        for j in 0..geo.nmutot {
            let uj = geo.u[j];
            for i in 0..geo.nmutot {
                let ui = geo.u[i];
                let idx = i * geo.nmutot + j;
                geo.dmu_plus[idx] = 0.25 / (ui + uj).max(1.0e-12);
                let du = ui - uj;
                if du.abs() < 1.0e-6 {
                    geo.dmu_same[idx] = true;
                    geo.dmu_min[idx] = 0.25 / (ui * uj).max(1.0e-12);
                } else {
                    geo.dmu_same[idx] = false;
                    geo.dmu_min[idx] = 0.25 / du;
                }
            }
        }
        Ok(geo)
    }

    pub fn view_idx(&self) -> usize {
        self.n_gauss
    }
}
