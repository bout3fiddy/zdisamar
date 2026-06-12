const std = @import("std");

const internal = @import("internal");

const controls = internal.transport.controls;
const gauss_angles = internal.transport.gauss_angles;
const rows = internal.transport.rows;
const scattering_orders = internal.transport.scattering_orders;

test "orders work arrays keep borrowed workspace layout" {
    const expected_size: usize = if (internal.transport.phase_timing.enabled) 120 else 112;
    try std.testing.expectEqual(expected_size, @sizeOf(scattering_orders.OrdersWorkArrays));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(scattering_orders.OrdersWorkArrays));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(scattering_orders.OrdersWorkArrays, "ud"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(scattering_orders.OrdersWorkArrays, "ud_sum_local"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(scattering_orders.OrdersWorkArrays, "ud_orde"));
    try std.testing.expectEqual(@as(usize, 48), @offsetOf(scattering_orders.OrdersWorkArrays, "ud_local"));
    try std.testing.expectEqual(@as(usize, 64), @offsetOf(scattering_orders.OrdersWorkArrays, "ud_tangent_orde"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(scattering_orders.OrdersWorkArrays, "ud_tangent_local"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(scattering_orders.OrdersWorkArrays, "rt_active"));
}

test "single-scattering orders match scalar first-order reference" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const level_count = 3;
    const attenuation = TestAttenuation{ .stream_count = geometry.stream_count };
    const rt = testRtRows(level_count, geometry.stream_count);
    var work = testWork(level_count);
    var reference = scalarFirstOrder(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        geometry.stream_count,
    );

    installActiveMask(&work, scalarActiveMask(&rt, level_count, geometry.stream_count), level_count);
    const result = scattering_orders.solveOrdersWithActive(
        &work,
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        .{ .scattering = .single, .n_streams = 8 },
        5,
    );

    try expectFieldSlicesClose(&reference.ud, result.ud, level_count, geometry.stream_count, 1.0e-14);
    try std.testing.expectEqual(@as(usize, 0), result.ud_sum_local.len);
}

test "multiple-scattering orders add accepted second order and keep local sums" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const level_count = 3;
    const attenuation = TestAttenuation{ .stream_count = geometry.stream_count };
    const rt = testRtRows(level_count, geometry.stream_count);
    var work = testWork(level_count);
    var reference = scalarFirstOrder(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        geometry.stream_count,
    );
    scalarAcceptNextOrder(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        geometry.stream_count,
        &reference,
    );
    const thresholds = controls.PerformanceThresholds{
        .threshold_conv_first = 0.0,
        .threshold_conv_mult = 0.0,
    };

    installActiveMask(&work, scalarActiveMask(&rt, level_count, geometry.stream_count), level_count);
    const result = scattering_orders.solveOrdersWithActiveLocalSum(
        &work,
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        .{
            .scattering = .multiple,
            .n_streams = 8,
            .performance_thresholds = thresholds,
        },
        3,
    );

    try expectFieldSlicesClose(&reference.ud, result.ud, level_count, geometry.stream_count, 1.0e-14);
    try expectLocalSlicesClose(
        &reference.ud_sum_local,
        result.ud_sum_local,
        level_count,
        geometry.stream_count,
        1.0e-14,
    );
}

test "active-mask order route can skip zero RT row without rescanning" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const level_count = 3;
    const attenuation = TestAttenuation{ .stream_count = geometry.stream_count };
    var rt = testRtRows(level_count, geometry.stream_count);
    rt[1] = zeroLayerRt(geometry.stream_count);
    var work = testWork(level_count);
    work.rt_active[0] = true;
    work.rt_active[1] = false;
    work.rt_active[2] = true;
    var reference = scalarFirstOrder(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        geometry.stream_count,
    );

    const result = scattering_orders.solveOrdersWithActive(
        &work,
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        .{ .scattering = .single, .n_streams = 8 },
        5,
    );

    try expectFieldSlicesClose(&reference.ud, result.ud, level_count, geometry.stream_count, 1.0e-14);
}

