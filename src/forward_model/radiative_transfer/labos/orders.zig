const std = @import("std");
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../root.zig");

pub const OrdersResult = struct {
    allocator: Allocator,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,

    pub fn deinit(self: *OrdersResult) void {
        self.allocator.free(self.ud);
        self.allocator.free(self.ud_sum_local);
        self.* = undefined;
    }
};

pub const OrdersResultView = struct {
    ud: []const basis.UDField,
    ud_sum_local: []const basis.UDLocal,
};

pub const OrdersWorkspace = struct {
    allocator: Allocator,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []basis.UDField,
    ud_local: []basis.UDLocal,

    pub fn init(
        allocator: Allocator,
        nlevel: usize,
    ) !OrdersWorkspace {
        const ud = try allocator.alloc(basis.UDField, nlevel);
        errdefer allocator.free(ud);
        const ud_sum_local = try allocator.alloc(basis.UDLocal, nlevel);
        errdefer allocator.free(ud_sum_local);
        const ud_orde = try allocator.alloc(basis.UDField, nlevel);
        errdefer allocator.free(ud_orde);
        const ud_local = try allocator.alloc(basis.UDLocal, nlevel);
        return .{
            .allocator = allocator,
            .ud = ud,
            .ud_sum_local = ud_sum_local,
            .ud_orde = ud_orde,
            .ud_local = ud_local,
        };
    }

    pub fn deinit(self: *OrdersWorkspace) void {
        self.allocator.free(self.ud);
        self.allocator.free(self.ud_sum_local);
        self.allocator.free(self.ud_orde);
        self.allocator.free(self.ud_local);
        self.* = undefined;
    }
};

fn transportToOtherLevels(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: anytype,
    ud_local: []const basis.UDLocal,
    ud_orde: []basis.UDField,
) void {
    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |ilevel| {
        const local_u0 = ud_local[ilevel].U.col[0].data;
        const local_u1 = ud_local[ilevel].U.col[1].data;
        const prev_u0 = ud_orde[ilevel - 1].U.col[0].data;
        const prev_u1 = ud_orde[ilevel - 1].U.col[1].data;
        const out_u0 = &ud_orde[ilevel].U.col[0].data;
        const out_u1 = &ud_orde[ilevel].U.col[1].data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, ilevel - 1, ilevel);
            out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
            out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
        }
    }

    ud_orde[end_level].D = basis.Vec2.zero(nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        const local_d0 = ud_local[ilevel].D.col[0].data;
        const local_d1 = ud_local[ilevel].D.col[1].data;
        const prev_d0 = ud_orde[ilevel + 1].D.col[0].data;
        const prev_d1 = ud_orde[ilevel + 1].D.col[1].data;
        const out_d0 = &ud_orde[ilevel].D.col[0].data;
        const out_d1 = &ud_orde[ilevel].D.col[1].data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, ilevel + 1, ilevel);
            out_d0[imu] = local_d0[imu] + att * prev_d0[imu];
            out_d1[imu] = local_d1[imu] + att * prev_d1[imu];
        }
    }
}

pub fn dotGauss(mat: *const basis.Mat, row: usize, vec_col: *const basis.Vec, n_gauss: usize) f64 {
    const row_offset = row * mat.n;
    if (n_gauss == 10) {
        const data = mat.data[row_offset..];
        const vec_data = vec_col.data;
        var s = data[0] * vec_data[0];
        s += data[1] * vec_data[1];
        s += data[2] * vec_data[2];
        s += data[3] * vec_data[3];
        s += data[4] * vec_data[4];
        s += data[5] * vec_data[5];
        s += data[6] * vec_data[6];
        s += data[7] * vec_data[7];
        s += data[8] * vec_data[8];
        s += data[9] * vec_data[9];
        return s;
    }
    var s: f64 = 0.0;
    for (0..n_gauss) |k| {
        s += mat.data[row_offset + k] * vec_col.data[k];
    }
    return s;
}

