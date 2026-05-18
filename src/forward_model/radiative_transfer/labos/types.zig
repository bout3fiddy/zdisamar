const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");

pub const max_gauss: usize = 10;
pub const max_extra: usize = 2;
pub const max_nmutot: usize = max_gauss + max_extra;
pub const max_n2: usize = max_nmutot * max_nmutot;
pub const max_phase_coef: usize = phase_functions.phase_coefficient_count;

// layout(64-bit):
//   size: 1160 B, align: 8 B
//   field storage: data=1152 B, n=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: n=8 B
//   inline arrays: data:[144]f64=1152 B
//   cache span: 19 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 1160 B (1.133 KiB); total = per instance * live instance count
pub const Mat = struct {
    data: [max_n2]f64,
    n: usize,

    const Self = @This();

    pub fn zero(n: usize) Self {
        return .{ .data = .{0.0} ** max_n2, .n = n };
    }

    pub fn identity(n: usize) Self {
        var m = zero(n);
        for (0..n) |i| m.set(i, i, 1.0);
        return m;
    }

    pub fn get(self: *const Self, i: usize, j: usize) f64 {
        return self.data[i * self.n + j];
    }

    pub fn set(self: *Self, i: usize, j: usize, val: f64) void {
        self.data[i * self.n + j] = val;
    }
};

// layout(64-bit):
//   size: 104 B, align: 8 B
//   field storage: data=96 B, n=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: n=8 B
//   inline arrays: data:[12]f64=96 B
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 104 B (0.102 KiB); total = per instance * live instance count
pub const Vec = struct {
    data: [max_nmutot]f64,
    n: usize,

    pub fn zero(n: usize) Vec {
        return .{ .data = .{0.0} ** max_nmutot, .n = n };
    }

    pub fn get(self: *const Vec, i: usize) f64 {
        return self.data[i];
    }

    pub fn set(self: *Vec, i: usize, val: f64) void {
        self.data[i] = val;
    }
};

// layout(64-bit):
//   size: 216 B, align: 8 B
//   field storage: col=208 B, n=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: n=8 B
//   inline arrays: col:[2]Vec=208 B
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 216 B (0.211 KiB); total = per instance * live instance count
pub const Vec2 = struct {
    col: [2]Vec,
    n: usize,

    pub fn zero(n: usize) Vec2 {
        return .{
            .col = .{ Vec.zero(n), Vec.zero(n) },
            .n = n,
        };
    }
};

// layout(64-bit):
//   size: 2320 B, align: 8 B
//   field storage: R=1160 B, T=1160 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 37 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 2320 B (2.266 KiB); total = per instance * live instance count
pub const LayerRT = struct {
    R: Mat,
    T: Mat,
};

// layout(64-bit):
//   size: 536 B, align: 8 B
//   field storage: E=104 B, U=216 B, D=216 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 9 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 536 B (0.523 KiB); total = per instance * live instance count
pub const UDField = struct {
    E: Vec,
    U: Vec2,
    D: Vec2,
};

// layout(64-bit):
//   size: 432 B, align: 8 B
//   field storage: U=216 B, D=216 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 7 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 432 B (0.422 KiB); total = per instance * live instance count
pub const UDLocal = struct {
    U: Vec2,
    D: Vec2,
};

// layout(64-bit):
//   size: 2832 B, align: 8 B
//   field storage: 2832 B across 11 fields; largest: dmu_plus=1152 B, dmu_min=1152 B, dmu_same=144 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   inline arrays: 7 fields reserve 2800 B inside each instance
//   cache span: 45 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 2832 B (2.766 KiB); total = per instance * live instance count
pub const Geometry = struct {
    n_gauss: usize,
    nmutot: usize,
    u: [max_nmutot]f64,
    w: [max_nmutot]f64,
    ug: [max_gauss]f64,
    wg: [max_gauss]f64,
    dmu_plus: [max_n2]f64,
    dmu_min: [max_n2]f64,
    dmu_same: [max_n2]bool,
    mu0: f64,
    muv: f64,

    pub fn init(n_gauss: usize, mu0: f64, muv: f64) Geometry {
        var nodes_01: [max_gauss]f64 = undefined;
        var weights_01: [max_gauss]f64 = undefined;
        gauss_legendre.fillDisamarDivPoints01(
            @intCast(n_gauss),
            nodes_01[0..],
            weights_01[0..],
        ) catch unreachable;

        var geo: Geometry = undefined;
        geo.n_gauss = n_gauss;
        geo.nmutot = n_gauss + max_extra;
        geo.mu0 = mu0;
        geo.muv = muv;

        for (0..n_gauss) |i| {
            const ug = nodes_01[i];
            const wg = weights_01[i];
            geo.u[i] = ug;
            geo.w[i] = @sqrt(2.0 * ug * wg);
            geo.ug[i] = ug;
            geo.wg[i] = wg;
        }
        geo.u[n_gauss] = muv;
        geo.w[n_gauss] = 1.0;
        geo.u[n_gauss + 1] = mu0;
        geo.w[n_gauss + 1] = 1.0;

        for (geo.nmutot..max_nmutot) |i| {
            geo.u[i] = 0.0;
            geo.w[i] = 0.0;
        }
        for (geo.n_gauss..max_gauss) |i| {
            geo.ug[i] = 0.0;
            geo.wg[i] = 0.0;
        }
        for (0..geo.nmutot) |j| {
            const uj = geo.u[j];
            for (0..geo.nmutot) |i| {
                const ui = geo.u[i];
                const idx = i * geo.nmutot + j;
                geo.dmu_plus[idx] = 0.25 / @max(ui + uj, 1.0e-12);
                const du = ui - uj;
                if (@abs(du) < 1.0e-6) {
                    geo.dmu_same[idx] = true;
                    geo.dmu_min[idx] = 0.25 / @max(ui * uj, 1.0e-12);
                } else {
                    geo.dmu_same[idx] = false;
                    geo.dmu_min[idx] = 0.25 / du;
                }
            }
        }
        return geo;
    }

    pub fn viewIdx(self: *const Geometry) usize {
        return self.n_gauss;
    }
};
