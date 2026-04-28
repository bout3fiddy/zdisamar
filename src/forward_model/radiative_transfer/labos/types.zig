const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");

pub const max_gauss: usize = 10;
pub const max_extra: usize = 2;
pub const max_nmutot: usize = max_gauss + max_extra;
pub const max_n2: usize = max_nmutot * max_nmutot;
pub const max_phase_coef: usize = phase_functions.phase_coefficient_count;

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

    pub fn addTo(self: *Self, i: usize, j: usize, val: f64) void {
        self.data[i * self.n + j] += val;
    }
};

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

pub const LayerRT = struct {
    R: Mat,
    T: Mat,
};

pub const UDField = struct {
    E: Vec,
    U: Vec2,
    D: Vec2,
};

pub const UDLocal = struct {
    U: Vec2,
    D: Vec2,
};

pub const Geometry = struct {
    n_gauss: usize,
    nmutot: usize,
    u: [max_nmutot]f64,
    w: [max_nmutot]f64,
    ug: [max_gauss]f64,
    wg: [max_gauss]f64,
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
        return geo;
    }

    pub fn viewIdx(self: *const Geometry) usize {
        return self.n_gauss;
    }
};
