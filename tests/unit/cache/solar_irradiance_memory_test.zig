const std = @import("std");
const builtin = @import("builtin");

const internal = @import("internal");

const solar_irradiance_memory = internal.cache.solar_irradiance_memory;

test "SolarIrradianceMemory keys exact f64 bit patterns" {
    try std.testing.expectEqual(
        @as(u64, @bitCast(@as(f64, 0.0))),
        solar_irradiance_memory.keyFor(0.0),
    );
    try std.testing.expectEqual(
        @as(u64, @bitCast(@as(f64, -0.0))),
        solar_irradiance_memory.keyFor(-0.0),
    );
    try std.testing.expect(solar_irradiance_memory.keyFor(0.0) != solar_irradiance_memory.keyFor(-0.0));
}

test "SolarIrradianceMemory reserves and reuses exact wavelength values" {
    var memory = solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.reserve(2);
    memory.putAssumeCapacity(760.0, 1.25);
    memory.putAssumeCapacity(760.01, 2.5);

    try std.testing.expectApproxEqAbs(1.25, memory.get(760.0) orelse return error.MissingIrradiance, 0.0);
    try std.testing.expectApproxEqAbs(2.5, memory.get(760.01) orelse return error.MissingIrradiance, 0.0);
    try std.testing.expectEqual(@as(?f64, null), memory.get(760.02));

    memory.putAssumeCapacity(760.0, 3.0);
    try std.testing.expectApproxEqAbs(3.0, memory.get(760.0) orelse return error.MissingIrradiance, 0.0);
}

test "SolarIrradianceMemory reset clears values without destroying the map" {
    var memory = solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer memory.deinit();

    try memory.reserve(1);
    memory.putAssumeCapacity(760.0, 1.0);
    memory.reset();
    try std.testing.expectEqual(@as(?f64, null), memory.get(760.0));

    memory.putAssumeCapacity(760.0, 2.0);
    try std.testing.expectApproxEqAbs(2.0, memory.get(760.0) orelse return error.MissingIrradiance, 0.0);
}

test "SolarIrradianceMemory layout matches exact irradiance owner contract" {
    const expected_size: usize = if (builtin.mode == .Debug) 40 else 32;
    try std.testing.expectEqual(expected_size, @sizeOf(solar_irradiance_memory.SolarIrradianceMemory));
}
