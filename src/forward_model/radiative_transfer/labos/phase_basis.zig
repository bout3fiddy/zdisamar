const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const types = @import("types.zig");

const Mat = types.Mat;
const Geometry = types.Geometry;

// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: plus=96 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: minus derives from plus by (-1)^(coef_idx - i_fourier)
//   inline arrays: plus:[12]f64=96 B
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count
const PlmArrays = struct {
    plus: [types.max_nmutot]f64,
};

// layout(64-bit):
//   size: 2320 B, align: 8 B
//   field storage: Zplus=1160 B, Zmin=1160 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   cache span: 37 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 2320 B (2.266 KiB); total = per instance * live instance count
pub const PhaseKernel = struct {
    Zplus: Mat,
    Zmin: Mat,
};

// layout(64-bit):
//   size: 200 B, align: 8 B
//   field storage: zplus=96 B, zmin=96 B, n=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   metadata fields: n=8 B
//   inline arrays: zplus:[12]f64=96 B, zmin:[12]f64=96 B
//   cache span: 4 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 200 B (0.195 KiB); total = per instance * live instance count
pub const PhaseKernelRow = struct {
    zplus: [types.max_nmutot]f64,
    zmin: [types.max_nmutot]f64,
    n: usize,
};

// hot path:
//   when: once per Fourier term before phase matrices and reflectance rows are built
//   work: stores associated Legendre basis values for stream and solar/view geometries
//   data: PLM basis arrays, Gaussian stream geometry, Fourier index
//   follow: fillZplusZminFromBasisLimited and reflectance phase-row builders
// layout(64-bit):
//   size: 14512 B, align: 8 B
//   field storage: i_fourier=8 B, max_phase_index=8 B, plus=14496 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   encoded fields: minus basis derives from plus by (-1)^(coef_idx - i_fourier)
//   inline arrays: plus:[151][12]f64=14496 B
//   cache span: 227 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 14512 B (14.2 KiB); total = per instance * live instance count
pub const FourierPlmBasis = struct {
    i_fourier: usize,
    max_phase_index: usize,
    plus: [types.max_phase_coef][types.max_nmutot]f64,

    fn storeWeighted(
        self: *FourierPlmBasis,
        coef_idx: usize,
        p_l_plus: *const [types.max_nmutot]f64,
        geo: *const Geometry,
    ) void {
        for (0..geo.nmutot) |imu| {
            // math: stored PLM basis includes LABOS stream weight, P_l^m(mu_i) * w_i.
            self.plus[coef_idx][imu] = p_l_plus[imu] * geo.w[imu];
        }
    }

    pub fn init(i_fourier: usize, max_phase_index: usize, geo: *const Geometry) FourierPlmBasis {
        var result = FourierPlmBasis{
            .i_fourier = i_fourier,
            .max_phase_index = max_phase_index,
            .plus = undefined,
        };
        if (max_phase_index < i_fourier) return result;

        var sqlm: [types.max_phase_coef]f64 = .{0.0} ** types.max_phase_coef;
        for (i_fourier + 1..max_phase_index + 1) |l| {
            const lf: f64 = @floatFromInt(l);
            const mf: f64 = @floatFromInt(i_fourier);
            // math: recurrence coefficient sqrt(l^2 - m^2).
            sqlm[l] = @sqrt(lf * lf - mf * mf);
        }

        var p_lm1_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
        var p_l_plus: [types.max_nmutot]f64 = undefined;
        for (0..geo.nmutot) |imu| {
            const u = geo.u[imu];
            const one_minus_uu = 1.0 - u * u;
            const squu = @sqrt(@max(one_minus_uu, 0.0));
            // math: seed P_m^m(mu) for m=i_fourier using DISAMAR-normalized low-order cases.
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
        }

        result.storeWeighted(i_fourier, &p_l_plus, geo);
        if (max_phase_index == i_fourier) return result;

        for (i_fourier..max_phase_index) |l| {
            const a_coef = sqlm[l + 1];
            const c_coef = -sqlm[l];
            for (0..geo.nmutot) |imu| {
                const b_plus = (2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
                // math: recurrence P_{l+1}^m = ((2l+1) mu P_l^m - sqrt(l^2-m^2) P_{l-1}^m) / sqrt((l+1)^2-m^2).
                const p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
                p_lm1_plus[imu] = p_l_plus[imu];
                p_l_plus[imu] = p_lp1;
            }
            result.storeWeighted(l + 1, &p_l_plus, geo);
        }

        return result;
    }
};

inline fn minusParitySign(i_fourier: usize, coef_idx: usize) f64 {
    // math: Z- uses (-1)^(l-m) parity relative to Z+.
    return if (((coef_idx - i_fourier) & 1) == 0) 1.0 else -1.0;
}

fn computePlm(i_fourier: usize, coef_idx: usize, geo: *const Geometry) PlmArrays {
    const n = geo.nmutot;
    if (coef_idx < i_fourier) {
        return .{ .plus = .{0.0} ** types.max_nmutot };
    }

    var sqlm: [types.max_phase_coef]f64 = .{0.0} ** types.max_phase_coef;
    for (i_fourier + 1..coef_idx + 1) |l| {
        const lf: f64 = @floatFromInt(l);
        const mf: f64 = @floatFromInt(i_fourier);
        sqlm[l] = @sqrt(lf * lf - mf * mf);
    }

    var plm_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var p_lm1_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
    var p_l_plus: [types.max_nmutot]f64 = undefined;

    for (0..n) |imu| {
        const u = geo.u[imu];
        const one_minus_uu = 1.0 - u * u;
        const squu = @sqrt(@max(one_minus_uu, 0.0));
        // math: seed P_m^m(mu) for standalone PLM calculation.
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
    }

    if (coef_idx == i_fourier) {
        for (0..n) |imu| {
            plm_plus[imu] = p_l_plus[imu] * geo.w[imu];
        }
        return .{ .plus = plm_plus };
    }

    for (i_fourier..coef_idx) |l| {
        const a_coef = sqlm[l + 1];
        const c_coef = -sqlm[l];
        for (0..n) |imu| {
            const b_plus = (2.0 * @as(f64, @floatFromInt(l)) + 1.0) * geo.u[imu];
            // math: recurrence P_{l+1}^m = ((2l+1) mu P_l^m - sqrt(l^2-m^2) P_{l-1}^m) / sqrt((l+1)^2-m^2).
            const p_lp1 = (b_plus * p_l_plus[imu] + c_coef * p_lm1_plus[imu]) / a_coef;
            p_lm1_plus[imu] = p_l_plus[imu];
            p_l_plus[imu] = p_lp1;
        }
    }

    for (0..n) |imu| {
        plm_plus[imu] = p_l_plus[imu] * geo.w[imu];
    }
    return .{ .plus = plm_plus };
}

pub fn fillZplusZminFromBasis(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
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

// hot path:
//   when: for each layer/Fourier term during RT layer construction
//   work: builds dense Z+ and Z- phase matrices from coefficients and PLM basis
//   data: phase coefficients, Fourier PLM basis, stream dimensions, Z matrix outputs
//   follow: calcRTlayersIntoWithBasis and fixed 12x10 phase builder variants
//   math: Zplus_ij = sum_l beta_l P_l^m(mu_i)P_l^m(mu_j); Zmin uses (-1)^(l-m) beta_l.
pub fn fillZplusZminFromBasisLimited(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
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
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_sign * plus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plus_l[j];
                        zmin.data[row + j] = scaled_minus_i * plus_l[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_sign * plus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] += scaled_plus_i * plus_l[j];
                        zmin.data[row + j] += scaled_minus_i * plus_l[j];
                    }
                }
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * minus_sign * plm.plus[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plm.plus[j];
                        zmin.data[row + j] = scaled_minus_i * plm.plus[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * minus_sign * plm.plus[i];
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

// hot path:
//   when: layer RT construction stores phase rows as gas/aerosol weights
//   work: builds dense Z+ and Z- phase matrices directly from encoded phase weights
//   data: phase weights, prepared particle phase rows, Fourier PLM basis
//   follow: calcRTlayersIntoWithBasis and fixed 12x10 phase builder variants
//   math: beta_l = aerosol_weight*aerosol_beta_l + rayleigh2_weight for l=2, beta_0=1.
pub fn fillZplusZminFromWeightedPhaseLimited(
    i_fourier: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    const n = geo.nmutot;
    if (n == 12) {
        return fillZplusZminFromWeightedPhaseLimited12(
            i_fourier,
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
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
        const alpha1 = weightedPhaseCoefficient(
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
            l,
        );
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_sign * plus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plus_l[j];
                        zmin.data[row + j] = scaled_minus_i * plus_l[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plus_l[i];
                    const scaled_minus_i = alpha1 * minus_sign * plus_l[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] += scaled_plus_i * plus_l[j];
                        zmin.data[row + j] += scaled_minus_i * plus_l[j];
                    }
                }
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * minus_sign * plm.plus[i];
                    const row = i * n;
                    for (0..n) |j| {
                        zplus.data[row + j] = scaled_plus_i * plm.plus[j];
                        zmin.data[row + j] = scaled_minus_i * plm.plus[j];
                    }
                }
            } else {
                for (0..n) |i| {
                    const scaled_plus_i = alpha1 * plm.plus[i];
                    const scaled_minus_i = alpha1 * minus_sign * plm.plus[i];
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

// hot path:
//   when: reflectance and Jacobian weighting need phase rows rather than full matrices
//   work: builds one Z+/Z- row from phase coefficients and PLM basis
//   data: phase coefficients, row index, PLM basis, Z row outputs
//   follow: reflectance buildPhaseRowCache and scattering-source weighting
//   math: row Zplus_j = sum_l beta_l P_l^m(mu_row)P_l^m(mu_j); Zmin row applies parity (-1)^(l-m).
pub fn fillZplusZminRowFromBasisLimited(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    const n = geo.nmutot;
    if (n == 12) {
        return fillZplusZminRowFromBasisLimited12(
            i_fourier,
            phase_coefs,
            max_phase_index,
            geo,
            plm_basis,
            row_index,
        );
    }

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
            const minus_sign = minusParitySign(i_fourier, l);
            const scaled_plus_row = alpha1 * plus_l[row_index];
            const scaled_minus_row = alpha1 * minus_sign * plus_l[row_index];
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
            const minus_sign = minusParitySign(i_fourier, l);
            const scaled_plus_row = alpha1 * plm.plus[row_index];
            const scaled_minus_row = alpha1 * minus_sign * plm.plus[row_index];
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

fn fillZplusZminRowFromBasisLimited12(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    const bounded_max_phase_index = @min(max_phase_index, types.max_phase_coef - 1);
    if (row_index >= 12 or i_fourier > bounded_max_phase_index) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = 12,
        };
    }

    var row = PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = 12,
    };
    var first_order = true;
    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = phase_coefs[l];
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseRow12(&row, alpha1, plus_l, minus_sign, row_index, true);
            } else {
                fillPhaseRow12(&row, alpha1, plus_l, minus_sign, row_index, false);
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseRow12(&row, alpha1, &plm.plus, minus_sign, row_index, true);
            } else {
                fillPhaseRow12(&row, alpha1, &plm.plus, minus_sign, row_index, false);
            }
        }
        first_order = false;
    }
    if (first_order) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = 12,
        };
    }
    return row;
}

