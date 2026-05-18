const std = @import("std");
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../root.zig");
const attenuation_mod = @import("attenuation.zig");
const Trace = @import("../../performance_trace.zig");

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
    rt_active: []bool,

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
        errdefer allocator.free(ud_local);
        const rt_active = try allocator.alloc(bool, nlevel);
        return .{
            .allocator = allocator,
            .ud = ud,
            .ud_sum_local = ud_sum_local,
            .ud_orde = ud_orde,
            .ud_local = ud_local,
            .rt_active = rt_active,
        };
    }

    pub fn deinit(self: *OrdersWorkspace) void {
        self.allocator.free(self.ud);
        self.allocator.free(self.ud_sum_local);
        self.allocator.free(self.ud_orde);
        self.allocator.free(self.ud_local);
        self.allocator.free(self.rt_active);
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
    if (nmutot == basis.max_nmutot) {
        if (comptime isDynamicAttenPointer(@TypeOf(atten))) {
            transportToOtherLevelsDynamic12(start_level, end_level, atten, ud_local, ud_orde);
            return;
        }
        if (comptime isRuntimeAttenPointer(@TypeOf(atten))) {
            transportToOtherLevelsRuntime12(start_level, end_level, atten, ud_local, ud_orde);
            return;
        }
        transportToOtherLevels12(start_level, end_level, atten, ud_local, ud_orde);
        return;
    }

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

fn isDynamicAttenPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child == attenuation_mod.DynamicAttenArray,
        else => false,
    };
}

fn isRuntimeAttenPointer(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .pointer => |ptr| ptr.child == attenuation_mod.RuntimeAttenArray,
        else => false,
    };
}

fn dynamicAttenAt(atten: *const attenuation_mod.DynamicAttenArray, stream_stride: usize, imu: usize, level_offset: usize) f64 {
    return atten.data[imu * stream_stride + level_offset];
}

fn transportToOtherLevelsDynamic12(
    start_level: usize,
    end_level: usize,
    atten: *const attenuation_mod.DynamicAttenArray,
    ud_local: []const basis.UDLocal,
    ud_orde: []basis.UDField,
) void {
    const nlevel = atten.nlevel;
    const stream_stride = nlevel * nlevel;

    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |ilevel| {
        const level_offset = (ilevel - 1) * nlevel + ilevel;
        const local_u0 = ud_local[ilevel].U.col[0].data;
        const local_u1 = ud_local[ilevel].U.col[1].data;
        const prev_u0 = ud_orde[ilevel - 1].U.col[0].data;
        const prev_u1 = ud_orde[ilevel - 1].U.col[1].data;
        const out_u0 = &ud_orde[ilevel].U.col[0].data;
        const out_u1 = &ud_orde[ilevel].U.col[1].data;
        inline for (0..basis.max_nmutot) |imu| {
            const att = dynamicAttenAt(atten, stream_stride, imu, level_offset);
            out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
            out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
        }
    }

    ud_orde[end_level].D = basis.Vec2.zero(basis.max_nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        const level_offset = (ilevel + 1) * nlevel + ilevel;
        const local_d0 = ud_local[ilevel].D.col[0].data;
        const local_d1 = ud_local[ilevel].D.col[1].data;
        const prev_d0 = ud_orde[ilevel + 1].D.col[0].data;
        const prev_d1 = ud_orde[ilevel + 1].D.col[1].data;
        const out_d0 = &ud_orde[ilevel].D.col[0].data;
        const out_d1 = &ud_orde[ilevel].D.col[1].data;
        inline for (0..basis.max_nmutot) |imu| {
            const att = dynamicAttenAt(atten, stream_stride, imu, level_offset);
            out_d0[imu] = local_d0[imu] + att * prev_d0[imu];
            out_d1[imu] = local_d1[imu] + att * prev_d1[imu];
        }
    }
}

fn transportToOtherLevelsRuntime12(
    start_level: usize,
    end_level: usize,
    atten: *const attenuation_mod.RuntimeAttenArray,
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
        inline for (0..basis.max_nmutot) |imu| {
            const att = atten.adjacent(imu, ilevel - 1);
            out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
            out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
        }
    }

    ud_orde[end_level].D = basis.Vec2.zero(basis.max_nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        const local_d0 = ud_local[ilevel].D.col[0].data;
        const local_d1 = ud_local[ilevel].D.col[1].data;
        const prev_d0 = ud_orde[ilevel + 1].D.col[0].data;
        const prev_d1 = ud_orde[ilevel + 1].D.col[1].data;
        const out_d0 = &ud_orde[ilevel].D.col[0].data;
        const out_d1 = &ud_orde[ilevel].D.col[1].data;
        inline for (0..basis.max_nmutot) |imu| {
            const att = atten.adjacent(imu, ilevel);
            out_d0[imu] = local_d0[imu] + att * prev_d0[imu];
            out_d1[imu] = local_d1[imu] + att * prev_d1[imu];
        }
    }
}

