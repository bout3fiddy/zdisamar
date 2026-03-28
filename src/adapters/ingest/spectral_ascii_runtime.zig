//! Purpose:
//!   Shared runtime helpers for spectral ASCII ingest.
//!
//! Physics:
//!   These helpers normalize loaded channel data into measurement vectors,
//!   solar spectra, and auxiliary metadata used by the canonical adapters.
//!
//! Vendor:
//!   Spectral ASCII ingest runtime and wavelength-alignment rules.
//!
//! Design:
//!   Keep the channel extraction and wavelength alignment logic reusable so
//!   file parsing and mission wiring can share the same behavior.
//!
//! Invariants:
//!   Radiance and irradiance channels must remain aligned within the declared
//!   wavelength thresholds before a measured spectrum is reused directly.
//!
//! Validation:
//!   Spectral ASCII ingest tests cover channel counts, wavelength alignment,
//!   and irradiance correction behavior.

const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Scene.zig").SpectralGrid;
const SpectralBand = @import("../../model/Scene.zig").SpectralBand;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const MeasurementQuantity = @import("../../model/Measurement.zig").Quantity;
const OperationalBandSupport = @import("../../model/Instrument.zig").Instrument.OperationalBandSupport;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;
const OperationalMetadata = @import("spectral_ascii_metadata.zig").OperationalMetadata;
pub const ParseError = @import("spectral_ascii_metadata.zig").Error;

pub const wavelength_alignment_threshold_nm: f64 = 1.0e-3;
pub const wavelength_alignment_error_threshold_nm: f64 = 0.06;

pub const OperationalArtifacts = struct {
    measured_input: Request.MeasuredInput,
    band_support: OperationalBandSupport,

    pub fn deinitOwned(self: *OperationalArtifacts, allocator: std.mem.Allocator) void {
        self.measured_input.deinitOwned(allocator);
        self.band_support.deinitOwned(allocator);
        self.* = undefined;
    }
};

// UNITS:
//   Wavelength thresholds are in nanometers and gate whether a measured
//   irradiance grid may be reused directly or must be regridded.

/// Purpose:
///   Count channels of a given kind in a loaded ingest bundle.
pub fn channelCount(loaded: anytype, kind: anytype) usize {
    var count: usize = 0;
    for (loaded.channels) |channel| {
        if (channel.kind == kind) count += 1;
    }
    return count;
}

/// Purpose:
///   Count samples of a given kind in a loaded ingest bundle.
pub fn sampleCount(loaded: anytype, kind: anytype) u32 {
    var count: u32 = 0;
    for (loaded.channels) |channel| {
        if (channel.kind == kind) count += @intCast(channel.samples.len);
    }
    return count;
}

/// Purpose:
///   Build a measurement descriptor from the loaded channels.
pub fn measurement(loaded: anytype, product: []const u8, radiance_kind: anytype, irradiance_kind: anytype) Measurement {
    const radiance_count = sampleCount(loaded, radiance_kind);
    const total_samples = if (radiance_count > 0) radiance_count else sampleCount(loaded, irradiance_kind);
    return .{
        .product_name = product,
        .observable = MeasurementQuantity.parse(product) catch .radiance,
        .sample_count = total_samples,
    };
}

/// Purpose:
///   Derive a spectral grid from the loaded channels.
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

/// Purpose:
///   Collect wavelengths for a given channel kind.
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

/// Purpose:
///   Collect channel values for a given kind.
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

/// Purpose:
///   Build an operational solar spectrum from loaded channels.
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

/// Purpose:
///   Derive sigma values from loaded radiance-channel SNR data.
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

/// Purpose:
///   Correct or interpolate irradiance onto a target wavelength grid.
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

