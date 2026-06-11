const std = @import("std");

const internal = @import("internal");

const gauss_angles = internal.transport.gauss_angles;
const layer_rt = internal.transport.layer_reflect_transmit;
const rows = internal.transport.rows;

test "single-scatter reflection and transmission match scalar references for generic stream count" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    var attenuation = rows.Vec.zero(geometry.stream_count);
    var zmin = rows.Mat.zero(geometry.stream_count);
    var zplus = rows.Mat.zero(geometry.stream_count);
    fillAttenuation(&attenuation, geometry.stream_count);
    fillPhaseMatrix(&zmin, geometry.stream_count, 0.07, 0.013);
    fillPhaseMatrix(&zplus, geometry.stream_count, 0.11, -0.009);

    const omega: f64 = 0.73;
    const optical_depth_start: f64 = 0.19;
    var reflection = rows.Mat.zero(geometry.stream_count);
    var transmission = rows.Mat.zero(geometry.stream_count);

    layer_rt.fillSingleScatterReflection(&reflection, omega, &attenuation, &zmin, &geometry);
    layer_rt.fillSingleScatterTransmission(&transmission, omega, optical_depth_start, &attenuation, &zplus, &geometry);

    try expectMatrixClose(
        scalarReflection(geometry.stream_count, omega, &attenuation, &zmin, &geometry),
        reflection,
        geometry.stream_count,
        1.0e-14,
    );
    try expectMatrixClose(
        scalarTransmission(geometry.stream_count, omega, optical_depth_start, &attenuation, &zplus, &geometry),
        transmission,
        geometry.stream_count,
        1.0e-14,
    );
}

test "single-scatter reflection and transmission match scalar references for fixed 12-stream path" {
    const geometry = try gauss_angles.GaussGeometry.init(10, 0.58, 0.64);
    try std.testing.expectEqual(@as(usize, rows.max_stream_count), geometry.stream_count);

    var attenuation = rows.Vec.zero(geometry.stream_count);
    var zmin = rows.Mat.zero(geometry.stream_count);
    var zplus = rows.Mat.zero(geometry.stream_count);
    fillAttenuation(&attenuation, geometry.stream_count);
    fillPhaseMatrix(&zmin, geometry.stream_count, 0.05, 0.017);
    fillPhaseMatrix(&zplus, geometry.stream_count, 0.09, -0.011);

    const omega: f64 = 0.81;
    const optical_depth_start: f64 = 0.23;
    var reflection = rows.Mat.zero(geometry.stream_count);
    var transmission = rows.Mat.zero(geometry.stream_count);

    layer_rt.fillSingleScatterReflection(&reflection, omega, &attenuation, &zmin, &geometry);
    layer_rt.fillSingleScatterTransmission(&transmission, omega, optical_depth_start, &attenuation, &zplus, &geometry);

    try expectMatrixClose(
        scalarReflection(geometry.stream_count, omega, &attenuation, &zmin, &geometry),
        reflection,
        geometry.stream_count,
        1.0e-14,
    );
    try expectMatrixClose(
        scalarTransmission(geometry.stream_count, omega, optical_depth_start, &attenuation, &zplus, &geometry),
        transmission,
        geometry.stream_count,
        1.0e-14,
    );
}

fn fillAttenuation(attenuation: *rows.Vec, n: usize) void {
    // fillAttenuation --------------------------------------------------------------------------------------- |
    // Build deterministic direct-beam survival values in (0, 1).                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (0..n) |index| {
        attenuation.set(index, 0.91 - 0.025 * @as(f64, @floatFromInt(index)));
    }
}

fn fillPhaseMatrix(matrix: *rows.Mat, n: usize, row_factor: f64, col_factor: f64) void {
    // fillPhaseMatrix --------------------------------------------------------------------------------------- |
    // Build deterministic phase-kernel values with row/column variation.                                      |
    // --------------------------------------------------------------------------------------------------------|
    matrix.* = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const row_term = row_factor * @as(f64, @floatFromInt(row + 1));
            const col_term = col_factor * @as(f64, @floatFromInt(col + 2));
            matrix.set(row, col, 0.4 + row_term + col_term);
        }
    }
}

fn scalarReflection(
    n: usize,
    single_scatter_albedo: f64,
    attenuation: *const rows.Vec,
    zmin: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) rows.Mat {
    // scalarReflection -------------------------------------------------------------------------------------- |
    // Independent test reference for old LABOS `fillSingleScatterR`.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const index = geometry.pairIndex(row, col);
            const direct_pair = attenuation.get(row) * attenuation.get(col);
            const phase_term = single_scatter_albedo * zmin.get(row, col);

            const value = phase_term * (1.0 - direct_pair) * geometry.dmu_plus[index];
            result.set(row, col, value);
        }
    }
    return result;
}

fn scalarTransmission(
    n: usize,
    single_scatter_albedo: f64,
    optical_depth_start: f64,
    attenuation: *const rows.Vec,
    zplus: *const rows.Mat,
    geometry: *const gauss_angles.GaussGeometry,
) rows.Mat {
    // scalarTransmission ------------------------------------------------------------------------------------ |
    // Independent test reference for old LABOS `fillSingleScatterT`.                                          |
    // --------------------------------------------------------------------------------------------------------|
    var result = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const index = geometry.pairIndex(row, col);
            const integrated_attenuation = if (geometry.dmu_same[index])
                optical_depth_start * attenuation.get(row)
            else
                attenuation.get(row) - attenuation.get(col);
            const phase_term = single_scatter_albedo * zplus.get(row, col);

            const value = phase_term * integrated_attenuation * geometry.dmu_min[index];
            result.set(row, col, value);
        }
    }
    return result;
}

fn expectMatrixClose(expected: rows.Mat, actual: rows.Mat, n: usize, tolerance: f64) !void {
    // expectMatrixClose ------------------------------------------------------------------------------------- |
    // Compare only the active stream block; inactive fixed storage is outside the layer matrix contract.      |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectEqual(n, actual.n);
    for (0..n) |row| {
        for (0..n) |col| {
            try std.testing.expectApproxEqAbs(expected.get(row, col), actual.get(row, col), tolerance);
        }
    }
}
