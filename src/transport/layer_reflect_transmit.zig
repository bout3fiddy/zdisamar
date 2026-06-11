const gauss_angles = @import("gauss_angles.zig");
const rows = @import("rows.zig");

// layer_reflect_transmit.zig ---------------------------------------------------------------------------------|
// Single-layer LABOS reflection/transmission matrix fills.                                                    |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/layers.zig` `fillSingleScatterR`,                  |
//   `fillSingleScatterR12`, `fillSingleScatterT`, and `fillSingleScatterT12`.                                 |
//                                                                                                             |
// math                                                                                                        |
//   R[i,j] = omega * Zmin[i,j]  * (1 - E[i] * E[j]) * dmu_plus[i,j]                                           |
//   T[i,j] = omega * Zplus[i,j] * EET[i,j]             * dmu_min[i,j]                                         |
//                                                                                                             |
//   EET[i,j] = tau_start * E[i]     when mu_i ~= mu_j                                                         |
//            = E[i] - E[j]          otherwise                                                                 |
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