/// Purpose:
///   Return the mean spacing between adjacent wavelength samples.
pub fn meanSpacingNm(wavelengths_nm: []const f64) f64 {
    if (wavelengths_nm.len < 2) return 1.0;

    var spacing_sum: f64 = 0.0;
    for (wavelengths_nm[0 .. wavelengths_nm.len - 1], wavelengths_nm[1..]) |left_nm, right_nm| {
        spacing_sum += right_nm - left_nm;
    }
    return spacing_sum / @as(f64, @floatFromInt(wavelengths_nm.len - 1));
}

/// Purpose:
///   Convert loaded radiance/irradiance channels and metadata into typed measured-input artifacts.
pub fn operationalArtifacts(
    allocator: std.mem.Allocator,
    loaded: anytype,
    source_name: []const u8,
    band_id: []const u8,
    radiance_kind: anytype,
    irradiance_kind: anytype,
) !OperationalArtifacts {
    const measured_input = try buildMeasuredInput(
        allocator,
        loaded,
        source_name,
        radiance_kind,
        irradiance_kind,
    );
    errdefer {
        var cleanup = measured_input;
        cleanup.deinitOwned(allocator);
    }

    const fallback_solar = if (measured_input.irradiance) |irradiance|
        OperationalSolarSpectrum{
            .wavelengths_nm = irradiance.wavelengths_nm,
            .irradiance = irradiance.values,
        }
    else
        OperationalSolarSpectrum{};

    const band_support = try buildOperationalBandSupport(
        allocator,
        loaded.metadata,
        band_id,
        &fallback_solar,
    );
    errdefer {
        var cleanup = band_support;
        cleanup.deinitOwned(allocator);
    }

    return .{
        .measured_input = measured_input,
        .band_support = band_support,
    };
}

/// Purpose:
///   Convert a loaded ingest bundle into a canonical retrieval request.
pub fn toRequest(
    allocator: std.mem.Allocator,
    loaded: anytype,
    scene_id: []const u8,
    requested_products: []const Request.RequestedProduct,
    radiance_kind: anytype,
    irradiance_kind: anytype,
) !Request {
    var scene: Scene = .{ .id = scene_id };
    errdefer scene.deinitOwned(allocator);
    if (spectralGrid(loaded, radiance_kind, irradiance_kind)) |resolved_grid| {
        scene.spectral_grid = resolved_grid;
    }

    if (channelCount(loaded, radiance_kind) == 0) return ParseError.MissingChannels;
    var artifacts = try operationalArtifacts(
        allocator,
        loaded,
        scene_id,
        "operational-band-0",
        radiance_kind,
        irradiance_kind,
    );
    errdefer artifacts.deinitOwned(allocator);

    scene.observation_model.sampling = .measured_channels;
    scene.observation_model.noise_model = .snr_from_input;
    scene.observation_model.measured_wavelengths_nm = try allocator.dupe(
        f64,
        artifacts.measured_input.radiance.wavelengths_nm,
    );
    scene.observation_model.owns_measured_wavelengths = true;
    scene.observation_model.reference_radiance = try allocator.dupe(
        f64,
        artifacts.measured_input.radiance.values,
    );
    scene.observation_model.owns_reference_radiance = true;
    scene.observation_model.ingested_noise_sigma = try allocator.dupe(
        f64,
        artifacts.measured_input.radiance.noise_sigma,
    );
    scene.observation_model.operational_solar_spectrum = try artifacts.band_support.operational_solar_spectrum.clone(allocator);
    scene.observation_model.high_resolution_step_nm = artifacts.band_support.high_resolution_step_nm;
    scene.observation_model.high_resolution_half_span_nm = artifacts.band_support.high_resolution_half_span_nm;
    scene.observation_model.instrument_line_shape = try artifacts.band_support.instrument_line_shape.clone(allocator);
    scene.observation_model.instrument_line_shape_table = try artifacts.band_support.instrument_line_shape_table.clone(allocator);
    scene.observation_model.operational_refspec_grid = try artifacts.band_support.operational_refspec_grid.clone(allocator);
    scene.observation_model.o2_operational_lut = try artifacts.band_support.o2_operational_lut.clone(allocator);
    scene.observation_model.o2o2_operational_lut = try artifacts.band_support.o2o2_operational_lut.clone(allocator);

    const band_step_nm = if (artifacts.measured_input.radiance.wavelengths_nm.len > 1)
        meanSpacingNm(artifacts.measured_input.radiance.wavelengths_nm)
    else
        1.0;
    scene.bands.items = try allocator.dupe(SpectralBand, &[_]SpectralBand{.{
        .id = "operational-band-0",
        .start_nm = scene.spectral_grid.start_nm,
        .end_nm = scene.spectral_grid.end_nm,
        .step_nm = band_step_nm,
    }});
    scene.observation_model.operational_band_support = try allocator.dupe(
        OperationalBandSupport,
        &[_]OperationalBandSupport{artifacts.band_support},
    );
    scene.observation_model.owns_operational_band_support = true;
    artifacts.band_support = .{};

    var request = Request.init(scene);
    request.execution_mode = .operational_measured_input;
    request.measured_input = artifacts.measured_input;
    artifacts.measured_input = .{};
    request.requested_products = requested_products;
    return request;
}

