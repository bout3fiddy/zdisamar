const phase_functions = @import("../../optics/prepare/phase_functions.zig");
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
            .plus = [_][types.max_nmutot]f64{.{0.0} ** types.max_nmutot} ** types.max_phase_coef,
            .minus = [_][types.max_nmutot]f64{.{0.0} ** types.max_nmutot} ** types.max_phase_coef,
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

/// Purpose:
///   Build a LABOS phase kernel with an explicit vendor-style coefficient
///   ceiling.
///
/// Physics:
///   DISAMAR sometimes uses a carrier phase function from an interface but
///   truncates the Legendre sum with the maximum order of adjacent reduced
///   layers. Keeping the ceiling explicit preserves that source-function
///   behavior without mutating the phase carrier.
///
/// Vendor:
///   `LabosModule::CalcReflectance`
///
/// Inputs:
///   `max_phase_index` is the inclusive Legendre coefficient ceiling for the
///   current layer or source level.
///
/// Validation:
///   `reflectance.zig` source-level truncation tests and O2A function diff.
pub fn fillZplusZminFromBasisLimited(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    const n = geo.nmutot;
    var zplus = Mat.zero(n);
    var zmin = Mat.zero(n);
    const bounded_max_phase_index = @min(
        max_phase_index,
        phase_functions.maxPhaseCoefficientIndex(phase_coefs),
    );
    if (i_fourier > bounded_max_phase_index) return .{ .Zplus = zplus, .Zmin = zmin };

    for (i_fourier..bounded_max_phase_index + 1) |l| {
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

pub fn fillZplusZmin(
    i_fourier: usize,
    phase_coefs: [types.max_phase_coef]f64,
    geo: *const Geometry,
) PhaseKernel {
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    const plm_basis = FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return fillZplusZminFromBasis(i_fourier, phase_coefs, geo, &plm_basis);
}