fn initializeOrdersBuffers(
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []basis.UDField,
    ud_local: []basis.UDLocal,
    nmutot: usize,
) void {
    const vec = basis.Vec{ .data = undefined, .n = nmutot };
    const vec2 = basis.Vec2{ .col = .{ vec, vec }, .n = nmutot };
    for (ud, ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
        field.* = .{
            .E = vec,
            .U = vec2,
            .D = vec2,
        };
        sum_local.* = .{
            .U = vec2,
            .D = vec2,
        };
        orde.* = .{
            .E = vec,
            .U = vec2,
            .D = vec2,
        };
        local.* = .{
            .U = vec2,
            .D = vec2,
        };
    }
}

fn accumulateOrderContribution(
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []const basis.UDField,
    ud_local: []const basis.UDLocal,
    start_level: usize,
    end_level: usize,
    nmutot: usize,
) void {
    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const orde_u = ud_orde[ilevel].U.col[imu0].data;
            const orde_d = ud_orde[ilevel].D.col[imu0].data;
            const local_u = ud_local[ilevel].U.col[imu0].data;
            const local_d = ud_local[ilevel].D.col[imu0].data;
            const ud_u = &ud[ilevel].U.col[imu0].data;
            const ud_d = &ud[ilevel].D.col[imu0].data;
            const sum_u = &ud_sum_local[ilevel].U.col[imu0].data;
            const sum_d = &ud_sum_local[ilevel].D.col[imu0].data;
            for (0..nmutot) |imu| {
                ud_u[imu] += orde_u[imu];
                ud_d[imu] += orde_d[imu];
                sum_u[imu] += local_u[imu];
                sum_d[imu] += local_d[imu];
            }
        }
    }
}

