//! Purpose:
//!   Own the scalar LABOS basis math, stack-backed matrix/vector helpers, and
//!   the geometry used by the transport solver facade.
//!
//! Physics:
//!   Implements the discrete ordinate geometry and scalar phase-basis
//!   operators used to build layer reflection/transmission kernels.
//!
//! Vendor:
//!   LABOS matrix/phase basis stages
//!
//! Design:
//!   The Zig version keeps the numerical primitives isolated from attenuation
//!   and solver orchestration so that the higher-level transport stages can be
//!   composed without re-implementing shared arithmetic.
//!
//! Invariants:
//!   Direction arrays are sized for the Gauss nodes plus the explicit viewing
//!   and solar directions. The scalar phase basis only handles the scalar case
//!   used by the current LABOS path.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for geometry, matrix, and
//!   phase-basis smoke coverage.

const std = @import("std");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const phase_functions = @import("../../optics/prepare/phase_functions.zig");

pub const max_gauss: usize = 10;
pub const max_extra: usize = 2; // viewing + solar
pub const max_nmutot: usize = max_gauss + max_extra;
pub const max_n2: usize = max_nmutot * max_nmutot;
pub const max_phase_coef: usize = phase_functions.phase_coefficient_count;

const threshold_q: f64 = 1.0e-3;

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
        const rule = gauss_legendre.rule(@intCast(n_gauss)) catch unreachable;
        var geo: Geometry = undefined;
        geo.n_gauss = n_gauss;
        geo.nmutot = n_gauss + max_extra;
        geo.mu0 = mu0;
        geo.muv = muv;

        for (0..n_gauss) |i| {
            const ug = (rule.nodes[i] + 1.0) * 0.5;
            const wg = rule.weights[i] * 0.5;
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

/// Matrix multiply that sums only over Gauss-point indices (0..nGauss).
/// This ensures that the extra directions (view, solar) participate only
/// as row/column recipients, not as quadrature nodes.
pub fn smul(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    var result = Mat.zero(n);
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
/// For small trace(AB), just returns AB (single-term approximation).
pub fn qseries(n: usize, n_gauss: usize, threshold_mul: f64, a: *const Mat, b: *const Mat) Mat {
    const ab = smul(n, n_gauss, threshold_mul, a, b);

    var trab: f64 = 0.0;
    for (0..n_gauss) |k| trab += ab.get(k, k);
    if (@abs(trab) < threshold_q) return ab;

    const n_extra = n - n_gauss;

    var one_minus_ab_gg: [max_gauss * max_gauss]f64 = undefined;
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.get(i, j);
        }
    }

    var pivot: [max_gauss]usize = undefined;
    for (0..n_gauss) |i| pivot[i] = i;

    for (0..n_gauss) |col| {
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
        if (@abs(diag) < 1.0e-30) return ab;
        for (col + 1..n_gauss) |row| {
            const factor = one_minus_ab_gg[pivot[row] * n_gauss + col] / diag;
            one_minus_ab_gg[pivot[row] * n_gauss + col] = factor;
            for (col + 1..n_gauss) |k| {
                one_minus_ab_gg[pivot[row] * n_gauss + k] -=
                    factor * one_minus_ab_gg[pivot[col] * n_gauss + k];
            }
        }
    }

    var inverse: [max_gauss * max_gauss]f64 = .{0.0} ** (max_gauss * max_gauss);
    for (0..n_gauss) |rhs_col| {
        var y: [max_gauss]f64 = .{0.0} ** max_gauss;
        for (0..n_gauss) |i| {
            var s: f64 = if (pivot[i] == rhs_col) 1.0 else 0.0;
            for (0..i) |j| {
                s -= one_minus_ab_gg[pivot[i] * n_gauss + j] * y[j];
            }
            y[i] = s;
        }

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

    var result = Mat.zero(n);
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            const delta: f64 = if (i == j) 1.0 else 0.0;
            result.set(i, j, inverse[i * n_gauss + j] - delta);
        }
    }

    for (0..n_extra) |ja| {
        for (0..n_gauss) |i| {
            var s: f64 = 0.0;
            for (0..n_gauss) |k| {
                s += inverse[i * n_gauss + k] * ab.get(k, n_gauss + ja);
            }
            result.set(i, n_gauss + ja, s);
        }
    }

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

const PlmArrays = struct {
    plus: [max_nmutot]f64,
    minus: [max_nmutot]f64,
};