fn transportToOtherLevels12(
    start_level: usize,
    end_level: usize,
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
        inline for (0..basis.max_nmutot) |imu| {
            const att = atten.get(imu, ilevel - 1, ilevel);
            out_u0[imu] = local_u0[imu] + att * prev_u0[imu];
            out_u1[imu] = local_u1[imu] + att * prev_u1[imu];
        }
    }

    ud_orde[end_level].D = basis.Vec2.zero(basis.max_nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        const local_d0 = ud_local[ilevel].D.col[0].data;
        const local_d1 = ud_local[ilevel].D.col[1].data;
        const prev_d0 = ud_orde[ilevel + 1].D.col[0].data;
        const prev_d1 = ud_orde[ilevel + 1].D.col[1].data;
        const out_d0 = &ud_orde[ilevel].D.col[0].data;
        const out_d1 = &ud_orde[ilevel].D.col[1].data;
        inline for (0..basis.max_nmutot) |imu| {
            const att = atten.get(imu, ilevel + 1, ilevel);
            out_d0[imu] = local_d0[imu] + att * prev_d0[imu];
            out_d1[imu] = local_d1[imu] + att * prev_d1[imu];
        }
    }
}

fn transportToOtherLevelsTangent(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: anytype,
    atten_tangent: anytype,
    _: []const basis.UDLocal,
    ud_local_tangent: []const basis.UDLocal,
    ud_orde: []const basis.UDField,
    ud_orde_tangent: []basis.UDField,
) void {
    ud_orde_tangent[start_level].U = ud_local_tangent[start_level].U;
    for (start_level + 1..end_level + 1) |ilevel| {
        const local_du0 = ud_local_tangent[ilevel].U.col[0].data;
        const local_du1 = ud_local_tangent[ilevel].U.col[1].data;
        const prev_u0 = ud_orde[ilevel - 1].U.col[0].data;
        const prev_u1 = ud_orde[ilevel - 1].U.col[1].data;
        const prev_du0 = ud_orde_tangent[ilevel - 1].U.col[0].data;
        const prev_du1 = ud_orde_tangent[ilevel - 1].U.col[1].data;
        const out_u0 = &ud_orde_tangent[ilevel].U.col[0].data;
        const out_u1 = &ud_orde_tangent[ilevel].U.col[1].data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, ilevel - 1, ilevel);
            const datt = atten_tangent.get(imu, ilevel - 1, ilevel);
            out_u0[imu] = local_du0[imu] + datt * prev_u0[imu] + att * prev_du0[imu];
            out_u1[imu] = local_du1[imu] + datt * prev_u1[imu] + att * prev_du1[imu];
        }
    }

    ud_orde_tangent[end_level].D = basis.Vec2.zero(nmutot);
    var ilevel = end_level;
    while (ilevel > start_level) {
        ilevel -= 1;
        const local_dd0 = ud_local_tangent[ilevel].D.col[0].data;
        const local_dd1 = ud_local_tangent[ilevel].D.col[1].data;
        const prev_d0 = ud_orde[ilevel + 1].D.col[0].data;
        const prev_d1 = ud_orde[ilevel + 1].D.col[1].data;
        const prev_dd0 = ud_orde_tangent[ilevel + 1].D.col[0].data;
        const prev_dd1 = ud_orde_tangent[ilevel + 1].D.col[1].data;
        const out_d0 = &ud_orde_tangent[ilevel].D.col[0].data;
        const out_d1 = &ud_orde_tangent[ilevel].D.col[1].data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, ilevel + 1, ilevel);
            const datt = atten_tangent.get(imu, ilevel + 1, ilevel);
            out_d0[imu] = local_dd0[imu] + datt * prev_d0[imu] + att * prev_dd0[imu];
            out_d1[imu] = local_dd1[imu] + datt * prev_d1[imu] + att * prev_dd1[imu];
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

const DotPair = struct {
    col0: f64,
    col1: f64,
};

inline fn dotGaussPair(
    mat: *const basis.Mat,
    row: usize,
    vec_col0: *const basis.Vec,
    vec_col1: *const basis.Vec,
    n_gauss: usize,
) DotPair {
    const row_offset = row * mat.n;
    if (n_gauss == 10) {
        const data = mat.data[row_offset..];
        const vec0 = vec_col0.data;
        const vec1 = vec_col1.data;
        return dotGaussPair10(data, &vec0, &vec1);
    }
    var s0: f64 = 0.0;
    var s1: f64 = 0.0;
    for (0..n_gauss) |k| {
        const value = mat.data[row_offset + k];
        s0 += value * vec_col0.data[k];
        s1 += value * vec_col1.data[k];
    }
    return .{ .col0 = s0, .col1 = s1 };
}

