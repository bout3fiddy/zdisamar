const std = @import("std");
const math = std.math;
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");

const gauss_legendre = @import("../quadrature/gauss_legendre.zig");
const Allocator = std.mem.Allocator;

// --- Compile-time sizing ---------------------------------------------------
// Maximum Gauss points for integration over the hemisphere. The total direction
// count is nGauss + 2 (viewing + solar). With max_gauss=10 the largest matrix
// is 12x12 = 144 f64s, still comfortably stack-allocated.
pub const max_gauss: usize = 10;
pub const max_extra: usize = 2; // viewing + solar
pub const max_nmutot: usize = max_gauss + max_extra;
pub const max_n2: usize = max_nmutot * max_nmutot;
pub const max_phase_coef: usize = @import("../optics/prepare/phase_functions.zig").phase_coefficient_count;

const threshold_q: f64 = 1.0e-3;

// ---------- Stack-allocated matrix type (nmutot x nmutot) ------------------
// Stored row-major: element (i,j) = data[i * stride + j], where stride = nmutot.
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

// Column vector sized nmutot.
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

// Two-column array for (viewing, solar) internal fields.
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

// Per-layer reflection/transmission operators.
pub const LayerRT = struct {
    R: Mat, // reflection from top
    T: Mat, // transmission from top
};

// Internal radiation field at one level.
pub const UDField = struct {
    E: Vec, // direct beam attenuation
    U: Vec2, // upward diffuse (2 cols: view, solar)
    D: Vec2, // downward diffuse (2 cols: view, solar)
};

// Local source at one layer boundary (upward + downward).
pub const UDLocal = struct {
    U: Vec2,
    D: Vec2,
};

// --- Geometry setup --------------------------------------------------------
pub const Geometry = struct {
    n_gauss: usize,
    nmutot: usize,
    u: [max_nmutot]f64, // direction cosines: gauss[0..nGauss], muv, mu0
    w: [max_nmutot]f64, // supermatrix weights: sqrt(2*ug*wg) for gauss, 1.0 for extra
    mu0: f64,
    muv: f64,

    pub fn init(n_gauss: usize, mu0: f64, muv: f64) Geometry {
        const rule = gauss_legendre.rule(@intCast(n_gauss)) catch unreachable;
        var geo: Geometry = undefined;
        geo.n_gauss = n_gauss;
        geo.nmutot = n_gauss + max_extra;
        geo.mu0 = mu0;
        geo.muv = muv;

        // Gauss-Legendre points are on [-1,1]; map to (0,1) via x = (node+1)/2, w = weight/2
        for (0..n_gauss) |i| {
            const ug = (rule.nodes[i] + 1.0) * 0.5;
            const wg = rule.weights[i] * 0.5;
            geo.u[i] = ug;
            geo.w[i] = @sqrt(2.0 * ug * wg);
        }
        geo.u[n_gauss] = muv;
        geo.w[n_gauss] = 1.0;
        geo.u[n_gauss + 1] = mu0;
        geo.w[n_gauss + 1] = 1.0;

        // Fill remaining slots to defined values for safety
        for (geo.nmutot..max_nmutot) |i| {
            geo.u[i] = 0.0;
            geo.w[i] = 0.0;
        }
        return geo;
    }

    pub fn viewIdx(self: *const Geometry) usize {
        return self.n_gauss;
    }
};

// ---------- Math helpers matching vendor smul/esmul/semul/Qseries ----------

/// Matrix multiply that sums only over Gauss-point indices (0..nGauss).
/// This ensures that the extra directions (view, solar) participate only
/// as row/column recipients, not as quadrature nodes.
pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    var result = Mat.zero(n);
    // Threshold: skip multiplication if both traces are essentially zero
    var tra: f64 = 0.0;
    var trb: f64 = 0.0;
    for (0..n_gauss) |k| {
        tra += a.get(k, k);
        trb += b.get(k, k);
    }
    if (@abs(tra * trb) <= threshold_mul) return result;

    for (0..n) |j| {
        for (0..n_gauss) |k| {
            const bkj = b.get(k, j);
            for (0..n) |i| {
                result.addTo(i, j, a.get(i, k) * bkj);
            }
        }
    }
    return result;
}

/// Diagonal * matrix: result(i,j) = e(i) * a(i,j)
pub fn esmul(n: usize, e: *const Vec, a: *const Mat) Mat {
    var result = Mat.zero(n);
    for (0..n) |j| {
        for (0..n) |i| {
            result.set(i, j, e.get(i) * a.get(i, j));
        }
    }
    return result;
}

/// Matrix * diagonal: result(i,j) = a(i,j) * e(j)
pub fn semul(n: usize, a: *const Mat, e: *const Vec) Mat {
    var result = Mat.zero(n);
    for (0..n) |j| {
        const ej = e.get(j);
        for (0..n) |i| {
            result.set(i, j, a.get(i, j) * ej);
        }
    }
    return result;
}

/// Sum two matrices element-wise.
pub fn matAdd(n: usize, a: *const Mat, b: *const Mat) Mat {
    var result = Mat.zero(n);
    for (0..n * n) |idx| {
        result.data[idx] = a.data[idx] + b.data[idx];
    }
    return result;
}

/// Compute Q = (I - A*B)^{-1} * A*B via LU decomposition of the Gauss block.
/// For small Trace(AB), just returns AB (single-term approximation).
pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    const ab = smul(n, n_gauss, threshold_mul, a, b);

    // Check trace of the Gauss-Gauss block
    var trab: f64 = 0.0;
    for (0..n_gauss) |k| trab += ab.get(k, k);
    if (@abs(trab) < threshold_q) return ab;

    // Need full LU solve on the (I - AB_gg) block
    const n_extra = n - n_gauss;

    // Extract sub-blocks of AB
    var one_minus_ab_gg: [max_gauss * max_gauss]f64 = undefined;
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.get(i, j);
        }
    }

    // LU decomposition with partial pivoting (Doolittle, in-place)
    var pivot: [max_gauss]usize = undefined;
    for (0..n_gauss) |i| pivot[i] = i;

    for (0..n_gauss) |col| {
        // Find pivot
        var max_val: f64 = @abs(one_minus_ab_gg[pivot[col] * n_gauss + col]);
        var max_row: usize = col;
        for (col + 1..n_gauss) |row| {
            const val = @abs(one_minus_ab_gg[pivot[row] * n_gauss + col]);
            if (val > max_val) {
                max_val = val;
                max_row = row;
            }
        }
        if (max_row != col) {
            const tmp = pivot[col];
            pivot[col] = pivot[max_row];
            pivot[max_row] = tmp;
        }
        const diag = one_minus_ab_gg[pivot[col] * n_gauss + col];
        if (@abs(diag) < 1.0e-30) {
            // Singular — fall back to single-term
            return ab;
        }
        for (col + 1..n_gauss) |row| {
            const factor = one_minus_ab_gg[pivot[row] * n_gauss + col] / diag;
            one_minus_ab_gg[pivot[row] * n_gauss + col] = factor;
            for (col + 1..n_gauss) |k| {
                one_minus_ab_gg[pivot[row] * n_gauss + k] -= factor * one_minus_ab_gg[pivot[col] * n_gauss + k];
            }
        }
    }

    // Solve for inverse column by column
    var inverse: [max_gauss * max_gauss]f64 = .{0.0} ** (max_gauss * max_gauss);
    for (0..n_gauss) |rhs_col| {
        // Forward substitution
        var y: [max_gauss]f64 = .{0.0} ** max_gauss;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            for (0..i) |j| {
                s -= one_minus_ab_gg[pivot[i] * n_gauss + j] * y[j];
            }
            y[i] = s;
        }
        // Back substitution
        var x: [max_gauss]f64 = .{0.0} ** max_gauss;
        var ii: usize = n_gauss;
        while (ii > 0) {
            ii -= 1;
            var s: f64 = y[ii];
            for (ii + 1..n_gauss) |j| {
                s -= one_minus_ab_gg[pivot[ii] * n_gauss + j] * x[j];
            }
            x[ii] = s / one_minus_ab_gg[pivot[ii] * n_gauss + ii];
        }
        for (0..n_gauss) |i| inverse[i * n_gauss + rhs_col] = x[i];
    }

    // Build result: Q(gg) = inv - I, Q(ag) = ab_ag * inv, Q(ga) = inv * ab_ga,
    // Q(aa) = ab_ag * inv * ab_ga + ab_aa
    var result = Mat.zero(n);

    // Q(gg) = inverse - I
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.set(i, j, inverse[i * n_gauss + j] - delta);
        }
    }

    // Q(ga) = inverse * ab_ga
    for (0..n_extra) |ja| {
        for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| {
                s += inverse[i * n_gauss + k] * ab.get(k, n_gauss + ja);
            }
            result.set(i, n_gauss + ja, s);
        }
    }

    // tmp = ab_ag * inverse, and Q(ag) = tmp
    var tmp: [max_extra * max_gauss]f64 = .{0.0} ** (max_extra * max_gauss);
    for (0..n_extra) |ia| {
        for (0..n_gauss) |j| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| {
                s += ab.get(n_gauss + ia, k) * inverse[k * n_gauss + j];
            }
            tmp[ia * n_gauss + j] = s;
            result.set(n_gauss + ia, j, s);
        }
    }

    // Q(aa) = tmp * ab_ga + ab_aa
    for (0..n_extra) |ia| {
        for (0..n_extra) |ja| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| {
                s += tmp[ia * n_gauss + k] * ab.get(k, n_gauss + ja);
            }
            result.set(n_gauss + ia, n_gauss + ja, s + ab.get(n_gauss + ia, n_gauss + ja));
        }
    }

    return result;
}

