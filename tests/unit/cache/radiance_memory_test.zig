const std = @import("std");

const internal = @import("internal");

const hashing = internal.common.hashing;
const radiance_memory = internal.cache.radiance_memory;
const radiance_results = internal.spectrum.radiance_results;
const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const sampling_table = internal.spectrum.sampling_table;

test "RadianceMemory takes exact wavelength list ownership and exposes active views" {
    const rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = .disabled(),
            .irradiance_integration = .disabled(),
        },
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = .disabled(),
            .irradiance_integration = .disabled(),
        },
    };
    var list = try radiance_wavelengths.buildRadianceWavelengthList(
        std.testing.allocator,
        .{ .rows = rows[0..] },
    );
    errdefer list.deinit(std.testing.allocator);

    var memory = radiance_memory.RadianceMemory{};
    defer memory.deinit(std.testing.allocator);
    const stamp = hashing.ReuseStamp{ .value = 0x1234 };
    memory.takeWavelengthList(std.testing.allocator, &list, stamp);

    try std.testing.expectEqual(@as(usize, 0), list.rows.len);
    try std.testing.expectEqual(@as(usize, 2), memory.wavelength_rows.len);
    try std.testing.expectEqual(@as(usize, 2), memory.sample_indices.len);
    try std.testing.expectEqual(@as(usize, 1), memory.wavelengths.len);

    const view = memory.wavelengthList();
    try std.testing.expectEqual(@as(usize, 2), view.rows.len);
    try std.testing.expectEqual(@as(usize, 2), view.sample_indices.len);
    try std.testing.expectEqual(@as(usize, 1), view.wavelengths.len);
    try std.testing.expectEqual(@as(u32, 0), view.sample_indices[0]);
    try std.testing.expectEqual(@as(u32, 0), view.sample_indices[1]);
    try std.testing.expect(memory.hasWavelengthList(stamp, 2, 2, 1));
    try std.testing.expect(!memory.resultsValid(stamp, false));
}

test "RadianceMemory owns dense radiance-only result rows" {
    var memory = radiance_memory.RadianceMemory{};
    defer memory.deinit(std.testing.allocator);

    memory.active.wavelength_count = 2;
    try memory.ensureResultCapacity(std.testing.allocator, 2, false);
    const rows = memory.resultRows();
    rows.radiance[0] = 1.0;
    rows.radiance[1] = 2.0;
    const stamp = hashing.ReuseStamp{ .value = 0x5678 };
    memory.markResultsValid(stamp);

    try std.testing.expectEqual(@as(usize, 2), rows.radiance.len);
    try std.testing.expectEqual(@as(usize, 0), rows.jacobian.len);
    try std.testing.expectApproxEqAbs(2.0, memory.resultRows().radiance[1], 0.0);
    try std.testing.expect(memory.resultsValid(stamp, false));
    try std.testing.expect(!memory.resultsValid(stamp, true));

    try memory.ensureResultCapacity(std.testing.allocator, 3, false);
    try std.testing.expect(!memory.resultsValid(stamp, false));
}

test "RadianceMemory owns optional dense Jacobian result rows" {
    var memory = radiance_memory.RadianceMemory{};
    defer memory.deinit(std.testing.allocator);

    memory.active.wavelength_count = 2;
    try memory.ensureResultCapacity(std.testing.allocator, 2, true);
    const rows = memory.resultRows();
    try rows.set(0, .{ .radiance = 1.0, .jacobian = .{ 1.0, 2.0 } });
    try rows.set(1, .{ .radiance = 2.0, .jacobian = .{ 4.0, 5.0 } });
    const stamp = hashing.ReuseStamp{ .value = 0x9abc };
    memory.markResultsValid(stamp);

    try std.testing.expectEqual(@as(usize, 2), rows.radiance.len);
    try std.testing.expectEqual(@as(usize, 2), rows.jacobian.len);
    try std.testing.expectApproxEqAbs(2.0, memory.resultRows().radiance[1], 0.0);
    try std.testing.expectApproxEqAbs(5.0, memory.resultRows().jacobian[1][1], 0.0);
    try std.testing.expect(memory.resultsValid(stamp, true));

    try memory.ensureResultCapacity(std.testing.allocator, 2, false);
    try std.testing.expectEqual(@as(usize, 0), memory.resultRows().jacobian.len);
    try std.testing.expect(!memory.resultsValid(stamp, true));
}

test "RadianceMemory dense result allocation cleans up across allocation failures" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        buildTinyDenseRadianceMemory,
        .{},
    );
}

test "RadianceMemory layout matches retained owner contract" {
    try std.testing.expectEqual(@as(usize, 136), @sizeOf(radiance_memory.RadianceMemory));
    try std.testing.expectEqual(@as(usize, 40), @sizeOf(radiance_memory.RadianceMemoryActive));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(radiance_results.RadianceResult));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(radiance_results.DenseRadianceResults));
}

fn buildTinyDenseRadianceMemory(allocator: std.mem.Allocator) !void {
    var memory = radiance_memory.RadianceMemory{};
    defer memory.deinit(allocator);

    memory.active.wavelength_count = 3;
    try memory.ensureResultCapacity(allocator, 3, true);
    const rows = memory.resultRows();
    try rows.set(0, .{ .radiance = 1.0, .jacobian = .{ 1.0, 2.0 } });
    try rows.set(1, .{ .radiance = 2.0, .jacobian = .{ 3.0, 4.0 } });
    try rows.set(2, .{ .radiance = 3.0, .jacobian = .{ 5.0, 6.0 } });

    try std.testing.expectEqual(@as(usize, 3), rows.radiance.len);
    try std.testing.expectApproxEqAbs(6.0, rows.jacobian[2][1], 0.0);
}
