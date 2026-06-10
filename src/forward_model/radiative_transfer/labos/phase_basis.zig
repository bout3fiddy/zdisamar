const phase_functions = @import("../../optical_properties/shared/phase_functions.zig");
const types = @import("types.zig");

const Mat = types.Mat;
const Geometry = types.Geometry;

// phase_basis.zig --------------------------------------------------------------------------------------------|
// Builds LABOS Fourier phase-basis data: associated Legendre values, Z+ phase matrices, and Z- phase          |
// matrices. Layers use full matrices. Reflectance and Jacobian weighting often use one row at a time.         |
//                                                                                                             |
// called by                                                                                                   |
//   layers.zig      during RT layer construction                                                              |
//   reflectance.zig during integrated-source weighting and phase-row caching                                  |
//   workspace.zig   when PLM basis values are cached across one Fourier term                                  |
//                                                                                                             |
// main paths                                                                                                  |
//   FourierPlmBasis.init                                                                                      |
//     -> build weighted P_l^m(mu_i) basis for one Fourier index                                               |
//   fillZplusZminFromBasisLimited                                                                             |
//     -> full Z+/Z- matrices from phase coefficients                                                          |
//   fillZplusZminRowFromBasisLimited                                                                          |
//     -> one Z+/Z- row for reflectance weighting                                                              |
//   weighted variants                                                                                         |
//     -> mix aerosol phase with Rayleigh l=2 before building the same Z+/Z- objects                           |
//                                                                                                             |
// math names                                                                                                  |
//   m              : Fourier index                                                                            |
//   l              : phase coefficient index                                                                  |
//   P_l^m(mu_i)    : associated Legendre value for stream i                                                   |
//   beta_l         : phase coefficient for order l                                                            |
//   Zplus(i,j)     : sum over l of beta_l * P_l^m(mu_i) * P_l^m(mu_j)                                         |
//   Zmin(i,j)      : same outer product with parity (-1)^(l-m)                                                |
//                                                                                                             |
// scalar reduction from reference fillZplusZmin                                                               |
//   The reference has a full polarized Stokes matrix form. The O2 A scalar path keeps only alpha1, so the     |
//   large D1/D2 matrix product becomes one weighted outer product per phase coefficient.                      |
//                                                                                                             |
//   polarized S_l shape before the scalar reduction                                                           |
//                                                                                                             |
//       | alpha1  beta1    0       0    |                                                                     |
//       | beta1   alpha2   0       0    |                                                                     |
//   S = |   0       0    alpha3  beta2  |                                                                     |
//       |   0       0   -beta2   alpha4 |                                                                     |
//                                                                                                             |
//   scalar path keeps S[0,0] = alpha1 = beta_l                                                                |
//                                                                                                             |
// memory                                                                                                      |
//   FourierPlmBasis stores weighted plus-basis rows. Minus is reconstructed from parity when needed.          |
//   PhaseKernel stores dense Z+ and Z- matrices. PhaseKernelRow stores one dense row from each matrix.        |
// ------------------------------------------------------------------------------------------------------------|