// ---------- Legendre functions for scalar Fourier decomposition -----------

/// Associated Legendre function values P_l^m(u) for scalar case (dimSV=1).
/// Returns PlmPlus (for +u) and PlmMin (for -u), both multiplied by
/// the supermatrix weight w(imu). These are used in fillZplusZmin.
const PlmArrays = struct {
    plus: [max_nmutot]f64,
    minus: [max_nmutot]f64,
};

fn computePlm(
    i_fourier: usize,
    coef_idx: usize,
    geo: *const Geometry,
) PlmArrays {
    // Compute PlmPlus and PlmMin for all direction cosines at a single l value.
    // For the scalar case this is the associated Legendre polynomial P_l^m.
    const n = geo.nmutot;
    if (coef_idx < i_fourier) {
        return .{
            .plus = .{0.0} ** max_nmutot,
            .minus = .{0.0} ** max_nmutot,
        };
    }

    // Pre-compute sqrt(l^2 - m^2)
    var sqlm: [max_phase_coef]f64 = .{0.0} ** max_phase_coef;
    for (i_fourier + 1..max_phase_coef) |l| {
        const lf: f64 = @floatFromInt(l);
        const mf: f64 = @floatFromInt(i_fourier);
        sqlm[l] = @sqrt(lf * lf - mf * mf);
    }

    // Compute starting values and recurrence for +u and -u
    var plm_plus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
    var plm_minus: [max_nmutot]f64 = .{0.0} ** max_nmutot;

    // Starting values at l = m = iFourier
    var p_lm1_plus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
    var p_l_plus: [max_nmutot]f64 = undefined;
    var p_lm1_minus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
    var p_l_minus: [max_nmutot]f64 = undefined;

    for (0..n) |imu| {
        const u = geo.u[imu];
        const one_minus_uu = 1.0 - u * u;
        const squu = @sqrt(@max(one_minus_uu, 0.0));

        const start_val: f64 = switch (i_fourier) {
            0 => 1.0,
            1 => squu / @sqrt(2.0),
            2 => 0.25 * @sqrt(6.0) * one_minus_uu,
            else => blk: {
                // pmm = sqrt( (1-u^2)^m * 4^(-m) * (2m)! / (m!)^2 )
                var f: f64 = 0.375 * one_minus_uu * one_minus_uu;
                for (3..i_fourier + 1) |m_idx| {
                    const mf: f64 = @floatFromInt(m_idx);
                    f *= one_minus_uu * (mf - 0.5) / mf;
                }
                break :blk @sqrt(@max(f, 0.0));
            },
        };
        p_l_plus[imu] = start_val;
        p_l_minus[imu] = start_val;
    }

    // Store starting value
    if (coef_idx == i_fourier) {
        for (0..n) |imu| {
            plm_plus[imu] = p_l_plus[imu] * geo.w[imu];
            plm_minus[imu] = p_l_minus[imu] * geo.w[imu];
        }
        return .{ .plus = plm_plus, .minus = plm_minus };
    }

    // Recurrence for +u up to coef_idx
    for (i_fourier..coef_idx) |l| {
        const a_coef = sqlm[l + 1];
        const c_coef = -sqlm[l];
        for (0..n) |imu| {
            const b_plus = (2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
            const p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
            p_lm1_plus[imu] = p_l_plus[imu];
            p_l_plus[imu] = p_lp1;

            const b_minus = -(2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
            const p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
            p_lm1_minus[imu] = p_l_minus[imu];
            p_l_minus[imu] = p_lp1_m;
        }
    }

    for (0..n) |imu| {
        plm_plus[imu] = p_l_plus[imu] * geo.w[imu];
        plm_minus[imu] = p_l_minus[imu] * geo.w[imu];
    }

    return .{ .plus = plm_plus, .minus = plm_minus };
}

// ---------- Phase function matrix construction (scalar case) ---------------

/// Build Zplus(i,j) and Zmin(i,j) for scalar case (dimSV_fc=1):
///   Zplus(i,j) = sum_l alpha1(l) * Plm(+u_i) * Plm(+u_j)
///   Zmin(i,j)  = sum_l alpha1(l) * Plm(-u_i) * Plm(+u_j)
/// where the Plm values already include the supermatrix weights.
fn fillZplusZmin(
    i_fourier: usize,
    phase_coefs: [max_phase_coef]f64,
    geo: *const Geometry,
) struct { Zplus: Mat, Zmin: Mat } {
    const n = geo.nmutot;
    var zplus = Mat.zero(n);
    var zmin = Mat.zero(n);

    const max_coef = max_phase_coef;
    for (i_fourier..max_coef) |l| {
        const plm = computePlm(i_fourier, l, geo);
        const alpha1 = phase_coefs[l];
        for (0..n) |j| {
            const pj = plm.plus[j];
            for (0..n) |i| {
                zplus.addTo(i, j, alpha1 * plm.plus[i] * pj);
                zmin.addTo(i, j, alpha1 * plm.minus[i] * pj);
            }
        }
    }

    return .{ .Zplus = zplus, .Zmin = zmin };
}

// ---------- Attenuation between levels -------------------------------------

/// Attenuation array: atten[imu][from][to] = exp(-slant optical depth between
/// levels `from` and `to` along direction u[imu]). For plane-parallel geometry,
/// atten(from,to) = atten(to,from). Indices: level 0 = surface, level nlayer = TOA.
pub const AttenArray = struct {
    pub const max_levels: usize = 65; // max transport layers + 1

    /// data[imu][from][to]
    data: [max_nmutot][max_levels][max_levels]f64,
    nmutot: usize,
    nlayer: usize,

    pub fn get(self: *const AttenArray, imu: usize, from: usize, to: usize) f64 {
        return self.data[imu][from][to];
    }

    fn set(self: *AttenArray, imu: usize, from: usize, to: usize, val: f64) void {
        self.data[imu][from][to] = val;
    }
};

pub const DynamicAttenArray = struct {
    allocator: Allocator,
    data: []f64,
    nmutot: usize,
    nlevel: usize,

    fn init(allocator: Allocator, nmutot: usize, nlevel: usize) !DynamicAttenArray {
        const data = try allocator.alloc(f64, nmutot * nlevel * nlevel);
        for (data) |*value| value.* = 1.0;
        return .{
            .allocator = allocator,
            .data = data,
            .nmutot = nmutot,
            .nlevel = nlevel,
        };
    }

    pub fn deinit(self: *DynamicAttenArray) void {
        self.allocator.free(self.data);
        self.* = undefined;
    }

    fn index(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) usize {
        return (imu * self.nlevel + from) * self.nlevel + to;
    }

    pub fn get(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) f64 {
        return self.data[self.index(imu, from, to)];
    }

    pub fn set(self: *DynamicAttenArray, imu: usize, from: usize, to: usize, value: f64) void {
        self.data[self.index(imu, from, to)] = value;
    }
};

pub fn fillAttenuation(
    layers: []const common.LayerInput,
    geo: *const Geometry,
    use_spherical_correction: bool,
) AttenArray {
    const nlayer = layers.len;
    var atten: AttenArray = undefined;
    atten.nmutot = geo.nmutot;
    atten.nlayer = nlayer;

    // Initialize to 1.0 (no attenuation for same level)
    for (0..geo.nmutot) |imu| {
        for (0..nlayer + 1) |from| {
            for (0..nlayer + 1) |to| {
                atten.data[imu][from][to] = 1.0;
            }
        }
    }

    // Per-layer attenuation: attenLay[imu][ilayer] = exp(-tau_layer / u_imu)
    // Layer indexing: layer i has index i+1 (1-based in Fortran), level 0=surface, level nlayer=TOA.
    // In our 0-based scheme: layer_idx 0 maps to Fortran layer 1 (between levels 0 and 1).

    // Build cumulative attenuation from level ilTo downward (Fortran convention)
    // atten(imu, ilFrom-1, ilTo) = atten(imu, ilFrom, ilTo) * exp(-tau[ilFrom]/u)
    for (0..nlayer) |ilTo_0| {
        const ilTo = ilTo_0 + 1;
        // Start: atten(imu, ilTo, ilTo) = 1.0 (already set)
        // Go downward
        var ilFrom_idx = ilTo;
        while (ilFrom_idx >= 1) : (ilFrom_idx -= 1) {
            const layer_idx = ilFrom_idx - 1; // 0-based layer index
            for (0..geo.nmutot) |imu| {
                const u = @max(geo.u[imu], 1.0e-6);
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);
                atten.data[imu][ilFrom_idx - 1][ilTo] = atten.data[imu][ilFrom_idx][ilTo] * atten_lay;
            }
        }
    }

    // Symmetry for plane-parallel: atten(from, to) = atten(to, from) when from > to
    for (0..nlayer + 1) |ilTo| {
        for (ilTo..nlayer + 1) |ilFrom| {
            for (0..geo.nmutot) |imu| {
                atten.data[imu][ilFrom][ilTo] = atten.data[imu][ilTo][ilFrom];
            }
        }
    }

    if (use_spherical_correction) {
        applyPseudoSphericalTopLevelAttenuation(&atten, layers, geo);
    }

    return atten;
}

pub fn fillAttenuationDynamic(
    allocator: Allocator,
    layers: []const common.LayerInput,
    geo: *const Geometry,
    use_spherical_correction: bool,
) !DynamicAttenArray {
    return fillAttenuationDynamicWithGrid(
        allocator,
        layers,
        .{},
        geo,
        use_spherical_correction,
    );
}

pub fn fillAttenuationDynamicWithGrid(
    allocator: Allocator,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const Geometry,
    use_spherical_correction: bool,
) !DynamicAttenArray {
    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    var atten = try DynamicAttenArray.init(allocator, geo.nmutot, nlevel);

    for (0..nlayer) |ilTo_0| {
        const ilTo = ilTo_0 + 1;
        var ilFrom_idx = ilTo;
        while (ilFrom_idx >= 1) : (ilFrom_idx -= 1) {
            const layer_idx = ilFrom_idx - 1;
            for (0..geo.nmutot) |imu| {
                const u = @max(geo.u[imu], 1.0e-6);
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);
                atten.set(imu, ilFrom_idx - 1, ilTo, atten.get(imu, ilFrom_idx, ilTo) * atten_lay);
            }
        }
    }

    for (0..nlevel) |ilTo| {
        for (ilTo..nlevel) |ilFrom| {
            for (0..geo.nmutot) |imu| {
                atten.set(imu, ilFrom, ilTo, atten.get(imu, ilTo, ilFrom));
            }
        }
    }

    if (use_spherical_correction) {
        if (pseudo_spherical_grid.isValidFor(nlayer)) {
            applyPseudoSphericalTopLevelAttenuationDynamicWithGrid(&atten, pseudo_spherical_grid, geo);
        } else {
            applyPseudoSphericalTopLevelAttenuationDynamic(&atten, layers, geo);
        }
    }

    return atten;
}

