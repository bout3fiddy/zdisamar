use super::{
    attenuation::{AttenArray, DynamicAttenArray},
    types::{Geometry, LayerRt, Mat, UdField, UdLocal, Vec as LabosVec, Vec2},
};
use crate::forward_model::radiative_transfer::{RadiativeTransferControls, ScatteringMode};

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

#[allow(clippy::too_many_arguments)]
pub fn transport_to_other_levels_tangent<A: AttenuationAccess, B: AttenuationAccess>(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: &A,
    atten_tangent: &B,
    ud_orde: &[UdField],
    ud_local_tangent: &[UdLocal],
    ud_orde_tangent: &mut [UdField],
) {
    ud_orde_tangent[start_level].u = ud_local_tangent[start_level].u;
    for ilevel in start_level + 1..=end_level {
        let local_du0 = ud_local_tangent[ilevel].u.col[0].data;
        let local_du1 = ud_local_tangent[ilevel].u.col[1].data;
        let prev_u0 = ud_orde[ilevel - 1].u.col[0].data;
        let prev_u1 = ud_orde[ilevel - 1].u.col[1].data;
        let prev_du0 = ud_orde_tangent[ilevel - 1].u.col[0].data;
        let prev_du1 = ud_orde_tangent[ilevel - 1].u.col[1].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel - 1, ilevel);
            let datt = atten_tangent.get(imu, ilevel - 1, ilevel);
            ud_orde_tangent[ilevel].u.col[0].data[imu] =
                local_du0[imu] + datt * prev_u0[imu] + att * prev_du0[imu];
            ud_orde_tangent[ilevel].u.col[1].data[imu] =
                local_du1[imu] + datt * prev_u1[imu] + att * prev_du1[imu];
        }
    }

    ud_orde_tangent[end_level].d = Vec2::zero(nmutot);
    let mut ilevel = end_level;
    while ilevel > start_level {
        ilevel -= 1;
        let local_dd0 = ud_local_tangent[ilevel].d.col[0].data;
        let local_dd1 = ud_local_tangent[ilevel].d.col[1].data;
        let prev_d0 = ud_orde[ilevel + 1].d.col[0].data;
        let prev_d1 = ud_orde[ilevel + 1].d.col[1].data;
        let prev_dd0 = ud_orde_tangent[ilevel + 1].d.col[0].data;
        let prev_dd1 = ud_orde_tangent[ilevel + 1].d.col[1].data;
        for imu in 0..nmutot {
            let att = atten.get(imu, ilevel + 1, ilevel);
            let datt = atten_tangent.get(imu, ilevel + 1, ilevel);
            ud_orde_tangent[ilevel].d.col[0].data[imu] =
                local_dd0[imu] + datt * prev_d0[imu] + att * prev_dd0[imu];
            ud_orde_tangent[ilevel].d.col[1].data[imu] =
                local_dd1[imu] + datt * prev_d1[imu] + att * prev_dd1[imu];
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

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_internal<'a, A: AttenuationAccess>(
    track_sum_local: bool,
    rt_active_ready: bool,
    ud: &'a mut [UdField],
    ud_sum_local: &'a mut [UdLocal],
    ud_orde: &mut [UdField],
    ud_local: &mut [UdLocal],
    rt_active: &mut [bool],
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    let nmutot = geo.nmutot;
    let n_gauss = geo.n_gauss;
    let nlevel = end_level + 1;
    assert!(ud.len() >= nlevel);
    assert!(ud_sum_local.len() >= nlevel);
    assert!(ud_orde.len() >= nlevel);
    assert!(ud_local.len() >= nlevel);
    assert!(rt_active.len() >= nlevel);

    let ud_view = &mut ud[..nlevel];
    let ud_sum_local_view = &mut ud_sum_local[..nlevel];
    let ud_orde_view = &mut ud_orde[..nlevel];
    let ud_local_view = &mut ud_local[..nlevel];
    let rt_active_view = &mut rt_active[..nlevel];

    initialize_orders_buffers(
        track_sum_local,
        ud_view,
        ud_sum_local_view,
        ud_orde_view,
        ud_local_view,
        nmutot,
    );

    if !rt_active_ready {
        refresh_active_layer_mask(&rt[..nlevel], rt_active_view, nmutot);
    }

    for ilevel in start_level..=end_level {
        for imu in 0..nmutot {
            let att = atten.get(imu, end_level, ilevel);
            ud_orde_view[ilevel].e.data[imu] = att;
            ud_view[ilevel].e.data[imu] = att;
        }
    }

    for ilevel in start_level..end_level {
        for imu0 in 0..2 {
            if !rt_active_view[ilevel + 1] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = atten.get(col_idx, end_level, ilevel + 1);
            let rt_t = &rt[ilevel + 1].t;
            for imu in 0..nmutot {
                let rt_idx = imu * rt_t.n + col_idx;
                ud_local_view[ilevel].d.col[imu0].data[imu] = rt_t.data[rt_idx] * att;
            }
        }
    }

    for ilevel in start_level..=end_level {
        for imu0 in 0..2 {
            if !rt_active_view[ilevel] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = atten.get(col_idx, end_level, ilevel);
            let rt_r = &rt[ilevel].r;
            for imu in 0..nmutot {
                let rt_idx = imu * rt_r.n + col_idx;
                ud_local_view[ilevel].u.col[imu0].data[imu] = rt_r.data[rt_idx] * att;
            }
        }
    }

    if track_sum_local {
        for ilevel in start_level..=end_level {
            ud_sum_local_view[ilevel].u = ud_local_view[ilevel].u;
            ud_sum_local_view[ilevel].d = ud_local_view[ilevel].d;
        }
    }

    transport_to_other_levels(
        start_level,
        end_level,
        nmutot,
        atten,
        ud_local_view,
        ud_orde_view,
    );
    copy_transported_order_into_output(ud_view, ud_orde_view, start_level, end_level);

    let mut max_value = max_outgoing_upward(ud_orde_view, end_level, n_gauss, nmutot);
    if controls.scattering != ScatteringMode::Multiple
        || max_value < controls.performance_thresholds.threshold_conv_first
    {
        return OrdersResultView {
            ud: ud_view,
            ud_sum_local: ud_sum_local_view,
        };
    }

    let mut num_orders = 1;
    loop {
        num_orders += 1;

        for ilevel in start_level..end_level {
            if !rt_active_view[ilevel + 1] {
                continue;
            }
            let prev_u0 = ud_orde_view[ilevel].u.col[0];
            let prev_u1 = ud_orde_view[ilevel].u.col[1];
            let prev_d0 = ud_orde_view[ilevel + 1].d.col[0];
            let prev_d1 = ud_orde_view[ilevel + 1].d.col[1];
            for imu in 0..nmutot {
                let rst_dot_u = dot_gauss_pair(&rt[ilevel + 1].r, imu, &prev_u0, &prev_u1, n_gauss);
                let t_dot_d = dot_gauss_pair(&rt[ilevel + 1].t, imu, &prev_d0, &prev_d1, n_gauss);
                ud_local_view[ilevel].d.col[0].data[imu] = rst_dot_u.col0 + t_dot_d.col0;
                ud_local_view[ilevel].d.col[1].data[imu] = rst_dot_u.col1 + t_dot_d.col1;
            }
        }
        ud_local_view[end_level].d = Vec2::zero(nmutot);

        if rt_active_view[start_level] {
            let prev_d_start0 = ud_orde_view[start_level].d.col[0];
            let prev_d_start1 = ud_orde_view[start_level].d.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(
                    &rt[start_level].r,
                    imu,
                    &prev_d_start0,
                    &prev_d_start1,
                    n_gauss,
                );
                ud_local_view[start_level].u.col[0].data[imu] = r_dot_d.col0;
                ud_local_view[start_level].u.col[1].data[imu] = r_dot_d.col1;
            }
        }

        for ilevel in start_level + 1..=end_level {
            if !rt_active_view[ilevel] {
                continue;
            }
            let prev_d0 = ud_orde_view[ilevel].d.col[0];
            let prev_d1 = ud_orde_view[ilevel].d.col[1];
            let prev_u0 = ud_orde_view[ilevel - 1].u.col[0];
            let prev_u1 = ud_orde_view[ilevel - 1].u.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(&rt[ilevel].r, imu, &prev_d0, &prev_d1, n_gauss);
                let tst_dot_u = dot_gauss_pair(&rt[ilevel].t, imu, &prev_u0, &prev_u1, n_gauss);
                ud_local_view[ilevel].u.col[0].data[imu] = r_dot_d.col0 + tst_dot_u.col0;
                ud_local_view[ilevel].u.col[1].data[imu] = r_dot_d.col1 + tst_dot_u.col1;
            }
        }

        transport_to_other_levels(
            start_level,
            end_level,
            nmutot,
            atten,
            ud_local_view,
            ud_orde_view,
        );
        max_value = max_outgoing_upward(ud_orde_view, end_level, n_gauss, nmutot);

        // The current below-threshold order is intentionally not accumulated; this matches DISAMAR's loop exit.
        if max_value < controls.performance_thresholds.threshold_conv_mult
            || num_orders >= num_orders_max
        {
            break;
        }

        accumulate_order_contribution(
            track_sum_local,
            ud_view,
            ud_sum_local_view,
            ud_orde_view,
            ud_local_view,
            start_level,
            end_level,
            nmutot,
        );
    }

    OrdersResultView {
        ud: ud_view,
        ud_sum_local: ud_sum_local_view,
    }
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into<'a, A: AttenuationAccess>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        false,
        false,
        &mut storage.ud,
        &mut storage.ud_sum_local,
        &mut storage.ud_orde,
        &mut storage.ud_local,
        &mut storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_local_sum<'a, A: AttenuationAccess>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        true,
        false,
        &mut storage.ud,
        &mut storage.ud_sum_local,
        &mut storage.ud_orde,
        &mut storage.ud_local,
        &mut storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_active<'a, A: AttenuationAccess>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        false,
        true,
        &mut storage.ud,
        &mut storage.ud_sum_local,
        &mut storage.ud_orde,
        &mut storage.ud_local,
        &mut storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_into_with_active_local_sum<'a, A: AttenuationAccess>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_internal(
        true,
        true,
        &mut storage.ud,
        &mut storage.ud_sum_local,
        &mut storage.ud_orde,
        &mut storage.ud_local,
        &mut storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_transport_into<'a, A: AttenuationAccess>(
    storage: &'a mut OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResultView<'a> {
    orders_scat_into(
        storage,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat<A: AttenuationAccess>(
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    rt: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResult {
    let nlevel = end_level + 1;
    let mut result = zero_orders_result(nlevel, geo);
    let mut ud_orde = vec![zero_ud_field(geo.nmutot); nlevel];
    let mut ud_local = vec![zero_ud_local(geo.nmutot); nlevel];
    let mut rt_active = vec![false; nlevel];
    orders_scat_internal(
        true,
        false,
        &mut result.ud,
        &mut result.ud_sum_local,
        &mut ud_orde,
        &mut ud_local,
        &mut rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    result
}

#[allow(clippy::too_many_arguments)]
pub fn orders_scat_tangent<A: AttenuationAccess, B: AttenuationAccess>(
    start_level: usize,
    end_level: usize,
    geo: &Geometry,
    atten: &A,
    atten_tangent: &B,
    rt: &[LayerRt],
    rt_tangent: &[LayerRt],
    controls: RadiativeTransferControls,
    num_orders_max: usize,
) -> OrdersResult {
    let nlevel = end_level + 1;
    let nmutot = geo.nmutot;
    let n_gauss = geo.n_gauss;

    let mut result = zero_orders_result(nlevel, geo);
    let mut base_ud = vec![zero_ud_field(nmutot); nlevel];
    let mut base_ud_sum_local = vec![zero_ud_local(nmutot); nlevel];
    let mut base_orde = vec![zero_ud_field(nmutot); nlevel];
    let mut base_local = vec![zero_ud_local(nmutot); nlevel];
    let mut tangent_orde = vec![zero_ud_field(nmutot); nlevel];
    let mut tangent_local = vec![zero_ud_local(nmutot); nlevel];
    let mut rt_active = vec![false; nlevel];

    initialize_orders_buffers(
        false,
        &mut base_ud,
        &mut base_ud_sum_local,
        &mut base_orde,
        &mut base_local,
        nmutot,
    );
    initialize_orders_buffers(
        false,
        &mut result.ud,
        &mut result.ud_sum_local,
        &mut tangent_orde,
        &mut tangent_local,
        nmutot,
    );
    refresh_active_layer_mask(&rt[..nlevel], &mut rt_active, nmutot);

    for ilevel in start_level..=end_level {
        for imu in 0..nmutot {
            let att = atten.get(imu, end_level, ilevel);
            base_orde[ilevel].e.data[imu] = att;
            base_ud[ilevel].e.data[imu] = att;
            result.ud[ilevel].e.data[imu] = 0.0;
            tangent_orde[ilevel].e.data[imu] = 0.0;
        }
    }

    for ilevel in start_level..end_level {
        for imu0 in 0..2 {
            if !rt_active[ilevel + 1] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = atten.get(col_idx, end_level, ilevel + 1);
            let datt = atten_tangent.get(col_idx, end_level, ilevel + 1);
            let rt_t = &rt[ilevel + 1].t;
            let drt_t = &rt_tangent[ilevel + 1].t;
            for imu in 0..nmutot {
                let rt_idx = imu * rt_t.n + col_idx;
                base_local[ilevel].d.col[imu0].data[imu] = rt_t.data[rt_idx] * att;
                tangent_local[ilevel].d.col[imu0].data[imu] =
                    drt_t.data[rt_idx] * att + rt_t.data[rt_idx] * datt;
            }
        }
    }
    base_local[end_level].d = Vec2::zero(nmutot);
    tangent_local[end_level].d = Vec2::zero(nmutot);

    for ilevel in start_level..=end_level {
        for imu0 in 0..2 {
            if !rt_active[ilevel] {
                continue;
            }
            let col_idx = n_gauss + imu0;
            let att = atten.get(col_idx, end_level, ilevel);
            let datt = atten_tangent.get(col_idx, end_level, ilevel);
            let rt_r = &rt[ilevel].r;
            let drt_r = &rt_tangent[ilevel].r;
            for imu in 0..nmutot {
                let rt_idx = imu * rt_r.n + col_idx;
                base_local[ilevel].u.col[imu0].data[imu] = rt_r.data[rt_idx] * att;
                tangent_local[ilevel].u.col[imu0].data[imu] =
                    drt_r.data[rt_idx] * att + rt_r.data[rt_idx] * datt;
            }
        }
    }

    transport_to_other_levels(
        start_level,
        end_level,
        nmutot,
        atten,
        &base_local,
        &mut base_orde,
    );
    transport_to_other_levels_tangent(
        start_level,
        end_level,
        nmutot,
        atten,
        atten_tangent,
        &base_orde,
        &tangent_local,
        &mut tangent_orde,
    );
    copy_transported_order_into_output(&mut base_ud, &base_orde, start_level, end_level);
    copy_transported_order_into_output(&mut result.ud, &tangent_orde, start_level, end_level);

    let mut max_value = max_outgoing_upward(&base_orde, end_level, n_gauss, nmutot);
    if controls.scattering != ScatteringMode::Multiple
        || max_value < controls.performance_thresholds.threshold_conv_first
    {
        return result;
    }

    let mut num_orders = 1;
    loop {
        num_orders += 1;

        for ilevel in start_level..end_level {
            if !rt_active[ilevel + 1] {
                base_local[ilevel].d = Vec2::zero(nmutot);
                tangent_local[ilevel].d = Vec2::zero(nmutot);
                continue;
            }
            let prev_u0 = base_orde[ilevel].u.col[0];
            let prev_u1 = base_orde[ilevel].u.col[1];
            let prev_d0 = base_orde[ilevel + 1].d.col[0];
            let prev_d1 = base_orde[ilevel + 1].d.col[1];
            let tangent_prev_u0 = tangent_orde[ilevel].u.col[0];
            let tangent_prev_u1 = tangent_orde[ilevel].u.col[1];
            let tangent_prev_d0 = tangent_orde[ilevel + 1].d.col[0];
            let tangent_prev_d1 = tangent_orde[ilevel + 1].d.col[1];
            for imu in 0..nmutot {
                let rst_dot_u = dot_gauss_pair(&rt[ilevel + 1].r, imu, &prev_u0, &prev_u1, n_gauss);
                let t_dot_d = dot_gauss_pair(&rt[ilevel + 1].t, imu, &prev_d0, &prev_d1, n_gauss);
                base_local[ilevel].d.col[0].data[imu] = rst_dot_u.col0 + t_dot_d.col0;
                base_local[ilevel].d.col[1].data[imu] = rst_dot_u.col1 + t_dot_d.col1;

                let drst_dot_u =
                    dot_gauss_pair(&rt_tangent[ilevel + 1].r, imu, &prev_u0, &prev_u1, n_gauss);
                let rst_dot_du = dot_gauss_pair(
                    &rt[ilevel + 1].r,
                    imu,
                    &tangent_prev_u0,
                    &tangent_prev_u1,
                    n_gauss,
                );
                let dt_dot_d =
                    dot_gauss_pair(&rt_tangent[ilevel + 1].t, imu, &prev_d0, &prev_d1, n_gauss);
                let t_dot_dd = dot_gauss_pair(
                    &rt[ilevel + 1].t,
                    imu,
                    &tangent_prev_d0,
                    &tangent_prev_d1,
                    n_gauss,
                );
                tangent_local[ilevel].d.col[0].data[imu] =
                    drst_dot_u.col0 + rst_dot_du.col0 + dt_dot_d.col0 + t_dot_dd.col0;
                tangent_local[ilevel].d.col[1].data[imu] =
                    drst_dot_u.col1 + rst_dot_du.col1 + dt_dot_d.col1 + t_dot_dd.col1;
            }
        }
        base_local[end_level].d = Vec2::zero(nmutot);
        tangent_local[end_level].d = Vec2::zero(nmutot);

        if rt_active[start_level] {
            let prev_d_start0 = base_orde[start_level].d.col[0];
            let prev_d_start1 = base_orde[start_level].d.col[1];
            let tangent_prev_d_start0 = tangent_orde[start_level].d.col[0];
            let tangent_prev_d_start1 = tangent_orde[start_level].d.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(
                    &rt[start_level].r,
                    imu,
                    &prev_d_start0,
                    &prev_d_start1,
                    n_gauss,
                );
                base_local[start_level].u.col[0].data[imu] = r_dot_d.col0;
                base_local[start_level].u.col[1].data[imu] = r_dot_d.col1;

                let dr_dot_d = dot_gauss_pair(
                    &rt_tangent[start_level].r,
                    imu,
                    &prev_d_start0,
                    &prev_d_start1,
                    n_gauss,
                );
                let r_dot_dd = dot_gauss_pair(
                    &rt[start_level].r,
                    imu,
                    &tangent_prev_d_start0,
                    &tangent_prev_d_start1,
                    n_gauss,
                );
                tangent_local[start_level].u.col[0].data[imu] = dr_dot_d.col0 + r_dot_dd.col0;
                tangent_local[start_level].u.col[1].data[imu] = dr_dot_d.col1 + r_dot_dd.col1;
            }
        } else {
            base_local[start_level].u = Vec2::zero(nmutot);
            tangent_local[start_level].u = Vec2::zero(nmutot);
        }

        for ilevel in start_level + 1..=end_level {
            if !rt_active[ilevel] {
                base_local[ilevel].u = Vec2::zero(nmutot);
                tangent_local[ilevel].u = Vec2::zero(nmutot);
                continue;
            }
            let prev_d0 = base_orde[ilevel].d.col[0];
            let prev_d1 = base_orde[ilevel].d.col[1];
            let prev_u0 = base_orde[ilevel - 1].u.col[0];
            let prev_u1 = base_orde[ilevel - 1].u.col[1];
            let tangent_prev_d0 = tangent_orde[ilevel].d.col[0];
            let tangent_prev_d1 = tangent_orde[ilevel].d.col[1];
            let tangent_prev_u0 = tangent_orde[ilevel - 1].u.col[0];
            let tangent_prev_u1 = tangent_orde[ilevel - 1].u.col[1];
            for imu in 0..nmutot {
                let r_dot_d = dot_gauss_pair(&rt[ilevel].r, imu, &prev_d0, &prev_d1, n_gauss);
                let tst_dot_u = dot_gauss_pair(&rt[ilevel].t, imu, &prev_u0, &prev_u1, n_gauss);
                base_local[ilevel].u.col[0].data[imu] = r_dot_d.col0 + tst_dot_u.col0;
                base_local[ilevel].u.col[1].data[imu] = r_dot_d.col1 + tst_dot_u.col1;

                let dr_dot_d =
                    dot_gauss_pair(&rt_tangent[ilevel].r, imu, &prev_d0, &prev_d1, n_gauss);
                let r_dot_dd = dot_gauss_pair(
                    &rt[ilevel].r,
                    imu,
                    &tangent_prev_d0,
                    &tangent_prev_d1,
                    n_gauss,
                );
                let dtst_dot_u =
                    dot_gauss_pair(&rt_tangent[ilevel].t, imu, &prev_u0, &prev_u1, n_gauss);
                let tst_dot_du = dot_gauss_pair(
                    &rt[ilevel].t,
                    imu,
                    &tangent_prev_u0,
                    &tangent_prev_u1,
                    n_gauss,
                );
                tangent_local[ilevel].u.col[0].data[imu] =
                    dr_dot_d.col0 + r_dot_dd.col0 + dtst_dot_u.col0 + tst_dot_du.col0;
                tangent_local[ilevel].u.col[1].data[imu] =
                    dr_dot_d.col1 + r_dot_dd.col1 + dtst_dot_u.col1 + tst_dot_du.col1;
            }
        }

        transport_to_other_levels(
            start_level,
            end_level,
            nmutot,
            atten,
            &base_local,
            &mut base_orde,
        );
        transport_to_other_levels_tangent(
            start_level,
            end_level,
            nmutot,
            atten,
            atten_tangent,
            &base_orde,
            &tangent_local,
            &mut tangent_orde,
        );

        max_value = max_outgoing_upward(&base_orde, end_level, n_gauss, nmutot);
        if max_value < controls.performance_thresholds.threshold_conv_mult
            || num_orders >= num_orders_max
        {
            break;
        }

        accumulate_order_contribution(
            false,
            &mut base_ud,
            &mut base_ud_sum_local,
            &base_orde,
            &base_local,
            start_level,
            end_level,
            nmutot,
        );
        accumulate_order_contribution(
            false,
            &mut result.ud,
            &mut result.ud_sum_local,
            &tangent_orde,
            &tangent_local,
            start_level,
            end_level,
            nmutot,
        );
    }

    result
}
