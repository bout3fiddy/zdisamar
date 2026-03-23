//! Purpose:
//!   Own LABOS orders-of-scattering transport and the internal radiation field
//!   accumulation logic.
//!
//! Physics:
//!   Propagates local layer sources through the level grid, accumulates the
//!   diffuse field across successive scattering orders, and applies convergence
//!   control.
//!
//! Vendor:
//!   LABOS orders-of-scattering stage
//!
//! Design:
//!   The transport recursion is isolated from the layer operator generation so
//!   the higher-level solver can combine the stages without one monolithic
//!   implementation file.
//!
//! Invariants:
//!   Upward diffuse light is accumulated from the start level toward TOA while
//!   downward diffuse light propagates from TOA toward the surface.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for orders-of-scattering and
//!   end-to-end execution coverage.

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
pub fn dotGauss(mat: *const basis.Mat, row: usize, vec_col: *const basis.Vec, n_gauss: usize) f64 {
    var s: f64 = 0.0;
    for (0..n_gauss) |k| {
        s += mat.get(row, k) * vec_col.get(k);
    }
    return s;
}

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
    const nmutot = geo.nmutot;
    const n_gauss = geo.n_gauss;
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

    var ud_orde = try allocator.alloc(basis.UDField, nlevel);
    defer allocator.free(ud_orde);
    var ud_local = try allocator.alloc(basis.UDLocal, nlevel);
    defer allocator.free(ud_local);

    for (result.ud, result.ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
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

    for (start_level..end_level + 1) |ilevel| {
        for (0..nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            ud_orde[ilevel].E.set(imu, att);
            result.ud[ilevel].E.set(imu, att);
        }
    }

    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..nmutot) |imu| {
                ud_local[ilevel].D.col[imu0].set(imu, rt[ilevel + 1].T.get(imu, col_idx) * att);
            }
        }
    }
    ud_local[end_level].D = basis.Vec2.zero(nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            for (0..nmutot) |imu| {
                ud_local[ilevel].U.col[imu0].set(imu, rt[ilevel].R.get(imu, col_idx) * att);
            }
        }
    }

    for (start_level..end_level + 1) |ilevel| {
        result.ud_sum_local[ilevel].U = ud_local[ilevel].U;
        result.ud_sum_local[ilevel].D = ud_local[ilevel].D;
    }

    transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local, ud_orde);

    for (start_level..end_level + 1) |ilevel| {
        result.ud[ilevel].U = ud_orde[ilevel].U;
        result.ud[ilevel].D = ud_orde[ilevel].D;
    }

    var max_value: f64 = 0.0;
    for (0..2) |imu0| {
        for (n_gauss..nmutot) |imu| {
            const val = @abs(ud_orde[end_level].U.col[imu0].get(imu));
            if (val > max_value) max_value = val;
        }
    }
    if (controls.scattering != .multiple or max_value < controls.threshold_conv_first) return result;

    var num_orders: usize = 1;
    var sum_int_field_prev: [2]f64 = .{ 0.0, 0.0 };

    while (true) {
        num_orders += 1;

        for (start_level..end_level) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const rst_dot_u = dotGauss(&rt[ilevel + 1].R, imu, &ud_orde[ilevel].U.col[imu0], n_gauss);
                    const t_dot_d = dotGauss(&rt[ilevel + 1].T, imu, &ud_orde[ilevel + 1].D.col[imu0], n_gauss);
                    ud_local[ilevel].D.col[imu0].set(imu, rst_dot_u + t_dot_d);
                }
            }
        }
        ud_local[end_level].D = basis.Vec2.zero(nmutot);

        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const r_dot_d = dotGauss(&rt[start_level].R, imu, &ud_orde[start_level].D.col[imu0], n_gauss);
                ud_local[start_level].U.col[imu0].set(imu, r_dot_d);
            }
        }

        for (start_level + 1..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const r_dot_d = dotGauss(&rt[ilevel].R, imu, &ud_orde[ilevel].D.col[imu0], n_gauss);
                    const tst_dot_u = dotGauss(&rt[ilevel].T, imu, &ud_orde[ilevel - 1].U.col[imu0], n_gauss);
                    ud_local[ilevel].U.col[imu0].set(imu, r_dot_d + tst_dot_u);
                }
            }
        }

        transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local, ud_orde);

        max_value = 0.0;
        for (0..2) |imu0| {
            for (n_gauss..nmutot) |imu| {
                const val = @abs(ud_orde[end_level].U.col[imu0].get(imu));
                if (val > max_value) max_value = val;
            }
        }

        if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) {
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

            if (num_orders >= num_orders_max) {
                for (0..2) |imu0| {
                    var eigenvalue: f64 = 0.0;
                    if (sum_int_field_prev[imu0] > 1.0e-10) {
                        eigenvalue = sum_int_field[imu0] / sum_int_field_prev[imu0];
                    }
                    const scale = if (@abs(1.0 - eigenvalue) > 1.0e-10) 1.0 / (1.0 - eigenvalue) else 1.0;
                    for (start_level..end_level + 1) |ilevel| {
                        for (0..nmutot) |imu| {
                            const uval = result.ud[ilevel].U.col[imu0].get(imu) + ud_orde[ilevel].U.col[imu0].get(imu) * scale;
                            result.ud[ilevel].U.col[imu0].set(imu, uval);
                            const dval = result.ud[ilevel].D.col[imu0].get(imu) + ud_orde[ilevel].D.col[imu0].get(imu) * scale;
                            result.ud[ilevel].D.col[imu0].set(imu, dval);
                            const su = result.ud_sum_local[ilevel].U.col[imu0].get(imu) + ud_local[ilevel].U.col[imu0].get(imu) * scale;
                            result.ud_sum_local[ilevel].U.col[imu0].set(imu, su);
                            const sd = result.ud_sum_local[ilevel].D.col[imu0].get(imu) + ud_local[ilevel].D.col[imu0].get(imu) * scale;
                            result.ud_sum_local[ilevel].D.col[imu0].set(imu, sd);
                        }
                    }
                }
            } else {
                for (start_level..end_level + 1) |ilevel| {
                    for (0..2) |imu0| {
                        for (0..nmutot) |imu| {
                            const uval = result.ud[ilevel].U.col[imu0].get(imu) + ud_orde[ilevel].U.col[imu0].get(imu);
                            result.ud[ilevel].U.col[imu0].set(imu, uval);
                            const dval = result.ud[ilevel].D.col[imu0].get(imu) + ud_orde[ilevel].D.col[imu0].get(imu);
                            result.ud[ilevel].D.col[imu0].set(imu, dval);
                            const su = result.ud_sum_local[ilevel].U.col[imu0].get(imu) + ud_local[ilevel].U.col[imu0].get(imu);
                            result.ud_sum_local[ilevel].U.col[imu0].set(imu, su);
                            const sd = result.ud_sum_local[ilevel].D.col[imu0].get(imu) + ud_local[ilevel].D.col[imu0].get(imu);
                            result.ud_sum_local[ilevel].D.col[imu0].set(imu, sd);
                        }
                    }
                }
            }
            break;
        }

        for (start_level..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const uval = result.ud[ilevel].U.col[imu0].get(imu) + ud_orde[ilevel].U.col[imu0].get(imu);
                    result.ud[ilevel].U.col[imu0].set(imu, uval);
                    const dval = result.ud[ilevel].D.col[imu0].get(imu) + ud_orde[ilevel].D.col[imu0].get(imu);
                    result.ud[ilevel].D.col[imu0].set(imu, dval);
                    const su = result.ud_sum_local[ilevel].U.col[imu0].get(imu) + ud_local[ilevel].U.col[imu0].get(imu);
                    result.ud_sum_local[ilevel].U.col[imu0].set(imu, su);
                    const sd = result.ud_sum_local[ilevel].D.col[imu0].get(imu) + ud_local[ilevel].D.col[imu0].get(imu);
                    result.ud_sum_local[ilevel].D.col[imu0].set(imu, sd);
                }
            }
        }

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
        sum_int_field_prev = sum_int_field;
    }

    return result;
}