fn levelAltitudeFromPseudoSphericalGrid(
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    level: usize,
) f64 {
    if (pseudo_spherical_grid.level_altitudes_km.len != 0) {
        return pseudo_spherical_grid.level_altitudes_km[level];
    }
    if (level == 0) {
        const first = pseudo_spherical_grid.samples[0];
        return @max(first.altitude_km - 0.5 * first.thickness_km, 0.0);
    }

    const start_index = pseudo_spherical_grid.level_sample_starts[level];
    if (start_index >= pseudo_spherical_grid.samples.len) {
        const last = pseudo_spherical_grid.samples[pseudo_spherical_grid.samples.len - 1];
        return @max(last.altitude_km + 0.5 * last.thickness_km, 0.0);
    }

    const sample = pseudo_spherical_grid.samples[start_index];
    return @max(sample.altitude_km - 0.5 * sample.thickness_km, 0.0);
}

fn applyPseudoSphericalTopLevelAttenuationDynamicWithGrid(
    atten: *DynamicAttenArray,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const Geometry,
) void {
    const rearth_km = 6371.0;
    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;
    for (0..geo.nmutot) |imu| {
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const level_radius = rearth_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
            const sqrx_sin2theta = sin2theta * level_radius * level_radius;
            var sumkext: f64 = 0.0;
            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const sample = pseudo_spherical_grid.samples[index];
                if (sample.optical_depth <= 0.0) continue;
                const sample_radius = rearth_km + sample.altitude_km;
                const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
                sumkext += (sample.optical_depth * sample_radius) / @max(denominator, 1.0e-12);
            }
            atten.set(imu, top_level, level, math.exp(-sumkext));
        }
    }
}

fn pseudoSphericalDirectionCosine(
    geo: *const Geometry,
    layer: common.LayerInput,
    imu: usize,
) f64 {
    if (imu == geo.viewIdx()) return layer.view_mu;
    if (imu == geo.n_gauss + 1) return layer.solar_mu;
    return geo.u[imu];
}

fn applyPseudoSphericalTopLevelAttenuation(
    atten: *AttenArray,
    layers: []const common.LayerInput,
    geo: *const Geometry,
) void {
    const top_level = layers.len;
    for (0..geo.nmutot) |imu| {
        var cumulative: f64 = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), 1.0e-6);
            cumulative *= math.exp(-layers[level].optical_depth / u);
            atten.set(imu, top_level, level, cumulative);
        }
    }
}

fn applyPseudoSphericalTopLevelAttenuationDynamic(
    atten: *DynamicAttenArray,
    layers: []const common.LayerInput,
    geo: *const Geometry,
) void {
    const top_level = layers.len;
    for (0..geo.nmutot) |imu| {
        var cumulative: f64 = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), 1.0e-6);
            cumulative *= math.exp(-layers[level].optical_depth / u);
            atten.set(imu, top_level, level, cumulative);
        }
    }
}

// ---------- Single-scatter R and T for a layer ----------------------------

/// Rsingle: single-scattering reflection for a homogeneous layer.
///   R(i,j) = a * Zmin(i,j) * (1 - E(i)*E(j)) * DmuPlus(i,j)
/// where DmuPlus(i,j) = 0.25 / (u_i + u_j).
fn singleScatterR(
    a: f64,
    E: *const Vec,
    Zmin: *const Mat,
    geo: *const Geometry,
) Mat {
    const n = geo.nmutot;
    var result = Mat.zero(n);

    for (0..n) |j| {
        const uj = geo.u[j];
        const ej = E.get(j);
        for (0..n) |i| {
            const ui = geo.u[i];
            const dmu_plus = 0.25 / @max(ui + uj, 1.0e-12);
            const eer = E.get(i) * ej;
            result.set(i, j, a * Zmin.get(i, j) * (1.0 - eer) * dmu_plus);
        }
    }
    return result;
}

/// Tsingle: single-scattering transmission for a homogeneous layer.
///   T(i,j) = a * Zplus(i,j) * EET(i,j) * DmuMin(i,j)
/// where DmuMin(i,j) = 0.25/(u_i - u_j) when |u_i-u_j| > eps, else 0.25/(u_i*u_j)
/// and EET(i,j) = (E(i) - E(j))/(u_i-u_j) when |u_i-u_j| > eps, else b*E(i)
fn singleScatterT(
    a: f64,
    b: f64,
    E: *const Vec,
    Zplus: *const Mat,
    geo: *const Geometry,
) Mat {
    const n = geo.nmutot;
    var result = Mat.zero(n);

    for (0..n) |j| {
        const uj = geo.u[j];
        for (0..n) |i| {
            const ui = geo.u[i];
            const du = ui - uj;
            var eet: f64 = undefined;
            var dmu_min: f64 = undefined;
            if (@abs(du) < 1.0e-6) {
                eet = b * E.get(i);
                dmu_min = 0.25 / @max(ui * uj, 1.0e-12);
            } else {
                eet = E.get(i) - E.get(j);
                dmu_min = 0.25 / du;
            }
            result.set(i, j, a * Zplus.get(i, j) * eet * dmu_min);
        }
    }
    return result;
}

// ---------- Doubling for thick layers -------------------------------------