inline fn dotGaussPair10(
    data: []const f64,
    vec0: *const [basis.max_nmutot]f64,
    vec1: *const [basis.max_nmutot]f64,
) DotPair {
    const Vec2 = @Vector(2, f64);
    var sum0: Vec2 = @as(Vec2, .{ data[0], data[1] }) * @as(Vec2, .{ vec0[0], vec0[1] });
    var sum1: Vec2 = @as(Vec2, .{ data[0], data[1] }) * @as(Vec2, .{ vec1[0], vec1[1] });
    const data2: Vec2 = @as(Vec2, .{ data[2], data[3] });
    sum0 += data2 * @as(Vec2, .{ vec0[2], vec0[3] });
    sum1 += data2 * @as(Vec2, .{ vec1[2], vec1[3] });
    const data4: Vec2 = @as(Vec2, .{ data[4], data[5] });
    sum0 += data4 * @as(Vec2, .{ vec0[4], vec0[5] });
    sum1 += data4 * @as(Vec2, .{ vec1[4], vec1[5] });
    const data6: Vec2 = @as(Vec2, .{ data[6], data[7] });
    sum0 += data6 * @as(Vec2, .{ vec0[6], vec0[7] });
    sum1 += data6 * @as(Vec2, .{ vec1[6], vec1[7] });
    const data8: Vec2 = @as(Vec2, .{ data[8], data[9] });
    sum0 += data8 * @as(Vec2, .{ vec0[8], vec0[9] });
    sum1 += data8 * @as(Vec2, .{ vec1[8], vec1[9] });
    return .{
        .col0 = @reduce(.Add, sum0),
        .col1 = @reduce(.Add, sum1),
    };
}

fn rtLayerHasSignal(rt: *const basis.LayerRT, nmutot: usize) bool {
    const count = nmutot * nmutot;
    for (rt.R.data[0..count]) |value| {
        if (value != 0.0) return true;
    }
    for (rt.T.data[0..count]) |value| {
        if (value != 0.0) return true;
    }
    return false;
}

fn refreshActiveLayerMask(rt: []const basis.LayerRT, rt_active: []bool, nmutot: usize) void {
    for (rt, rt_active) |*layer_rt, *active| {
        active.* = rtLayerHasSignal(layer_rt, nmutot);
    }
}

fn copyTransportedOrderIntoOutput(
    ud: []basis.UDField,
    ud_orde: []const basis.UDField,
    start_level: usize,
    end_level: usize,
) void {
    for (start_level..end_level + 1) |ilevel| {
        ud[ilevel].U = ud_orde[ilevel].U;
        ud[ilevel].D = ud_orde[ilevel].D;
    }
}

fn maxOutgoingUpward(
    ud_orde: []const basis.UDField,
    end_level: usize,
    n_gauss: usize,
    nmutot: usize,
) f64 {
    var max_value: f64 = 0.0;
    for (0..2) |imu0| {
        const end_u = ud_orde[end_level].U.col[imu0].data;
        for (n_gauss..nmutot) |imu| {
            const val = @abs(end_u[imu]);
            if (val > max_value) max_value = val;
        }
    }
    return max_value;
}

fn initializeOrdersBuffers(
    comptime track_sum_local: bool,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []basis.UDField,
    ud_local: []basis.UDLocal,
    nmutot: usize,
) void {
    for (ud, ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
        field.* = undefined;
        field.E.n = nmutot;
        initVec2Metadata(&field.U, nmutot);
        initVec2Metadata(&field.D, nmutot);

        if (track_sum_local) {
            sum_local.U = basis.Vec2.zero(nmutot);
            sum_local.D = basis.Vec2.zero(nmutot);
        }

        orde.* = undefined;
        orde.E.n = nmutot;
        initVec2Metadata(&orde.U, nmutot);
        initVec2Metadata(&orde.D, nmutot);

        local.U = basis.Vec2.zero(nmutot);
        local.D = basis.Vec2.zero(nmutot);
    }
}

fn initVec2Metadata(vec2: *basis.Vec2, nmutot: usize) void {
    vec2.n = nmutot;
    vec2.col[0].n = nmutot;
    vec2.col[1].n = nmutot;
}

