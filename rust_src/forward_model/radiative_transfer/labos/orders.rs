use super::{
    attenuation::{AttenArray, DynamicAttenArray},
    types::{Geometry, LayerRt, Mat, UdField, UdLocal, Vec as LabosVec, Vec2},
};

pub trait AttenuationAccess {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64;
}

impl AttenuationAccess for AttenArray {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.get(imu, from, to)
    }
}

impl AttenuationAccess for DynamicAttenArray {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.get(imu, from, to)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct OrdersResult {
    pub ud: std::vec::Vec<UdField>,
    pub ud_sum_local: std::vec::Vec<UdLocal>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OrdersResultView<'a> {
    pub ud: &'a [UdField],
    pub ud_sum_local: &'a [UdLocal],
}

#[derive(Debug, Clone, PartialEq)]
pub struct OrdersWorkspace {
    pub ud: std::vec::Vec<UdField>,
    pub ud_sum_local: std::vec::Vec<UdLocal>,
    pub ud_orde: std::vec::Vec<UdField>,
    pub ud_local: std::vec::Vec<UdLocal>,
    pub rt_active: std::vec::Vec<bool>,
}

impl OrdersWorkspace {
    pub fn new(nlevel: usize, nmutot: usize) -> Self {
        Self {
            ud: vec![zero_ud_field(nmutot); nlevel],
            ud_sum_local: vec![zero_ud_local(nmutot); nlevel],
            ud_orde: vec![zero_ud_field(nmutot); nlevel],
            ud_local: vec![zero_ud_local(nmutot); nlevel],
            rt_active: vec![false; nlevel],
        }
    }

    pub fn resize(&mut self, nlevel: usize, nmutot: usize) {
        self.ud.resize(nlevel, zero_ud_field(nmutot));
        self.ud_sum_local.resize(nlevel, zero_ud_local(nmutot));
        self.ud_orde.resize(nlevel, zero_ud_field(nmutot));
        self.ud_local.resize(nlevel, zero_ud_local(nmutot));
        self.rt_active.resize(nlevel, false);
        initialize_orders_buffers(
            true,
            &mut self.ud,
            &mut self.ud_sum_local,
            &mut self.ud_orde,
            &mut self.ud_local,
            nmutot,
        );
        self.rt_active.fill(false);
    }
}

pub fn zero_ud_field(nmutot: usize) -> UdField {
    UdField {
        e: LabosVec::zero(nmutot),
        u: Vec2::zero(nmutot),
        d: Vec2::zero(nmutot),
    }
}

pub fn zero_ud_local(nmutot: usize) -> UdLocal {
    UdLocal {
        u: Vec2::zero(nmutot),
        d: Vec2::zero(nmutot),
    }
}

pub fn transport_to_other_levels<A: AttenuationAccess>(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: &A,
    ud_local: &[UdLocal],
    ud_orde: &mut [UdField],
) {
    ud_orde[start_level].u = ud_local[start_level].u;
    for ilevel in start_level + 1..=end_level {
        let local_u0 = ud_local[ilevel].u.col[0].data;
        let local_u1 = ud_local[ilevel].u.col[1].data;
        let prev_u0 = ud_orde[ilevel - 1].u.col[0].data;
        let prev_u1 = ud_orde[ilevel - 1].u.col[1].data;
        let out_u0 = &mut ud_orde[ilevel].u.col[0].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel - 1, ilevel);
            out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
        }
        let out_u1 = &mut ud_orde[ilevel].u.col[1].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel - 1, ilevel);
            out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
        }
    }

    ud_orde[end_level].d = Vec2::zero(nmutot);
    let mut ilevel = end_level;
    while ilevel > start_level {
        ilevel -= 1;
        let local_d0 = ud_local[ilevel].d.col[0].data;
        let local_d1 = ud_local[ilevel].d.col[1].data;
        let prev_d0 = ud_orde[ilevel + 1].d.col[0].data;
        let prev_d1 = ud_orde[ilevel + 1].d.col[1].data;
        let out_d0 = &mut ud_orde[ilevel].d.col[0].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel + 1, ilevel);
            out_d0[imu] = local_d0[imu] + att * prev_d0[imu];
        }
        let out_d1 = &mut ud_orde[ilevel].d.col[1].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel + 1, ilevel);
            out_d1[imu] = local_d1[imu] + att * prev_d1[imu];
        }
    }
}

