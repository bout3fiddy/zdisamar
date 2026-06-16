const std = @import("std");
const internal = @import("internal");
const CountingAllocator = @import("../support/counting_allocator.zig").CountingAllocator;

const retrieval = internal.retrieval.root;

test "pressure profile validates two-point samples before linear log-pressure shortcut" {
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, 950.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 0.0 },
            &.{ 900.0, 800.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        retrieval.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, -1.0 },
        ),
    );

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const profile = try retrieval.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer retrieval.freePressureProfile(std.testing.allocator, profile);

    try std.testing.expectEqual(@as(usize, 2), profile.second.len);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[0]);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[1]);
}

test "pressure profile derivative matches the canonical expectation two-point log-pressure route" {
    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const profile = try retrieval.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer retrieval.freePressureProfile(std.testing.allocator, profile);

    const pressure = 850.0;
    const step = @max(@abs(pressure) * 1.0e-4, 1.0e-3);
    const log_span = @log(pressure_hpa[1]) - @log(pressure_hpa[0]);
    const expected =
        ((@log(pressure + step) - @log(pressure_hpa[0])) / log_span) -
        ((@log(pressure - step) - @log(pressure_hpa[0])) / log_span);

    try std.testing.expectApproxEqAbs(
        expected / (2.0 * step),
        try profile.altitudeDerivativeAtPressure(pressure),
        2.0e-13,
    );
}

test "pressure profile dynamic spline uses stack scratch for small profiles" {
    const altitude_km = [_]f64{ 0.0, 1.0, 2.0, 3.0, 4.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0, 710.0, 630.0, 560.0 };

    const expected = try retrieval.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer retrieval.freePressureProfile(std.testing.allocator, expected);

    var counter = CountingAllocator.init(std.testing.allocator);
    const counting_allocator = counter.allocator();
    const actual = try retrieval.buildPressureProfile(
        counting_allocator,
        &altitude_km,
        &pressure_hpa,
    );
    errdefer retrieval.freePressureProfile(counting_allocator, actual);

    try std.testing.expectEqual(@as(usize, 1), counter.alloc_calls);
    try std.testing.expectEqual(@as(usize, 1), counter.live_allocations);
    try std.testing.expectEqualSlices(f64, expected.second, actual.second);
    try std.testing.expectApproxEqAbs(
        try expected.altitudeDerivativeAtPressure(700.0),
        try actual.altitudeDerivativeAtPressure(700.0),
        0.0,
    );

    retrieval.freePressureProfile(counting_allocator, actual);
    try std.testing.expectEqual(@as(usize, 0), counter.live_allocations);
}
