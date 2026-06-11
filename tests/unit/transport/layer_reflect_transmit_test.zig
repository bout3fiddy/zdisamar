const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const gauss_angles = internal.transport.gauss_angles;
const layer_rt = internal.transport.layer_reflect_transmit;
const rows = internal.transport.rows;

test "layer-doubling decision keeps old layout" {
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(layer_rt.LayerDoublingDecision));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(layer_rt.LayerDoublingDecision));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(layer_rt.LayerDoublingDecision, "start_optical_depth"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(layer_rt.LayerDoublingDecision, "doubling_count"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(layer_rt.LayerDoublingDecision, "uses_doubling"));
}

test "layer-doubling decision skips non-multiple and weak layers" {
    const no_scatter = layer_rt.classifyLayerDoubling(.single, 0.1, 2.5, 0.4, 1.0);
    try expectDoublingDecision(no_scatter, 2.5, 0, false);

    const weak = layer_rt.classifyLayerDoubling(.multiple, 0.1, 2.5, 0.01, 0.025);
    try expectDoublingDecision(weak, 2.5, 0, false);

    const equal_threshold = layer_rt.classifyLayerDoubling(.multiple, 0.1, 2.5, 0.04, 0.1);
    try expectDoublingDecision(equal_threshold, 2.5, 0, false);
}

test "layer-doubling decision matches old split selection loops" {
    const normal = layer_rt.classifyLayerDoubling(.multiple, 0.1, 4.0, 0.4, 1.6);
    try expectDoublingDecision(normal, 0.125, 5, true);
    try std.testing.expect(normal.start_optical_depth * 0.4 < 0.1);
    try std.testing.expect(normal.start_optical_depth * 2.0 * 0.4 >= 0.1);

    const smaller_ratio = layer_rt.classifyLayerDoubling(.multiple, 0.1, 4.0, 0.2, 0.8);
    try expectDoublingDecision(smaller_ratio, 0.25, 4, true);
    try std.testing.expect(smaller_ratio.start_optical_depth * 0.2 < 0.1);
    try std.testing.expect(smaller_ratio.start_optical_depth * 2.0 * 0.2 >= 0.1);
}

test "layer-doubling decision caps pathological split count at sixty" {
    const decision = layer_rt.classifyLayerDoubling(.multiple, 0.1, 1.0, 1.0e30, 1.0e30);
    try std.testing.expectEqual(@as(usize, 60), decision.doubling_count);
    try std.testing.expect(decision.uses_doubling);
    try std.testing.expectApproxEqAbs(@as(f64, 0x1p-60), decision.start_optical_depth, 0.0);

    const o2a_thresholds = controls.PerformanceThresholds.o2a_default;
    const o2a_decision = layer_rt.classifyLayerDoubling(.multiple, o2a_thresholds.threshold_doubl, 1.0, 3.0e-6, 3.0e-6);
    try expectDoublingDecision(o2a_decision, 0.25, 2, true);
}

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

test "Gaussian block trace matches scalar reference for generic and fixed paths" {
    var generic = rows.Mat.zero(6);
    fillTraceMatrix(&generic, 6, 0.2);
    try std.testing.expectApproxEqAbs(
        scalarGaussianTrace(6, 4, &generic),
        layer_rt.gaussianBlockTrace(6, 4, &generic),
        1.0e-14,
    );

    var fixed = rows.Mat.zero(rows.max_stream_count);
    fillTraceMatrix(&fixed, rows.max_stream_count, 0.37);
    try std.testing.expectApproxEqAbs(
        scalarGaussianTrace(rows.max_stream_count, rows.max_gauss, &fixed),
        layer_rt.gaussianBlockTrace(rows.max_stream_count, rows.max_gauss, &fixed),
        1.0e-14,
    );
}

test "attenuation square matches old layer-doubling support path" {
    var generic = rows.Vec.zero(6);
    fillAttenuationWithSentinel(&generic, 6, 0.123);
    layer_rt.squareAttenuation(6, &generic);
    try expectSquaredPrefix(generic, 6, 0.123);

    var fixed = rows.Vec.zero(rows.max_stream_count);
    fillAttenuationWithSentinel(&fixed, rows.max_stream_count, -1.0);
    layer_rt.squareAttenuation(rows.max_stream_count, &fixed);
    try expectSquaredPrefix(fixed, rows.max_stream_count, -1.0);
}

