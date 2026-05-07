const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const types = @import("types.zig");

const Mat = types.Mat;
const Geometry = types.Geometry;

const PlmArrays = struct {
    plus: [types.max_nmutot]f64,
    minus: [types.max_nmutot]f64,
};

pub const PhaseKernel = struct {
    Zplus: Mat,
    Zmin: Mat,
};

pub const PhaseKernelRow = struct {
    zplus: [types.max_nmutot]f64,
    zmin: [types.max_nmutot]f64,
    n: usize,
};

pub const FourierPlmBasis = struct {
    i_fourier: usize,
    max_phase_index: usize,
    plus: [types.max_phase_coef][types.max_nmutot]f64,
    minus: [types.max_phase_coef][types.max_nmutot]f64,

    fn storeWeighted(
        self: *FourierPlmBasis,
        coef_idx: usize,
        p_l_plus: *const [types.max_nmutot]f64,
        p_l_minus: *const [types.max_nmutot]f64,
        geo: *const Geometry,
    ) void {
        for (0..geo.nmutot) |imu| {
            self.plus[coef_idx][imu] = p_l_plus[imu] * geo.w[imu];
            self.minus[coef_idx][imu] = p_l_minus[imu] * geo.w[imu];
        }
    }

    pub fn init(i_fourier: usize, max_phase_index: usize, geo: *const Geometry) FourierPlmBasis {
        var result = FourierPlmBasis{
            .i_fourier = i_fourier,
            .max_phase_index = max_phase_index,
            .plus = undefined,
            .minus = undefined,
        };
        if (max_phase_index < i_fourier) return result;

        var sqlm: [types.max_phase_coef]f64 = .{0.0} ** types.max_phase_coef;
        for (i_fourier + 1..max_phase_index + 1) |l| {
            const lf: f64 = @floatFromInt(l);
            const mf: f64 = @floatFromInt(i_fourier);
            sqlm[l] = @sqrt(lf * lf - mf * mf);
        }

        var p_lm1_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
        var p_l_plus: [types.max_nmutot]f64 = undefined;
        var p_lm1_minus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
        var p_l_minus: [types.max_nmutot]f64 = undefined;

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

fn computePlm(i_fourier: usize, coef_idx: usize, geo: *const Geometry) PlmArrays {
    const n = geo.nmutot;
    if (coef_idx < i_fourier) {
        return .{ .plus = .{0.0} ** types.max_nmutot, .minus = .{0.0} ** types.max_nmutot };
    }

    var sqlm: [types.max_phase_coef]f64 = .{0.0} ** types.max_phase_coef;
    for (i_fourier + 1..coef_idx + 1) |l| {
        const lf: f64 = @floatFromInt(l);
        const mf: f64 = @floatFromInt(i_fourier);
        sqlm[l] = @sqrt(lf * lf - mf * mf);
    }

    var plm_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var plm_minus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var p_lm1_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var p_l_plus: [types.max_nmutot]f64 = undefined;
    var p_lm1_minus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var p_l_minus: [types.max_nmutot]f64 = undefined;

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

pub fn fillZplusZminFromBasis(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    return fillZplusZminFromBasisLimited(
        i_fourier,
        phase_coefs,
        phase_functions.maxPhaseCoefficientIndex(phase_coefs),
        geo,
        plm_basis,
    );
}

pub fn fillZplusZminFromBasisLimited(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    const n = geo.nmutot;
    if (n == 12) {
        return fillZplusZminFromBasisLimited12(
            i_fourier,
            phase_coefs,
            max_phase_index,
            geo,
            plm_basis,
        );
    }
    const bounded_max_phase_index = @min(max_phase_index, types.max_phase_coef - 1);
    if (i_fourier > bounded_max_phase_index) return .{ .Zplus = Mat.zero(n), .Zmin = Mat.zero(n) };

    var zplus = Mat{ .data = undefined, .n = n };
    var zmin = Mat{ .data = undefined, .n = n };
    var first_order = true;
    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = phase_coefs[l];
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_l = &plm_basis.minus[l];
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plus_l[j];
                        zmin.data[row + j] = scaled_minus_i * plus_l[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] += scaled_plus_i * plus_l[j];
                        zmin.data[row + j] += scaled_minus_i * plus_l[j];
                    }
                }
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * plm.minus[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plm.plus[j];
                        zmin.data[row + j] = scaled_minus_i * plm.plus[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * plm.minus[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] += scaled_plus_i * plm.plus[j];
                        zmin.data[row + j] += scaled_minus_i * plm.plus[j];
                    }
                }
            }
        }
        first_order = false;
    }
    if (first_order) return .{ .Zplus = Mat.zero(n), .Zmin = Mat.zero(n) };

    return .{ .Zplus = zplus, .Zmin = zmin };
}