pub const PhaseKernel = struct {
    Zplus: Mat,
    Zmin: Mat,
};

pub const FourierPlmBasis = struct {
    i_fourier: usize,
    max_phase_index: usize,
    plus: [max_phase_coef][max_nmutot]f64,
    minus: [max_phase_coef][max_nmutot]f64,

    fn storeWeighted(
        self: *FourierPlmBasis,
        coef_idx: usize,
        p_l_plus: *const [max_nmutot]f64,
        p_l_minus: *const [max_nmutot]f64,
        geo: *const Geometry,
    ) void {
        for (0..geo.nmutot) |imu| {
            self.plus[coef_idx][imu] = p_l_plus[imu] * geo.w[imu];
            self.minus[coef_idx][imu] = p_l_minus[imu] * geo.w[imu];
        }
    }

    /// Purpose:
    ///   Precompute the weighted associated-Legendre basis for one Fourier term.
    ///
    /// Physics:
    ///   Carries the Fourier-specific `P_l^m(mu) * w(mu)` basis used by the
    ///   LABOS phase-kernel builders.
    ///
    /// Vendor:
    ///   `labosModule phase-basis preparation`
    ///
    /// Inputs:
    ///   `i_fourier` selects the azimuthal Fourier order, `max_phase_index`
    ///   bounds the highest phase coefficient needed by the current transport
    ///   execution, and `geo` supplies the discrete-ordinate directions.
    ///
    /// Outputs:
    ///   Returns a stack-backed cache covering all coefficients in
    ///   `[i_fourier, max_phase_index]`.
    ///
    /// Decisions:
    ///   The vendor path keeps this basis work outside the inner kernel loops.
    ///   Zig preserves the explicit call graph by precomputing the basis once
    ///   per `(geometry, Fourier, max_phase_index)` context instead of
    ///   rebuilding it inside every `fillZplusZmin(...)` call.
    pub fn init(
        i_fourier: usize,
        max_phase_index: usize,
        geo: *const Geometry,
    ) FourierPlmBasis {
        var result = FourierPlmBasis{
            .i_fourier = i_fourier,
            .max_phase_index = max_phase_index,
            .plus = [_][max_nmutot]f64{.{0.0} ** max_nmutot} ** max_phase_coef,
            .minus = [_][max_nmutot]f64{.{0.0} ** max_nmutot} ** max_phase_coef,
        };
        if (max_phase_index < i_fourier) return result;

        var sqlm: [max_phase_coef]f64 = .{0.0} ** max_phase_coef;
        for (i_fourier + 1..max_phase_index + 1) |l| {
            const lf: f64 = @floatFromInt(l);
            const mf: f64 = @floatFromInt(i_fourier);
            sqlm[l] = @sqrt(lf * lf - mf * mf);
        }

        var p_lm1_plus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
        var p_l_plus: [max_nmutot]f64 = undefined;
        var p_lm1_minus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
        var p_l_minus: [max_nmutot]f64 = undefined;

        for (0..geo.nmutot) |imu| {
            const u = geo.u[imu];
            const one_minus_uu = 1.0 - u * u;
            const squu = @sqrt(@max(one_minus_uu, 0.0));

            const start_val: f64 = switch (i_fourier) {
                0 => 1.0,
                1 => squu / @sqrt(2.0),
                2 => 0.25 * @sqrt(6.0) * one_minus_uu,
                else => blk: {
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

        result.storeWeighted(i_fourier, &p_l_plus, &p_l_minus, geo);
        if (max_phase_index == i_fourier) return result;

        for (i_fourier..max_phase_index) |l| {
            const a_coef = sqlm[l + 1];
            const c_coef = -sqlm[l];
            for (0..geo.nmutot) |imu| {
                const b_plus = (2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
                const p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
                p_lm1_plus[imu] = p_l_plus[imu];
                p_l_plus[imu] = p_lp1;

                const b_minus = -(2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
                const p_lp1_m = (b_minus * p_l_minus[imu] + c_coef * p_lm1_minus[imu]) / a_coef;
                p_lm1_minus[imu] = p_l_minus[imu];
                p_l_minus[imu] = p_lp1_m;
            }
            result.storeWeighted(l + 1, &p_l_plus, &p_l_minus, geo);
        }

        return result;
    }
};

fn computePlm(
    i_fourier: usize,
    coef_idx: usize,
    geo: *const Geometry,
) PlmArrays {
    const n = geo.nmutot;
    if (coef_idx < i_fourier) {
        return .{
            .plus = .{0.0} ** max_nmutot,
            .minus = .{0.0} ** max_nmutot,
        };
    }

    var sqlm: [max_phase_coef]f64 = .{0.0} ** max_phase_coef;
    for (i_fourier + 1..coef_idx + 1) |l| {
        const lf: f64 = @floatFromInt(l);
        const mf: f64 = @floatFromInt(i_fourier);
        sqlm[l] = @sqrt(lf * lf - mf * mf);
    }

    var plm_plus: [max_nmutot]f64 = .{0.0} ** max_nmutot;
    var plm_minus: [max_nmutot]f64 = .{0.0} ** max_nmutot;

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

    if (coef_idx == i_fourier) {
        for (0..n) |imu| {
            plm_plus[imu] = p_l_plus[imu] * geo.w[imu];
            plm_minus[imu] = p_l_minus[imu] * geo.w[imu];
        }
        return .{ .plus = plm_plus, .minus = plm_minus };
    }

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

/// Build Zplus(i,j) and Zmin(i,j) for scalar case.
pub fn fillZplusZminFromBasis(
    i_fourier: usize,
    phase_coefs: [max_phase_coef]f64,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    const n = geo.nmutot;
    var zplus = Mat.zero(n);
    var zmin = Mat.zero(n);
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    if (i_fourier > max_phase_index) {
        return .{ .Zplus = zplus, .Zmin = zmin };
    }

    for (i_fourier..max_phase_index + 1) |l| {
        const alpha1 = phase_coefs[l];
        if (l <= plm_basis.max_phase_index) {
            for (0..n) |j| {
                const pj = plm_basis.plus[l][j];
                for (0..n) |i| {
                    zplus.addTo(i, j, alpha1 * plm_basis.plus[l][i] * pj);
                    zmin.addTo(i, j, alpha1 * plm_basis.minus[l][i] * pj);
                }
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            for (0..n) |j| {
                const pj = plm.plus[j];
                for (0..n) |i| {
                    zplus.addTo(i, j, alpha1 * plm.plus[i] * pj);
                    zmin.addTo(i, j, alpha1 * plm.minus[i] * pj);
                }
            }
        }
    }

    return .{ .Zplus = zplus, .Zmin = zmin };
}

/// Build Zplus(i,j) and Zmin(i,j) for scalar case.
pub fn fillZplusZmin(
    i_fourier: usize,
    phase_coefs: [max_phase_coef]f64,
    geo: *const Geometry,
) PhaseKernel {
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    const plm_basis = FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return fillZplusZminFromBasis(i_fourier, phase_coefs, geo, &plm_basis);
}

test "FourierPlmBasis reproduces direct Zplus/Zmin construction" {
    const geo = Geometry.init(8, 0.54, 0.67);
    const phase_coefficients = phase_functions.phaseCoefficientsFromLegacy(.{
        1.0,
        0.62,
        0.31,
        0.15,
    });

    var baseline: PhaseKernel = .{
        .Zplus = Mat.zero(geo.nmutot),
        .Zmin = Mat.zero(geo.nmutot),
    };
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefficients);
    for (1..max_phase_index + 1) |l| {
        const plm = computePlm(1, l, &geo);
        const alpha1 = phase_coefficients[l];
        for (0..geo.nmutot) |j| {
            const pj = plm.plus[j];
            for (0..geo.nmutot) |i| {
                baseline.Zplus.addTo(i, j, alpha1 * plm.plus[i] * pj);
                baseline.Zmin.addTo(i, j, alpha1 * plm.minus[i] * pj);
            }
        }
    }
    const basis_cache = FourierPlmBasis.init(
        1,
        max_phase_index,
        &geo,
    );
    const cached = fillZplusZminFromBasis(1, phase_coefficients, &geo, &basis_cache);

    for (0..geo.nmutot) |j| {
        for (0..geo.nmutot) |i| {
            try std.testing.expectApproxEqAbs(
                baseline.Zplus.get(i, j),
                cached.Zplus.get(i, j),
                1.0e-12,
            );
            try std.testing.expectApproxEqAbs(
                baseline.Zmin.get(i, j),
                cached.Zmin.get(i, j),
                1.0e-12,
            );
        }
    }
}
