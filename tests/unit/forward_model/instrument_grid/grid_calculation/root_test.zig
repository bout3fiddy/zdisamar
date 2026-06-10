const std = @import("std");
const internal = @import("internal");

test {
    const measurement = internal.forward_model.instrument_grid;

    _ = measurement.types;
    _ = measurement.storage;
    _ = measurement.cache;
    _ = measurement.forward_input;
    _ = measurement.spectral_eval;
    _ = measurement.simulate;
    _ = measurement.simulateProduct;
    _ = measurement.simulateProductWithWorkspace;
    _ = measurement.warmProductWorkspace;
}

test "instrument-grid wavelength-plan row layouts match documented comments" {
    const Plan = internal.forward_model.instrument_grid.wavelength_plan;

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Plan.IntegrationKernelStorage));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Plan.IntegrationKernelStorage));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Plan.IntegrationKernelStorage, "offsets_nm"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Plan.IntegrationKernelStorage, "weights"));

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(Plan.IntegrationKernelSamples));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Plan.IntegrationKernelSamples));

    try std.testing.expectEqual(@as(usize, 88), @sizeOf(Plan.IntegrationKernelRef));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Plan.IntegrationKernelRef));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Plan.IntegrationKernelRef, "inline_offsets_nm"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(Plan.IntegrationKernelRef, "inline_weights"));
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(Plan.IntegrationKernelRef, "side_start"));
    try std.testing.expectEqual(@as(usize, 84), @offsetOf(Plan.IntegrationKernelRef, "sample_count"));
    try std.testing.expectEqual(@as(usize, 86), @offsetOf(Plan.IntegrationKernelRef, "encoding"));

    try std.testing.expectEqual(@as(usize, 200), @sizeOf(Plan.WavelengthSampling));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Plan.WavelengthSampling));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Plan.WavelengthSampling, "nominal_wavelength_nm"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Plan.WavelengthSampling, "radiance_wavelength_nm"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(Plan.WavelengthSampling, "irradiance_wavelength_nm"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(Plan.WavelengthSampling, "radiance_integration"));
    try std.testing.expectEqual(@as(usize, 112), @offsetOf(Plan.WavelengthSampling, "irradiance_integration"));

    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Plan.WavelengthSamplingTable));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Plan.OwnedWavelengthSampling));
    try std.testing.expectEqual(@as(usize, 4), @sizeOf(Plan.ForwardSampleIndexRef));
    try std.testing.expectEqual(@as(usize, 4), @alignOf(Plan.ForwardSampleIndexRef));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Plan.ForwardMissPlan));
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(Plan.OwnedForwardMissPlan));
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Plan.ForwardCacheMiss));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Plan.ForwardCacheMiss));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Plan.ForwardCacheMiss, "key"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Plan.ForwardCacheMiss, "wavelength_nm"));
}
