const std = @import("std");
const zdisamar = @import("zdisamar");

const optimal_estimation = zdisamar.optimal_estimation;

test "native optimal-estimation layouts avoid optional payload overhead" {
    try std.testing.expectEqual(@as(usize, 104), @sizeOf(optimal_estimation.StateSpec));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(optimal_estimation.PressureAltitudeProfile));
    try std.testing.expectEqual(@as(usize, 232), @sizeOf(optimal_estimation.Result));
}

test "pressure profile validates two-point samples before linear spline shortcut" {
    try std.testing.expectError(
        error.InvalidPressureProfile,
        optimal_estimation.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, 950.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        optimal_estimation.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 0.0 },
            &.{ 900.0, 800.0 },
        ),
    );
    try std.testing.expectError(
        error.InvalidPressureProfile,
        optimal_estimation.buildPressureProfile(
            std.testing.allocator,
            &.{ 0.0, 1.0 },
            &.{ 900.0, -1.0 },
        ),
    );

    const altitude_km = [_]f64{ 0.0, 1.0 };
    const pressure_hpa = [_]f64{ 900.0, 800.0 };
    const profile = try optimal_estimation.buildPressureProfile(
        std.testing.allocator,
        &altitude_km,
        &pressure_hpa,
    );
    defer optimal_estimation.freePressureProfile(std.testing.allocator, profile);

    try std.testing.expectEqual(@as(usize, 2), profile.second.len);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[0]);
    try std.testing.expectEqual(@as(f64, 0.0), profile.second[1]);
}
