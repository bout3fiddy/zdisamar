const std = @import("std");

const gauss_angles = @import("gauss_angles.zig");
const phase_table = @import("../setup/phase_table.zig");

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
//   FourierPlmBasis stores weighted plus-basis rows for one Fourier term and one geometry. The minus basis    |
//   is derived from parity, so no second [151][12] row is retained.                                           |
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