// PlmArrays --------------------------------------------------------------------------------------------------|
// Temporary plus-basis values for one phase coefficient. Minus is not stored; it is plus times                |
// (-1)^(l-m).                                                                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..95] plus : [12]f64                                                                                     |
//          |----- [ 0.. 7] plus[0]                                                                            |
//          |----- [88..95] plus[11]                                                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 96 B (0.094 KiB); total = per instance * live instance count                      |
const PlmArrays = struct {
    plus: [types.max_nmutot]f64,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseKernel ------------------------------------------------------------------------------------------------|
// Dense Z+ and Z- phase matrices for one Fourier term and one layer/phase mixture.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2320 B (2.266 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1159] Zplus : Mat                                                                                    |
// [1160..2319] Zmin  : Mat                                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 2320 B (2.266 KiB); total = per instance * live instance count                    |
pub const PhaseKernel = struct {
    Zplus: Mat,
    Zmin: Mat,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseKernelRow ---------------------------------------------------------------------------------------------|
// One row from Z+ and one row from Z-. Used when reflectance weighting needs row-local values.                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 200 B (0.195 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 95] zplus : [12]f64                                                                                  |
// [ 96..191] zmin  : [12]f64                                                                                  |
// [192..199] n     : usize                                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 200 B (0.195 KiB); total = per instance * live instance count                     |
pub const PhaseKernelRow = struct {
    zplus: [types.max_nmutot]f64,
    zmin: [types.max_nmutot]f64,
    n: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// FourierPlmBasis --------------------------------------------------------------------------------------------|
// Cached weighted associated Legendre basis for one Fourier index.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 14512 B (14.172 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..    7] i_fourier       : usize                                                                      |
// [    8..   15] max_phase_index : usize                                                                      |
// [   16..14511] plus            : [151][12]f64                                                               |
//                  |----- [   16..  111] plus[0]                                                              |
//                  |----- [14416..14511] plus[150]                                                            |
//                                                                                                             |
// encoded fields                                                                                              |
//   minus basis derives from plus by (-1)^(coef_idx - i_fourier)                                              |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 14512 B (14.172 KiB); total = per instance * live instance count                  |
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
        // FourierPlmBasis.storeWeighted ----------------------------------------------------------------------|
        // Store P_l^m(mu_i) * w_i for one phase coefficient.                                                  |
        //                                                                                                     |
        // The stream weights live in Geometry. Z-matrix builders reuse this weighted basis so the inner outer |
        // products do not multiply by w_i every time.                                                         |
        // ----------------------------------------------------------------------------------------------------|

        for (0..geo.nmutot) |imu| {
            self.plus[coef_idx][imu] = p_l_plus[imu] * geo.w[imu];
        }
    }

    pub fn init(i_fourier: usize, max_phase_index: usize, geo: *const Geometry) FourierPlmBasis {
        // FourierPlmBasis.init -------------------------------------------------------------------------------|
        // Build weighted associated Legendre basis values for one Fourier index m. Steps:                     |
        //                                                                                                     |
        //   1. precompute sqrt(l^2 - m^2) recurrence coefficients                                             |
        //   2. seed P_m^m(mu_i) for every stream                                                              |
        //   3. store weighted P_m^m(mu_i) * w_i                                                               |
        //   4. walk l upward and store each weighted P_l^m row                                                |
        //                                                                                                     |
        // math                                                                                                |
        //   P_{l+1}^m = ((2 * l + 1) * mu * P_l^m - sqrt(l^2 - m^2) * P_{l-1}^m)                              |
        //                 / sqrt((l + 1)^2 - m^2)                                                             |
        //                                                                                                     |
        //   The m=0,1,2 seed cases and the m>=3 product follow the reference-normalized phase basis.          |
        // ----------------------------------------------------------------------------------------------------|

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
            sqlm[l] = @sqrt(lf * lf - mf * mf);
        }

        var p_lm1_plus: [types.max_nmutot]f64 = .{0.0} ** types.max_nmutot;
        var p_l_plus: [types.max_nmutot]f64 = undefined;
        for (0..geo.nmutot) |imu| {
            const u = geo.u[imu];
            const one_minus_uu = 1.0 - u * u;
            const squu = @sqrt(@max(one_minus_uu, 0.0));
            const start_val: f64 = switch (i_fourier) {
                0 => 1.0,
                1 => squu / @sqrt(2.0),
                2 => 0.25 * @sqrt(6.0) * one_minus_uu,
                else => build_high_order_seed: {
                    var f: f64 = 0.375 * one_minus_uu * one_minus_uu;
                    for (3..i_fourier + 1) |m_idx| {
                        const mf: f64 = @floatFromInt(m_idx);
                        f *= one_minus_uu * (mf - 0.5) / mf;
                    }
                    break :build_high_order_seed @sqrt(@max(f, 0.0));
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
    // minusParitySign ----------------------------------------------------------------------------------------|
    // Return the Z- parity sign for coefficient l at Fourier index m.                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   sign = (-1)^(l - m)                                                                                   |
    // --------------------------------------------------------------------------------------------------------|

    return if (((coef_idx - i_fourier) & 1) == 0) 1.0 else -1.0;
}

fn computePlm(i_fourier: usize, coef_idx: usize, geo: *const Geometry) PlmArrays {
    // computePlm ---------------------------------------------------------------------------------------------|
    // Build one weighted associated Legendre row when it was not already cached in FourierPlmBasis.           |
    //                                                                                                         |
    // Used by phase builders when a caller asks for l beyond plm_basis.max_phase_index. The math is the       |
    // same recurrence as FourierPlmBasis.init, but only the requested coefficient row is returned.            |
    //                                                                                                         |
    // math                                                                                                    |
    //   plus[i] = P_l^m(mu_i) * w_i                                                                           |
    //   minus is not stored here; callers apply (-1)^(l-m) when they build Z-.                                |
    // --------------------------------------------------------------------------------------------------------|

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

        const start_val: f64 = switch (i_fourier) {
            0 => 1.0,
            1 => squu / @sqrt(2.0),
            2 => 0.25 * @sqrt(6.0) * one_minus_uu,
            else => build_high_order_seed: {
                var f: f64 = 0.375 * one_minus_uu * one_minus_uu;
                for (3..i_fourier + 1) |m_idx| {
                    const mf: f64 = @floatFromInt(m_idx);
                    f *= one_minus_uu * (mf - 0.5) / mf;
                }
                break :build_high_order_seed @sqrt(@max(f, 0.0));
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
    // fillZplusZminFromBasis ---------------------------------------------------------------------------------|
    // Convenience wrapper for callers that want the phase ceiling inferred from phase_coefs.                  |
    // Builds no new math itself; it chooses max l and delegates to fillZplusZminFromBasisLimited.             |
    // --------------------------------------------------------------------------------------------------------|

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
    phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromBasisLimited --------------------------------------------------------------------------|
    // Build dense Z+ and Z- phase matrices from phase coefficients and a PLM basis. Steps:                    |
    //                                                                                                         |
    //   1. use the fixed 12-stream builder when the geometry has the normal LABOS stream count                |
    //   2. clamp the requested phase ceiling to the storage limit                                             |
    //   3. loop retained phase coefficients l                                                                 |
    //   4. add one outer product into Z+ and Z- for each nonzero coefficient                                  |
    //   5. return zero matrices when no coefficient contributed                                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : once per layer and Fourier term during RT layer construction                               |
    //   costly   : dense n x n outer product for every retained phase coefficient                             |
    //   memory   : uses cached FourierPlmBasis when l is inside plm_basis.max_phase_index                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   Zplus(i,j) += beta_l * P_l^m(mu_i) * P_l^m(mu_j)                                                      |
    //   Zmin(i,j)  += (-1)^(l-m) * beta_l * P_l^m(mu_i) * P_l^m(mu_j)                                         |
    //                                                                                                         |
    // zdisamar's scalar path uses the same fillZplusZmin reduction:                                           |
    //                                                                                                         |
    //   Z+ = sum_l alpha1_l * Plm_0(+mu_i) * Plm_0(+mu_j)                                                     |
    //   Z- = sum_l alpha1_l * Plm_0(-mu_i) * Plm_0(+mu_j)                                                     |
    //                                                                                                         |
    // The stored basis already includes stream weight w_j, so each row update is an outer product using       |
    // plus_l[j] = P_l^m(mu_j) * w_j.                                                                          |
    // --------------------------------------------------------------------------------------------------------|

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
            // Cached basis path ------------------------------------------------------------------------------|
            // Reuse P_l^m(mu_i) * w_i from FourierPlmBasis.                                                   |
            // ------------------------------------------------------------------------------------------------|

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
            // One-off basis path -----------------------------------------------------------------------------|
            // Build only this l when it sits beyond the cached PLM ceiling.                                   |
            // ------------------------------------------------------------------------------------------------|

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

pub fn fillZplusZminFromWeightedPhaseLimited(
    i_fourier: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromWeightedPhaseLimited ------------------------------------------------------------------|
    // Build dense Z+ and Z- matrices after mixing aerosol phase with Rayleigh l=2. Steps:                     |
    //                                                                                                         |
    //   1. use the fixed 12-stream builder for the normal LABOS geometry                                      |
    //   2. clamp the requested phase ceiling to the storage limit                                             |
    //   3. compute beta_l from aerosol weight, aerosol phase, and Rayleigh l=2                                |
    //   4. add one outer product into Z+ and Z- for each nonzero beta_l                                       |
    //   5. return zero matrices when no coefficient contributed                                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : layer RT construction when phase is stored as gas/aerosol weights                          |
    //   costly   : dense n x n outer product for every retained phase coefficient                             |
    //   memory   : uses cached FourierPlmBasis when l is inside plm_basis.max_phase_index                     |
    //                                                                                                         |
    // math                                                                                                    |
    //   beta_0 = 1                                                                                            |
    //   beta_l = aerosol_weight * aerosol_beta_l                                                              |
    //   beta_2 += rayleigh2_weight                                                                            |
    // --------------------------------------------------------------------------------------------------------|

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
            // Cached basis path ------------------------------------------------------------------------------|
            // Reuse P_l^m(mu_i) * w_i from FourierPlmBasis.                                                   |
            // ------------------------------------------------------------------------------------------------|

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
            // One-off basis path -----------------------------------------------------------------------------|
            // Build only this l when it sits beyond the cached PLM ceiling.                                   |
            // ------------------------------------------------------------------------------------------------|

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

pub fn fillZplusZminRowFromBasisLimited(
    i_fourier: usize,
    phase_coefs: *const [types.max_phase_coef]f64,
    max_phase_index: usize,
    geo: *const Geometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    // fillZplusZminRowFromBasisLimited -----------------------------------------------------------------------|
    // Build one row of Z+ and Z- from phase coefficients and a PLM basis. Steps:                              |
    //                                                                                                         |
    //   1. use the fixed 12-stream row builder for the normal LABOS geometry                                  |
    //   2. reject invalid row or phase range with a zero row                                                  |
    //   3. loop retained phase coefficients l                                                                 |
    //   4. add one row of the phase outer product for each nonzero coefficient                                |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : reflectance and Jacobian weighting when only one phase row is needed                       |
    //   costly   : n output columns for every retained phase coefficient                                      |
    //   memory   : avoids building a full PhaseKernel when the caller only needs one row                      |
    //                                                                                                         |
    // math                                                                                                    |
    //   row.zplus(j) += beta_l * P_l^m(mu_row) * P_l^m(mu_j)                                                  |
    //   row.zmin(j)  += (-1)^(l-m) * beta_l * P_l^m(mu_row) * P_l^m(mu_j)                                     |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillZplusZminRowFromBasisLimited12 ---------------------------------------------------------------------|
    // Fixed 12-stream version of fillZplusZminRowFromBasisLimited.                                            |
    //                                                                                                         |
    // Keeps the column loop in fillPhaseRow12 so the compiler sees constant 12-wide bounds.                   |
    // --------------------------------------------------------------------------------------------------------|

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
    // weightedPhaseCoefficient -------------------------------------------------------------------------------|
    // Return beta_l for a mixed aerosol/Rayleigh phase expansion.                                             |
    //                                                                                                         |
    // math                                                                                                    |
    //   beta_0 = 1                                                                                            |
    //   beta_l = aerosol_weight * aerosol_beta_l                                                              |
    //   beta_2 += rayleigh2_weight                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    if (index == 0) return 1.0;
    var coefficient = aerosol_weight * aerosol_phase_coefs[index];

    if (index == 2) coefficient += rayleigh2_weight;
    return coefficient;
}

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
    // fillZplusZminRowFromWeightedPhaseLimited ---------------------------------------------------------------|
    // Build one Z+/Z- row after mixing aerosol phase with Rayleigh l=2. Steps:                                |
    //                                                                                                         |
    //   1. use the fixed 12-stream row builder for the normal LABOS geometry                                  |
    //   2. reject invalid row or phase range with a zero row                                                  |
    //   3. compute beta_l from aerosol weight, aerosol phase, and Rayleigh l=2                                |
    //   4. add one row of the phase outer product for each nonzero beta_l                                     |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : integrated-source RTM quadrature weighting                                                 |
    //   costly   : n output columns for every retained phase coefficient                                      |
    //   memory   : avoids building a full PhaseKernel when the caller only needs one row                      |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillZplusZminRowFromWeightedPhaseLimited12 -------------------------------------------------------------|
    // Fixed 12-stream row builder for mixed aerosol/Rayleigh phase.                                           |
    //                                                                                                         |
    // Keeps the column loop in fillPhaseRow12. The caller gets one Z+ row and one Z- row for weighting.       |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillZplusZminFromBasisLimited12 ------------------------------------------------------------------------|
    // Fixed 12-stream full-matrix builder for one layer and one Fourier term.                                 |
    //                                                                                                         |
    // This is the normal LABOS path. Each retained beta_l adds one 12x12 outer product into Z+ and Z-.        |
    // fillPhaseTerm12 keeps that fixed-size outer product in one small helper.                                |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillZplusZminFromWeightedPhaseLimited12 ----------------------------------------------------------------|
    // Fixed 12-stream full-matrix builder for mixed aerosol/Rayleigh phase.                                   |
    //                                                                                                         |
    // Same matrix work as fillZplusZminFromBasisLimited12, but beta_l is assembled from aerosol phase plus    |
    // the Rayleigh l=2 term before the outer product is added.                                                |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillPhaseTerm12 ----------------------------------------------------------------------------------------|
    // Add one beta_l outer product into fixed 12x12 Z+ and Z- matrices.                                       |
    //                                                                                                         |
    // The column side is scaled once, then reused for every row. first_order chooses between initializing     |
    // the matrix and accumulating into an existing matrix.                                                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   scaled_col[j] = beta_l * P_l^m(mu_j) * w_j                                                            |
    //                                                                                                         |
    //   Zplus(i,j) += P_l^m(mu_i) * scaled_col[j]                                                             |
    //   Zmin(i,j)  += (-1)^(l-m) * P_l^m(mu_i) * scaled_col[j]                                                |
    // --------------------------------------------------------------------------------------------------------|

    var scaled_plus_col: [12]f64 = undefined;

    inline for (0..12) |j| {
        scaled_plus_col[j] = alpha1 * plus_l[j];
    }

    inline for (0..12) |i| {
        const plus_i = plus_l[i];
        const minus_i = minus_sign * plus_l[i];
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

inline fn fillPhaseRow12(
    noalias row: *PhaseKernelRow,
    alpha1: f64,
    noalias plus_l: *const [types.max_nmutot]f64,
    minus_sign: f64,
    row_index: usize,
    comptime first_order: bool,
) void {
    // fillPhaseRow12 -----------------------------------------------------------------------------------------|
    // Add one beta_l row contribution into fixed 12-wide Z+ and Z- rows.                                      |
    //                                                                                                         |
    // Used by integrated-source reflectance code that only needs one phase row. first_order chooses between   |
    // initializing the row and accumulating into an existing row.                                             |
    //                                                                                                         |
    // math                                                                                                    |
    //   row.zplus(j) += beta_l * P_l^m(mu_row) * P_l^m(mu_j) * w_j                                            |
    //   row.zmin(j)  += (-1)^(l-m) times the same term                                                        |
    // --------------------------------------------------------------------------------------------------------|

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
    // fillZplusZmin ------------------------------------------------------------------------------------------|
    // Build a PLM basis and then build dense Z+ and Z- phase matrices.                                        |
    //                                                                                                         |
    // Used by callers that do not already have a FourierPlmBasis cached for this Fourier term.                |
    // --------------------------------------------------------------------------------------------------------|

    const max_phase_index = phase_functions.maxPhaseCoefficientIndex(phase_coefs);
    const plm_basis = FourierPlmBasis.init(i_fourier, max_phase_index, geo);
    return fillZplusZminFromBasis(i_fourier, phase_coefs, geo, &plm_basis);
}