test "layer doubling matches scalar q-skipped reference for generic stream count" {
    const n = 6;
    const n_gauss = 4;
    const thresholds = controls.PerformanceThresholds{ .threshold_mul = 1.0e9 };
    var reflection = rows.Mat.zero(n);
    var transmission = rows.Mat.zero(n);
    var attenuation = rows.Vec.zero(n);
    fillDoublingInputs(&reflection, &transmission, &attenuation, n);

    var expected_reflection = reflection;
    var expected_transmission = transmission;
    var expected_attenuation = attenuation;
    scalarDoubleLayerSkippedProducts(2, n, &expected_reflection, &expected_transmission, &expected_attenuation);

    layer_rt.doubleLayer(
        2,
        n,
        n_gauss,
        thresholds,
        &reflection,
        &transmission,
        &attenuation,
        1,
        3,
        5,
        null,
    );

    try expectMatrixClose(expected_reflection, reflection, n, 1.0e-14);
    try expectMatrixClose(expected_transmission, transmission, n, 1.0e-14);
    try expectVecClose(expected_attenuation, attenuation, n, 1.0e-14);
}

test "layer doubling matches scalar q-skipped reference for fixed 12x10 path" {
    const n = rows.max_stream_count;
    const n_gauss = rows.max_gauss;
    const thresholds = controls.PerformanceThresholds{ .threshold_mul = 1.0e9 };
    var reflection = rows.Mat.zero(n);
    var transmission = rows.Mat.zero(n);
    var attenuation = rows.Vec.zero(n);
    fillDoublingInputs(&reflection, &transmission, &attenuation, n);

    var expected_reflection = reflection;
    var expected_transmission = transmission;
    var expected_attenuation = attenuation;
    scalarDoubleLayerSkippedProducts(2, n, &expected_reflection, &expected_transmission, &expected_attenuation);

    layer_rt.doubleLayer(
        2,
        n,
        n_gauss,
        thresholds,
        &reflection,
        &transmission,
        &attenuation,
        2,
        4,
        6,
        null,
    );

    try expectMatrixClose(expected_reflection, reflection, n, 1.0e-14);
    try expectMatrixClose(expected_transmission, transmission, n, 1.0e-14);
    try expectVecClose(expected_attenuation, attenuation, n, 1.0e-14);
}

fn expectDoublingDecision(
    actual: layer_rt.LayerDoublingDecision,
    expected_start_optical_depth: f64,
    expected_doubling_count: usize,
    expected_uses_doubling: bool,
) !void {
    // expectDoublingDecision -------------------------------------------------------------------------------- |
    // Compare the old LABOS layer-doubling decision row.                                                      |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected_start_optical_depth, actual.start_optical_depth, 1.0e-14);
    try std.testing.expectEqual(expected_doubling_count, actual.doubling_count);
    try std.testing.expectEqual(expected_uses_doubling, actual.uses_doubling);
}

fn fillAttenuation(attenuation: *rows.Vec, n: usize) void {
    // fillAttenuation --------------------------------------------------------------------------------------- |
    // Build deterministic direct-beam survival values in (0, 1).                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (0..n) |index| {
        attenuation.set(index, 0.91 - 0.025 * @as(f64, @floatFromInt(index)));
    }
}

