const std = @import("std");

const gauss_angles = @import("gauss_angles.zig");
const phase_table = @import("../setup/phase_table.zig");
const rows = @import("rows.zig");

// phase_basis.zig --------------------------------------------------------------------------------------------|
// LABOS Fourier phase-basis rows used by layer phase kernels and reflectance weighting.                       |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/phase_basis.zig` `FourierPlmBasis.init` and        |
//   `minusParitySign`. The fixed row dimensions come from the old LABOS `types.zig` phase/stream caps.        |
//                                                                                                             |
// math                                                                                                        |
//   m           : Fourier index                                                                               |
//   l           : phase coefficient index                                                                     |
//   P_l^m(mu_i) : associated Legendre value for stream i                                                      |
//   plus[l][i]  : P_l^m(mu_i) * stream_weight_i                                                               |
//   minus sign  : (-1)^(l-m), applied later by Z- phase-kernel builders                                       |
//                                                                                                             |
// memory                                                                                                      |
//   FourierPlmBasis stores weighted plus-basis rows for one Fourier term and one geometry. PhaseKernel and    |
//   PhaseKernelRow store full or row-local Z+/Z- products. The minus basis derives from parity.               |
// ------------------------------------------------------------------------------------------------------------|

// PlmArrays --------------------------------------------------------------------------------------------------|
// Temporary weighted plus-basis row for one phase coefficient.                                                |
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
// footprint: per instance = 96 B (0.094 KiB); stack row for uncached coefficient fallback                     |
const PlmArrays = struct {
    plus: [gauss_angles.max_stream_count]f64,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseKernel ------------------------------------------------------------------------------------------------|
// Dense Z+ and Z- phase matrices for one Fourier term and one phase mixture.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2320 B (2.266 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1159] zplus : Mat                                                                                    |
// [1160..2319] zmin  : Mat                                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 37 cache line(s) at 64 B per line                                                               |
// footprint: per instance = 2320 B (2.266 KiB); stack/workspace row for one layer/Fourier term                |
pub const PhaseKernel = struct {
    zplus: rows.Mat,
    zmin: rows.Mat,
};
// ------------------------------------------------------------------------------------------------------------|

// PhaseKernelRow ---------------------------------------------------------------------------------------------|
// One row from Z+ and one row from Z- for source-interface and reflectance weighting.                         |
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
// cache span: 4 cache line(s) at 64 B per line                                                                |
// footprint: per instance = 200 B (0.195 KiB); one cached phase row per source/interface slot                 |
pub const PhaseKernelRow = struct {
    zplus: [gauss_angles.max_stream_count]f64,
    zmin: [gauss_angles.max_stream_count]f64,
    n: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// FourierPlmBasis --------------------------------------------------------------------------------------------|
// Cached weighted associated-Legendre rows for one Fourier index.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 14512 B (14.172 KiB), align: 8 B                                                                      |
//                                                                                                             |
// memory                                                                                                      |
// [    0..    7] fourier_index   : usize                                                                      |
// [    8..   15] max_phase_index : usize                                                                      |
// [   16..14511] plus            : [151][12]f64                                                               |
//                  |----- [   16..  111] plus[0]                                                              |
//                  |----- [14416..14511] plus[150]                                                            |
//                                                                                                             |
// encoded fields                                                                                              |
//   minus basis derives from plus by (-1)^(phase_index - fourier_index).                                      |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 227 cache line(s) at 64 B per line                                                              |
// footprint: per instance = 14512 B (14.172 KiB); one cached row per retained Fourier term/workspace slot     |
pub const FourierPlmBasis = struct {
    fourier_index: usize,
    max_phase_index: usize,
    plus: [phase_table.coefficient_count][gauss_angles.max_stream_count]f64,

    fn storeWeighted(
        self: *FourierPlmBasis,
        phase_index: usize,
        p_l_plus: *const [gauss_angles.max_stream_count]f64,
        geometry: *const gauss_angles.GaussGeometry,
    ) void {
        // FourierPlmBasis.storeWeighted --------------------------------------------------------------------- |
        // Store P_l^m(mu_i) * w_i for one phase coefficient and active stream.                                |
        // ----------------------------------------------------------------------------------------------------|
        for (0..geometry.stream_count) |stream_index| {
            self.plus[phase_index][stream_index] = p_l_plus[stream_index] * geometry.w[stream_index];
        }
    }

    pub fn init(
        fourier_index: usize,
        max_phase_index: usize,
        geometry: *const gauss_angles.GaussGeometry,
    ) FourierPlmBasis {
        // FourierPlmBasis.init ------------------------------------------------------------------------------ |
        // Build weighted associated-Legendre basis values for one Fourier index m.                            |
        //                                                                                                     |
        // math                                                                                                |
        //   P_{l+1}^m = ((2l + 1) * mu * P_l^m - sqrt(l^2 - m^2) * P_{l-1}^m)                                 |
        //                 / sqrt((l + 1)^2 - m^2)                                                             |
        //                                                                                                     |
        //   The m=0,1,2 seed cases and the m>=3 product follow the reference-normalized LABOS basis.          |
        // ----------------------------------------------------------------------------------------------------|
        var result = FourierPlmBasis{
            .fourier_index = fourier_index,
            .max_phase_index = max_phase_index,
            .plus = undefined,
        };
        if (max_phase_index < fourier_index) return result;

        var sqlm: [phase_table.coefficient_count]f64 = .{0.0} ** phase_table.coefficient_count;
        for (fourier_index + 1..max_phase_index + 1) |phase_index| {
            const lf: f64 = @floatFromInt(phase_index);
            const mf: f64 = @floatFromInt(fourier_index);
            sqlm[phase_index] = @sqrt(lf * lf - mf * mf);
        }

        var p_lm1_plus: [gauss_angles.max_stream_count]f64 = .{0.0} ** gauss_angles.max_stream_count;
        var p_l_plus: [gauss_angles.max_stream_count]f64 = undefined;
        for (0..geometry.stream_count) |stream_index| {
            const mu = geometry.u[stream_index];
            const one_minus_mu_squared = 1.0 - mu * mu;
            const sqrt_one_minus_mu_squared = @sqrt(@max(one_minus_mu_squared, 0.0));
            const start_value: f64 = switch (fourier_index) {
                0 => 1.0,
                1 => sqrt_one_minus_mu_squared / @sqrt(2.0),
                2 => 0.25 * @sqrt(6.0) * one_minus_mu_squared,
                else => build_high_order_seed: {
                    var seed: f64 = 0.375 * one_minus_mu_squared * one_minus_mu_squared;
                    for (3..fourier_index + 1) |m_index| {
                        const mf: f64 = @floatFromInt(m_index);
                        seed *= one_minus_mu_squared * (mf - 0.5) / mf;
                    }
                    break :build_high_order_seed @sqrt(@max(seed, 0.0));
                },
            };
            p_l_plus[stream_index] = start_value;
        }

        result.storeWeighted(fourier_index, &p_l_plus, geometry);
        if (max_phase_index == fourier_index) return result;

        for (fourier_index..max_phase_index) |phase_index| {
            const a_coefficient = sqlm[phase_index + 1];
            const c_coefficient = -sqlm[phase_index];
            for (0..geometry.stream_count) |stream_index| {
                const b_plus = (2.0 * @as(f64, @floatFromInt(phase_index)) + 1.0) *
                    geometry.u[stream_index];
                const p_lp1 =
                    (b_plus * p_l_plus[stream_index] + c_coefficient * p_lm1_plus[stream_index]) /
                    a_coefficient;
                p_lm1_plus[stream_index] = p_l_plus[stream_index];
                p_l_plus[stream_index] = p_lp1;
            }
            result.storeWeighted(phase_index + 1, &p_l_plus, geometry);
        }

        return result;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub inline fn minusParitySign(fourier_index: usize, phase_index: usize) f64 {
    // minusParitySign --------------------------------------------------------------------------------------- |
    // Return the Z- parity sign for coefficient l at Fourier index m.                                         |
    //                                                                                                         |
    // math                                                                                                    |
    //   sign = (-1)^(l - m)                                                                                   |
    // --------------------------------------------------------------------------------------------------------|
    return if (((phase_index - fourier_index) & 1) == 0) 1.0 else -1.0;
}

fn computePlm(
    fourier_index: usize,
    phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
) PlmArrays {
    // computePlm -------------------------------------------------------------------------------------------- |
    // Build one weighted associated-Legendre row when it was not already cached in FourierPlmBasis.           |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `phase_basis.zig` `computePlm`; same recurrence as `FourierPlmBasis.init`.                  |
    // --------------------------------------------------------------------------------------------------------|
    if (phase_index < fourier_index) {
        return .{ .plus = .{0.0} ** gauss_angles.max_stream_count };
    }

    var sqlm: [phase_table.coefficient_count]f64 = .{0.0} ** phase_table.coefficient_count;
    for (fourier_index + 1..phase_index + 1) |l_index| {
        const lf: f64 = @floatFromInt(l_index);
        const mf: f64 = @floatFromInt(fourier_index);
        sqlm[l_index] = @sqrt(lf * lf - mf * mf);
    }

    var plm_plus: [gauss_angles.max_stream_count]f64 = .{0.0} ** gauss_angles.max_stream_count;
    var p_lm1_plus: [gauss_angles.max_stream_count]f64 = .{0.0} ** gauss_angles.max_stream_count;
    var p_l_plus: [gauss_angles.max_stream_count]f64 = undefined;
    for (0..geometry.stream_count) |stream_index| {
        const mu = geometry.u[stream_index];
        const one_minus_mu_squared = 1.0 - mu * mu;
        const sqrt_one_minus_mu_squared = @sqrt(@max(one_minus_mu_squared, 0.0));
        const start_value: f64 = switch (fourier_index) {
            0 => 1.0,
            1 => sqrt_one_minus_mu_squared / @sqrt(2.0),
            2 => 0.25 * @sqrt(6.0) * one_minus_mu_squared,
            else => build_high_order_seed: {
                var seed: f64 = 0.375 * one_minus_mu_squared * one_minus_mu_squared;
                for (3..fourier_index + 1) |m_index| {
                    const mf: f64 = @floatFromInt(m_index);
                    seed *= one_minus_mu_squared * (mf - 0.5) / mf;
                }
                break :build_high_order_seed @sqrt(@max(seed, 0.0));
            },
        };
        p_l_plus[stream_index] = start_value;
    }

    if (phase_index == fourier_index) {
        for (0..geometry.stream_count) |stream_index| {
            plm_plus[stream_index] = p_l_plus[stream_index] * geometry.w[stream_index];
        }
        return .{ .plus = plm_plus };
    }

    for (fourier_index..phase_index) |l_index| {
        const a_coefficient = sqlm[l_index + 1];
        const c_coefficient = -sqlm[l_index];
        for (0..geometry.stream_count) |stream_index| {
            const b_plus = (2.0 * @as(f64, @floatFromInt(l_index)) + 1.0) *
                geometry.u[stream_index];
            const p_lp1 =
                (b_plus * p_l_plus[stream_index] + c_coefficient * p_lm1_plus[stream_index]) /
                a_coefficient;
            p_lm1_plus[stream_index] = p_l_plus[stream_index];
            p_l_plus[stream_index] = p_lp1;
        }
    }

    for (0..geometry.stream_count) |stream_index| {
        plm_plus[stream_index] = p_l_plus[stream_index] * geometry.w[stream_index];
    }
    return .{ .plus = plm_plus };
}

pub fn fillZplusZminFromBasis(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromBasis -------------------------------------------------------------------------------- |
    // Infer the active phase ceiling and build dense Z+/Z- matrices from a cached PLM basis.                  |
    // --------------------------------------------------------------------------------------------------------|
    return fillZplusZminFromBasisLimited(
        fourier_index,
        phase_coefficients,
        phase_table.maxPhaseCoefficientIndex(phase_coefficients),
        geometry,
        plm_basis,
    );
}

pub fn fillZplusZmin(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    geometry: *const gauss_angles.GaussGeometry,
) PhaseKernel {
    // fillZplusZmin ----------------------------------------------------------------------------------------- |
    // Build a one-off PLM basis and dense Z+/Z- matrices for callers without a cached basis row.              |
    // --------------------------------------------------------------------------------------------------------|
    const max_phase_index = phase_table.maxPhaseCoefficientIndex(phase_coefficients);
    const plm_basis = FourierPlmBasis.init(fourier_index, max_phase_index, geometry);
    return fillZplusZminFromBasis(fourier_index, phase_coefficients, geometry, &plm_basis);
}

pub fn fillZplusZminFromBasisLimited(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromBasisLimited ------------------------------------------------------------------------- |
    // Build dense Z+ and Z- phase matrices from phase coefficients and one Fourier PLM basis.                 |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `phase_basis.zig` `fillZplusZminFromBasisLimited`.                                          |
    //                                                                                                         |
    // math                                                                                                    |
    //   Zplus(i,j) += beta_l * P_l^m(mu_i) * P_l^m(mu_j)                                                      |
    //   Zmin(i,j)  += (-1)^(l-m) * beta_l * P_l^m(mu_i) * P_l^m(mu_j)                                         |
    //                                                                                                         |
    //   FourierPlmBasis stores P_l^m(mu_i) * w_i, so this builder reuses the old weighted outer product.      |
    // --------------------------------------------------------------------------------------------------------|
    if (geometry.stream_count == rows.max_stream_count) {
        return fillZplusZminFromBasisLimited12(
            fourier_index,
            phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
        );
    }

    return fillZplusZminGeneric(
        fourier_index,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        false,
        0.0,
        0.0,
    );
}

pub fn fillZplusZminFromWeightedPhaseLimited(
    fourier_index: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromWeightedPhaseLimited ----------------------------------------------------------------- |
    // Build dense Z+/Z- matrices after mixing aerosol phase with the Rayleigh l=2 coefficient.                |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `phase_basis.zig` `fillZplusZminFromWeightedPhaseLimited`.                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   beta_0 = 1                                                                                            |
    //   beta_l = aerosol_weight * aerosol_beta_l                                                              |
    //   beta_2 += rayleigh2_weight                                                                            |
    // --------------------------------------------------------------------------------------------------------|
    if (geometry.stream_count == rows.max_stream_count) {
        return fillZplusZminFromWeightedPhaseLimited12(
            fourier_index,
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
        );
    }

    return fillZplusZminGeneric(
        fourier_index,
        aerosol_phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        true,
        aerosol_weight,
        rayleigh2_weight,
    );
}

pub fn fillZplusZminRowFromBasisLimited(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    // fillZplusZminRowFromBasisLimited ---------------------------------------------------------------------- |
    // Build one Z+/Z- row from phase coefficients and one Fourier PLM basis.                                  |
    // --------------------------------------------------------------------------------------------------------|
    if (geometry.stream_count == rows.max_stream_count) {
        return fillZplusZminRowFromBasisLimited12(
            fourier_index,
            phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
            row_index,
        );
    }

    return fillZplusZminRowGeneric(
        fourier_index,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        row_index,
        false,
        0.0,
        0.0,
    );
}

pub fn fillZplusZminRowFromWeightedPhaseLimited(
    fourier_index: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    // fillZplusZminRowFromWeightedPhaseLimited -------------------------------------------------------------- |
    // Build one Z+/Z- row after mixing aerosol phase with the Rayleigh l=2 coefficient.                       |
    // --------------------------------------------------------------------------------------------------------|
    if (geometry.stream_count == rows.max_stream_count) {
        return fillZplusZminRowFromWeightedPhaseLimited12(
            fourier_index,
            aerosol_weight,
            rayleigh2_weight,
            aerosol_phase_coefficients,
            max_phase_index,
            geometry,
            plm_basis,
            row_index,
        );
    }

    return fillZplusZminRowGeneric(
        fourier_index,
        aerosol_phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        row_index,
        true,
        aerosol_weight,
        rayleigh2_weight,
    );
}

inline fn weightedPhaseCoefficient(
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_table.coefficient_count]f64,
    index: usize,
) f64 {
    // weightedPhaseCoefficient ------------------------------------------------------------------------------ |
    // Return beta_l for a mixed aerosol/Rayleigh phase expansion.                                             |
    // --------------------------------------------------------------------------------------------------------|
    if (index == 0) return 1.0;

    var coefficient = aerosol_weight * aerosol_phase_coefficients[index];
    if (index == 2) coefficient += rayleigh2_weight;
    return coefficient;
}

inline fn chooseCoefficient(
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    phase_index: usize,
    use_weighted_phase: bool,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
) f64 {
    // chooseCoefficient ------------------------------------------------------------------------------------- |
    // Select either the direct phase row or the old aerosol/Rayleigh mixed coefficient.                       |
    // --------------------------------------------------------------------------------------------------------|
    if (use_weighted_phase) {
        return weightedPhaseCoefficient(
            aerosol_weight,
            rayleigh2_weight,
            phase_coefficients,
            phase_index,
        );
    }
    return phase_coefficients[phase_index];
}

fn fillZplusZminGeneric(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    use_weighted_phase: bool,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
) PhaseKernel {
    // fillZplusZminGeneric ---------------------------------------------------------------------------------- |
    // Shared variable-stream Z+/Z- builder used outside the fixed 12-stream LABOS route.                      |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const bounded_max_phase_index = @min(max_phase_index, phase_table.coefficient_count - 1);
    if (fourier_index > bounded_max_phase_index) {
        return .{ .zplus = rows.Mat.zero(stream_count), .zmin = rows.Mat.zero(stream_count) };
    }

    var zplus = rows.Mat{ .data = undefined, .n = stream_count };
    var zmin = rows.Mat{ .data = undefined, .n = stream_count };
    var first_order = true;

    for (fourier_index..bounded_max_phase_index + 1) |phase_index| {
        const coefficient = chooseCoefficient(
            phase_coefficients,
            phase_index,
            use_weighted_phase,
            aerosol_weight,
            rayleigh2_weight,
        );
        if (coefficient == 0.0) continue;

        const plus_l = choosePlusBasis(fourier_index, phase_index, geometry, plm_basis);
        fillPhaseTermGeneric(
            &zplus,
            &zmin,
            stream_count,
            coefficient,
            &plus_l.plus,
            minusParitySign(fourier_index, phase_index),
            first_order,
        );
        first_order = false;
    }

    if (first_order) return .{ .zplus = rows.Mat.zero(stream_count), .zmin = rows.Mat.zero(stream_count) };
    return .{ .zplus = zplus, .zmin = zmin };
}

fn fillZplusZminRowGeneric(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
    use_weighted_phase: bool,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
) PhaseKernelRow {
    // fillZplusZminRowGeneric ------------------------------------------------------------------------------- |
    // Shared variable-stream row builder used outside the fixed 12-stream LABOS route.                        |
    // --------------------------------------------------------------------------------------------------------|
    const stream_count = geometry.stream_count;
    const bounded_max_phase_index = @min(max_phase_index, phase_table.coefficient_count - 1);
    if (row_index >= stream_count or fourier_index > bounded_max_phase_index) {
        return .{
            .zplus = .{0.0} ** gauss_angles.max_stream_count,
            .zmin = .{0.0} ** gauss_angles.max_stream_count,
            .n = stream_count,
        };
    }

    var row = PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = stream_count,
    };
    var first_order = true;

    for (fourier_index..bounded_max_phase_index + 1) |phase_index| {
        const coefficient = chooseCoefficient(
            phase_coefficients,
            phase_index,
            use_weighted_phase,
            aerosol_weight,
            rayleigh2_weight,
        );
        if (coefficient == 0.0) continue;

        const plus_l = choosePlusBasis(fourier_index, phase_index, geometry, plm_basis);
        fillPhaseRowGeneric(
            &row,
            stream_count,
            coefficient,
            &plus_l.plus,
            minusParitySign(fourier_index, phase_index),
            row_index,
            first_order,
        );
        first_order = false;
    }

    if (first_order) {
        return .{
            .zplus = .{0.0} ** gauss_angles.max_stream_count,
            .zmin = .{0.0} ** gauss_angles.max_stream_count,
            .n = stream_count,
        };
    }
    return row;
}

inline fn choosePlusBasis(
    fourier_index: usize,
    phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PlmArrays {
    // choosePlusBasis --------------------------------------------------------------------------------------- |
    // Return cached or one-off weighted P_l^m rows with the same value shape.                                 |
    // --------------------------------------------------------------------------------------------------------|
    if (phase_index <= plm_basis.max_phase_index) {
        return .{ .plus = plm_basis.plus[phase_index] };
    }
    return computePlm(fourier_index, phase_index, geometry);
}

fn fillZplusZminFromBasisLimited12(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromBasisLimited12 ----------------------------------------------------------------------- |
    // Fixed 12-stream full-matrix builder for one layer and one Fourier term.                                 |
    // --------------------------------------------------------------------------------------------------------|
    return fillZplusZmin12(
        fourier_index,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        false,
        0.0,
        0.0,
    );
}

fn fillZplusZminFromWeightedPhaseLimited12(
    fourier_index: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
) PhaseKernel {
    // fillZplusZminFromWeightedPhaseLimited12 --------------------------------------------------------------- |
    // Fixed 12-stream full-matrix builder for mixed aerosol/Rayleigh phase.                                   |
    // --------------------------------------------------------------------------------------------------------|
    return fillZplusZmin12(
        fourier_index,
        aerosol_phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        true,
        aerosol_weight,
        rayleigh2_weight,
    );
}

fn fillZplusZmin12(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    use_weighted_phase: bool,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
) PhaseKernel {
    // fillZplusZmin12 --------------------------------------------------------------------------------------- |
    // Fixed stream-count route. Each retained beta_l adds one 12x12 outer product into Z+ and Z-.             |
    // --------------------------------------------------------------------------------------------------------|
    const bounded_max_phase_index = @min(max_phase_index, phase_table.coefficient_count - 1);
    if (fourier_index > bounded_max_phase_index) return .{ .zplus = rows.Mat.zero(12), .zmin = rows.Mat.zero(12) };

    var zplus = rows.Mat{ .data = undefined, .n = 12 };
    var zmin = rows.Mat{ .data = undefined, .n = 12 };
    var first_order = true;

    for (fourier_index..bounded_max_phase_index + 1) |phase_index| {
        const coefficient = chooseCoefficient(
            phase_coefficients,
            phase_index,
            use_weighted_phase,
            aerosol_weight,
            rayleigh2_weight,
        );
        if (coefficient == 0.0) continue;

        const plus_l = choosePlusBasis(fourier_index, phase_index, geometry, plm_basis);
        fillPhaseTerm12(
            &zplus,
            &zmin,
            coefficient,
            &plus_l.plus,
            minusParitySign(fourier_index, phase_index),
            first_order,
        );
        first_order = false;
    }

    if (first_order) return .{ .zplus = rows.Mat.zero(12), .zmin = rows.Mat.zero(12) };
    return .{ .zplus = zplus, .zmin = zmin };
}

fn fillZplusZminRowFromBasisLimited12(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    // fillZplusZminRowFromBasisLimited12 -------------------------------------------------------------------- |
    // Fixed 12-stream row builder for one Z+ row and one Z- row.                                              |
    // --------------------------------------------------------------------------------------------------------|
    return fillZplusZminRow12(
        fourier_index,
        phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        row_index,
        false,
        0.0,
        0.0,
    );
}

fn fillZplusZminRowFromWeightedPhaseLimited12(
    fourier_index: usize,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
    aerosol_phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
) PhaseKernelRow {
    // fillZplusZminRowFromWeightedPhaseLimited12 ------------------------------------------------------------ |
    // Fixed 12-stream row builder for mixed aerosol/Rayleigh phase.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return fillZplusZminRow12(
        fourier_index,
        aerosol_phase_coefficients,
        max_phase_index,
        geometry,
        plm_basis,
        row_index,
        true,
        aerosol_weight,
        rayleigh2_weight,
    );
}

fn fillZplusZminRow12(
    fourier_index: usize,
    phase_coefficients: *const [phase_table.coefficient_count]f64,
    max_phase_index: usize,
    geometry: *const gauss_angles.GaussGeometry,
    plm_basis: *const FourierPlmBasis,
    row_index: usize,
    use_weighted_phase: bool,
    aerosol_weight: f64,
    rayleigh2_weight: f64,
) PhaseKernelRow {
    // fillZplusZminRow12 ------------------------------------------------------------------------------------ |
    // Fixed stream-count row route. Each retained beta_l adds one 12-wide contribution.                       |
    // --------------------------------------------------------------------------------------------------------|
    const bounded_max_phase_index = @min(max_phase_index, phase_table.coefficient_count - 1);
    if (row_index >= 12 or fourier_index > bounded_max_phase_index) {
        return .{
            .zplus = .{0.0} ** gauss_angles.max_stream_count,
            .zmin = .{0.0} ** gauss_angles.max_stream_count,
            .n = 12,
        };
    }

    var row = PhaseKernelRow{
        .zplus = undefined,
        .zmin = undefined,
        .n = 12,
    };
    var first_order = true;

    for (fourier_index..bounded_max_phase_index + 1) |phase_index| {
        const coefficient = chooseCoefficient(
            phase_coefficients,
            phase_index,
            use_weighted_phase,
            aerosol_weight,
            rayleigh2_weight,
        );
        if (coefficient == 0.0) continue;

        const minus_sign = minusParitySign(fourier_index, phase_index);
        if (phase_index <= plm_basis.max_phase_index) {
            const plus_l = &plm_basis.plus[phase_index];
            const scaled_plus_row = coefficient * plus_l[row_index];
            const scaled_minus_row = coefficient * minus_sign * plus_l[row_index];

            inline for (0..12) |column| {
                if (first_order) {
                    row.zplus[column] = scaled_plus_row * plus_l[column];
                    row.zmin[column] = scaled_minus_row * plus_l[column];
                } else {
                    row.zplus[column] += scaled_plus_row * plus_l[column];
                    row.zmin[column] += scaled_minus_row * plus_l[column];
                }
            }
        } else {
            const plm = computePlm(fourier_index, phase_index, geometry);
            const scaled_plus_row = coefficient * plm.plus[row_index];
            const scaled_minus_row = coefficient * minus_sign * plm.plus[row_index];

            inline for (0..12) |column| {
                if (first_order) {
                    row.zplus[column] = scaled_plus_row * plm.plus[column];
                    row.zmin[column] = scaled_minus_row * plm.plus[column];
                } else {
                    row.zplus[column] += scaled_plus_row * plm.plus[column];
                    row.zmin[column] += scaled_minus_row * plm.plus[column];
                }
            }
        }
        first_order = false;
    }

    if (first_order) {
        return .{
            .zplus = .{0.0} ** gauss_angles.max_stream_count,
            .zmin = .{0.0} ** gauss_angles.max_stream_count,
            .n = 12,
        };
    }
    return row;
}

inline fn fillPhaseTerm12(
    noalias zplus: *rows.Mat,
    noalias zmin: *rows.Mat,
    coefficient: f64,
    noalias plus_l: *const [gauss_angles.max_stream_count]f64,
    minus_sign: f64,
    first_order: bool,
) void {
    // fillPhaseTerm12 --------------------------------------------------------------------------------------- |
    // Add one beta_l outer product into fixed 12x12 Z+ and Z- matrices.                                       |
    // --------------------------------------------------------------------------------------------------------|
    var scaled_plus_col: [12]f64 = undefined;

    inline for (0..12) |col| {
        scaled_plus_col[col] = coefficient * plus_l[col];
    }

    inline for (0..12) |row| {
        const plus_i = plus_l[row];
        const minus_i = minus_sign * plus_l[row];
        const row_offset = row * 12;

        inline for (0..12) |col| {
            const index = row_offset + col;
            if (first_order) {
                zplus.data[index] = plus_i * scaled_plus_col[col];
                zmin.data[index] = minus_i * scaled_plus_col[col];
            } else {
                zplus.data[index] += plus_i * scaled_plus_col[col];
                zmin.data[index] += minus_i * scaled_plus_col[col];
            }
        }
    }
}

fn fillPhaseTermGeneric(
    zplus: *rows.Mat,
    zmin: *rows.Mat,
    stream_count: usize,
    coefficient: f64,
    plus_l: *const [gauss_angles.max_stream_count]f64,
    minus_sign: f64,
    first_order: bool,
) void {
    // fillPhaseTermGeneric ---------------------------------------------------------------------------------- |
    // Add one beta_l outer product into variable-size Z+ and Z- matrices.                                     |
    // --------------------------------------------------------------------------------------------------------|
    for (0..stream_count) |row| {
        const scaled_plus_i = coefficient * plus_l[row];
        const scaled_minus_i = coefficient * minus_sign * plus_l[row];
        const row_offset = row * stream_count;

        for (0..stream_count) |col| {
            const index = row_offset + col;
            if (first_order) {
                zplus.data[index] = scaled_plus_i * plus_l[col];
                zmin.data[index] = scaled_minus_i * plus_l[col];
            } else {
                zplus.data[index] += scaled_plus_i * plus_l[col];
                zmin.data[index] += scaled_minus_i * plus_l[col];
            }
        }
    }
}

fn fillPhaseRowGeneric(
    row: *PhaseKernelRow,
    stream_count: usize,
    coefficient: f64,
    plus_l: *const [gauss_angles.max_stream_count]f64,
    minus_sign: f64,
    row_index: usize,
    first_order: bool,
) void {
    // fillPhaseRowGeneric ----------------------------------------------------------------------------------- |
    // Add one beta_l row contribution into variable-size Z+ and Z- rows.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const scaled_plus_row = coefficient * plus_l[row_index];
    const scaled_minus_row = coefficient * minus_sign * plus_l[row_index];

    for (0..stream_count) |col| {
        const zplus_value = scaled_plus_row * plus_l[col];
        const zmin_value = scaled_minus_row * plus_l[col];

        if (first_order) {
            row.zplus[col] = zplus_value;
            row.zmin[col] = zmin_value;
        } else {
            row.zplus[col] += zplus_value;
            row.zmin[col] += zmin_value;
        }
    }
}
