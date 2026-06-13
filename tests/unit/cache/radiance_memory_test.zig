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
    try std.testing.expect(!memory.resultsValid(stamp));
}

test "RadianceMemory owns dense radiance result rows" {
    var memory = radiance_memory.RadianceMemory{};
    defer memory.deinit(std.testing.allocator);

    memory.active.wavelength_count = 2;
    try memory.ensureResultCapacity(std.testing.allocator, 2);
    const rows = memory.resultRows();
    rows[0] = .{ .radiance = 1.0, .jacobian = .{ 1.0, 2.0 } };
    rows[1] = .{ .radiance = 2.0, .jacobian = .{ 4.0, 5.0 } };
    const stamp = hashing.ReuseStamp{ .value = 0x5678 };
    memory.markResultsValid(stamp);

    try std.testing.expectEqual(@as(usize, 2), rows.len);
    try std.testing.expectApproxEqAbs(2.0, memory.resultRows()[1].radiance, 0.0);
    try std.testing.expectApproxEqAbs(5.0, memory.resultRows()[1].jacobian[1], 0.0);
    try std.testing.expect(memory.resultsValid(stamp));

    try memory.ensureResultCapacity(std.testing.allocator, 3);
    try std.testing.expect(!memory.resultsValid(stamp));
}

test "RadianceMemory layout matches retained owner contract" {
    try std.testing.expectEqual(@as(usize, 112), @sizeOf(radiance_memory.RadianceMemory));
    try std.testing.expectEqual(@as(usize, 32), @sizeOf(radiance_memory.RadianceMemoryActive));
    try std.testing.expectEqual(@as(usize, 24), @sizeOf(radiance_results.RadianceResult));
}
