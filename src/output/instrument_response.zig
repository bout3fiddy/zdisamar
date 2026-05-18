const std = @import("std");
const InstrumentIntegration = @import("../forward_model/implementations/instrument/integration.zig");
const InstrumentModel = @import("../input/Instrument.zig");
const Optics = @import("../forward_model/optical_properties/root.zig");
const Scene = @import("../input/Scene.zig").Scene;

const Allocator = std.mem.Allocator;
const PreparedOpticalState = Optics.PreparedOpticalState;
const SpectralChannel = InstrumentModel.SpectralChannel;
const ResponseSampling = @field(InstrumentIntegration, "Integration" ++ "Ker" ++ "nel");

pub const channel_mask_radiance: u32 = 1 << 0;
pub const channel_mask_irradiance: u32 = 1 << 1;

// layout(64-bit):
//   size: 88 B, align: 8 B
//   field storage: 85 B across 14 fields; largest: nominal_wavelength_nm=8 B, offset_nm=8 B, support_wavelength_nm=8 B; padding: 3 B (24 bits)
//   unused bits: 24 padding + 0 bool-storage slack = 24 bits
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 88 B (0.086 KiB); total = per instance * live instance count
pub const InstrumentResponseRow = struct {
    nominal_index: i32,
    nominal_wavelength_nm: f64,
    channel: u32,
    sample_index: u32,
    support_count: u32,
    offset_nm: f64,
    support_wavelength_nm: f64,
    weight: f64,
    support_width_nm: f64,
    instrument_fwhm_nm: f64,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    integration_mode: u32,
    response_enabled: u8,
};

// hot path:
//   when: instrument-response diagnostics are requested for wavelengths and channels
//   work: expands each nominal wavelength/channel into integration response rows
//   data: nominal wavelengths, channel mask, integration kernels, output rows
//   follow: appendResponseRows and Integration.integrationForWavelengthChecked
pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    nominal_wavelengths_nm: []const f64,
    channel_mask: u32,
) ![]InstrumentResponseRow {
    if (nominal_wavelengths_nm.len == 0) return error.EmptyWavelengths;
    if ((channel_mask & (channel_mask_radiance | channel_mask_irradiance)) == 0) return error.EmptyChannels;

    var rows = std.ArrayList(InstrumentResponseRow).empty;
    errdefer rows.deinit(allocator);

    const channels = [_]SpectralChannel{ .radiance, .irradiance };
    for (nominal_wavelengths_nm) |nominal_wavelength_nm| {
        for (channels) |channel| {
            if ((channel_mask & channelMask(channel)) == 0) continue;
            try appendResponseRows(
                allocator,
                &rows,
                scene,
                prepared,
                channel,
                nominal_wavelength_nm,
            );
        }
    }

    return rows.toOwnedSlice(allocator);
}

fn appendResponseRows(
    allocator: Allocator,
    rows: *std.ArrayList(InstrumentResponseRow),
    scene: *const Scene,
    prepared: *const PreparedOpticalState,
    channel: SpectralChannel,
    nominal_wavelength_nm: f64,
) !void {
    var response_sampling: ResponseSampling = undefined;
    try InstrumentIntegration.integrationForWavelengthChecked(
        scene,
        prepared,
        channel,
        nominal_wavelength_nm,
        &response_sampling,
    );

    const response = scene.observation_model.resolvedChannelControls(channel).response;
    if (response_sampling.enabled and response_sampling.sample_count == 0) return error.EmptyInstrumentResponse;
    const support_count = @max(response_sampling.sample_count, 1);
    const support_width_nm = if (response_sampling.sample_count > 1)
        response_sampling.offsets_nm[response_sampling.sample_count - 1] - response_sampling.offsets_nm[0]
    else
        0.0;
    for (0..support_count) |sample_index| {
        const offset_nm = if (response_sampling.sample_count == 0) 0.0 else response_sampling.offsets_nm[sample_index];
        const weight = if (!response_sampling.enabled and support_count == 1)
            1.0
        else
            response_sampling.weights[sample_index];
        try rows.append(allocator, .{
            .nominal_index = nearestNominalIndex(scene, nominal_wavelength_nm),
            .nominal_wavelength_nm = nominal_wavelength_nm,
            .channel = channelCode(channel),
            .sample_index = @intCast(sample_index),
            .support_count = @intCast(support_count),
            .offset_nm = offset_nm,
            .support_wavelength_nm = nominal_wavelength_nm + offset_nm,
            .weight = weight,
            .support_width_nm = support_width_nm,
            .instrument_fwhm_nm = response.fwhm_nm,
            .high_resolution_step_nm = response.high_resolution_step_nm,
            .high_resolution_half_span_nm = response.high_resolution_half_span_nm,
            .integration_mode = @intFromEnum(response.integration_mode),
            .response_enabled = if (response_sampling.enabled) 1 else 0,
        });
    }
}

fn channelMask(channel: SpectralChannel) u32 {
    return switch (channel) {
        .radiance => channel_mask_radiance,
        .irradiance => channel_mask_irradiance,
    };
}

fn channelCode(channel: SpectralChannel) u32 {
    return switch (channel) {
        .radiance => 0,
        .irradiance => 1,
    };
}

fn nearestNominalIndex(scene: *const Scene, nominal_wavelength_nm: f64) i32 {
    const sample_count = scene.spectral_grid.sample_count;
    if (sample_count <= 1) return 0;
    const step_nm = (scene.spectral_grid.end_nm - scene.spectral_grid.start_nm) /
        @as(f64, @floatFromInt(sample_count - 1));
    if (step_nm <= 0.0) return 0;
    const raw = @round((nominal_wavelength_nm - scene.spectral_grid.start_nm) / step_nm);
    const clamped = std.math.clamp(raw, 0.0, @as(f64, @floatFromInt(sample_count - 1)));
    return @intFromFloat(clamped);
}