fn accumulateOrderContribution(
    comptime track_sum_local: bool,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []const basis.UDField,
    ud_local: []const basis.UDLocal,
    start_level: usize,
    end_level: usize,
    nmutot: usize,
) void {
    if (nmutot == basis.max_nmutot) {
        accumulateOrderContribution12(
            track_sum_local,
            ud,
            ud_sum_local,
            ud_orde,
            ud_local,
            start_level,
            end_level,
        );
        return;
    }

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const orde_u = ud_orde[ilevel].U.col[imu0].data;
            const orde_d = ud_orde[ilevel].D.col[imu0].data;
            const ud_u = &ud[ilevel].U.col[imu0].data;
            const ud_d = &ud[ilevel].D.col[imu0].data;
            if (track_sum_local) {
                const local_u = ud_local[ilevel].U.col[imu0].data;
                const local_d = ud_local[ilevel].D.col[imu0].data;
                const sum_u = &ud_sum_local[ilevel].U.col[imu0].data;
                const sum_d = &ud_sum_local[ilevel].D.col[imu0].data;
                for (0..nmutot) |imu| {
                    ud_u[imu] += orde_u[imu];
                    ud_d[imu] += orde_d[imu];
                    sum_u[imu] += local_u[imu];
                    sum_d[imu] += local_d[imu];
                }
            } else {
                for (0..nmutot) |imu| {
                    ud_u[imu] += orde_u[imu];
                    ud_d[imu] += orde_d[imu];
                }
            }
        }
    }
}

fn accumulateOrderContribution12(
    comptime track_sum_local: bool,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []const basis.UDField,
    ud_local: []const basis.UDLocal,
    start_level: usize,
    end_level: usize,
) void {
    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const orde_u = ud_orde[ilevel].U.col[imu0].data;
            const orde_d = ud_orde[ilevel].D.col[imu0].data;
            const ud_u = &ud[ilevel].U.col[imu0].data;
            const ud_d = &ud[ilevel].D.col[imu0].data;
            if (track_sum_local) {
                const local_u = ud_local[ilevel].U.col[imu0].data;
                const local_d = ud_local[ilevel].D.col[imu0].data;
                const sum_u = &ud_sum_local[ilevel].U.col[imu0].data;
                const sum_d = &ud_sum_local[ilevel].D.col[imu0].data;
                inline for (0..basis.max_nmutot) |imu| {
                    ud_u[imu] += orde_u[imu];
                    ud_d[imu] += orde_d[imu];
                    sum_u[imu] += local_u[imu];
                    sum_d[imu] += local_d[imu];
                }
            } else {
                inline for (0..basis.max_nmutot) |imu| {
                    ud_u[imu] += orde_u[imu];
                    ud_d[imu] += orde_d[imu];
                }
            }
        }
    }
}