pub fn fillZplusZminRowFromBasisLimited(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    const n = geo.nmutot;
    const bounded_max_phase_index = @min(max_phase_index, types.max_phase_coef - 1);
    if (row_index >= n or i_fourier > bounded_max_phase_index) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = n,
        };
    }

    var row = PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = n,
    };
    var first_order = true;
    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = phase_coefs[l];
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_l = &plm_basis.minus[l];
            const scaled_plus_row = alpha1 * plus_l[row_index];
            const scaled_minus_row = alpha1 * minus_l[row_index];
            if (first_order) {
                for (0..n) |j| {
                    row.zplus[j] = scaled_plus_row * plus_l[j];
                    row.zmin[j] = scaled_minus_row * plus_l[j];
                }
            } else {
                for (0..n) |j| {
                    row.zplus[j] += scaled_plus_row * plus_l[j];
                    row.zmin[j] += scaled_minus_row * plus_l[j];
                }
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const scaled_plus_row = alpha1 * plm.plus[row_index];
            const scaled_minus_row = alpha1 * plm.minus[row_index];
            if (first_order) {
                for (0..n) |j| {
                    row.zplus[j] = scaled_plus_row * plm.plus[j];
                    row.zmin[j] = scaled_minus_row * plm.plus[j];
                }
            } else {
                for (0..n) |j| {
                    row.zplus[j] += scaled_plus_row * plm.plus[j];
                    row.zmin[j] += scaled_minus_row * plm.plus[j];
                }
            }
        }
        first_order = false;
    }
    if (first_order) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = n,
        };
    }
    return row;
}

fn fillZplusZminFromBasisLimited12(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    const bounded_max_phase_index = @min(max_phase_index, types.max_phase_coef - 1);
    if (i_fourier > bounded_max_phase_index) return .{ .Zplus = Mat.zero(12), .Zmin = Mat.zero(12) };

    var zplus = Mat{ .data = undefined, .n = 12 };
    var zmin = Mat{ .data = undefined, .n = 12 };
    var first_order = true;
    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = phase_coefs[l];
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_l = &plm_basis.minus[l];
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_l, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_l, false);
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, &plm.minus, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, &plm.minus, false);
            }
        }
        first_order = false;
    }
    if (first_order) return .{ .Zplus = Mat.zero(12), .Zmin = Mat.zero(12) };

    return .{ .Zplus = zplus, .Zmin = zmin };
}

inline fn fillPhaseTerm12(
    noalias zplus: *Mat,
    noalias zmin: *Mat,
    alpha1: f64,
    noalias plus_l: *const [types.max_nmutot]f64,
    noalias minus_l: *const [types.max_nmutot]f64,
    comptime first_order: bool,
) void {
    var scaled_plus_col: [12]f64 = undefined;
    inline for (0..12) |j| {
        scaled_plus_col[j] = alpha1 * plus_l[j];
    }

    inline for (0..12) |i| {
        const plus_i = plus_l[i];
        const minus_i = minus_l[i];
        const row = i * 12;
        inline for (0..12) |j| {
            const idx = row + j;
            if (first_order) {
                zplus.data[idx] = plus_i * scaled_plus_col[j];
                zmin.data[idx] = minus_i * scaled_plus_col[j];
            } else {
                zplus.data[idx] += plus_i * scaled_plus_col[j];
                zmin.data[idx] += minus_i * scaled_plus_col[j];
            }
        }
    }
}

pub fn fillZplusZmin(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    geo: *const Geometry,
) PhaseKernel {
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    const plm_basis = FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return fillZplusZminFromBasis(i_fourier, phase_coefs, geo, &plm_basis);
}