/// Perform ndouble doubling steps on R, T, E for a layer.
fn doDouble(
    ndouble: usize,
    n: usize,
    n_gauss: usize,
    threshold_mul: f64,
    geo: *const Geometry,
    b_start: f64,
    R: *Mat,
    T: *Mat,
    E: *Vec,
) void {
    var b = b_start;
    for (0..ndouble) |_| {
        // For scalar case, Rst = R and Tst = T (transform_top_bottom is identity for dimSV_fc < 3)
        const Q = qseries(n, n_gauss, threshold_mul, R, R);
        // D = T + semul(Q, E) + smul(Q, T)
        const qe = semul(n, &Q, E);
        const qt = smul(n, n_gauss, threshold_mul, &Q, T);
        var D = matAdd(n, T, &qe);
        D = matAdd(n, &D, &qt);

        // U = semul(R, E) + smul(R, D)
        const re = semul(n, R, E);
        const rd = smul(n, n_gauss, threshold_mul, R, &D);
        const U = matAdd(n, &re, &rd);

        // R_new = R + esmul(E, U) + smul(Tst, U) — Tst = T for scalar
        const eu = esmul(n, E, &U);
        const tu = smul(n, n_gauss, threshold_mul, T, &U);
        var R_new = matAdd(n, R, &eu);
        R_new = matAdd(n, &R_new, &tu);
        R.* = R_new;

        // T_new = esmul(E, D) + semul(T, E) + smul(T, D)
        const ed = esmul(n, E, &D);
        const te = semul(n, T, E);
        const td = smul(n, n_gauss, threshold_mul, T, &D);
        var T_new = matAdd(n, &ed, &te);
        T_new = matAdd(n, &T_new, &td);
        T.* = T_new;

        b *= 2.0;
        // Recompute E to avoid loss of significant digits
        if (b < 0.001) {
            for (0..geo.nmutot) |imu| {
                E.set(imu, math.exp(-b / @max(geo.u[imu], 1.0e-12)));
            }
        } else {
            for (0..geo.nmutot) |imu| {
                const e = E.get(imu);
                E.set(imu, e * e);
            }
        }
    }
}

// ---------- Per-layer R/T calculation (CalcRTlayers) -----------------------

pub fn calcRTlayersInto(
    rt: []LayerRT,
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const Geometry,
    controls: common.RtmControls,
) void {
    const nlayer = layers.len;

    for (rt) |*entry| {
        entry.* = .{
            .R = Mat.zero(geo.nmutot),
            .T = Mat.zero(geo.nmutot),
        };
    }

    // Pre-compute DmuPlus and DmuMin (not needed explicitly since singleScatterR/T compute inline)

    for (0..nlayer) |layer_idx| {
        // Fortran layer numbering starts at 1 for atmospheric layers (above surface)
        const rt_idx = layer_idx + 1;
        const layer = layers[layer_idx];

        if (layer.optical_depth < 1.0e-20) continue;

        // Check if this Fourier term is needed (phase coef count check)
        if (i_fourier >= max_phase_coef) continue;

        const b = layer.optical_depth;
        const a = layer.single_scatter_albedo;
        const phase_coefs = layer.phase_coefficients;

        // Determine effective SSA for doubling threshold
        var max_beta_eff: f64 = 0.0;
        for (i_fourier..max_phase_coef) |ic| {
            const icf: f64 = @floatFromInt(ic);
            const beta_eff = @abs(phase_coefs[ic]) / (2.0 * icf + 1.0);
            if (beta_eff > max_beta_eff) max_beta_eff = beta_eff;
        }
        const a_eff = a * max_beta_eff;

        // Build Z matrices for this layer
        const z = fillZplusZmin(i_fourier, phase_coefs, geo);

        var use_doubling = false;
        var b_start = b;
        var ndouble: usize = 0;

        if (controls.scattering == .multiple and a_eff * b > controls.threshold_doubl) {
            use_doubling = true;
            var bd = b;
            for (0..60) |_| {
                bd /= 2.0;
                ndouble += 1;
                if (a_eff * bd < controls.threshold_doubl) break;
            }
            b_start = bd;
        }

        // Compute E vector
        var E = Vec.zero(geo.nmutot);
        for (0..geo.nmutot) |imu| {
            E.set(imu, math.exp(-b_start / @max(geo.u[imu], 1.0e-12)));
        }

        var R = singleScatterR(a, &E, &z.Zmin, geo);
        var T = singleScatterT(a, b_start, &E, &z.Zplus, geo);

        if (use_doubling) {
            doDouble(ndouble, geo.nmutot, geo.n_gauss, controls.threshold_mul, geo, b_start, &R, &T, &E);
        }

        rt[rt_idx].R = R;
        rt[rt_idx].T = T;
    }
}

pub fn calcRTlayers(
    layers: []const common.LayerInput,
    i_fourier: usize,
    geo: *const Geometry,
    controls: common.RtmControls,
) [AttenArray.max_levels]LayerRT {
    var rt: [AttenArray.max_levels]LayerRT = undefined;
    calcRTlayersInto(rt[0 .. layers.len + 1], layers, i_fourier, geo, controls);
    return rt;
}

// ---------- Surface treatment (Lambertian) --------------------------------

/// Fill the surface R/T for a Lambertian reflector at level 0 (or cloud level).
/// For iFourier=0, R(i,j) = w(i) * albedo * w(j). Otherwise R=T=0.
pub fn fillSurface(
    i_fourier: usize,
    albedo: f64,
    geo: *const Geometry,
) LayerRT {
    const n = geo.nmutot;
    var result: LayerRT = .{
        .R = Mat.zero(n),
        .T = Mat.zero(n),
    };

    if (i_fourier == 0) {
        for (0..n) |j| {
            for (0..n) |i| {
                result.R.set(i, j, geo.w[i] * albedo * geo.w[j]);
            }
        }
    }

    return result;
}

// ---------- Orders of scattering ------------------------------------------

const OrdersResult = struct {
    allocator: Allocator,
    ud: []UDField,
    ud_sum_local: []UDLocal,

    fn deinit(self: *OrdersResult) void {
        self.allocator.free(self.ud);
        self.allocator.free(self.ud_sum_local);
        self.* = undefined;
    }
};

