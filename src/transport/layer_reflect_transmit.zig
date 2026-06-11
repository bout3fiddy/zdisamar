const gauss_angles = @import("gauss_angles.zig");
const rows = @import("rows.zig");

// layer_reflect_transmit.zig ---------------------------------------------------------------------------------|
// Single-layer LABOS reflection/transmission matrix fills and layer-doubling support math.                    |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/layers.zig` `fillSingleScatterR`,                  |
//   `fillSingleScatterR12`, `fillSingleScatterT`, `fillSingleScatterT12`, `gaussTrace`, and                   |
//   `squareAttenuation`.                                                                                      |
//                                                                                                             |
// math                                                                                                        |
//   R[i,j] = omega * Zmin[i,j]  * (1 - E[i] * E[j]) * dmu_plus[i,j]                                           |
//   T[i,j] = omega * Zplus[i,j] * EET[i,j]             * dmu_min[i,j]                                         |
//                                                                                                             |
//   EET[i,j] = tau_start * E[i]     when mu_i ~= mu_j                                                         |
//            = E[i] - E[j]          otherwise                                                                 |
//   trace_gg = sum over Gaussian k of M[k,k]                                                                  |
//   E <- E * E after each layer-doubling step                                                                 |
//                                                                                                             |
// memory                                                                                                      |
//   The functions write caller-owned Mat rows and allocate no storage. Fixed stream_count=12 keeps the old    |
//   constant-bound loop shape used by the O2 A LABOS route.                                                   |
// ------------------------------------------------------------------------------------------------------------|

pub fn fillSingleScatterReflection(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    attenuation: *const rows.Vec,
    zmin: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterReflection ----------------------------------------------------------------------------|
    // Fill one homogeneous layer reflection matrix.                                                           |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and fixed stream_count=12 dispatch follow old `layers.zig` `fillSingleScatterR`.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   R[i,j] = omega * Zmin[i,j] * (1 - E[i] * E[j]) * dmu_plus[i,j]                                        |
    // --------------------------------------------------------------------------------------------------------|

    const n = geometry.stream_count;
    if (n == rows.max_stream_count) {
        return fillSingleScatterReflection12(out, single_scatter_albedo, attenuation, zmin, geometry);
    }

    out.* = rows.Mat.zero(n);

    for (0..n) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        for (0..n) |i| {
            const direct_pair = attenuation.data[i] * ej;
            const phase_term = single_scatter_albedo * zmin.data[idx];
            out.data[idx] = phase_term * (1.0 - direct_pair) * geometry.dmu_plus[idx];
            idx += n;
        }
    }
}

pub fn fillSingleScatterTransmission(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    optical_depth_start: f64,
    attenuation: *const rows.Vec,
    zplus: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterTransmission --------------------------------------------------------------------------|
    // Fill one homogeneous layer transmission matrix.                                                         |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Formula and fixed stream_count=12 dispatch follow old `layers.zig` `fillSingleScatterT`.              |
    //                                                                                                         |
    // math                                                                                                    |
    //   T[i,j] = omega * Zplus[i,j] * EET[i,j] * dmu_min[i,j]                                                 |
    //   EET[i,j] = tau_start * E[i] when geometry.dmu_same[i,j], otherwise E[i] - E[j]                        |
    // --------------------------------------------------------------------------------------------------------|

    const n = geometry.stream_count;
    if (n == rows.max_stream_count) {
        return fillSingleScatterTransmission12(
            out,
            single_scatter_albedo,
            optical_depth_start,
            attenuation,
            zplus,
            geometry,
        );
    }

    out.* = rows.Mat.zero(n);

    for (0..n) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        for (0..n) |i| {
            const integrated_attenuation = if (geometry.dmu_same[idx])
                optical_depth_start * attenuation.data[i]
            else
                attenuation.data[i] - ej;

            const phase_term = single_scatter_albedo * zplus.data[idx];
            out.data[idx] = phase_term * integrated_attenuation * geometry.dmu_min[idx];
            idx += n;
        }
    }
}

