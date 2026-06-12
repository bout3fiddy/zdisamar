const std = @import("std");

const internal = @import("internal");

const spectrum_memory = internal.cache.spectrum_memory;
const sampling_table = internal.spectrum.sampling_table;

test "SpectrumMemory owns sampling rows and side-array prefixes" {
    var memory = spectrum_memory.SpectrumMemory{};
    defer memory.deinit(std.testing.allocator);

    try memory.ensureCapacity(std.testing.allocator, 2, 3);
    memory.rows[0] = .{
        .nominal_wavelength_nm = 760.0,
        .radiance_wavelength_nm = 760.0,
        .irradiance_wavelength_nm = 760.0,
        .radiance_integration = .disabled(),
        .irradiance_integration = .disabled(),
    };
    memory.rows[1] = .{
        .nominal_wavelength_nm = 760.1,
        .radiance_wavelength_nm = 760.1,
        .irradiance_wavelength_nm = 760.1,
        .radiance_integration = .{
            .side_start = 0,
            .sample_count = 3,
            .encoding = .side_samples,
        },
        .irradiance_integration = .disabled(),
    };
    memory.kernel_offsets_nm[0..3].* = .{ -0.01, 0.0, 0.01 };
    memory.kernel_weights[0..3].* = .{ 0.25, 0.5, 0.25 };

    const table = try memory.table(2, 3);
    try std.testing.expectEqual(@as(usize, 2), table.rows.len);
    try std.testing.expectEqual(@as(usize, 3), table.kernel_storage.offsets_nm.len);
    try std.testing.expectApproxEqAbs(0.5, table.rows[1].radiance_integration.weight(table.kernel_storage, 1), 0.0);
}

test "SpectrumMemory rejects active prefixes beyond retained capacity" {
    var memory = spectrum_memory.SpectrumMemory{};
    defer memory.deinit(std.testing.allocator);

    try memory.ensureCapacity(std.testing.allocator, 1, 1);
    try std.testing.expectError(error.ShapeMismatch, memory.table(2, 1));
    try std.testing.expectError(error.ShapeMismatch, memory.table(1, 2));
}

test "SpectrumMemory layout matches retained owner contract" {
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(spectrum_memory.SpectrumMemory));
    try std.testing.expectEqual(@as(usize, 200), @sizeOf(sampling_table.SpectrumSamplingRow));
}