/// Transport scattered light from local sources to all interface levels.
/// Upward: accumulate from surface toward TOA.
/// Downward: accumulate from TOA toward surface. No diffuse light enters at TOA.
fn transportToOtherLevels(
    start_level: usize,
    end_level: usize,
    nmutot: usize,
    atten: anytype,
    ud_local: []const UDLocal,
    ud_orde: []UDField,
) void {
    // Upward: level start -> end
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

    // Downward: no diffuse light at TOA
    ud_orde[end_level].D = Vec2.zero(nmutot);
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
pub fn dotGauss(mat: *const Mat, row: usize, vec_col: *const Vec, n_gauss: usize) f64 {
    var s: f64 = 0.0;
    for (0..n_gauss) |k| {
        s += mat.get(row, k) * vec_col.get(k);
    }
    return s;
}

fn ordersScat(
    allocator: Allocator,
    start_level: usize,
    end_level: usize,
    geo: *const Geometry,
    atten: anytype,
    rt: []const LayerRT,
    controls: common.RtmControls,
    num_orders_max: usize,
) !OrdersResult {
    const nmutot = geo.nmutot;
    const n_gauss = geo.n_gauss;
    const nlevel = end_level + 1;

    const ud = try allocator.alloc(UDField, nlevel);
    var ud_owned_by_result = false;
    errdefer if (!ud_owned_by_result) allocator.free(ud);
    const ud_sum_local = try allocator.alloc(UDLocal, nlevel);
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

    var ud_orde = try allocator.alloc(UDField, nlevel);
    defer allocator.free(ud_orde);
    var ud_local = try allocator.alloc(UDLocal, nlevel);
    defer allocator.free(ud_local);

    for (result.ud, result.ud_sum_local, ud_orde, ud_local) |*field, *sum_local, *orde, *local| {
        field.* = .{
            .E = Vec.zero(nmutot),
            .U = Vec2.zero(nmutot),
            .D = Vec2.zero(nmutot),
        };
        sum_local.* = .{
            .U = Vec2.zero(nmutot),
            .D = Vec2.zero(nmutot),
        };
        orde.* = .{
            .E = Vec.zero(nmutot),
            .U = Vec2.zero(nmutot),
            .D = Vec2.zero(nmutot),
        };
        local.* = .{
            .U = Vec2.zero(nmutot),
            .D = Vec2.zero(nmutot),
        };
    }

    // Copy attenuation from TOA (end_level) to each level
    for (start_level..end_level + 1) |ilevel| {
        for (0..nmutot) |imu| {
            const att = atten.get(imu, end_level, ilevel);
            ud_orde[ilevel].E.set(imu, att);
            result.ud[ilevel].E.set(imu, att);
        }
    }

    // First order: single scattering by layers
    // Downward local source: T(all, nGauss+imu0) * atten(nGauss+imu0, TOA, layer_top)
    for (start_level..end_level) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0; // viewing or solar column
            const att = atten.get(col_idx, end_level, ilevel + 1);
            for (0..nmutot) |imu| {
                ud_local[ilevel].D.col[imu0].set(imu, rt[ilevel + 1].T.get(imu, col_idx) * att);
            }
        }
    }
    // No diffuse light at TOA
    ud_local[end_level].D = Vec2.zero(nmutot);

    // Upward local source: R(all, nGauss+imu0) * atten(nGauss+imu0, TOA, level)
    for (start_level..end_level + 1) |ilevel| {
        for (0..2) |imu0| {
            const col_idx = n_gauss + imu0;
            const att = atten.get(col_idx, end_level, ilevel);
            for (0..nmutot) |imu| {
                ud_local[ilevel].U.col[imu0].set(imu, rt[ilevel].R.get(imu, col_idx) * att);
            }
        }
    }

    // Initialize UDsumLocal with first order
    for (start_level..end_level + 1) |ilevel| {
        result.ud_sum_local[ilevel].U = ud_local[ilevel].U;
        result.ud_sum_local[ilevel].D = ud_local[ilevel].D;
    }

    transportToOtherLevels(start_level, end_level, nmutot, atten, ud_local, ud_orde);

    // Copy first order to total
    for (start_level..end_level + 1) |ilevel| {
        result.ud[ilevel].U = ud_orde[ilevel].U;
        result.ud[ilevel].D = ud_orde[ilevel].D;
    }

    // Test convergence after first order
    var max_value: f64 = 0.0;
    for (0..2) |imu0| {
        for (n_gauss..nmutot) |imu| {
            const val = @abs(ud_orde[end_level].U.col[imu0].get(imu));
            if (val > max_value) max_value = val;
        }
    }
    if (controls.scattering != .multiple or max_value < controls.threshold_conv_first) return result;

    // Higher orders of scattering
    var num_orders: usize = 1;
    var sum_int_field_prev: [2]f64 = .{ 0.0, 0.0 };

    while (true) {
        num_orders += 1;

        // Compute new local sources from previous order's field
        // Downward at internal levels: D_local = Rst * U_prev + T * D_prev (Gauss part only)
        // For scalar: Rst = R (transform_top_bottom is identity)
        for (start_level..end_level) |ilevel| {
            for (0..2) |imu0| {
                for (0..nmutot) |imu| {
                    const rst_dot_u = dotGauss(&rt[ilevel + 1].R, imu, &ud_orde[ilevel].U.col[imu0], n_gauss);
                    const t_dot_d = dotGauss(&rt[ilevel + 1].T, imu, &ud_orde[ilevel + 1].D.col[imu0], n_gauss);
                    ud_local[ilevel].D.col[imu0].set(imu, rst_dot_u + t_dot_d);
                }
            }
        }
        ud_local[end_level].D = Vec2.zero(nmutot);

        // Upward at surface/start level: R * D_prev (Gauss part only)
        for (0..2) |imu0| {
            for (0..nmutot) |imu| {
                const r_dot_d = dotGauss(&rt[start_level].R, imu, &ud_orde[start_level].D.col[imu0], n_gauss);
                ud_local[start_level].U.col[imu0].set(imu, r_dot_d);
            }
        }

        // Upward at higher levels: R * D_prev + Tst * U_prev (Gauss part only)
        // For scalar: Tst = T
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

        // Test convergence
        max_value = 0.0;
        for (0..2) |imu0| {
            for (n_gauss..nmutot) |imu| {
                const val = @abs(ud_orde[end_level].U.col[imu0].get(imu));
                if (val > max_value) max_value = val;
            }
        }

        if (max_value < controls.threshold_conv_mult or num_orders >= num_orders_max) {
            // Compute eigenvalue for geometric-series summation of remaining orders
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
                // Use geometric series approximation for remaining orders
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
                // Simple accumulation for early exit
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

        // Accumulate this order into totals
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

        // Update prev sum for eigenvalue calculation
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

// ---------- Reflectance calculation (CalcReflectance) ----------------------

/// Extract TOA reflectance from the internal radiation field.
/// For scalar case, uses U at TOA for the solar column (col index 1 = solar).
pub fn calcReflectance(
    ud: []const UDField,
    end_level: usize,
    geo: *const Geometry,
) f64 {
    // The reflectance for the solar column (is=2 in Fortran, is=1 in 0-based)
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    return ud[end_level].U.col[solar_col].get(view_idx);
}

fn sourceInterfaceAtLevel(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) common.SourceInterfaceInput {
    if (source_interfaces.len == layers.len + 1 and ilevel < source_interfaces.len) {
        return source_interfaces[ilevel];
    }
    return common.sourceInterfaceFromLayers(layers, ilevel);
}

fn maxPhaseCoefficientIndex(phase_coefficients: [max_phase_coef]f64) usize {
    var max_index: usize = 0;
    for (1..max_phase_coef) |idx| {
        if (@abs(phase_coefficients[idx]) > 1.0e-12) {
            max_index = idx;
        }
    }
    return max_index;
}

fn maxInterfacePhaseCoefficientIndex(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    ilevel: usize,
) usize {
    const source_interface = sourceInterfaceAtLevel(layers, source_interfaces, ilevel);
    const above_max = maxPhaseCoefficientIndex(source_interface.phase_coefficients_above);
    if (layers.len == 0 or ilevel == 0 or ilevel > layers.len - 1) return above_max;
    const below_max = maxPhaseCoefficientIndex(layers[ilevel - 1].phase_coefficients);
    return @max(above_max, below_max);
}

pub fn calcIntegratedReflectance(
    layers: []const common.LayerInput,
    source_interfaces: []const common.SourceInterfaceInput,
    rtm_quadrature: common.RtmQuadratureGrid,
    ud: []const UDField,
    end_level: usize,
    i_fourier: usize,
    geo: *const Geometry,
) f64 {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const view_mu = @max(geo.u[view_idx], 1.0e-12);
    var reflectance: f64 = 0.0;
    const use_rtm_quadrature = rtm_quadrature.isValidFor(layers.len);

    for (0..end_level + 1) |ilevel| {
        const source_interface = if (use_rtm_quadrature)
            common.SourceInterfaceInput{}
        else
            sourceInterfaceAtLevel(layers, source_interfaces, ilevel);
        const source_weight = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].weightedScattering()
        else
            source_interface.effectiveWeight();
        if (source_weight <= 0.0) continue;
        const phase_coefficients = if (use_rtm_quadrature)
            rtm_quadrature.levels[ilevel].phase_coefficients
        else
            source_interface.phase_coefficients_above;
        if (i_fourier > if (use_rtm_quadrature)
            maxPhaseCoefficientIndex(phase_coefficients)
        else
            maxInterfacePhaseCoefficientIndex(layers, source_interfaces, ilevel))
        {
            continue;
        }

        const z = fillZplusZmin(i_fourier, phase_coefficients, geo);
        var pmin_ed: f64 = 0.0;
        var pplusst_u: f64 = 0.0;

        for (0..geo.n_gauss) |imu| {
            const mu = @max(geo.u[imu], 1.0e-12);
            const pmin = 0.25 * z.Zmin.get(view_idx, imu) / (view_mu * mu);
            const pplusst = 0.25 * z.Zplus.get(view_idx, imu) / (view_mu * mu);
            pmin_ed += pmin * ud[ilevel].D.col[solar_col].get(imu);
            pplusst_u += pplusst * ud[ilevel].U.col[solar_col].get(imu);
        }

        const solar_mu = @max(geo.u[solar_idx], 1.0e-12);
        pmin_ed += 0.25 * z.Zmin.get(view_idx, solar_idx) /
            (view_mu * solar_mu) * ud[ilevel].E.get(solar_idx);

        reflectance += ud[ilevel].E.get(view_idx) *
            source_weight *
            (pmin_ed + pplusst_u);
    }

    if (i_fourier == 0) {
        reflectance += ud[0].E.get(view_idx) * ud[0].U.col[solar_col].get(view_idx);
    }

    return reflectance;
}

fn totalScatteringOpticalDepth(layers: []const common.LayerInput) f64 {
    var total: f64 = 0.0;
    for (layers) |layer| total += @max(layer.scattering_optical_depth, 0.0);
    return total;
}

fn maxFourierIndex(layers: []const common.LayerInput) usize {
    var max_index: usize = 0;
    for (layers) |layer| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(layer.phase_coefficients));
    }
    return max_index;
}

fn maxFourierIndexInterfaces(source_interfaces: []const common.SourceInterfaceInput) usize {
    var max_index: usize = 0;
    for (source_interfaces) |source_interface| {
        max_index = @max(max_index, maxPhaseCoefficientIndex(source_interface.phase_coefficients_above));
    }
    return max_index;
}

fn maxFourierIndexQuadrature(rtm_quadrature: common.RtmQuadratureGrid) usize {
    var max_index: usize = 0;
    for (rtm_quadrature.levels) |level| {
        if (level.weight <= 0.0 or level.ksca <= 0.0) continue;
        max_index = @max(max_index, maxPhaseCoefficientIndex(level.phase_coefficients));
    }
    return max_index;
}

pub fn resolvedFourierMax(input: common.ForwardInput, controls: common.RtmControls) usize {
    _ = controls;
    if (input.layers.len == 0) return 0;
    // Match the vendor scalar short-circuit for near-normal geometries where
    // azimuth dependence vanishes numerically.
    if ((1.0 - input.muv) < 1.0e-5 or (1.0 - input.mu0) < 1.0e-5) return 0;
    if (input.rtm_quadrature.isValidFor(input.layers.len)) {
        return maxFourierIndexQuadrature(input.rtm_quadrature);
    }
    if (input.source_interfaces.len == input.layers.len + 1) {
        return maxFourierIndexInterfaces(input.source_interfaces);
    }
    return maxFourierIndex(input.layers);
}

