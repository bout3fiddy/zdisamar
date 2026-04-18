const std = @import("std");
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../common.zig");

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
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const local_val = ud_local[ilevel].U.col[imu0].get(imu);
                const prev_val = ud_orde[ilevel - 1].U.col[imu0].get(imu);
                const att = atten.get(imu, ilevel - 1, ilevel);
                ud_orde[ilevel].U.col[imu0].set(imu, local_val + att * prev_val);
            }
        }
    }

    ud_orde[end_level].D = basis.Vec2.zero(nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const local_val = ud_local[ilevel].D.col[imu0].get(imu);
                const prev_val = ud_orde[ilevel + 1].D.col[imu0].get(imu);
                const att = atten.get(imu, ilevel + 1, ilevel);
                ud_orde[ilevel].D.col[imu0].set(imu, local_val + att * prev_val);
            }
        }
    }
}

/// Dot product over the first n_gauss elements of a matrix row and a vector column.
///
/// Physics:
///   Computes the Gauss-point-only contraction used by the LABOS recursion.
pub fn dotGauss(mat: *const basis.Mat, row: usize, vec_col: *const basis.Vec, n_gauss: usize) f64 {
    var s: f64 = 0.0;
    for (0..n_gauss) |k| {
        s += mat.get(row, k) * vec_col.get(k);
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
    for (ud, ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
        field.* = .{
            .E = basis.Vec.zero(nmutot),
            .U = basis.Vec2.zero(nmutot),
            .D = basis.Vec2.zero(nmutot),
        };
        sum_local.* = .{
            .U = basis.Vec2.zero(nmutot),
            .D = basis.Vec2.zero(nmutot),
        };
        orde.* = .{
            .E = basis.Vec.zero(nmutot),
            .U = basis.Vec2.zero(nmutot),
            .D = basis.Vec2.zero(nmutot),
        };
        local.* = .{
            .U = basis.Vec2.zero(nmutot),
            .D = basis.Vec2.zero(nmutot),
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
            for (0..nmutot) |imu| {
                const uval = ud[ilevel].U.col[imu0].get(imu) + ud_orde[ilevel].U.col[imu0].get(imu);
                ud[ilevel].U.col[imu0].set(imu, uval);
                const dval = ud[ilevel].D.col[imu0].get(imu) + ud_orde[ilevel].D.col[imu0].get(imu);
                ud[ilevel].D.col[imu0].set(imu, dval);
                const su = ud_sum_local[ilevel].U.col[imu0].get(imu) + ud_local[ilevel].U.col[imu0].get(imu);
                ud_sum_local[ilevel].U.col[imu0].set(imu, su);
                const sd = ud_sum_local[ilevel].D.col[imu0].get(imu) + ud_local[ilevel].D.col[imu0].get(imu);
                ud_sum_local[ilevel].D.col[imu0].set(imu, sd);
            }
        }
    }
}

fn integralFieldMagnitude(
    ud_orde: []const basis.UDField,
    start_level: usize,
    end_level: usize,
    n_gauss: usize,
    nmutot: usize,
    geo: *const basis.Geometry,
) [2]f64 {
    var sum_int_field: [2]f64 = .{ 0.0, 0.0 };
    for (0..2) |imu0| {
        for (start_level..end_level + 1) |ilevel| {
            for (n_gauss..nmutot) |imu| {
                const wt = geo.w[imu];
                sum_int_field[imu0] += @abs(ud_orde[ilevel].U.col[imu0].get(imu)) / wt +
                    @abs(ud_orde[ilevel].D.col[imu0].get(imu)) / wt;
            }
        }
    }
    return sum_int_field;
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
    controls: common.RtmControls,
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
        for (0..nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            ud_orde_view[ilevel].E.set(imu, att);
            ud_view[ilevel].E.set(imu, att);
        }
    }

    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..nmutot) |imu| {
                ud_local_view[ilevel].D.col[imu0].set(imu, rt[ilevel + 1].T.get(imu, col_idx) * att);
            }
        }
    }
    ud_local_view[end_level].D = basis.Vec2.zero(nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            for (0..nmutot) |imu| {
                ud_local_view[ilevel].U.col[imu0].set(imu, rt[ilevel].R.get(imu, col_idx) * att);
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
        for (n_gauss..nmutot) |imu| {
            const val = @abs(ud_orde_view[end_level].U.col[imu0].get(imu));
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
    var sum_int_field_prev: [2]f64 = .{ 0.0, 0.0 };

    while (true) {
        num_orders += 1;

        for (start_level..end_level) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const rst_dot_u = dotGauss(&rt[ilevel + 1].R, imu, &ud_orde_view[ilevel].U.col[imu0], n_gauss);
                    const t_dot_d = dotGauss(&rt[ilevel + 1].T, imu, &ud_orde_view[ilevel + 1].D.col[imu0], n_gauss);
                    ud_local_view[ilevel].D.col[imu0].set(imu, rst_dot_u + t_dot_d);
                }
            }
        }
        ud_local_view[end_level].D = basis.Vec2.zero(nmutot);

        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const r_dot_d = dotGauss(&rt[start_level].R, imu, &ud_orde_view[start_level].D.col[imu0], n_gauss);
                ud_local_view[start_level].U.col[imu0].set(imu, r_dot_d);
            }
        }

        for (start_level + 1..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const r_dot_d = dotGauss(&rt[ilevel].R, imu, &ud_orde_view[ilevel].D.col[imu0], n_gauss);
                    const tst_dot_u = dotGauss(&rt[ilevel].T, imu, &ud_orde_view[ilevel - 1].U.col[imu0], n_gauss);
                    ud_local_view[ilevel].U.col[imu0].set(imu, r_dot_d + tst_dot_u);
                }
            }
        }

        transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local_view, ud_orde_view);

        max_value = 0.0;
        for (0..2) |imu0| {
            for (n_gauss..nmutot) |imu| {
                const val = @abs(ud_orde_view[end_level].U.col[imu0].get(imu));
                if (val > max_value) max_value = val;
            }
        }

        if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) {
            const sum_int_field = integralFieldMagnitude(
                ud_orde_view,
                start_level,
                end_level,
                n_gauss,
                nmutot,
                geo,
            );

            if (num_orders >= num_orders_max) {
                // DECISION:
                //   Preserve the vendor truncation fallback by scaling the
                //   final unresolved order with the observed growth ratio.
                for (0..2) |imu0| {
                    var eigenvalue: f64 = 0.0;
                    if (sum_int_field_prev[imu0] > 1.0e-10) {
                        eigenvalue = sum_int_field[imu0] / sum_int_field_prev[imu0];
                    }
                    const scale = if (@abs(1.0 - eigenvalue) > 1.0e-10) 1.0 / (1.0 - eigenvalue) else 1.0;
                    for (start_level..end_level + 1) |ilevel| {
                        for (0..nmutot) |imu| {
                            const uval = ud_view[ilevel].U.col[imu0].get(imu) + ud_orde_view[ilevel].U.col[imu0].get(imu) * scale;
                            ud_view[ilevel].U.col[imu0].set(imu, uval);
                            const dval = ud_view[ilevel].D.col[imu0].get(imu) + ud_orde_view[ilevel].D.col[imu0].get(imu) * scale;
                            ud_view[ilevel].D.col[imu0].set(imu, dval);
                            const su = ud_sum_local_view[ilevel].U.col[imu0].get(imu) + ud_local_view[ilevel].U.col[imu0].get(imu) * scale;
                            ud_sum_local_view[ilevel].U.col[imu0].set(imu, su);
                            const sd = ud_sum_local_view[ilevel].D.col[imu0].get(imu) + ud_local_view[ilevel].D.col[imu0].get(imu) * scale;
                            ud_sum_local_view[ilevel].D.col[imu0].set(imu, sd);
                        }
                    }
                }
            } else {
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
        sum_int_field_prev = integralFieldMagnitude(
            ud_orde_view,
            start_level,
            end_level,
            n_gauss,
            nmutot,
            geo,
        );
    }

    return .{
        .ud = ud_view,
        .ud_sum_local = ud_sum_local_view,
    };
}

/// Purpose:
///   Propagate scattered radiation through the LABOS order recursion using
///   caller-owned reusable buffers.
pub fn ordersScatInto(
    workspace: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RtmControls,
    num_orders_max: usize,
) OrdersResultView {
    return ordersScatInternal(
        workspace.ud,
        workspace.ud_sum_local,
        workspace.ud_orde,
        workspace.ud_local,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
}

/// Purpose:
///   Propagate scattered radiation through the LABOS order recursion.
///
/// Physics:
///   Accumulates successive scattering orders across the level grid while
///   applying the configured convergence thresholds.
///
/// Vendor:
///   `LABOS orders-of-scattering`
///
/// Inputs:
///   `rt` holds the layer reflection/transmission operators, `atten` holds the
///   inter-level attenuation grid, and `controls` governs truncation.
///
/// Outputs:
///   Returns the accumulated diffuse field and local source summaries.
///
/// Assumptions:
///   The transport grid is already resolved and `start_level <= end_level`.
///
/// Validation:
///   `tests/unit/transport_labos_test.zig`
pub fn ordersScat(
    allocator: Allocator,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RtmControls,
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