test "tangent orders match scalar product-rule reference through second order" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const level_count = 3;
    const attenuation = TestAttenuation{ .stream_count = geometry.stream_count };
    const attenuation_tangent = TestAttenuationTangent{ .stream_count = geometry.stream_count };
    const rt = testRtRows(level_count, geometry.stream_count);
    const rt_tangent = testRtTangentRows(level_count, geometry.stream_count);
    var work = testWork(level_count);
    var base_reference = scalarFirstOrder(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        &rt,
        geometry.stream_count,
    );
    var tangent_reference = scalarFirstOrderTangent(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        attenuation_tangent,
        &rt,
        &rt_tangent,
        geometry.stream_count,
    );
    scalarAcceptNextOrderTangent(
        0,
        level_count - 1,
        &geometry,
        attenuation,
        attenuation_tangent,
        &rt,
        &rt_tangent,
        geometry.stream_count,
        &base_reference,
        &tangent_reference,
    );
    const thresholds = controls.PerformanceThresholds{
        .threshold_conv_first = 0.0,
        .threshold_conv_mult = 0.0,
    };

    const result = scattering_orders.solveOrdersTangent(
        &work,
        0,
        level_count - 1,
        &geometry,
        attenuation,
        attenuation_tangent,
        &rt,
        &rt_tangent,
        .{
            .scattering = .multiple,
            .n_streams = 8,
            .performance_thresholds = thresholds,
        },
        3,
    );

    try expectFieldSlicesClose(&tangent_reference.ud, result.ud, level_count, geometry.stream_count, 1.0e-14);
    try std.testing.expectEqual(@as(usize, 0), result.ud_sum_local.len);
}