inline fn weightedPhaseCoefficient(
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
    index: usize,
) f64 {
    if (index == 0) return 1.0;
    var coefficient = aerosol_weight * aerosol_phase_coefs[index];
    // math: weighted phase coefficient combines aerosol phase with Rayleigh l=2 contribution.
    if (index == 2) coefficient += rayleigh2_weight;
    return coefficient;
}

// hot path:
//   when: integrated-source RTM quadrature levels store phase mixture weights instead of combined rows
//   work: builds one Z+/Z- row directly from gas/aerosol phase weights
//   data: phase weights, prepared particle phase rows, row index, PLM basis
//   follow: reflectance RTM quadrature path
//   math: weighted row uses beta_l = aerosol_weight*aerosol_beta_l plus Rayleigh2 at l=2.
pub fn fillZplusZminRowFromWeightedPhaseLimited(
    i_fourier: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    const n = geo.nmutot;
    if (n == 12) {
        return fillZplusZminRowFromWeightedPhaseLimited12(
            i_fourier,
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
            max_phase_index,
            geo,
            plm_basis,
            row_index,
        );
    }

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
        const alpha1 = weightedPhaseCoefficient(
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
            l,
        );
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_sign = minusParitySign(i_fourier, l);
            const scaled_plus_row = alpha1 * plus_l[row_index];
            const scaled_minus_row = alpha1 * minus_sign * plus_l[row_index];
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
            const minus_sign = minusParitySign(i_fourier, l);
            const scaled_plus_row = alpha1 * plm.plus[row_index];
            const scaled_minus_row = alpha1 * minus_sign * plm.plus[row_index];
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

fn fillZplusZminRowFromWeightedPhaseLimited12(
    i_fourier: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    const bounded_max_phase_index = @min(max_phase_index, types.max_phase_coef - 1);
    if (row_index >= 12 or i_fourier > bounded_max_phase_index) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = 12,
        };
    }

    var row = PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = 12,
    };
    var first_order = true;
    for (i_fourier..bounded_max_phase_index + 1) |l| {
        const alpha1 = weightedPhaseCoefficient(
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
            l,
        );
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseRow12(&row, alpha1, plus_l, minus_sign, row_index, true);
            } else {
                fillPhaseRow12(&row, alpha1, plus_l, minus_sign, row_index, false);
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseRow12(&row, alpha1, &plm.plus, minus_sign, row_index, true);
            } else {
                fillPhaseRow12(&row, alpha1, &plm.plus, minus_sign, row_index, false);
            }
        }
        first_order = false;
    }
    if (first_order) {
        return .{
            .zplus = .{0.0} ** types.max_nmutot,
            .zmin = .{0.0} ** types.max_nmutot,
            .n = 12,
        };
    }
    return row;
}