fn fillAttenuationWithSentinel(attenuation: *rows.Vec, n: usize, sentinel: f64) void {
    // fillAttenuationWithSentinel ----------------------------------------------------------------------------|
    // Build deterministic direct-beam survival values and mark inactive storage.                              |
    // --------------------------------------------------------------------------------------------------------|
    for (0..rows.max_stream_count) |index| {
        attenuation.set(index, sentinel);
    }

    for (0..n) |index| {
        attenuation.set(index, 0.92 - 0.031 * @as(f64, @floatFromInt(index)));
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

fn fillTraceMatrix(matrix: *rows.Mat, n: usize, base: f64) void {
    // fillTraceMatrix --------------------------------------------------------------------------------------- |
    // Build deterministic row-major matrix values for the old Gaussian diagonal trace helper.                 |
    // --------------------------------------------------------------------------------------------------------|
    matrix.* = rows.Mat.zero(n);
    for (0..n) |row| {
        for (0..n) |col| {
            const row_term = 0.17 * @as(f64, @floatFromInt(row + 1));
            const col_term = 0.023 * @as(f64, @floatFromInt(col + 3));
            matrix.set(row, col, base + row_term - col_term);
        }
    }
}

fn fillDoublingInputs(reflection: *rows.Mat, transmission: *rows.Mat, attenuation: *rows.Vec, n: usize) void {
    // fillDoublingInputs -------------------------------------------------------------------------------------|
    // Build small deterministic LABOS layer rows that keep all trace products below the high skip threshold.  |
    // --------------------------------------------------------------------------------------------------------|
    reflection.* = rows.Mat.zero(n);
    transmission.* = rows.Mat.zero(n);
    attenuation.* = rows.Vec.zero(n);

    for (0..n) |row| {
        attenuation.set(row, 0.72 - 0.011 * @as(f64, @floatFromInt(row)));
        for (0..n) |col| {
            const row_term = 0.0007 * @as(f64, @floatFromInt(row + 1));
            const col_term = 0.00013 * @as(f64, @floatFromInt(col + 3));
            reflection.set(row, col, row_term + col_term);
            transmission.set(row, col, 0.0011 + row_term - 0.00007 * @as(f64, @floatFromInt(col + 1)));
        }
    }
}

fn scalarDoubleLayerSkippedProducts(
    doubling_count: usize,
    n: usize,
    reflection: *rows.Mat,
    transmission: *rows.Mat,
    attenuation: *rows.Vec,
) void {
    // scalarDoubleLayerSkippedProducts -----------------------------------------------------------------------|
    // Independent reference for the old doubling route when Q, R-D, T-U, and T-D products are skipped.        |
    //                                                                                                         |
    // math                                                                                                    |
    //   U = R*diag(E)                                                                                         |
    //   R = R + diag(E)*U                                                                                     |
    //   T = diag(E)*T + T*diag(E)                                                                             |
    //   E = E*E                                                                                               |
    // --------------------------------------------------------------------------------------------------------|
    for (0..doubling_count) |_| {
        var next_reflection = rows.Mat.zero(n);
        var next_transmission = rows.Mat.zero(n);
        for (0..n) |row| {
            const erow = attenuation.get(row);
            for (0..n) |col| {
                const ecol = attenuation.get(col);
                const u = reflection.get(row, col) * ecol;
                next_reflection.set(row, col, reflection.get(row, col) + erow * u);
                next_transmission.set(row, col, erow * transmission.get(row, col) + transmission.get(row, col) * ecol);
            }
        }

        reflection.* = next_reflection;
        transmission.* = next_transmission;
        for (0..n) |index| {
            const e = attenuation.get(index);
            attenuation.set(index, e * e);
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

fn scalarGaussianTrace(n: usize, n_gauss: usize, matrix: *const rows.Mat) f64 {
    // scalarGaussianTrace ----------------------------------------------------------------------------------- |
    // Independent test reference for old LABOS `gaussTrace`.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    var trace: f64 = 0.0;
    for (0..n_gauss) |index| {
        trace += matrix.data[index * n + index];
    }
    return trace;
}

fn expectSquaredPrefix(actual: rows.Vec, n: usize, sentinel: f64) !void {
    // expectSquaredPrefix ----------------------------------------------------------------------------------- |
    // Compare active attenuation entries after old LABOS `squareAttenuation`; inactive generic storage stays  |
    // untouched.                                                                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (0..n) |index| {
        const before = 0.92 - 0.031 * @as(f64, @floatFromInt(index));
        try std.testing.expectApproxEqAbs(before * before, actual.get(index), 1.0e-14);
    }

    for (n..rows.max_stream_count) |index| {
        try std.testing.expectEqual(sentinel, actual.get(index));
    }
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

fn expectVecClose(expected: rows.Vec, actual: rows.Vec, n: usize, tolerance: f64) !void {
    // expectVecClose -----------------------------------------------------------------------------------------|
    // Compare active vector entries used by one LABOS layer row.                                              |
    // --------------------------------------------------------------------------------------------------------|
    for (0..n) |index| {
        try std.testing.expectApproxEqAbs(expected.get(index), actual.get(index), tolerance);
    }
}