fn ordersScatInternal(
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []basis.UDField,
    ud_local: []basis.UDLocal,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    const nmutot = geo.nmutot;
    const n_gauss = geo.n_gauss;
    const nlevel = end_level + 1;
    std.debug.assert(ud.len >= nlevel);
    std.debug.assert(ud_sum_local.len >= nlevel);
    std.debug.assert(ud_orde.len >= nlevel);
    std.debug.assert(ud_local.len >= nlevel);

    const ud_view = ud[0..nlevel];
    const ud_sum_local_view = ud_sum_local[0..nlevel];
    const ud_orde_view = ud_orde[0..nlevel];
    const ud_local_view = ud_local[0..nlevel];
    initializeOrdersBuffers(ud_view, ud_sum_local_view, ud_orde_view, ud_local_view, nmutot);

    for (start_level..end_level + 1) |ilevel| {
        const e_data = &ud_view[ilevel].E.data;
        const orde_e_data = &ud_orde_view[ilevel].E.data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            orde_e_data[imu] = att;
            e_data[imu] = att;
        }
    }

    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel + 1);
            const local_d = &ud_local_view[ilevel].D.col[imu0].data;
            const rt_t = &rt[ilevel + 1].T;
            const rt_col_offset = col_idx;
            var rt_idx = rt_col_offset;
            for (0..nmutot) |imu| {
                local_d[imu] = rt_t.data[rt_idx] * att;
                rt_idx += rt_t.n;
            }
        }
    }
    ud_local_view[end_level].D = basis.Vec2.zero(nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            const local_u = &ud_local_view[ilevel].U.col[imu0].data;
            const rt_r = &rt[ilevel].R;
            const rt_col_offset = col_idx;
            var rt_idx = rt_col_offset;
            for (0..nmutot) |imu| {
                local_u[imu] = rt_r.data[rt_idx] * att;
                rt_idx += rt_r.n;
            }
        }
    }

    for (start_level..end_level + 1) |ilevel| {
        ud_sum_local_view[ilevel].U = ud_local_view[ilevel].U;
        ud_sum_local_view[ilevel].D = ud_local_view[ilevel].D;
    }

    transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local_view, ud_orde_view);

    for (start_level..end_level + 1) |ilevel| {
        ud_view[ilevel].U = ud_orde_view[ilevel].U;
        ud_view[ilevel].D = ud_orde_view[ilevel].D;
    }

    var max_value: f64 = 0.0;
    for (0..2) |imu0| {
        const end_u = ud_orde_view[end_level].U.col[imu0].data;
        for (n_gauss..nmutot) |imu| {
            const val = @abs(end_u[imu]);
            if (val > max_value) max_value = val;
        }
    }
    if (controls.scattering != .multiple or max_value < controls.threshold_conv_first) {
        return .{
            .ud = ud_view,
            .ud_sum_local = ud_sum_local_view,
        };
    }

    var num_orders: usize = 1;

    while (true) {
        num_orders += 1;

        for (start_level..end_level) |ilevel| {
            for (0..2) |imu0| {
                const local_d = &ud_local_view[ilevel].D.col[imu0].data;
                const prev_u = &ud_orde_view[ilevel].U.col[imu0];
                const prev_d = &ud_orde_view[ilevel + 1].D.col[imu0];
                for (0..nmutot) |imu| {
                    const rst_dot_u = dotGauss(&rt[ilevel + 1].R, imu, prev_u, n_gauss);
                    const t_dot_d = dotGauss(&rt[ilevel + 1].T, imu, prev_d, n_gauss);
                    local_d[imu] = rst_dot_u + t_dot_d;
                }
            }
        }
        ud_local_view[end_level].D = basis.Vec2.zero(nmutot);

        for (0..2) |imu0| {
            const local_u = &ud_local_view[start_level].U.col[imu0].data;
            const prev_d = &ud_orde_view[start_level].D.col[imu0];
            for (0..nmutot) |imu| {
                local_u[imu] = dotGauss(&rt[start_level].R, imu, prev_d, n_gauss);
            }
        }

        for (start_level + 1..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                const local_u = &ud_local_view[ilevel].U.col[imu0].data;
                const prev_d = &ud_orde_view[ilevel].D.col[imu0];
                const prev_u = &ud_orde_view[ilevel - 1].U.col[imu0];
                for (0..nmutot) |imu| {
                    const r_dot_d = dotGauss(&rt[ilevel].R, imu, prev_d, n_gauss);
                    const tst_dot_u = dotGauss(&rt[ilevel].T, imu, prev_u, n_gauss);
                    local_u[imu] = r_dot_d + tst_dot_u;
                }
            }
        }

        transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local_view, ud_orde_view);

        max_value = 0.0;
        for (0..2) |imu0| {
            const end_u = ud_orde_view[end_level].U.col[imu0].data;
            for (n_gauss..nmutot) |imu| {
                const val = @abs(end_u[imu]);
                if (val > max_value) max_value = val;
            }
        }

        if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) {
            // PARITY:
            //   `LabosModule::ordersScat` exits the scattering-order loop as
            //   soon as the current order falls below `thresholdConv_mult`.
            //   That current below-threshold order is not added to `UD_fc`.
            break;
        }

        accumulateOrderContribution(
            ud_view,
            ud_sum_local_view,
            ud_orde_view,
            ud_local_view,
            start_level,
            end_level,
            nmutot,
        );
    }

    return .{
        .ud = ud_view,
        .ud_sum_local = ud_sum_local_view,
    };
}

pub fn ordersScatInto(
    storage: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    return ordersScatInternal(
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
}

pub fn ordersScat(
    allocator: Allocator,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) !OrdersResult {
    const nlevel = end_level + 1;

    const ud = try allocator.alloc(basis.UDField, nlevel);
    var ud_owned_by_result = false;
    errdefer if (!ud_owned_by_result) allocator.free(ud);
    const ud_sum_local = try allocator.alloc(basis.UDLocal, nlevel);
    var ud_sum_local_owned_by_result = false;
    errdefer if (!ud_sum_local_owned_by_result) allocator.free(ud_sum_local);

    var result = OrdersResult{
        .allocator = allocator,
        .ud = ud,
        .ud_sum_local = ud_sum_local,
    };
    ud_owned_by_result = true;
    ud_sum_local_owned_by_result = true;
    errdefer result.deinit();

    const ud_orde = try allocator.alloc(basis.UDField, nlevel);
    defer allocator.free(ud_orde);
    const ud_local = try allocator.alloc(basis.UDLocal, nlevel);
    defer allocator.free(ud_local);

    _ = ordersScatInternal(
        result.ud,
        result.ud_sum_local,
        ud_orde,
        ud_local,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return result;
}