// TestAttenuation ------------------------------------------------------------------------------------------- |
// Deterministic attenuation object with the same `get(stream, from, to)` interface used by the solver.        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] stream_count : usize                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); stack-only test fixture row                                      |
const TestAttenuation = struct {
    stream_count: usize,

    pub fn get(self: TestAttenuation, stream_index: usize, from_level: usize, to_level: usize) f64 {
        // get ----------------------------------------------------------------------------------------------- |
        // Return deterministic attenuation that changes by stream and path length.                            |
        // ----------------------------------------------------------------------------------------------------|
        _ = self;
        const low = @min(from_level, to_level);
        const high = @max(from_level, to_level);
        const distance = @as(f64, @floatFromInt(high - low));
        const stream_term = 0.012 * @as(f64, @floatFromInt(stream_index + 1));
        return 0.86 - stream_term - 0.041 * distance;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// TestAttenuationTangent ------------------------------------------------------------------------------------ |
// Deterministic derivative attenuation object for product-rule order tests.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 8 B (0.008 KiB), align: 8 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..7] stream_count : usize                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 8 B (0.008 KiB); stack-only test fixture row                                      |
const TestAttenuationTangent = struct {
    stream_count: usize,

    pub fn get(self: TestAttenuationTangent, stream_index: usize, from_level: usize, to_level: usize) f64 {
        // get ----------------------------------------------------------------------------------------------- |
        // Return deterministic derivative attenuation that varies independently from the base attenuation.    |
        // ----------------------------------------------------------------------------------------------------|
        _ = self;
        const low = @min(from_level, to_level);
        const high = @max(from_level, to_level);
        const distance = @as(f64, @floatFromInt(high - low));
        const stream_term = 0.0017 * @as(f64, @floatFromInt(stream_index + 1));
        return -0.018 * distance + stream_term;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// ScalarOrders ---------------------------------------------------------------------------------------------- |
// Independent scalar reference storage for a tiny LABOS order solve.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 4896 B (4.781 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1439] ud           : [3]UDField                                                                      |
// [1440..2591] ud_sum_local : [3]UDLocal                                                                      |
// [2592..3743] ud_orde      : [3]UDLocal                                                                      |
// [3744..4895] ud_local     : [3]UDLocal                                                                      |
//                                                                                                             |
// footprint: stack-only scalar reference for three-level tests                                                |
const ScalarOrders = struct {
    ud: [3]rows.UDField,
    ud_sum_local: [3]rows.UDLocal,
    ud_orde: [3]rows.UDLocal,
    ud_local: [3]rows.UDLocal,
};
// ------------------------------------------------------------------------------------------------------------|

// TestWorkStorage ------------------------------------------------------------------------------------------- |
// Backing arrays borrowed by OrdersWorkArrays in tests.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 7208 B (7.039 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..1439] ud           : [3]UDField                                                                      |
// [1440..2591] ud_sum_local : [3]UDLocal                                                                      |
// [2592..3743] ud_orde      : [3]UDLocal                                                                      |
// [3744..4895] ud_local     : [3]UDLocal                                                                      |
// [4896..6047] ud_tangent_orde  : [3]UDLocal                                                                  |
// [6048..7199] ud_tangent_local : [3]UDLocal                                                                  |
// [7200..7202] rt_active        : [3]bool                                                                     |
// [7203..7207] trailing padding                                                                               |
//                                                                                                             |
// footprint: stack-only workspace fixture for three-level tests                                               |
const TestWorkStorage = struct {
    ud: [3]rows.UDField = undefined,
    ud_sum_local: [3]rows.UDLocal = undefined,
    ud_orde: [3]rows.UDLocal = undefined,
    ud_local: [3]rows.UDLocal = undefined,
    ud_tangent_orde: [3]rows.UDLocal = undefined,
    ud_tangent_local: [3]rows.UDLocal = undefined,
    rt_active: [3]bool = .{ false, false, false },
};
// ------------------------------------------------------------------------------------------------------------|

fn testWork(level_count: usize) scattering_orders.OrdersWorkArrays {
    // testWork ---------------------------------------------------------------------------------------------- |
    // Build borrowed order workspace slices from stack storage.                                               |
    // --------------------------------------------------------------------------------------------------------|
    _ = level_count;
    test_work_storage = .{};
    const storage = &test_work_storage;
    return .{
        .ud = storage.ud[0..],
        .ud_sum_local = storage.ud_sum_local[0..],
        .ud_orde = storage.ud_orde[0..],
        .ud_local = storage.ud_local[0..],
        .ud_tangent_orde = storage.ud_tangent_orde[0..],
        .ud_tangent_local = storage.ud_tangent_local[0..],
        .rt_active = storage.rt_active[0..],
    };
}

var test_work_storage = TestWorkStorage{};

fn testRtRows(level_count: usize, stream_count: usize) [3]rows.LayerRT {
    // testRtRows -------------------------------------------------------------------------------------------- |
    // Build deterministic surface/layer RT rows for order propagation tests.                                  |
    // --------------------------------------------------------------------------------------------------------|
    var rt = [_]rows.LayerRT{zeroLayerRt(stream_count)} ** 3;
    for (0..level_count) |level| {
        for (0..stream_count) |row| {
            for (0..stream_count) |col| {
                const level_term = 0.0009 * @as(f64, @floatFromInt(level + 1));
                const row_term = 0.00017 * @as(f64, @floatFromInt(row + 1));
                const col_term = 0.000031 * @as(f64, @floatFromInt(col + 1));
                rt[level].R.set(row, col, level_term + row_term + col_term);
                rt[level].T.set(row, col, 0.0004 + level_term - row_term + 0.5 * col_term);
            }
        }
    }
    return rt;
}

fn testRtTangentRows(level_count: usize, stream_count: usize) [3]rows.LayerRT {
    // testRtTangentRows ------------------------------------------------------------------------------------- |
    // Build deterministic derivative RT rows for tangent order propagation tests.                             |
    // --------------------------------------------------------------------------------------------------------|
    var rt = [_]rows.LayerRT{zeroLayerRt(stream_count)} ** 3;
    for (0..level_count) |level| {
        for (0..stream_count) |row| {
            for (0..stream_count) |col| {
                const level_term = -0.00021 * @as(f64, @floatFromInt(level + 1));
                const row_term = 0.000043 * @as(f64, @floatFromInt(row + 1));
                const col_term = -0.000011 * @as(f64, @floatFromInt(col + 1));
                rt[level].R.set(row, col, level_term + row_term + col_term);
                rt[level].T.set(row, col, -0.00007 + 0.5 * level_term - row_term + col_term);
            }
        }
    }
    return rt;
}

fn zeroLayerRt(stream_count: usize) rows.LayerRT {
    // zeroLayerRt ------------------------------------------------------------------------------------------- |
    // Build an inactive reflection/transmission layer row.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .R = rows.Mat.zero(stream_count),
        .T = rows.Mat.zero(stream_count),
    };
}

fn scalarFirstOrderTangent(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: TestAttenuation,
    attenuation_tangent: TestAttenuationTangent,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    stream_count: usize,
) ScalarOrders {
    // scalarFirstOrderTangent ------------------------------------------------------------------------------- |
    // Independent scalar reference for old `ordersScatTangent` first-order product rules.                     |
    // --------------------------------------------------------------------------------------------------------|
    var tangent = zeroScalarOrders(stream_count);
    var base = scalarFirstOrder(start_level, end_level, geometry, attenuation, rt, stream_count);
    const active = scalarActiveMask(rt, end_level + 1, stream_count);
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level) |level| {
        for (0..2) |extra_index| {
            if (!active[level + 1]) continue;
            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level + 1);
            const datt = attenuation_tangent.get(col, end_level, level + 1);
            for (0..stream_count) |stream_index| {
                tangent.ud_local[level].D.col[extra_index].data[stream_index] =
                    rt_tangent[level + 1].T.get(stream_index, col) * att +
                    rt[level + 1].T.get(stream_index, col) * datt;
            }
        }
    }

    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            if (!active[level]) continue;
            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level);
            const datt = attenuation_tangent.get(col, end_level, level);
            for (0..stream_count) |stream_index| {
                tangent.ud_local[level].U.col[extra_index].data[stream_index] =
                    rt_tangent[level].R.get(stream_index, col) * att +
                    rt[level].R.get(stream_index, col) * datt;
            }
        }
    }

    scalarTransportTangent(
        start_level,
        end_level,
        stream_count,
        attenuation,
        attenuation_tangent,
        &tangent.ud_local,
        &base.ud_orde,
        &tangent.ud_orde,
    );
    for (start_level..end_level + 1) |level| {
        tangent.ud[level].U = tangent.ud_orde[level].U;
        tangent.ud[level].D = tangent.ud_orde[level].D;
    }
    return tangent;
}

