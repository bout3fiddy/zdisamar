use std::{ops::RangeInclusive, vec::Vec as StdVec};

use super::{
    attenuation::{AttenArray, DynamicAttenArray},
    types::{Geometry, LayerRt, Mat, UdField, UdLocal, Vec as LabosVec, Vec2},
};
use crate::forward_model::radiative_transfer::common_types::{
    RadiativeTransferControls, ScatteringMode,
};

pub trait AttenuationLookup {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64;
}

impl AttenuationLookup for AttenArray {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.get(imu, from, to)
    }
}

impl AttenuationLookup for DynamicAttenArray {
    fn get(&self, imu: usize, from: usize, to: usize) -> f64 {
        self.get(imu, from, to)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct OrdersResult {
    pub ud: StdVec<UdField>,
    pub ud_sum_local: StdVec<UdLocal>,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct OrdersResultView<'a> {
    pub ud: &'a [UdField],
    pub ud_sum_local: &'a [UdLocal],
}

#[derive(Debug, Clone, PartialEq)]
pub struct OrdersWorkspace {
    pub ud: StdVec<UdField>,
    pub ud_sum_local: StdVec<UdLocal>,
    pub ud_orde: StdVec<UdField>,
    pub ud_local: StdVec<UdLocal>,
    pub rt_active: StdVec<bool>,
}

impl OrdersWorkspace {
    pub fn new(nlevel: usize) -> Self {
        Self {
            ud: vec![zero_ud(0); nlevel],
            ud_sum_local: vec![zero_local(0); nlevel],
            ud_orde: vec![zero_ud(0); nlevel],
            ud_local: vec![zero_local(0); nlevel],
            rt_active: vec![false; nlevel],
        }
    }
}

fn zero_ud(nmutot: usize) -> UdField {
    UdField {
        e: LabosVec::zero(nmutot),
        u: Vec2::zero(nmutot),
        d: Vec2::zero(nmutot),
    }
}

fn zero_local(nmutot: usize) -> UdLocal {
    UdLocal {
        u: Vec2::zero(nmutot),
        d: Vec2::zero(nmutot),
    }
}

fn transport_to_other_levels<A: AttenuationLookup>(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    attenuation: &A,
    ud_local: &[UdLocal],
    ud_orde: &mut [UdField],
) {
    ud_orde[start_level].u = ud_local[start_level].u;
    for ilevel in start_level + 1..=end_level {
        for col in 0..2 {
            for imu in 0..nmutot {
                let att = attenuation.get(imu, ilevel - 1, ilevel);
                ud_orde[ilevel].u.col[col].data[imu] = ud_local[ilevel].u.col[col].data[imu]
                    + att * ud_orde[ilevel - 1].u.col[col].data[imu];
            }
        }
    }

    ud_orde[end_level].d = Vec2::zero(nmutot);
    let mut ilevel = end_level;
    while ilevel > start_level {
        ilevel -= 1;
        for col in 0..2 {
            for imu in 0..nmutot {
                let att = attenuation.get(imu, ilevel + 1, ilevel);
                ud_orde[ilevel].d.col[col].data[imu] = ud_local[ilevel].d.col[col].data[imu]
                    + att * ud_orde[ilevel + 1].d.col[col].data[imu];
            }
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
struct DotPair {
    col0: f64,
    col1: f64,
}

fn dot_gauss_pair(
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

fn rt_layer_has_signal(rt: &LayerRt, nmutot: usize) -> bool {
    let count = nmutot * nmutot;
    rt.r.data[..count].iter().any(|value| *value != 0.0)
        || rt.t.data[..count].iter().any(|value| *value != 0.0)
}

fn refresh_active_layer_mask(rt: &[LayerRt], rt_active: &mut [bool], nmutot: usize) {
    for (layer_rt, active) in rt.iter().zip(rt_active.iter_mut()) {
        *active = rt_layer_has_signal(layer_rt, nmutot);
    }
}

fn copy_transported_order_into_output(
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

fn max_outgoing_upward(
    ud_orde: &[UdField],
    end_level: usize,
    n_gauss: usize,
    nmutot: usize,
) -> f64 {
    let mut max_value: f64 = 0.0;
    for col in 0..2 {
        let end_u = ud_orde[end_level].u.col[col].data;
        for val in end_u[n_gauss..nmutot].iter() {
            max_value = max_value.max(val.abs());
        }
    }
    max_value
}

fn initialize_orders_buffers(
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
        *field = zero_ud(nmutot);
        if track_sum_local {
            *sum_local = zero_local(nmutot);
        }
        *orde = zero_ud(nmutot);
        *local = zero_local(nmutot);
    }
}

fn accumulate_order_contribution(
    track_sum_local: bool,
    ud: &mut [UdField],
    ud_sum_local: &mut [UdLocal],
    ud_orde: &[UdField],
    ud_local: &[UdLocal],
    levels: RangeInclusive<usize>,
    nmutot: usize,
) {
    for ilevel in levels {
        for col in 0..2 {
            for imu in 0..nmutot {
                ud[ilevel].u.col[col].data[imu] += ud_orde[ilevel].u.col[col].data[imu];
                ud[ilevel].d.col[col].data[imu] += ud_orde[ilevel].d.col[col].data[imu];
                if track_sum_local {
                    ud_sum_local[ilevel].u.col[col].data[imu] +=
                        ud_local[ilevel].u.col[col].data[imu];
                    ud_sum_local[ilevel].d.col[col].data[imu] +=
                        ud_local[ilevel].d.col[col].data[imu];
                }
            }
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn orders_scat_internal<A: AttenuationLookup>(
    track_sum_local: bool,
    rt_active_ready: bool,
    storage: &mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) {
    let nmutot = geometry.nmutot;
    let n_gauss = geometry.n_gauss;
    let nlevel = end_level + 1;
    assert!(storage.ud.len() >= nlevel);
    assert!(storage.ud_sum_local.len() >= nlevel);
    assert!(storage.ud_orde.len() >= nlevel);
    assert!(storage.ud_local.len() >= nlevel);
    assert!(storage.rt_active.len() >= nlevel);
    assert!(rt.len() >= nlevel);

    let OrdersWorkspace {
        ud,
        ud_sum_local,
        ud_orde,
        ud_local,
        rt_active,
    } = storage;
    let ud = &mut ud[..nlevel];
    let ud_sum_local = &mut ud_sum_local[..nlevel];
    let ud_orde = &mut ud_orde[..nlevel];
    let ud_local = &mut ud_local[..nlevel];
    let rt_active = &mut rt_active[..nlevel];

    initialize_orders_buffers(track_sum_local, ud, ud_sum_local, ud_orde, ud_local, nmutot);

    if !rt_active_ready {
        refresh_active_layer_mask(&rt[..nlevel], rt_active, nmutot);
    }

    for ilevel in start_level..=end_level {
        for imu in 0..nmutot {
            let att = attenuation.get(imu, end_level, ilevel);
            ud_orde[ilevel].e.data[imu] = att;
            ud[ilevel].e.data[imu] = att;
        }
    }

    for ilevel in start_level..end_level {
        for imu0 in 0..2 {
            if !rt_active[ilevel + 1] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = attenuation.get(col_idx, end_level, ilevel + 1);
            let rt_t = &rt[ilevel + 1].t;
            let mut rt_idx = col_idx;
            for imu in 0..nmutot {
                ud_local[ilevel].d.col[imu0].data[imu] = rt_t.data[rt_idx] * att;
                rt_idx += rt_t.n;
            }
        }
    }

    for ilevel in start_level..=end_level {
        for imu0 in 0..2 {
            if !rt_active[ilevel] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = attenuation.get(col_idx, end_level, ilevel);
            let rt_r = &rt[ilevel].r;
            let mut rt_idx = col_idx;
            for imu in 0..nmutot {
                ud_local[ilevel].u.col[imu0].data[imu] = rt_r.data[rt_idx] * att;
                rt_idx += rt_r.n;
            }
        }
    }

    if track_sum_local {
        for ilevel in start_level..=end_level {
            ud_sum_local[ilevel].u = ud_local[ilevel].u;
            ud_sum_local[ilevel].d = ud_local[ilevel].d;
        }
    }

    transport_to_other_levels(
        start_level,
        end_level,
        nmutot,
        attenuation,
        ud_local,
        ud_orde,
    );
    copy_transported_order_into_output(ud, ud_orde, start_level, end_level);

    let mut max_value = max_outgoing_upward(ud_orde, end_level, n_gauss, nmutot);
    if controls.scattering != ScatteringMode::Multiple
        || max_value < controls.performance_thresholds.threshold_conv_first
    {
        return;
    }

    let mut num_orders = 1;
    loop {
        num_orders += 1;

        for ilevel in start_level..end_level {
            if !rt_active[ilevel + 1] {
                continue;
            }
            let prev_u0 = &ud_orde[ilevel].u.col[0];
            let prev_u1 = &ud_orde[ilevel].u.col[1];
            let prev_d0 = &ud_orde[ilevel + 1].d.col[0];
            let prev_d1 = &ud_orde[ilevel + 1].d.col[1];
            for imu in 0..nmutot {
                let rst_dot_u = dot_gauss_pair(&rt[ilevel + 1].r, imu, prev_u0, prev_u1, n_gauss);
                let t_dot_d = dot_gauss_pair(&rt[ilevel + 1].t, imu, prev_d0, prev_d1, n_gauss);
                ud_local[ilevel].d.col[0].data[imu] = rst_dot_u.col0 + t_dot_d.col0;
                ud_local[ilevel].d.col[1].data[imu] = rst_dot_u.col1 + t_dot_d.col1;
            }
        }
        ud_local[end_level].d = Vec2::zero(nmutot);

        if rt_active[start_level] {
            let prev_d_start0 = &ud_orde[start_level].d.col[0];
            let prev_d_start1 = &ud_orde[start_level].d.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(
                    &rt[start_level].r,
                    imu,
                    prev_d_start0,
                    prev_d_start1,
                    n_gauss,
                );
                ud_local[start_level].u.col[0].data[imu] = r_dot_d.col0;
                ud_local[start_level].u.col[1].data[imu] = r_dot_d.col1;
            }
        }

        for ilevel in start_level + 1..=end_level {
            if !rt_active[ilevel] {
                continue;
            }
            let prev_d0 = &ud_orde[ilevel].d.col[0];
            let prev_d1 = &ud_orde[ilevel].d.col[1];
            let prev_u0 = &ud_orde[ilevel - 1].u.col[0];
            let prev_u1 = &ud_orde[ilevel - 1].u.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(&rt[ilevel].r, imu, prev_d0, prev_d1, n_gauss);
                let tst_dot_u = dot_gauss_pair(&rt[ilevel].t, imu, prev_u0, prev_u1, n_gauss);
                ud_local[ilevel].u.col[0].data[imu] = r_dot_d.col0 + tst_dot_u.col0;
                ud_local[ilevel].u.col[1].data[imu] = r_dot_d.col1 + tst_dot_u.col1;
            }
        }

        transport_to_other_levels(
            start_level,
            end_level,
            nmutot,
            attenuation,
            ud_local,
            ud_orde,
        );
        max_value = max_outgoing_upward(ud_orde, end_level, n_gauss, nmutot);

        if max_value < controls.performance_thresholds.threshold_conv_mult
            || num_orders >= num_orders_max
        {
            // LABOS tests convergence before accumulation, so the first
            // below-threshold multiple-scattering order is intentionally
            // excluded from the output field.
            break;
        }

        accumulate_order_contribution(
            track_sum_local,
            ud,
            ud_sum_local,
            ud_orde,
            ud_local,
            start_level..=end_level,
            nmutot,
        );
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into<'a, A: AttenuationLookup>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        false,
        false,
        storage,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        controls,
        num_orders_max,
    );
    OrdersResultView {
        ud: &storage.ud[..end_level + 1],
        ud_sum_local: &[],
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_local_sum<'a, A: AttenuationLookup>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        true,
        false,
        storage,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        controls,
        num_orders_max,
    );
    OrdersResultView {
        ud: &storage.ud[..end_level + 1],
        ud_sum_local: &storage.ud_sum_local[..end_level + 1],
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_active<'a, A: AttenuationLookup>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        false,
        true,
        storage,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        controls,
        num_orders_max,
    );
    OrdersResultView {
        ud: &storage.ud[..end_level + 1],
        ud_sum_local: &[],
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_active_local_sum<'a, A: AttenuationLookup>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        true,
        true,
        storage,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        controls,
        num_orders_max,
    );
    OrdersResultView {
        ud: &storage.ud[..end_level + 1],
        ud_sum_local: &storage.ud_sum_local[..end_level + 1],
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_transport_into<'a, A: AttenuationLookup>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geometry: &Geometry,
    attenuation: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_into(
        storage,
        start_level,
        end_level,
        geometry,
        attenuation,
        rt,
        controls,
        num_orders_max,
    )
}