fn fillZplusZminFromBasisLimited12(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
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
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_sign, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_sign, false);
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, minus_sign, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, minus_sign, false);
            }
        }
        first_order = false;
    }
    if (first_order) return .{ .Zplus = Mat.zero(12), .Zmin = Mat.zero(12) };

    return .{ .Zplus = zplus, .Zmin = zmin };
}

fn fillZplusZminFromWeightedPhaseLimited12(
    i_fourier: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
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
        const alpha1 = weightedPhaseCoefficient(
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefs,
            l,
        );
        if (alpha1 == 0.0) continue;
        if (l <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[l];
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_sign, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, plus_l, minus_sign, false);
            }
        } else {
            const plm = computePlm(i_fourier, l, geo);
            const minus_sign = minusParitySign(i_fourier, l);
            if (first_order) {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, minus_sign, true);
            } else {
                fillPhaseTerm12(&zplus, &zmin, alpha1, &plm.plus, minus_sign, false);
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
    minus_sign: f64,
    comptime first_order: bool,
) void {
    var scaled_plus_col: [12]f64 = undefined;
    inline for (0..12) |j| {
        // math: precompute beta_l * P_l^m(mu_j) for the fixed 12-stream phase outer product.
        scaled_plus_col[j] = alpha1 * plus_l[j];
    }

    inline for (0..12) |i| {
        const plus_i = plus_l[i];
        const minus_i = minus_sign * plus_l[i];
        const row = i * 12;
        inline for (0..12) |j| {
            const idx = row + j;
            if (first_order) {
                // math: Zplus_ij += beta_l P_i P_j; Zmin_ij += parity * beta_l P_i P_j.
                zplus.data[idx] = plus_i * scaled_plus_col[j];
                zmin.data[idx] = minus_i * scaled_plus_col[j];
            } else {
                zplus.data[idx] += plus_i * scaled_plus_col[j];
                zmin.data[idx] += minus_i * scaled_plus_col[j];
            }
        }
    }
}

inline fn fillPhaseRow12(
    noalias row: *PhaseKernelRow,
    alpha1: f64,
    noalias plus_l: *const [types.max_nmutot]f64,
    minus_sign: f64,
    row_index: usize,
    comptime first_order: bool,
) void {
    const scaled_plus_row = alpha1 * plus_l[row_index];
    const scaled_minus_row = alpha1 * minus_sign * plus_l[row_index];
    inline for (0..12) |j| {
        const zplus_value = scaled_plus_row * plus_l[j];
        const zmin_value = scaled_minus_row * plus_l[j];
        if (first_order) {
            row.zplus[j] = zplus_value;
            row.zmin[j] = zmin_value;
        } else {
            row.zplus[j] += zplus_value;
            row.zmin[j] += zmin_value;
        }
    }
}

pub fn fillZplusZmin(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
    geo: *const Geometry,
) PhaseKernel {
    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    const plm_basis = FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return fillZplusZminFromBasis(i_fourier, phase_coefs, geo, &plm_basis);
}