fn directSurfaceOnlyReflectance(input: common.ForwardInput) f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const direct = math.exp(-input.optical_depth / mu0) * math.exp(-input.optical_depth / muv);
    return math.clamp(input.surface_albedo * direct, 0.0, 2.0);
}

fn directSurfaceOnlyReflectanceResolved(
    allocator: Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    if (input.layers.len == 0) return directSurfaceOnlyReflectance(input);

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const geo = Geometry.init(controls.nGauss(), mu0, muv);
    var atten = try fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();

    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;
    const surface = fillSurface(0, input.surface_albedo, &geo);
    var upward_path: f64 = 1.0;
    for (1..input.layers.len + 1) |ilevel| {
        upward_path *= atten.get(view_idx, ilevel - 1, ilevel);
    }

    return math.clamp(
        surface.R.get(view_idx, solar_idx) *
            atten.get(solar_idx, input.layers.len, 0) *
            upward_path,
        0.0,
        2.0,
    );
}

// ---------- Main entry point -----------------------------------------------

pub fn execute(
    allocator: Allocator,
    route: common.Route,
    input: common.ForwardInput,
) common.ExecuteError!common.ForwardResult {
    if (route.family != .labos) unreachable;
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const controls = route.rtm_controls;
    // Use the layer-resolved path when layers are provided
    const toa = if (controls.scattering == .none)
        try directSurfaceOnlyReflectanceResolved(allocator, input, controls)
    else if (input.layers.len > 0)
        try layerResolvedLabos(allocator, input, controls)
    else
        try singleLayerLabos(allocator, input, controls);

    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = toa,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.06),
            .analytical_plugin => null,
            .numerical => derivatives.proxyJacobianColumn(toa, input.optical_depth, 0.05),
        },
    };
}

/// LABOS implementation for multi-layer atmospheres.
/// This is the real implementation following the vendor's mathematical structure:
/// 1. Set up geometry (Gauss quadrature + viewing/solar directions)
/// 2. Compute inter-level attenuation
/// 3. Compute per-layer R/T operators (single scattering + doubling)
/// 4. Set surface reflector
/// 5. Solve for internal radiation field via successive orders of scattering
/// 6. Extract TOA reflectance from the internal field
fn layerResolvedLabos(
    allocator: Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    const nlayer = input.layers.len;
    if (nlayer == 0) return 0.0;

    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const n_gauss: usize = controls.nGauss();
    const nlevel = nlayer + 1;

    const geo = Geometry.init(n_gauss, mu0, muv);
    var atten = try fillAttenuationDynamicWithGrid(
        allocator,
        input.layers,
        input.pseudo_spherical_grid,
        &geo,
        controls.use_spherical_correction,
    );
    defer atten.deinit();
    var rt = try allocator.alloc(LayerRT, nlevel);
    defer allocator.free(rt);
    const start_level: usize = 0;
    const end_level: usize = nlayer;
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(totalScatteringOpticalDepth(input.layers)));
    const fourier_max = resolvedFourierMax(input, controls);
    // Prepared execution can carry either legacy source-interface metadata or
    // explicit RTM quadrature weights. Use the integrated-source path whenever
    // either representation is available on multi-layer scenes.
    const use_integrated_source =
        controls.integrate_source_function and
        nlayer > 1 and
        (input.source_interfaces.len == nlevel or
            input.rtm_quadrature.isValidFor(input.layers.len));

    var reflectance: f64 = 0.0;
    for (0..fourier_max + 1) |i_fourier| {
        calcRTlayersInto(rt, input.layers, i_fourier, &geo, controls);
        rt[0] = fillSurface(i_fourier, input.surface_albedo, &geo);
        var orders_result = try ordersScat(allocator, start_level, end_level, &geo, &atten, rt, controls, num_orders_max);
        defer orders_result.deinit();
        const refl_fc = if (use_integrated_source)
            calcIntegratedReflectance(input.layers, input.source_interfaces, input.rtm_quadrature, orders_result.ud, end_level, i_fourier, &geo)
        else
            calcReflectance(orders_result.ud, end_level, &geo);
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    return math.clamp(reflectance, 0.0, 2.0);
}

/// Simplified single-layer LABOS for backward compatibility when no layer data
/// is provided. Uses the bulk optical properties from ForwardInput.
fn singleLayerLabos(
    allocator: Allocator,
    input: common.ForwardInput,
    controls: common.RtmControls,
) common.ExecuteError!f64 {
    const mu0 = @max(input.mu0, 0.05);
    const muv = @max(input.muv, 0.05);
    const n_gauss: usize = controls.nGauss();

    const geo = Geometry.init(n_gauss, mu0, muv);

    // Create a single synthetic layer from the bulk properties
    const layer = common.LayerInput{
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .solar_mu = mu0,
        .view_mu = muv,
        .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
    };
    const layers = [_]common.LayerInput{layer};

    const atten = fillAttenuation(&layers, &geo, controls.use_spherical_correction);
    const num_orders_max: usize = @intCast(controls.resolvedNumOrdersMax(layer.scattering_optical_depth));
    const fourier_max = resolvedFourierMax(input, controls);
    const use_integrated_source = false;

    var reflectance: f64 = 0.0;
    for (0..fourier_max + 1) |i_fourier| {
        var rt = calcRTlayers(&layers, i_fourier, &geo, controls);
        rt[0] = fillSurface(i_fourier, input.surface_albedo, &geo);
        var orders_result = try ordersScat(allocator, 0, 1, &geo, &atten, rt[0..2], controls, num_orders_max);
        defer orders_result.deinit();
        const refl_fc = if (use_integrated_source)
            calcIntegratedReflectance(&layers, &.{}, .{}, orders_result.ud, 1, i_fourier, &geo)
        else
            calcReflectance(orders_result.ud, 1, &geo);
        const fourier_weight = if (i_fourier == 0)
            1.0
        else
            2.0 * math.cos(@as(f64, @floatFromInt(i_fourier)) * input.relative_azimuth_rad);
        reflectance += fourier_weight * refl_fc;
    }

    return math.clamp(reflectance, 0.0, 2.0);
}

// =================== Tests =================================================

test "labos execution supports semi-analytical derivatives but rejects plugin analytical mode" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try execute(std.testing.allocator, route, .{
        .spectral_weight = 1.0,
        .air_mass_factor = 1.0,
    });

    try std.testing.expectEqual(common.TransportFamily.labos, result.family);
    try std.testing.expect(result.jacobian_column != null);
    try std.testing.expect(result.jacobian_column.? < 0.0);
    try std.testing.expectError(common.Error.UnsupportedDerivativeMode, common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .analytical_plugin,
    }));
}

test "labos single-layer produces bounded positive reflectance" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.95,
        .surface_albedo = 0.05,
    });
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 2.0);
}

test "labos multi-layer produces bounded positive reflectance" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.1,
            .single_scatter_albedo = 0.99,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = .{ 1.0, 0.5, 0.25, 0.125 },
        },
        .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 0.8,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = .{ 1.0, 0.3, 0.09, 0.027 },
        },
        .{
            .optical_depth = 0.2,
            .single_scatter_albedo = 0.95,
            .solar_mu = 0.5,
            .view_mu = 0.6,
            .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
        },
    };

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.6,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.05,
        .layers = &layers,
    });
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result.toa_reflectance_factor <= 2.0);
}

test "labos supports 48 transport layers without collapsing to the synthetic single-layer fallback" {
    var layers: [48]common.LayerInput = undefined;
    for (&layers, 0..) |*layer, index| {
        const lower_haze = index < 24;
        layer.* = .{
            .optical_depth = if (lower_haze) 0.024 else 0.011,
            .scattering_optical_depth = if (lower_haze) 0.004 else 0.010,
            .single_scatter_albedo = if (lower_haze) 0.17 else 0.92,
            .solar_mu = 0.52,
            .view_mu = 0.63,
            .phase_coefficients = if (lower_haze)
                .{ 1.0, 0.02, 0.0, 0.0 }
            else
                .{ 1.0, 0.58, 0.21, 0.07 },
        };
    }

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });

    const result_multi = try execute(std.testing.allocator, route, .{
        .mu0 = 0.52,
        .muv = 0.63,
        .optical_depth = 0.84,
        .single_scatter_albedo = 0.54,
        .surface_albedo = 0.12,
        .layers = &layers,
    });
    const result_single = try execute(std.testing.allocator, route, .{
        .mu0 = 0.52,
        .muv = 0.63,
        .optical_depth = 0.84,
        .single_scatter_albedo = 0.54,
        .surface_albedo = 0.12,
    });

    try std.testing.expect(result_multi.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result_multi.toa_reflectance_factor <= 2.0);
    try std.testing.expect(@abs(
        result_multi.toa_reflectance_factor - result_single.toa_reflectance_factor,
    ) > 1.0e-5);
}

