const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Scene.zig").SpectralGrid;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;
pub const ParseError = @import("spectral_ascii_metadata.zig").Error;

pub const wavelength_alignment_threshold_nm: f64 = 1.0e-3;
pub const wavelength_alignment_error_threshold_nm: f64 = 0.06;

pub fn channelCount(loaded: anytype, kind: anytype) usize {
    var count: usize = 0;
    for (loaded.channels) |channel| {
        if (channel.kind == kind) count += 1;
    }
    return count;
}

pub fn sampleCount(loaded: anytype, kind: anytype) u32 {
    var count: u32 = 0;
    for (loaded.channels) |channel| {
        if (channel.kind == kind) count += @intCast(channel.samples.len);
    }
    return count;
}

pub fn measurement(loaded: anytype, product: []const u8, radiance_kind: anytype, irradiance_kind: anytype) Measurement {
    const radiance_count = sampleCount(loaded, radiance_kind);
    const total_samples = if (radiance_count > 0) radiance_count else sampleCount(loaded, irradiance_kind);
    return .{
        .product = product,
        .sample_count = total_samples,
    };
}

pub fn spectralGrid(loaded: anytype, radiance_kind: anytype, irradiance_kind: anytype) ?SpectralGrid {
    const preferred_kind = if (channelCount(loaded, radiance_kind) > 0) radiance_kind else irradiance_kind;

    var start_nm: ?f64 = null;
    var end_nm: ?f64 = null;
    var total_samples: u32 = 0;

    for (loaded.channels) |channel| {
        if (channel.kind != preferred_kind or channel.samples.len == 0) continue;

        const first = channel.samples[0].wavelength_nm;
        const last = channel.samples[channel.samples.len - 1].wavelength_nm;

        start_nm = if (start_nm) |value| @min(value, first) else first;
        end_nm = if (end_nm) |value| @max(value, last) else last;
        total_samples += @intCast(channel.samples.len);
    }

    if (start_nm == null or end_nm == null or total_samples == 0) return null;
    return .{
        .start_nm = start_nm.?,
        .end_nm = end_nm.?,
        .sample_count = total_samples,
    };
}

pub fn wavelengthsForKind(
    allocator: std.mem.Allocator,
    loaded: anytype,
    kind: anytype,
) ![]const f64 {
    const total_samples = sampleCount(loaded, kind);
    if (total_samples == 0) return &[_]f64{};

    const wavelengths = try allocator.alloc(f64, total_samples);
    errdefer allocator.free(wavelengths);

    var cursor: usize = 0;
    for (loaded.channels) |channel| {
        if (channel.kind != kind) continue;
        for (channel.samples) |sample| {
            wavelengths[cursor] = sample.wavelength_nm;
            cursor += 1;
        }
    }
    return wavelengths;
}

pub fn channelValuesForKind(
    allocator: std.mem.Allocator,
    loaded: anytype,
    kind: anytype,
) ![]f64 {
    const total_samples = sampleCount(loaded, kind);
    if (total_samples == 0) return try allocator.alloc(f64, 0);

    const values = try allocator.alloc(f64, total_samples);
    errdefer allocator.free(values);

    var cursor: usize = 0;
    for (loaded.channels) |channel| {
        if (channel.kind != kind) continue;
        for (channel.samples) |sample| {
            values[cursor] = sample.value;
            cursor += 1;
        }
    }
    return values;
}

pub fn solarSpectrumForKind(
    allocator: std.mem.Allocator,
    loaded: anytype,
    kind: anytype,
) !OperationalSolarSpectrum {
    const wavelengths = try wavelengthsForKind(allocator, loaded, kind);
    errdefer if (wavelengths.len != 0) allocator.free(wavelengths);
    const irradiance = try channelValuesForKind(allocator, loaded, kind);
    errdefer if (irradiance.len != 0) allocator.free(irradiance);

    if (wavelengths.len == 0) {
        allocator.free(irradiance);
        return .{};
    }

    return .{
        .wavelengths_nm = wavelengths,
        .irradiance = irradiance,
    };
}

