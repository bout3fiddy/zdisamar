const std = @import("std");
const calibration = @import("calibration.zig");
const integration = @import("integration.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

pub const Implementation = struct {
    id: []const u8,
    calibrationForScene: *const fn (scene: *const Scene, channel: SpectralChannel) calibration.Calibration,
    usesIntegratedSampling: *const fn (scene: *const Scene, channel: SpectralChannel) bool,
    integrationForWavelength: *const fn (scene: *const Scene, prepared: ?*const PreparedOpticalState, channel: SpectralChannel, nominal_wavelength_nm: f64, kernel: *types.IntegrationKernel) void,
    slitKernelForScene: *const fn (scene: *const Scene, channel: SpectralChannel) [5]f64,
};

pub fn resolve(provider_id: []const u8) ?Implementation {
    if (std.mem.eql(u8, provider_id, "builtin.generic_response")) {
        return genericProvider(provider_id);
    }
    return null;
}

fn genericProvider(provider_id: []const u8) Implementation {
    return .{
        .id = provider_id,
        .calibrationForScene = calibration.calibrationForScene,
        .usesIntegratedSampling = integration.usesIntegratedInstrumentSampling,
        .integrationForWavelength = integration.integrationForWavelength,
        .slitKernelForScene = integration.slitKernelForScene,
    };
}