fn scalarFirstOrder(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: TestAttenuation,
    rt: []const rows.LayerRT,
    stream_count: usize,
) ScalarOrders {
    // scalarFirstOrder -------------------------------------------------------------------------------------- |
    // Independent scalar implementation of old LABOS first-order source fill and transport.                   |
    // --------------------------------------------------------------------------------------------------------|
    var result = zeroScalarOrders(stream_count);
    const active = scalarActiveMask(rt, end_level + 1, stream_count);
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level + 1) |level| {
        for (0..stream_count) |stream_index| {
            result.ud[level].E.data[stream_index] = attenuation.get(stream_index, end_level, level);
        }
    }

    for (start_level..end_level) |level| {
        for (0..2) |extra_index| {
            if (!active[level + 1]) continue;
            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level + 1);
            for (0..stream_count) |stream_index| {
                result.ud_local[level].D.col[extra_index].data[stream_index] =
                    rt[level + 1].T.get(stream_index, col) * att;
            }
        }
    }

    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            if (!active[level]) continue;
            const col = gaussian_count + extra_index;
            const att = attenuation.get(col, end_level, level);
            for (0..stream_count) |stream_index| {
                result.ud_local[level].U.col[extra_index].data[stream_index] = rt[level].R.get(stream_index, col) * att;
            }
        }
    }

    for (start_level..end_level + 1) |level| {
        result.ud_sum_local[level].U = result.ud_local[level].U;
        result.ud_sum_local[level].D = result.ud_local[level].D;
    }
    scalarTransport(start_level, end_level, stream_count, attenuation, &result.ud_local, &result.ud_orde);
    for (start_level..end_level + 1) |level| {
        result.ud[level].U = result.ud_orde[level].U;
        result.ud[level].D = result.ud_orde[level].D;
    }

    return result;
}