pub fn gaussianBlockTrace(n: usize, n_gauss: usize, matrix: *const rows.Mat) f64 {
    // gaussianBlockTrace ------------------------------------------------------------------------------------ |
    // Sum the diagonal of the Gaussian block used by LABOS layer-doubling threshold gates.                    |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `gaussTrace`.                                                                  |
    //                                                                                                         |
    // Fixed n=12, n_gauss=10 uses literal row-major diagonal indexes: k*12 + k = 13*k.                        |
    // Generic stream counts use k*n + k.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    if (n == rows.max_stream_count and n_gauss == rows.max_gauss) {
        var trace = matrix.data[0];
        trace += matrix.data[13];
        trace += matrix.data[26];
        trace += matrix.data[39];
        trace += matrix.data[52];
        trace += matrix.data[65];
        trace += matrix.data[78];
        trace += matrix.data[91];
        trace += matrix.data[104];
        trace += matrix.data[117];
        return trace;
    }

    var trace: f64 = 0.0;
    for (0..n_gauss) |k| trace += matrix.data[k * n + k];

    return trace;
}

pub inline fn squareAttenuation(n: usize, attenuation: *rows.Vec) void {
    // squareAttenuation ------------------------------------------------------------------------------------- |
    // One doubling step turns half-layer attenuation into full-layer attenuation: E <- E * E.                 |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports old `layers.zig` `squareAttenuation`.                                                           |
    // --------------------------------------------------------------------------------------------------------|

    if (n == rows.max_stream_count) return squareAttenuation12(attenuation);

    for (0..n) |direction_index| {
        const e = attenuation.data[direction_index];
        attenuation.data[direction_index] = e * e;
    }
}

fn fillSingleScatterReflection12(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    attenuation: *const rows.Vec,
    zmin: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterReflection12 --------------------------------------------------------------------------|
    // Fixed 12x12 reflection fill.                                                                            |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = rows.Mat{ .data = undefined, .n = rows.max_stream_count };

    inline for (0..rows.max_stream_count) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        inline for (0..rows.max_stream_count) |i| {
            const direct_pair = attenuation.data[i] * ej;
            const phase_term = single_scatter_albedo * zmin.data[idx];
            out.data[idx] = phase_term * (1.0 - direct_pair) * geometry.dmu_plus[idx];
            idx += rows.max_stream_count;
        }
    }
}

inline fn squareAttenuation12(attenuation: *rows.Vec) void {
    // squareAttenuation12 ----------------------------------------------------------------------------------- |
    // Fixed 12-direction attenuation square for the LABOS O2 A rtm_config.                                    |
    // --------------------------------------------------------------------------------------------------------|

    inline for (0..rows.max_stream_count) |direction_index| {
        const e = attenuation.data[direction_index];
        attenuation.data[direction_index] = e * e;
    }
}

fn fillSingleScatterTransmission12(
    out: *rows.Mat,
    single_scatter_albedo: f64,
    optical_depth_start: f64,
    attenuation: *const rows.Vec,
    zplus: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillSingleScatterTransmission12 ------------------------------------------------------------------------|
    // Fixed 12x12 transmission fill.                                                                          |
    //                                                                                                         |
    // The inline loops assign every matrix element; undefined storage avoids clearing before the fill.        |
    // --------------------------------------------------------------------------------------------------------|

    out.* = rows.Mat{ .data = undefined, .n = rows.max_stream_count };

    inline for (0..rows.max_stream_count) |j| {
        const ej = attenuation.data[j];
        var idx = j;

        inline for (0..rows.max_stream_count) |i| {
            const integrated_attenuation = if (geometry.dmu_same[idx])
                optical_depth_start * attenuation.data[i]
            else
                attenuation.data[i] - ej;

            const phase_term = single_scatter_albedo * zplus.data[idx];
            out.data[idx] = phase_term * integrated_attenuation * geometry.dmu_min[idx];
            idx += rows.max_stream_count;
        }
    }
}