fn ordersScatInternal(
    comptime track_sum_local: bool,
    comptime rt_active_ready: bool,
    ud: []basis.UDField,
    ud_sum_local: []basis.UDLocal,
    ud_orde: []basis.UDField,
    ud_local: []basis.UDLocal,
    rt_active: []bool,
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
    std.debug.assert(rt_active.len >= nlevel);

    const ud_view = ud[0..nlevel];
    const ud_sum_local_view = ud_sum_local[0..nlevel];
    const ud_orde_view = ud_orde[0..nlevel];
    const ud_local_view = ud_local[0..nlevel];
    const rt_active_view = rt_active[0..nlevel];
    initializeOrdersBuffers(track_sum_local, ud_view, ud_sum_local_view, ud_orde_view, ud_local_view, nmutot);
    Trace.plotU("orders_calls", 1);

    if (!rt_active_ready) {
        refreshActiveLayerMask(rt[0..nlevel], rt_active_view, nmutot);
    }

    {
        const zone = Trace.deepStaticZone(@src(), "labos.orders.initial_sources");
        defer zone.end();
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
                if (!rt_active_view[ilevel + 1]) {
                    continue;
                }
                const col_idx = n_gauss + imu0;
                const att = atten.get(col_idx, end_level, ilevel + 1);
                const local_d = &ud_local_view[ilevel].D.col[imu0].data;
                const rt_t = &rt[ilevel + 1].T;
                var rt_idx = col_idx;
                for (0..nmutot) |imu| {
                    local_d[imu] = rt_t.data[rt_idx] * att;
                    rt_idx += rt_t.n;
                }
            }
        }

        for (start_level..end_level + 1) |ilevel| {
            for (0..2) |imu0| {
                if (!rt_active_view[ilevel]) {
                    continue;
                }
                const col_idx = n_gauss + imu0;
                const att = atten.get(col_idx, end_level, ilevel);
                const local_u = &ud_local_view[ilevel].U.col[imu0].data;
                const rt_r = &rt[ilevel].R;
                var rt_idx = col_idx;
                for (0..nmutot) |imu| {
                    local_u[imu] = rt_r.data[rt_idx] * att;
                    rt_idx += rt_r.n;
                }
            }
        }

        if (track_sum_local) {
            for (start_level..end_level + 1) |ilevel| {
                ud_sum_local_view[ilevel].U = ud_local_view[ilevel].U;
                ud_sum_local_view[ilevel].D = ud_local_view[ilevel].D;
            }
        }
    }

    {
        const zone = Trace.deepStaticZone(@src(), "labos.orders.initial_transport");
        defer zone.end();
        transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local_view, ud_orde_view);
    }

    copyTransportedOrderIntoOutput(ud_view, ud_orde_view, start_level, end_level);

    var max_value = maxOutgoingUpward(ud_orde_view, end_level, n_gauss, nmutot);
    if (controls.scattering != .multiple or max_value < controls.performance_thresholds.threshold_conv_first) {
        Trace.plotU("orders_initial_returns", 1);
        return .{
            .ud = ud_view,
            .ud_sum_local = ud_sum_local_view,
        };
    }

    var num_orders: usize = 1;

    while (true) {
        const multiple_loop_zone = Trace.deepStaticZone(@src(), "labos.orders.multiple_loop");
        num_orders += 1;
        Trace.plotU("orders_multiple_iterations", 1);

        {
            const zone = Trace.deepStaticZone(@src(), "labos.orders.local_down");
            defer zone.end();
            for (start_level..end_level) |ilevel| {
                const local_d0 = &ud_local_view[ilevel].D.col[0].data;
                const local_d1 = &ud_local_view[ilevel].D.col[1].data;
                if (!rt_active_view[ilevel + 1]) {
                    Trace.plotU("orders_inactive_down_layers", 1);
                    continue;
                }
                const prev_u0 = &ud_orde_view[ilevel].U.col[0];
                const prev_u1 = &ud_orde_view[ilevel].U.col[1];
                const prev_d0 = &ud_orde_view[ilevel + 1].D.col[0];
                const prev_d1 = &ud_orde_view[ilevel + 1].D.col[1];
                Trace.plotU("dot_gauss_pair_calls", @intCast(nmutot * 2));
                Trace.plotU("dot_gauss_pair_terms", @intCast(nmutot * 2 * n_gauss));
                for (0..nmutot) |imu| {
                    const rst_dot_u = dotGaussPair(&rt[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
                    const t_dot_d = dotGaussPair(&rt[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
                    local_d0[imu] = rst_dot_u.col0 + t_dot_d.col0;
                    local_d1[imu] = rst_dot_u.col1 + t_dot_d.col1;
                }
            }
            ud_local_view[end_level].D = basis.Vec2.zero(nmutot);
        }

        {
            const zone = Trace.deepStaticZone(@src(), "labos.orders.local_up");
            defer zone.end();
            const local_u_start0 = &ud_local_view[start_level].U.col[0].data;
            const local_u_start1 = &ud_local_view[start_level].U.col[1].data;
            const prev_d_start0 = &ud_orde_view[start_level].D.col[0];
            const prev_d_start1 = &ud_orde_view[start_level].D.col[1];
            if (rt_active_view[start_level]) {
                Trace.plotU("dot_gauss_pair_calls", @intCast(nmutot));
                Trace.plotU("dot_gauss_pair_terms", @intCast(nmutot * n_gauss));
                for (0..nmutot) |imu| {
                    const r_dot_d = dotGaussPair(&rt[start_level].R, imu, prev_d_start0, prev_d_start1, n_gauss);
                    local_u_start0[imu] = r_dot_d.col0;
                    local_u_start1[imu] = r_dot_d.col1;
                }
            }

            for (start_level + 1..end_level + 1) |ilevel| {
                const local_u0 = &ud_local_view[ilevel].U.col[0].data;
                const local_u1 = &ud_local_view[ilevel].U.col[1].data;
                if (!rt_active_view[ilevel]) {
                    Trace.plotU("orders_inactive_up_layers", 1);
                    continue;
                }
                const prev_d0 = &ud_orde_view[ilevel].D.col[0];
                const prev_d1 = &ud_orde_view[ilevel].D.col[1];
                const prev_u0 = &ud_orde_view[ilevel - 1].U.col[0];
                const prev_u1 = &ud_orde_view[ilevel - 1].U.col[1];
                Trace.plotU("dot_gauss_pair_calls", @intCast(nmutot * 2));
                Trace.plotU("dot_gauss_pair_terms", @intCast(nmutot * 2 * n_gauss));
                for (0..nmutot) |imu| {
                    const r_dot_d = dotGaussPair(&rt[ilevel].R, imu, prev_d0, prev_d1, n_gauss);
                    const tst_dot_u = dotGaussPair(&rt[ilevel].T, imu, prev_u0, prev_u1, n_gauss);
                    local_u0[imu] = r_dot_d.col0 + tst_dot_u.col0;
                    local_u1[imu] = r_dot_d.col1 + tst_dot_u.col1;
                }
            }
        }

        {
            const zone = Trace.deepStaticZone(@src(), "labos.orders.transport");
            defer zone.end();
            transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local_view, ud_orde_view);
        }

        max_value = maxOutgoingUpward(ud_orde_view, end_level, n_gauss, nmutot);

        if (max_value < controls.performance_thresholds.threshold_conv_mult or num_orders >= num_orders_max) {
            // PARITY:
            //   `LabosModule::ordersScat` exits the scattering-order loop as
            //   soon as the current order falls below `thresholdConv_mult`.
            //   That current below-threshold order is not added to `UD_fc`.
            multiple_loop_zone.end();
            break;
        }

        {
            const zone = Trace.deepStaticZone(@src(), "labos.orders.accumulate");
            defer zone.end();
            accumulateOrderContribution(
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
        multiple_loop_zone.end();
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
    const result = ordersScatInternal(
        false,
        false,
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = &.{},
    };
}

pub fn ordersScatIntoWithLocalSum(
    storage: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    const result = ordersScatInternal(
        true,
        false,
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = result.ud_sum_local,
    };
}

pub fn ordersScatIntoWithActive(
    storage: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    // INVARIANT:
    //   `rt_active` is populated by the paired LABOS layer builder for the
    //   same Fourier order. It may conservatively mark zero matrices active,
    //   but it must not mark a nonzero layer inactive.
    const result = ordersScatInternal(
        false,
        true,
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = &.{},
    };
}

pub fn ordersScatIntoWithActiveLocalSum(
    storage: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    // INVARIANT:
    //   `rt_active` is populated by the paired LABOS layer builder for the
    //   same Fourier order. It may conservatively mark zero matrices active,
    //   but it must not mark a nonzero layer inactive.
    const result = ordersScatInternal(
        true,
        true,
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = result.ud_sum_local,
    };
}

pub fn ordersScatTransportInto(
    storage: *OrdersWorkspace,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    rt: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) OrdersResultView {
    const result = ordersScatInternal(
        false,
        false,
        storage.ud,
        storage.ud_sum_local,
        storage.ud_orde,
        storage.ud_local,
        storage.rt_active,
        start_level,
        end_level,
        geo,
        atten,
        rt,
        controls,
        num_orders_max,
    );
    return .{
        .ud = result.ud,
        .ud_sum_local = &.{},
    };
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
    const rt_active = try allocator.alloc(bool, nlevel);
    defer allocator.free(rt_active);

    _ = ordersScatInternal(
        true,
        false,
        result.ud,
        result.ud_sum_local,
        ud_orde,
        ud_local,
        rt_active,
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

pub fn ordersScatTangent(
    allocator: Allocator,
    start_level: usize,
    end_level: usize,
    geo: *const basis.Geometry,
    atten: anytype,
    atten_tangent: anytype,
    rt: []const basis.LayerRT,
    rt_tangent: []const basis.LayerRT,
    controls: common.RadiativeTransferControls,
    num_orders_max: usize,
) !OrdersResult {
    const nlevel = end_level + 1;
    const nmutot = geo.nmutot;
    const n_gauss = geo.n_gauss;

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

    const base_ud = try allocator.alloc(basis.UDField, nlevel);
    defer allocator.free(base_ud);
    const base_ud_sum_local = try allocator.alloc(basis.UDLocal, nlevel);
    defer allocator.free(base_ud_sum_local);
    const base_orde = try allocator.alloc(basis.UDField, nlevel);
    defer allocator.free(base_orde);
    const base_local = try allocator.alloc(basis.UDLocal, nlevel);
    defer allocator.free(base_local);
    const tangent_orde = try allocator.alloc(basis.UDField, nlevel);
    defer allocator.free(tangent_orde);
    const tangent_local = try allocator.alloc(basis.UDLocal, nlevel);
    defer allocator.free(tangent_local);
    const rt_active = try allocator.alloc(bool, nlevel);
    defer allocator.free(rt_active);

    initializeOrdersBuffers(false, base_ud, base_ud_sum_local, base_orde, base_local, nmutot);
    initializeOrdersBuffers(false, result.ud, result.ud_sum_local, tangent_orde, tangent_local, nmutot);

    refreshActiveLayerMask(rt[0..nlevel], rt_active, nmutot);

    for (start_level..end_level + 1) |ilevel| {
        const e_data = &base_ud[ilevel].E.data;
        const orde_e_data = &base_orde[ilevel].E.data;
        const tangent_e_data = &result.ud[ilevel].E.data;
        const tangent_orde_e_data = &tangent_orde[ilevel].E.data;
        for (0..nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            orde_e_data[imu] = att;
            e_data[imu] = att;
            tangent_e_data[imu] = 0.0;
            tangent_orde_e_data[imu] = 0.0;
        }
    }

    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const local_d = &base_local[ilevel].D.col[imu0].data;
            const tangent_d = &tangent_local[ilevel].D.col[imu0].data;
            if (!rt_active[ilevel + 1]) {
                for (0..nmutot) |imu| {
                    local_d[imu] = 0.0;
                    tangent_d[imu] = 0.0;
                }
                continue;
            }
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel + 1);
            const datt = atten_tangent.get(col_idx, end_level, ilevel + 1);
            const rt_t = &rt[ilevel + 1].T;
            const drt_t = &rt_tangent[ilevel + 1].T;
            var rt_idx = col_idx;
            for (0..nmutot) |imu| {
                local_d[imu] = rt_t.data[rt_idx] * att;
                tangent_d[imu] = drt_t.data[rt_idx] * att + rt_t.data[rt_idx] * datt;
                rt_idx += rt_t.n;
            }
        }
    }
    base_local[end_level].D = basis.Vec2.zero(nmutot);
    tangent_local[end_level].D = basis.Vec2.zero(nmutot);

    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const local_u = &base_local[ilevel].U.col[imu0].data;
            const tangent_u = &tangent_local[ilevel].U.col[imu0].data;
            if (!rt_active[ilevel]) {
                for (0..nmutot) |imu| {
                    local_u[imu] = 0.0;
                    tangent_u[imu] = 0.0;
                }
                continue;
            }
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            const datt = atten_tangent.get(col_idx, end_level, ilevel);
            const rt_r = &rt[ilevel].R;
            const drt_r = &rt_tangent[ilevel].R;
            var rt_idx = col_idx;
            for (0..nmutot) |imu| {
                local_u[imu] = rt_r.data[rt_idx] * att;
                tangent_u[imu] = drt_r.data[rt_idx] * att + rt_r.data[rt_idx] * datt;
                rt_idx += rt_r.n;
            }
        }
    }

    transportToOtherLevels(start_level, end_level, nmutot, atten, base_local, base_orde);
    transportToOtherLevelsTangent(start_level, end_level, nmutot, atten, atten_tangent, base_local, tangent_local, base_orde, tangent_orde);

    copyTransportedOrderIntoOutput(base_ud, base_orde, start_level, end_level);
    copyTransportedOrderIntoOutput(result.ud, tangent_orde, start_level, end_level);

    var max_value = maxOutgoingUpward(base_orde, end_level, n_gauss, nmutot);
    if (controls.scattering != .multiple or max_value < controls.performance_thresholds.threshold_conv_first) return result;

    var num_orders: usize = 1;
    while (true) {
        num_orders += 1;

        for (start_level..end_level) |ilevel| {
            const local_d0 = &base_local[ilevel].D.col[0].data;
            const local_d1 = &base_local[ilevel].D.col[1].data;
            const tangent_d0 = &tangent_local[ilevel].D.col[0].data;
            const tangent_d1 = &tangent_local[ilevel].D.col[1].data;
            if (!rt_active[ilevel + 1]) {
                for (0..nmutot) |imu| {
                    local_d0[imu] = 0.0;
                    local_d1[imu] = 0.0;
                    tangent_d0[imu] = 0.0;
                    tangent_d1[imu] = 0.0;
                }
                continue;
            }
            const prev_u0 = &base_orde[ilevel].U.col[0];
            const prev_u1 = &base_orde[ilevel].U.col[1];
            const prev_d0 = &base_orde[ilevel + 1].D.col[0];
            const prev_d1 = &base_orde[ilevel + 1].D.col[1];
            const tangent_prev_u0 = &tangent_orde[ilevel].U.col[0];
            const tangent_prev_u1 = &tangent_orde[ilevel].U.col[1];
            const tangent_prev_d0 = &tangent_orde[ilevel + 1].D.col[0];
            const tangent_prev_d1 = &tangent_orde[ilevel + 1].D.col[1];
            for (0..nmutot) |imu| {
                const rst_dot_u = dotGaussPair(&rt[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
                const t_dot_d = dotGaussPair(&rt[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
                local_d0[imu] = rst_dot_u.col0 + t_dot_d.col0;
                local_d1[imu] = rst_dot_u.col1 + t_dot_d.col1;

                const drst_dot_u = dotGaussPair(&rt_tangent[ilevel + 1].R, imu, prev_u0, prev_u1, n_gauss);
                const rst_dot_du = dotGaussPair(&rt[ilevel + 1].R, imu, tangent_prev_u0, tangent_prev_u1, n_gauss);
                const dt_dot_d = dotGaussPair(&rt_tangent[ilevel + 1].T, imu, prev_d0, prev_d1, n_gauss);
                const t_dot_dd = dotGaussPair(&rt[ilevel + 1].T, imu, tangent_prev_d0, tangent_prev_d1, n_gauss);
                tangent_d0[imu] = drst_dot_u.col0 + rst_dot_du.col0 + dt_dot_d.col0 + t_dot_dd.col0;
                tangent_d1[imu] = drst_dot_u.col1 + rst_dot_du.col1 + dt_dot_d.col1 + t_dot_dd.col1;
            }
        }
        base_local[end_level].D = basis.Vec2.zero(nmutot);
        tangent_local[end_level].D = basis.Vec2.zero(nmutot);

        const local_u_start0 = &base_local[start_level].U.col[0].data;
        const local_u_start1 = &base_local[start_level].U.col[1].data;
        const tangent_u_start0 = &tangent_local[start_level].U.col[0].data;
        const tangent_u_start1 = &tangent_local[start_level].U.col[1].data;
        const prev_d_start0 = &base_orde[start_level].D.col[0];
        const prev_d_start1 = &base_orde[start_level].D.col[1];
        const tangent_prev_d_start0 = &tangent_orde[start_level].D.col[0];
        const tangent_prev_d_start1 = &tangent_orde[start_level].D.col[1];
        if (rt_active[start_level]) {
            for (0..nmutot) |imu| {
                const r_dot_d = dotGaussPair(&rt[start_level].R, imu, prev_d_start0, prev_d_start1, n_gauss);
                local_u_start0[imu] = r_dot_d.col0;
                local_u_start1[imu] = r_dot_d.col1;
                const dr_dot_d = dotGaussPair(&rt_tangent[start_level].R, imu, prev_d_start0, prev_d_start1, n_gauss);
                const r_dot_dd = dotGaussPair(&rt[start_level].R, imu, tangent_prev_d_start0, tangent_prev_d_start1, n_gauss);
                tangent_u_start0[imu] = dr_dot_d.col0 + r_dot_dd.col0;
                tangent_u_start1[imu] = dr_dot_d.col1 + r_dot_dd.col1;
            }
        } else {
            for (0..nmutot) |imu| {
                local_u_start0[imu] = 0.0;
                local_u_start1[imu] = 0.0;
                tangent_u_start0[imu] = 0.0;
                tangent_u_start1[imu] = 0.0;
            }
        }

        for (start_level + 1..end_level + 1) |ilevel| {
            const local_u0 = &base_local[ilevel].U.col[0].data;
            const local_u1 = &base_local[ilevel].U.col[1].data;
            const tangent_u0 = &tangent_local[ilevel].U.col[0].data;
            const tangent_u1 = &tangent_local[ilevel].U.col[1].data;
            if (!rt_active[ilevel]) {
                for (0..nmutot) |imu| {
                    local_u0[imu] = 0.0;
                    local_u1[imu] = 0.0;
                    tangent_u0[imu] = 0.0;
                    tangent_u1[imu] = 0.0;
                }
                continue;
            }
            const prev_d0 = &base_orde[ilevel].D.col[0];
            const prev_d1 = &base_orde[ilevel].D.col[1];
            const prev_u0 = &base_orde[ilevel - 1].U.col[0];
            const prev_u1 = &base_orde[ilevel - 1].U.col[1];
            const tangent_prev_d0 = &tangent_orde[ilevel].D.col[0];
            const tangent_prev_d1 = &tangent_orde[ilevel].D.col[1];
            const tangent_prev_u0 = &tangent_orde[ilevel - 1].U.col[0];
            const tangent_prev_u1 = &tangent_orde[ilevel - 1].U.col[1];
            for (0..nmutot) |imu| {
                const r_dot_d = dotGaussPair(&rt[ilevel].R, imu, prev_d0, prev_d1, n_gauss);
                const tst_dot_u = dotGaussPair(&rt[ilevel].T, imu, prev_u0, prev_u1, n_gauss);
                local_u0[imu] = r_dot_d.col0 + tst_dot_u.col0;
                local_u1[imu] = r_dot_d.col1 + tst_dot_u.col1;

                const dr_dot_d = dotGaussPair(&rt_tangent[ilevel].R, imu, prev_d0, prev_d1, n_gauss);
                const r_dot_dd = dotGaussPair(&rt[ilevel].R, imu, tangent_prev_d0, tangent_prev_d1, n_gauss);
                const dtst_dot_u = dotGaussPair(&rt_tangent[ilevel].T, imu, prev_u0, prev_u1, n_gauss);
                const tst_dot_du = dotGaussPair(&rt[ilevel].T, imu, tangent_prev_u0, tangent_prev_u1, n_gauss);
                tangent_u0[imu] = dr_dot_d.col0 + r_dot_dd.col0 + dtst_dot_u.col0 + tst_dot_du.col0;
                tangent_u1[imu] = dr_dot_d.col1 + r_dot_dd.col1 + dtst_dot_u.col1 + tst_dot_du.col1;
            }
        }

        transportToOtherLevels(start_level, end_level, nmutot, atten, base_local, base_orde);
        transportToOtherLevelsTangent(start_level, end_level, nmutot, atten, atten_tangent, base_local, tangent_local, base_orde, tangent_orde);

        max_value = maxOutgoingUpward(base_orde, end_level, n_gauss, nmutot);

        if (max_value < controls.performance_thresholds.threshold_conv_mult or num_orders >= num_orders_max) break;

        accumulateOrderContribution(false, base_ud, base_ud_sum_local, base_orde, base_local, start_level, end_level, nmutot);
        accumulateOrderContribution(false, result.ud, result.ud_sum_local, tangent_orde, tangent_local, start_level, end_level, nmutot);
    }

    return result;
}
