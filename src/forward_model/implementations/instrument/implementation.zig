const std = @import("std");
const calibration = @import("../../instrument_grid/spectral_math/calibration.zig");
const integration = @import("integration.zig");
const types = @import("types.zig");
const PreparedOpticalState = @import("../../optical_properties/root.zig").PreparedOpticalState;
const Scene = @import("../../../input/Scene.zig").Scene;
const SpectralChannel = @import("../../../input/Instrument.zig").SpectralChannel;

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: 48 B across 5 fields; largest: id=16 B, calibrationForScene=8 B, usesIntegratedSampling=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: id, calibrationForScene, usesIntegratedSampling, integrationForWavelength, slitKernelForScene carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
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
        .calibrationForScene = calibrationForScene,
        .usesIntegratedSampling = integration.usesIntegratedInstrumentSampling,
        .integrationForWavelength = integration.integrationForWavelength,
        .slitKernelForScene = integration.slitKernelForScene,
    };
}

fn calibrationForScene(scene: *const Scene, channel: SpectralChannel) calibration.Calibration {
    const controls = scene.observation_model.resolvedChannelControls(channel);
    // math: channel correction uses lambda' = lambda + wavelength_shift, y' = gain*(y + stray_light*(mean(y)-y)) + offset.
    return .{
        .gain = controls.multiplicative_offset,
        .offset = controls.additive_offset,
        .wavelength_shift_nm = controls.wavelength_shift_nm,
        .stray_light = controls.stray_light,
    };
}