fn scalarAcceptNextOrderTangent(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: TestAttenuation,
    attenuation_tangent: TestAttenuationTangent,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    stream_count: usize,
    base: *ScalarOrders,
    tangent: *ScalarOrders,
) void {
    // scalarAcceptNextOrderTangent -------------------------------------------------------------------------- |
    // Build and accumulate one later derivative order with direct scalar product-rule terms.                  |
    // --------------------------------------------------------------------------------------------------------|
    const active = scalarActiveMask(rt, end_level + 1, stream_count);
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level) |level| {
        if (!active[level + 1]) continue;

        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var base_value: f64 = 0.0;
                var tangent_value: f64 = 0.0;

                for (0..gaussian_count) |gauss_index| {
                    const base_u = base.ud_orde[level].U.col[extra_index].data[gauss_index];
                    const base_d = base.ud_orde[level + 1].D.col[extra_index].data[gauss_index];
                    const tangent_u = tangent.ud_orde[level].U.col[extra_index].data[gauss_index];
                    const tangent_d = tangent.ud_orde[level + 1].D.col[extra_index].data[gauss_index];

                    base_value += rt[level + 1].R.get(stream_index, gauss_index) * base_u;
                    base_value += rt[level + 1].T.get(stream_index, gauss_index) * base_d;

                    tangent_value += rt_tangent[level + 1].R.get(stream_index, gauss_index) * base_u;
                    tangent_value += rt[level + 1].R.get(stream_index, gauss_index) * tangent_u;
                    tangent_value += rt_tangent[level + 1].T.get(stream_index, gauss_index) * base_d;
                    tangent_value += rt[level + 1].T.get(stream_index, gauss_index) * tangent_d;
                }

                base.ud_local[level].D.col[extra_index].data[stream_index] = base_value;
                tangent.ud_local[level].D.col[extra_index].data[stream_index] = tangent_value;
            }
        }
    }
    base.ud_local[end_level].D = rows.Vec2.zero(stream_count);
    tangent.ud_local[end_level].D = rows.Vec2.zero(stream_count);

    scalarFillUpwardLocalTangent(
        start_level,
        end_level,
        geometry,
        rt,
        rt_tangent,
        stream_count,
        active,
        base,
        tangent,
    );
    scalarTransport(start_level, end_level, stream_count, attenuation, &base.ud_local, &base.ud_orde);
    scalarTransportTangent(
        start_level,
        end_level,
        stream_count,
        attenuation,
        attenuation_tangent,
        &tangent.ud_local,
        &base.ud_orde,
        &tangent.ud_orde,
    );
    scalarAccumulateTangentOrder(start_level, end_level, stream_count, tangent);
}