fn buildMeasuredInput(
    allocator: std.mem.Allocator,
    loaded: anytype,
    source_name: []const u8,
    radiance_kind: anytype,
    irradiance_kind: anytype,
) !Request.MeasuredInput {
    var measured_input: Request.MeasuredInput = .{
        .source_name = try allocator.dupe(u8, source_name),
        .owns_source_name = true,
        .radiance = .{
            .observable = .radiance,
            .owns_memory = true,
        },
    };
    errdefer measured_input.deinitOwned(allocator);

    measured_input.radiance.wavelengths_nm = try wavelengthsForKind(allocator, loaded, radiance_kind);
    measured_input.radiance.values = try channelValuesForKind(allocator, loaded, radiance_kind);
    measured_input.radiance.noise_sigma = try noiseSigmaForKind(allocator, loaded, radiance_kind);

    if (channelCount(loaded, irradiance_kind) != 0) {
        measured_input.irradiance = .{
            .observable = .irradiance,
            .owns_memory = true,
        };
        measured_input.irradiance.?.wavelengths_nm = try wavelengthsForKind(allocator, loaded, irradiance_kind);
        measured_input.irradiance.?.values = try channelValuesForKind(allocator, loaded, irradiance_kind);
        measured_input.irradiance.?.noise_sigma = try noiseSigmaForKind(allocator, loaded, irradiance_kind);
    }

    return measured_input;
}

fn buildOperationalBandSupport(
    allocator: std.mem.Allocator,
    metadata: OperationalMetadata,
    band_id: []const u8,
    fallback_solar: *const OperationalSolarSpectrum,
) !OperationalBandSupport {
    if (metadata.cross_section_operational_luts.len != 0) {
        return ParseError.InvalidLine;
    }

    var band_support: OperationalBandSupport = .{
        .id = try allocator.dupe(u8, band_id),
        .owns_id = true,
        .high_resolution_step_nm = metadata.high_resolution_step_nm orelse 0.0,
        .high_resolution_half_span_nm = metadata.high_resolution_half_span_nm orelse 0.0,
    };
    errdefer band_support.deinitOwned(allocator);

    band_support.instrument_line_shape = try metadata.instrument_line_shape.clone(allocator);
    band_support.instrument_line_shape_table = try metadata.instrument_line_shape_table.clone(allocator);
    band_support.operational_refspec_grid = try metadata.operational_refspec_grid.clone(allocator);
    band_support.operational_solar_spectrum = if (metadata.operational_solar_spectrum.enabled())
        try metadata.operational_solar_spectrum.clone(allocator)
    else
        try fallback_solar.clone(allocator);
    band_support.o2_operational_lut = try metadata.o2_operational_lut.clone(allocator);
    band_support.o2o2_operational_lut = try metadata.o2o2_operational_lut.clone(allocator);

    return band_support;
}