pub fn noiseSigmaForKind(
    allocator: std.mem.Allocator,
    loaded: anytype,
    kind: anytype,
) ![]const f64 {
    const total_samples = sampleCount(loaded, kind);
    if (total_samples == 0) return &[_]f64{};

    const sigma = try allocator.alloc(f64, total_samples);
    errdefer allocator.free(sigma);

    var cursor: usize = 0;
    for (loaded.channels) |channel| {
        if (channel.kind != kind) continue;
        for (channel.samples) |sample| {
            if (!std.math.isFinite(sample.snr) or sample.snr <= 0.0) return ParseError.InvalidLine;
            sigma[cursor] = @abs(sample.value) / sample.snr;
            cursor += 1;
        }
    }
    return sigma;
}

pub fn correctedIrradianceOnWavelengthGrid(
    allocator: std.mem.Allocator,
    loaded: anytype,
    irradiance_kind: anytype,
    source_solar: *const OperationalSolarSpectrum,
    target_wavelengths_nm: []const f64,
) ![]f64 {
    if (target_wavelengths_nm.len == 0) return try allocator.alloc(f64, 0);
    if (channelCount(loaded, irradiance_kind) == 0) {
        return source_solar.interpolateOnto(allocator, target_wavelengths_nm);
    }

    const irradiance_wavelengths = try wavelengthsForKind(allocator, loaded, irradiance_kind);
    defer if (irradiance_wavelengths.len != 0) allocator.free(irradiance_wavelengths);
    const measured_irradiance = try channelValuesForKind(allocator, loaded, irradiance_kind);
    defer if (measured_irradiance.len != 0) allocator.free(measured_irradiance);

    if (irradiance_wavelengths.len == target_wavelengths_nm.len) {
        var grids_differ = false;
        for (irradiance_wavelengths, target_wavelengths_nm) |irradiance_wavelength_nm, target_wavelength_nm| {
            const difference_nm = @abs(irradiance_wavelength_nm - target_wavelength_nm);
            if (difference_nm > wavelength_alignment_error_threshold_nm) return ParseError.InvalidLine;
            if (difference_nm > wavelength_alignment_threshold_nm) grids_differ = true;
        }
        if (!grids_differ) {
            return allocator.dupe(f64, measured_irradiance);
        }
        return source_solar.correctMeasuredSpectrumOnto(
            allocator,
            irradiance_wavelengths,
            measured_irradiance,
            target_wavelengths_nm,
        );
    }

    return source_solar.interpolateOnto(allocator, target_wavelengths_nm);
}

pub fn meanSpacingNm(wavelengths_nm: []const f64) f64 {
    if (wavelengths_nm.len < 2) return 1.0;

    var spacing_sum: f64 = 0.0;
    for (wavelengths_nm[0 .. wavelengths_nm.len - 1], wavelengths_nm[1..]) |left_nm, right_nm| {
        spacing_sum += right_nm - left_nm;
    }
    return spacing_sum / @as(f64, @floatFromInt(wavelengths_nm.len - 1));
}

pub fn toRequest(
    allocator: std.mem.Allocator,
    loaded: anytype,
    scene_id: []const u8,
    requested_products: []const []const u8,
    radiance_kind: anytype,
    irradiance_kind: anytype,
) !Request {
    var scene: Scene = .{ .id = scene_id };
    if (spectralGrid(loaded, radiance_kind, irradiance_kind)) |resolved_grid| {
        scene.spectral_grid = resolved_grid;
    }

    if (channelCount(loaded, radiance_kind) == 0) return ParseError.MissingChannels;
    scene.observation_model.sampling = .measured_channels;
    scene.observation_model.noise_model = .snr_from_input;
    scene.observation_model.measured_wavelengths_nm = try wavelengthsForKind(allocator, loaded, radiance_kind);
    scene.observation_model.owns_measured_wavelengths = true;
    scene.observation_model.reference_radiance = try channelValuesForKind(allocator, loaded, radiance_kind);
    scene.observation_model.owns_reference_radiance = true;
    scene.observation_model.operational_solar_spectrum = try solarSpectrumForKind(allocator, loaded, irradiance_kind);
    scene.observation_model.ingested_noise_sigma = try noiseSigmaForKind(allocator, loaded, radiance_kind);

    var request = Request.init(scene);
    request.requested_products = requested_products;
    return request;
}