fn scalarAcceptNextOrder(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    attenuation: TestAttenuation,
    rt: []const rows.LayerRT,
    stream_count: usize,
    result: *ScalarOrders,
) void {
    // scalarAcceptNextOrder --------------------------------------------------------------------------------- |
    // Build and accumulate one later scattering order with direct scalar dot products.                        |
    // --------------------------------------------------------------------------------------------------------|
    const active = scalarActiveMask(rt, end_level + 1, stream_count);
    const gaussian_count = geometry.n_gauss;

    for (start_level..end_level) |level| {
        if (!active[level + 1]) continue;

        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var value: f64 = 0.0;

                for (0..gaussian_count) |gauss_index| {
                    value += rt[level + 1].R.get(stream_index, gauss_index) *
                        result.ud_orde[level].U.col[extra_index].data[gauss_index];
                    value += rt[level + 1].T.get(stream_index, gauss_index) *
                        result.ud_orde[level + 1].D.col[extra_index].data[gauss_index];
                }

                result.ud_local[level].D.col[extra_index].data[stream_index] = value;
            }
        }
    }
    result.ud_local[end_level].D = rows.Vec2.zero(stream_count);

    if (active[start_level]) {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var value: f64 = 0.0;
                for (0..gaussian_count) |gauss_index| {
                    value += rt[start_level].R.get(stream_index, gauss_index) *
                        result.ud_orde[start_level].D.col[extra_index].data[gauss_index];
                }
                result.ud_local[start_level].U.col[extra_index].data[stream_index] = value;
            }
        }
    }

    for (start_level + 1..end_level + 1) |level| {
        if (!active[level]) continue;

        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var value: f64 = 0.0;

                for (0..gaussian_count) |gauss_index| {
                    value += rt[level].R.get(stream_index, gauss_index) *
                        result.ud_orde[level].D.col[extra_index].data[gauss_index];
                    value += rt[level].T.get(stream_index, gauss_index) *
                        result.ud_orde[level - 1].U.col[extra_index].data[gauss_index];
                }

                result.ud_local[level].U.col[extra_index].data[stream_index] = value;
            }
        }
    }

    scalarTransport(start_level, end_level, stream_count, attenuation, &result.ud_local, &result.ud_orde);
    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                result.ud[level].U.col[extra_index].data[stream_index] +=
                    result.ud_orde[level].U.col[extra_index].data[stream_index];
                result.ud[level].D.col[extra_index].data[stream_index] +=
                    result.ud_orde[level].D.col[extra_index].data[stream_index];
                result.ud_sum_local[level].U.col[extra_index].data[stream_index] +=
                    result.ud_local[level].U.col[extra_index].data[stream_index];
                result.ud_sum_local[level].D.col[extra_index].data[stream_index] +=
                    result.ud_local[level].D.col[extra_index].data[stream_index];
            }
        }
    }
}

fn scalarTransport(
    start_level: usize,
    end_level: usize,
    stream_count: usize,
    attenuation: TestAttenuation,
    ud_local: *const [3]rows.UDLocal,
    ud_orde: *[3]rows.UDLocal,
) void {
    // scalarTransport --------------------------------------------------------------------------------------- |
    // Independent scalar inter-level transport recurrence.                                                    |
    // --------------------------------------------------------------------------------------------------------|
    ud_orde[start_level].U = ud_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                const att = attenuation.get(stream_index, level - 1, level);
                ud_orde[level].U.col[extra_index].data[stream_index] =
                    ud_local[level].U.col[extra_index].data[stream_index] +
                    att * ud_orde[level - 1].U.col[extra_index].data[stream_index];
            }
        }
    }

    ud_orde[end_level].D = rows.Vec2.zero(stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                const att = attenuation.get(stream_index, level + 1, level);
                ud_orde[level].D.col[extra_index].data[stream_index] =
                    ud_local[level].D.col[extra_index].data[stream_index] +
                    att * ud_orde[level + 1].D.col[extra_index].data[stream_index];
            }
        }
    }
}