test "labos supports 80 transport layers without collapsing to the synthetic single-layer fallback" {
    var layers: [80]common.LayerInput = undefined;
    for (&layers, 0..) |*layer, index| {
        const lower_haze = index < 36;
        layer.* = .{
            .optical_depth = if (lower_haze) 0.016 else 0.009,
            .scattering_optical_depth = if (lower_haze) 0.003 else 0.008,
            .single_scatter_albedo = if (lower_haze) 0.19 else 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.61,
            .phase_coefficients = if (lower_haze)
                .{ 1.0, 0.03, 0.0, 0.0 }
            else
                .{ 1.0, 0.51, 0.18, 0.06 },
        };
    }

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });

    const result_multi = try execute(std.testing.allocator, route, .{
        .mu0 = 0.48,
        .muv = 0.61,
        .optical_depth = 0.88,
        .single_scatter_albedo = 0.53,
        .surface_albedo = 0.11,
        .layers = &layers,
    });
    const result_single = try execute(std.testing.allocator, route, .{
        .mu0 = 0.48,
        .muv = 0.61,
        .optical_depth = 0.88,
        .single_scatter_albedo = 0.53,
        .surface_albedo = 0.11,
    });

    try std.testing.expect(result_multi.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result_multi.toa_reflectance_factor <= 2.0);
    try std.testing.expect(@abs(
        result_multi.toa_reflectance_factor - result_single.toa_reflectance_factor,
    ) > 1.0e-5);
}

test "labos reflectance increases with surface albedo" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .solar_mu = 0.6,
        .view_mu = 0.7,
        .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
    }};

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result_low = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.05,
        .layers = &layers,
    });
    const result_high = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.5,
        .layers = &layers,
    });
    try std.testing.expect(result_high.toa_reflectance_factor > result_low.toa_reflectance_factor);
}

test "labos reflectance increases with single scatter albedo" {
    const make_layer = struct {
        fn f(ssa: f64) common.LayerInput {
            return .{
                .optical_depth = 0.4,
                .single_scatter_albedo = ssa,
                .solar_mu = 0.5,
                .view_mu = 0.6,
                .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
            };
        }
    }.f;

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });

    const layer_low = [_]common.LayerInput{make_layer(0.3)};
    const result_low = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.4,
        .single_scatter_albedo = 0.3,
        .surface_albedo = 0.05,
        .layers = &layer_low,
    });

    const layer_high = [_]common.LayerInput{make_layer(0.99)};
    const result_high = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.4,
        .single_scatter_albedo = 0.99,
        .surface_albedo = 0.05,
        .layers = &layer_high,
    });

    try std.testing.expect(result_high.toa_reflectance_factor > result_low.toa_reflectance_factor);
}

test "labos geometry initializes Gauss points on (0,1)" {
    const geo = Geometry.init(3, 0.6, 0.7);
    try std.testing.expectEqual(@as(usize, 5), geo.nmutot);
    // All Gauss points must be in (0,1)
    for (0..3) |i| {
        try std.testing.expect(geo.u[i] > 0.0);
        try std.testing.expect(geo.u[i] < 1.0);
    }
    // Extra directions
    try std.testing.expectApproxEqAbs(@as(f64, 0.7), geo.u[3], 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.6), geo.u[4], 1e-12);
}

test "labos smul with zero matrices returns zero" {
    const n: usize = 4;
    const a = Mat.zero(n);
    const b = Mat.zero(n);
    const c = smul(n, 2, 1e-12, &a, &b);
    for (0..n * n) |i| {
        try std.testing.expectApproxEqAbs(@as(f64, 0.0), c.data[i], 1e-15);
    }
}

test "labos smul with identity matrix returns original (Gauss block)" {
    const n: usize = 4;
    const n_gauss: usize = 2;
    var a = Mat.identity(n);
    // Set values large enough that trace threshold is exceeded
    a.set(0, 0, 2.0);
    a.set(1, 1, 2.0);
    var b = Mat.zero(n);
    b.set(0, 0, 3.0);
    b.set(0, 1, 1.0);
    b.set(1, 0, 0.5);
    b.set(1, 1, 2.0);
    const c = smul(n, n_gauss, 1e-12, &a, &b);
    // Only Gauss columns 0,1 of a contribute to the multiplication
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), c.get(0, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), c.get(0, 1), 1e-12);
}

test "labos esmul scales rows by diagonal" {
    const n: usize = 3;
    var a = Mat.zero(n);
    a.set(0, 0, 1.0);
    a.set(0, 1, 2.0);
    a.set(1, 0, 3.0);
    a.set(1, 1, 4.0);
    var e = Vec.zero(n);
    e.set(0, 0.5);
    e.set(1, 2.0);
    const c = esmul(n, &e, &a);
    try std.testing.expectApproxEqAbs(@as(f64, 0.5), c.get(0, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0), c.get(0, 1), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 6.0), c.get(1, 0), 1e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 8.0), c.get(1, 1), 1e-12);
}

test "labos attenuation is 1.0 for same level" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.9,
    }};
    const geo = Geometry.init(3, 0.6, 0.7);
    const atten = fillAttenuation(&layers, &geo, false);
    for (0..geo.nmutot) |imu| {
        try std.testing.expectApproxEqAbs(@as(f64, 1.0), atten.get(imu, 0, 0), 1e-12);
        try std.testing.expectApproxEqAbs(@as(f64, 1.0), atten.get(imu, 1, 1), 1e-12);
    }
}

test "labos attenuation decreases with optical depth" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.5,
        .single_scatter_albedo = 0.9,
    }};
    const geo = Geometry.init(3, 0.6, 0.7);
    const atten = fillAttenuation(&layers, &geo, false);
    // Attenuation from level 0 to level 1 should be < 1
    for (0..geo.nmutot) |imu| {
        try std.testing.expect(atten.get(imu, 0, 1) < 1.0);
        try std.testing.expect(atten.get(imu, 0, 1) > 0.0);
    }
}

test "labos spherical correction falls back to layer-dependent solar and view attenuation without explicit grid" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.2,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const geo = Geometry.init(3, 0.8, 0.9);
    const plane = fillAttenuation(&layers, &geo, false);
    const spherical = fillAttenuation(&layers, &geo, true);
    var plane_dynamic = try fillAttenuationDynamic(std.testing.allocator, &layers, &geo, false);
    defer plane_dynamic.deinit();
    var spherical_dynamic = try fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer spherical_dynamic.deinit();

    try std.testing.expectApproxEqAbs(plane.get(0, 0, 1), spherical.get(0, 0, 1), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.viewIdx(), 1, 0), spherical.get(geo.viewIdx(), 1, 0), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.n_gauss + 1, 1, 0), spherical.get(geo.n_gauss + 1, 1, 0), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.viewIdx(), 0, 2), spherical.get(geo.viewIdx(), 0, 2), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.n_gauss + 1, 0, 2), spherical.get(geo.n_gauss + 1, 0, 2), 1.0e-12);
    try std.testing.expect(plane.get(geo.viewIdx(), 2, 0) != spherical.get(geo.viewIdx(), 2, 0));
    try std.testing.expect(plane.get(geo.n_gauss + 1, 2, 0) != spherical.get(geo.n_gauss + 1, 2, 0));
    try std.testing.expectApproxEqAbs(plane_dynamic.get(geo.viewIdx(), 0, 2), spherical_dynamic.get(geo.viewIdx(), 0, 2), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane_dynamic.get(geo.n_gauss + 1, 0, 2), spherical_dynamic.get(geo.n_gauss + 1, 0, 2), 1.0e-12);
    try std.testing.expect(plane_dynamic.get(geo.viewIdx(), 2, 0) != spherical_dynamic.get(geo.viewIdx(), 2, 0));
    try std.testing.expect(plane_dynamic.get(geo.n_gauss + 1, 2, 0) != spherical_dynamic.get(geo.n_gauss + 1, 2, 0));
}

test "labos dynamic spherical correction uses pseudo-spherical sample grid when provided" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.27,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const pseudo_samples = [_]common.PseudoSphericalSample{
        .{ .altitude_km = 1.0, .thickness_km = 2.0, .optical_depth = 0.14 },
        .{ .altitude_km = 3.0, .thickness_km = 2.0, .optical_depth = 0.13 },
        .{ .altitude_km = 8.0, .thickness_km = 4.0, .optical_depth = 0.08 },
        .{ .altitude_km = 12.0, .thickness_km = 4.0, .optical_depth = 0.06 },
    };
    const pseudo_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
    };
    const rearth_km = 6371.0;
    const geo = Geometry.init(3, 0.8, 0.9);
    var spherical = try fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, pseudo_grid, &geo, true);
    defer spherical.deinit();
    var fallback = try fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer fallback.deinit();

    const view_u = geo.u[geo.viewIdx()];
    const sin2theta = 1.0 - view_u * view_u;
    const expected_surface = blk: {
        var sumkext: f64 = 0.0;
        for (pseudo_samples) |sample| {
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sin2theta * rearth_km * rearth_km));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk math.exp(-sumkext);
    };
    const expected_mid = blk: {
        var sumkext: f64 = 0.0;
        const level_radius = rearth_km + 6.0;
        const sqrx_sin2theta = sin2theta * level_radius * level_radius;
        for (pseudo_samples[2..]) |sample| {
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk math.exp(-sumkext);
    };

    try std.testing.expectApproxEqRel(expected_surface, spherical.get(geo.viewIdx(), 2, 0), 1.0e-12);
    try std.testing.expectApproxEqRel(expected_mid, spherical.get(geo.viewIdx(), 2, 1), 1.0e-12);
    try std.testing.expect(@abs(spherical.get(geo.viewIdx(), 2, 0) - fallback.get(geo.viewIdx(), 2, 0)) > 1.0e-6);
    try std.testing.expectApproxEqAbs(fallback.get(geo.viewIdx(), 0, 2), spherical.get(geo.viewIdx(), 0, 2), 1.0e-12);
}