pub fn dot_gauss(mat: &Mat, row: usize, vec_col: &LabosVec, n_gauss: usize) -> f64 {
    let row_offset = row * mat.n;
    let mut sum = 0.0;
    for k in 0..n_gauss {
        sum += mat.data[row_offset + k] * vec_col.data[k];
    }
    sum
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct DotPair {
    pub col0: f64,
    pub col1: f64,
}

pub fn dot_gauss_pair(
    mat: &Mat,
    row: usize,
    vec_col0: &LabosVec,
    vec_col1: &LabosVec,
    n_gauss: usize,
) -> DotPair {
    let row_offset = row * mat.n;
    let mut col0 = 0.0;
    let mut col1 = 0.0;
    for k in 0..n_gauss {
        let value = mat.data[row_offset + k];
        col0 += value * vec_col0.data[k];
        col1 += value * vec_col1.data[k];
    }
    DotPair { col0, col1 }
}

pub fn rt_layer_has_signal(rt: &LayerRt, nmutot: usize) -> bool {
    let count = nmutot * nmutot;
    rt.r.data[..count].iter().any(|value| *value != 0.0)
        || rt.t.data[..count].iter().any(|value| *value != 0.0)
}

pub fn refresh_active_layer_mask(rt: &[LayerRt], rt_active: &mut [bool], nmutot: usize) {
    for (layer_rt, active) in rt.iter().zip(rt_active.iter_mut()) {
        *active = rt_layer_has_signal(layer_rt, nmutot);
    }
}

pub fn copy_transported_order_into_output(
    ud: &mut [UdField],
    ud_orde: &[UdField],
    start_level: usize,
    end_level: usize,
) {
    for ilevel in start_level..=end_level {
        ud[ilevel].u = ud_orde[ilevel].u;
        ud[ilevel].d = ud_orde[ilevel].d;
    }
}

pub fn max_outgoing_upward(
    ud_orde: &[UdField],
    end_level: usize,
    n_gauss: usize,
    nmutot: usize,
) -> f64 {
    let mut max_value: f64 = 0.0;
    for imu0 in 0..2 {
        let end_u = ud_orde[end_level].u.col[imu0].data;
        for value in end_u.iter().take(nmutot).skip(n_gauss) {
            max_value = max_value.max(value.abs());
        }
    }
    max_value
}

pub fn initialize_orders_buffers(
    track_sum_local: bool,
    ud: &mut [UdField],
    ud_sum_local: &mut [UdLocal],
    ud_orde: &mut [UdField],
    ud_local: &mut [UdLocal],
    nmutot: usize,
) {
    for (((field, sum_local), orde), local) in ud
        .iter_mut()
        .zip(ud_sum_local.iter_mut())
        .zip(ud_orde.iter_mut())
        .zip(ud_local.iter_mut())
    {
        *field = zero_ud_field(nmutot);
        if track_sum_local {
            *sum_local = zero_ud_local(nmutot);
        }
        *orde = zero_ud_field(nmutot);
        *local = zero_ud_local(nmutot);
    }
}

#[allow(clippy::too_many_arguments)]
pub fn accumulate_order_contribution(
    track_sum_local: bool,
    ud: &mut [UdField],
    ud_sum_local: &mut [UdLocal],
    ud_orde: &[UdField],
    ud_local: &[UdLocal],
    start_level: usize,
    end_level: usize,
    nmutot: usize,
) {
    for ilevel in start_level..=end_level {
        for imu0 in 0..2 {
            let orde_u = ud_orde[ilevel].u.col[imu0].data;
            let orde_d = ud_orde[ilevel].d.col[imu0].data;
            for imu in 0..nmutot {
                ud[ilevel].u.col[imu0].data[imu] += orde_u[imu];
                ud[ilevel].d.col[imu0].data[imu] += orde_d[imu];
            }
            if track_sum_local {
                let local_u = ud_local[ilevel].u.col[imu0].data;
                let local_d = ud_local[ilevel].d.col[imu0].data;
                for imu in 0..nmutot {
                    ud_sum_local[ilevel].u.col[imu0].data[imu] += local_u[imu];
                    ud_sum_local[ilevel].d.col[imu0].data[imu] += local_d[imu];
                }
            }
        }
    }
}

pub fn zero_orders_result(nlevel: usize, geo: &Geometry) -> OrdersResult {
    OrdersResult {
        ud: vec![zero_ud_field(geo.nmutot); nlevel],
        ud_sum_local: vec![zero_ud_local(geo.nmutot); nlevel],
    }
}