fn scalarFillUpwardLocalTangent(
    start_level: usize,
    end_level: usize,
    geometry: *const gauss_angles.GaussGeometry,
    rt: []const rows.LayerRT,
    rt_tangent: []const rows.LayerRT,
    stream_count: usize,
    active: [3]bool,
    base: *ScalarOrders,
    tangent: *ScalarOrders,
) void {
    // scalarFillUpwardLocalTangent -------------------------------------------------------------------------- |
    // Build upward base and derivative local sources for one later scalar order.                              |
    // --------------------------------------------------------------------------------------------------------|
    const gaussian_count = geometry.n_gauss;

    if (active[start_level]) {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var base_value: f64 = 0.0;
                var tangent_value: f64 = 0.0;
                for (0..gaussian_count) |gauss_index| {
                    const base_d = base.ud_orde[start_level].D.col[extra_index].data[gauss_index];
                    const tangent_d = tangent.ud_orde[start_level].D.col[extra_index].data[gauss_index];
                    base_value += rt[start_level].R.get(stream_index, gauss_index) * base_d;
                    tangent_value += rt_tangent[start_level].R.get(stream_index, gauss_index) * base_d;
                    tangent_value += rt[start_level].R.get(stream_index, gauss_index) * tangent_d;
                }
                base.ud_local[start_level].U.col[extra_index].data[stream_index] = base_value;
                tangent.ud_local[start_level].U.col[extra_index].data[stream_index] = tangent_value;
            }
        }
    }

    for (start_level + 1..end_level + 1) |level| {
        if (!active[level]) continue;

        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                var base_value: f64 = 0.0;
                var tangent_value: f64 = 0.0;

                for (0..gaussian_count) |gauss_index| {
                    const base_d = base.ud_orde[level].D.col[extra_index].data[gauss_index];
                    const base_u = base.ud_orde[level - 1].U.col[extra_index].data[gauss_index];
                    const tangent_d = tangent.ud_orde[level].D.col[extra_index].data[gauss_index];
                    const tangent_u = tangent.ud_orde[level - 1].U.col[extra_index].data[gauss_index];

                    base_value += rt[level].R.get(stream_index, gauss_index) * base_d;
                    base_value += rt[level].T.get(stream_index, gauss_index) * base_u;

                    tangent_value += rt_tangent[level].R.get(stream_index, gauss_index) * base_d;
                    tangent_value += rt[level].R.get(stream_index, gauss_index) * tangent_d;
                    tangent_value += rt_tangent[level].T.get(stream_index, gauss_index) * base_u;
                    tangent_value += rt[level].T.get(stream_index, gauss_index) * tangent_u;
                }

                base.ud_local[level].U.col[extra_index].data[stream_index] = base_value;
                tangent.ud_local[level].U.col[extra_index].data[stream_index] = tangent_value;
            }
        }
    }
}

fn scalarTransportTangent(
    start_level: usize,
    end_level: usize,
    stream_count: usize,
    attenuation: TestAttenuation,
    attenuation_tangent: TestAttenuationTangent,
    tangent_local: *const [3]rows.UDLocal,
    base_orde: *const [3]rows.UDLocal,
    tangent_orde: *[3]rows.UDLocal,
) void {
    // scalarTransportTangent -------------------------------------------------------------------------------- |
    // Independent scalar derivative inter-level transport recurrence.                                         |
    // --------------------------------------------------------------------------------------------------------|
    tangent_orde[start_level].U = tangent_local[start_level].U;
    for (start_level + 1..end_level + 1) |level| {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                const att = attenuation.get(stream_index, level - 1, level);
                const datt = attenuation_tangent.get(stream_index, level - 1, level);
                tangent_orde[level].U.col[extra_index].data[stream_index] =
                    tangent_local[level].U.col[extra_index].data[stream_index] +
                    datt * base_orde[level - 1].U.col[extra_index].data[stream_index] +
                    att * tangent_orde[level - 1].U.col[extra_index].data[stream_index];
            }
        }
    }

    tangent_orde[end_level].D = rows.Vec2.zero(stream_count);
    var level = end_level;
    while (level > start_level) {
        level -= 1;
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                const att = attenuation.get(stream_index, level + 1, level);
                const datt = attenuation_tangent.get(stream_index, level + 1, level);
                tangent_orde[level].D.col[extra_index].data[stream_index] =
                    tangent_local[level].D.col[extra_index].data[stream_index] +
                    datt * base_orde[level + 1].D.col[extra_index].data[stream_index] +
                    att * tangent_orde[level + 1].D.col[extra_index].data[stream_index];
            }
        }
    }
}

fn scalarAccumulateTangentOrder(
    start_level: usize,
    end_level: usize,
    stream_count: usize,
    tangent: *ScalarOrders,
) void {
    // scalarAccumulateTangentOrder -------------------------------------------------------------------------- |
    // Add one accepted derivative order into the accumulated tangent UD field.                                |
    // --------------------------------------------------------------------------------------------------------|
    for (start_level..end_level + 1) |level| {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                tangent.ud[level].U.col[extra_index].data[stream_index] +=
                    tangent.ud_orde[level].U.col[extra_index].data[stream_index];
                tangent.ud[level].D.col[extra_index].data[stream_index] +=
                    tangent.ud_orde[level].D.col[extra_index].data[stream_index];
            }
        }
    }
}