test "labos dynamic spherical correction prefers explicit pseudo-spherical level altitudes" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.27,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const pseudo_samples = [_]common.PseudoSphericalSample{
        .{ .altitude_km = 0.75, .thickness_km = 0.0, .optical_depth = 0.0 },
        .{ .altitude_km = 4.25, .thickness_km = 1.0, .optical_depth = 0.14 },
        .{ .altitude_km = 7.75, .thickness_km = 0.0, .optical_depth = 0.0 },
        .{ .altitude_km = 10.0, .thickness_km = 1.0, .optical_depth = 0.08 },
    };
    const pseudo_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
        .level_altitudes_km = &.{ 0.75, 7.75, 12.25 },
    };
    const inferred_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
    };
    const rearth_km = 6371.0;
    const geo = Geometry.init(3, 0.8, 0.9);
    var explicit = try fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, pseudo_grid, &geo, true);
    defer explicit.deinit();
    var inferred = try fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, inferred_grid, &geo, true);
    defer inferred.deinit();

    const view_u = geo.u[geo.viewIdx()];
    const sin2theta = 1.0 - view_u * view_u;
    const expected_mid = blk: {
        var sumkext: f64 = 0.0;
        const level_radius = rearth_km + 7.75;
        const sqrx_sin2theta = sin2theta * level_radius * level_radius;
        for (pseudo_samples[2..]) |sample| {
            if (sample.optical_depth <= 0.0) continue;
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk math.exp(-sumkext);
    };

    try std.testing.expectApproxEqRel(expected_mid, explicit.get(geo.viewIdx(), 2, 1), 1.0e-12);
    try std.testing.expect(@abs(
        explicit.get(geo.viewIdx(), 2, 1) - inferred.get(geo.viewIdx(), 2, 1),
    ) > 1.0e-9);
}

test "labos surface reflector has correct structure" {
    const geo = Geometry.init(3, 0.6, 0.7);
    const surf = fillSurface(0, 0.3, &geo);
    // Diagonal elements should be w(i) * albedo * w(i) > 0
    for (0..geo.nmutot) |i| {
        try std.testing.expect(surf.R.get(i, i) >= 0.0);
    }
    // For iFourier > 0, surface is zero
    const surf1 = fillSurface(1, 0.3, &geo);
    for (0..geo.nmutot) |i| {
        for (0..geo.nmutot) |j| {
            try std.testing.expectApproxEqAbs(@as(f64, 0.0), surf1.R.get(i, j), 1e-15);
        }
    }
}

test "labos anisotropic layers respond to relative azimuth once Fourier terms are enabled" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.35,
            .scattering_optical_depth = 0.30,
            .single_scatter_albedo = 0.93,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.55, 0.24, 0.08 },
        },
        .{
            .optical_depth = 0.22,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.91,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.42, 0.16, 0.05 },
        },
    };

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.57,
        .single_scatter_albedo = 0.92,
        .surface_albedo = 0.12,
        .layers = &layers,
    };
    const result_zero = try execute(std.testing.allocator, route, forward_input);
    const result_oblique = try execute(std.testing.allocator, route, .{
        .mu0 = forward_input.mu0,
        .muv = forward_input.muv,
        .optical_depth = forward_input.optical_depth,
        .single_scatter_albedo = forward_input.single_scatter_albedo,
        .surface_albedo = forward_input.surface_albedo,
        .relative_azimuth_rad = std.math.degreesToRadians(120.0),
        .layers = &layers,
    });

    try std.testing.expect(@abs(result_zero.toa_reflectance_factor - result_oblique.toa_reflectance_factor) > 1.0e-5);
}

test "labos raw-layer integrated source-function fallback stays close to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        6.0e-3,
    );
}

test "labos single-layer integrated source-function falls back to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.31,
            .scattering_optical_depth = 0.24,
            .single_scatter_albedo = 0.91,
            .solar_mu = 0.59,
            .view_mu = 0.65,
            .phase_coefficients = .{ 1.0, 0.28, 0.07, 0.01 },
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.31,
        .single_scatter_albedo = 0.91,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(70.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        1.0e-12,
    );
}

test "labos integrated source-function path uses explicit source interface metadata" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
        },
    };
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    source_interfaces[1].rtm_weight = 2.0;
    source_interfaces[1].ksca_above = source_interfaces[1].source_weight / source_interfaces[1].rtm_weight;
    source_interfaces[1].source_weight = 0.0;

    const base_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
        .source_interfaces = &source_interfaces,
    };
    const baseline = try execute(std.testing.allocator, route, base_input);
    const direct_baseline = try execute(std.testing.allocator, route_direct, base_input);

    var altered_interfaces = source_interfaces;
    altered_interfaces[1].ksca_above *= 1.8;
    altered_interfaces[1].phase_coefficients_above[1] = 0.60;
    const altered = try execute(std.testing.allocator, route, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });
    const direct_altered = try execute(std.testing.allocator, route_direct, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });

    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
    try std.testing.expectApproxEqAbs(
        direct_baseline.toa_reflectance_factor,
        direct_altered.toa_reflectance_factor,
        1.0e-10,
    );
}

test "labos prepared RTM quadrature participates in integrated source-function reflectance" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
        },
    };

    const rtm_quadrature = [_]common.RtmQuadratureLevel{
        .{ .altitude_km = 0.0, .weight = 0.0, .ksca = 0.0, .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 } },
        .{ .altitude_km = 3.5, .weight = 4.0, .ksca = 0.055, .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 } },
        .{ .altitude_km = 8.0, .weight = 0.0, .ksca = 0.0, .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 } },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
        .rtm_quadrature = .{ .levels = &rtm_quadrature },
    };
    const baseline = try execute(std.testing.allocator, route_integrated, input);
    const direct_baseline = try execute(std.testing.allocator, route_direct, input);

    var altered_rtm_quadrature = rtm_quadrature;
    altered_rtm_quadrature[1].ksca *= 1.8;
    altered_rtm_quadrature[1].phase_coefficients[1] = 0.60;
    const altered = try execute(std.testing.allocator, route_integrated, .{
        .mu0 = input.mu0,
        .muv = input.muv,
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .surface_albedo = input.surface_albedo,
        .relative_azimuth_rad = input.relative_azimuth_rad,
        .layers = input.layers,
        .rtm_quadrature = .{ .levels = &altered_rtm_quadrature },
    });
    const direct_altered = try execute(std.testing.allocator, route_direct, .{
        .mu0 = input.mu0,
        .muv = input.muv,
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .surface_albedo = input.surface_albedo,
        .relative_azimuth_rad = input.relative_azimuth_rad,
        .layers = input.layers,
        .rtm_quadrature = .{ .levels = &altered_rtm_quadrature },
    });

    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
    try std.testing.expectApproxEqAbs(
        direct_baseline.toa_reflectance_factor,
        direct_altered.toa_reflectance_factor,
        1.0e-10,
    );
}

test "labos spherical correction changes reflectance for layered scalar scenes" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = .{ 1.0, 0.31, 0.10, 0.02 },
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = .{ 1.0, 0.26, 0.08, 0.02 },
        },
    };

    const route_plane = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = false,
        },
    });
    const route_spherical = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = true,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.40,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .layers = &layers,
    };
    const plane = try execute(std.testing.allocator, route_plane, forward_input);
    const spherical = try execute(std.testing.allocator, route_spherical, forward_input);

    try std.testing.expect(@abs(plane.toa_reflectance_factor - spherical.toa_reflectance_factor) > 1.0e-5);
}

test "labos optically thin layer has small reflectance" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.001,
        .single_scatter_albedo = 0.9,
        .solar_mu = 0.5,
        .view_mu = 0.6,
        .phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
    }};
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.001,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.0,
        .layers = &layers,
    });
    // Very thin layer with zero surface albedo: reflectance should be very small
    try std.testing.expect(result.toa_reflectance_factor < 0.05);
    try std.testing.expect(result.toa_reflectance_factor >= 0.0);
}