fn zeroScalarOrders(stream_count: usize) ScalarOrders {
    // zeroScalarOrders -------------------------------------------------------------------------------------- |
    // Build zeroed scalar reference rows.                                                                     |
    // --------------------------------------------------------------------------------------------------------|
    var result: ScalarOrders = undefined;
    for (0..3) |level| {
        result.ud[level] = .{
            .E = rows.Vec.zero(stream_count),
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        result.ud_sum_local[level] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        result.ud_orde[level] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
        result.ud_local[level] = .{
            .U = rows.Vec2.zero(stream_count),
            .D = rows.Vec2.zero(stream_count),
        };
    }
    return result;
}

fn scalarActiveMask(
    rt: []const rows.LayerRT,
    level_count: usize,
    stream_count: usize,
) [3]bool {
    // scalarActiveMask -------------------------------------------------------------------------------------- |
    // Independently scan RT rows for nonzero active-layer signal.                                             |
    // --------------------------------------------------------------------------------------------------------|
    var active = [_]bool{false} ** 3;
    for (0..level_count) |level| {
        var found = false;
        for (0..stream_count) |row| {
            for (0..stream_count) |col| {
                found = found or rt[level].R.get(row, col) != 0.0;
                found = found or rt[level].T.get(row, col) != 0.0;
            }
        }
        active[level] = found;
    }
    return active;
}

fn installActiveMask(
    work: *scattering_orders.OrdersWorkArrays,
    active: [3]bool,
    level_count: usize,
) void {
    // installActiveMask ------------------------------------------------------------------------------------- |
    // Copy scalar oracle active-layer decisions into the production order workspace.                          |
    // --------------------------------------------------------------------------------------------------------|
    for (0..level_count) |level| work.rt_active[level] = active[level];
}

fn expectFieldSlicesClose(
    expected: []const rows.UDField,
    actual: []const rows.UDField,
    level_count: usize,
    stream_count: usize,
    tolerance: f64,
) !void {
    // expectFieldSlicesClose -------------------------------------------------------------------------------- |
    // Compare direct and diffuse U/D fields across active levels and streams.                                 |
    // --------------------------------------------------------------------------------------------------------|
    for (0..level_count) |level| {
        for (0..stream_count) |stream_index| {
            try std.testing.expectApproxEqAbs(
                expected[level].E.get(stream_index),
                actual[level].E.get(stream_index),
                tolerance,
            );
            for (0..2) |extra_index| {
                try std.testing.expectApproxEqAbs(
                    expected[level].U.col[extra_index].get(stream_index),
                    actual[level].U.col[extra_index].get(stream_index),
                    tolerance,
                );
                try std.testing.expectApproxEqAbs(
                    expected[level].D.col[extra_index].get(stream_index),
                    actual[level].D.col[extra_index].get(stream_index),
                    tolerance,
                );
            }
        }
    }
}

fn expectLocalSlicesClose(
    expected: []const rows.UDLocal,
    actual: []const rows.UDLocal,
    level_count: usize,
    stream_count: usize,
    tolerance: f64,
) !void {
    // expectLocalSlicesClose -------------------------------------------------------------------------------- |
    // Compare accumulated untransported source sums.                                                          |
    // --------------------------------------------------------------------------------------------------------|
    for (0..level_count) |level| {
        for (0..2) |extra_index| {
            for (0..stream_count) |stream_index| {
                try std.testing.expectApproxEqAbs(
                    expected[level].U.col[extra_index].get(stream_index),
                    actual[level].U.col[extra_index].get(stream_index),
                    tolerance,
                );
                try std.testing.expectApproxEqAbs(
                    expected[level].D.col[extra_index].get(stream_index),
                    actual[level].D.col[extra_index].get(stream_index),
                    tolerance,
                );
            }
        }
    }
}
