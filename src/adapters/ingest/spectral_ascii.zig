//! Purpose:
//!   Parse vendor-style spectral ASCII files into typed measurement products
//!   and requests.
//!
//! Physics:
//!   This adapter hydrates measured radiance and irradiance samples, plus the
//!   ancillary metadata needed to reproduce the operational observation
//!   conditions.
//!
//! Vendor:
//!   Spectral ASCII ingest and fit-window legacy compatibility stages.
//!
//! Design:
//!   Keep the file parser separate from the runtime helpers so the ASCII
//!   format can evolve without forcing the selection logic to change.
//!
//! Invariants:
//!   Radiance and irradiance channel kinds must not be mixed, and the loaded
//!   sample counts must remain consistent with the derived measurement views.
//!
//! Validation:
//!   Spectral ASCII ingest tests cover channel parsing, measurement binding,
//!   and request generation.

const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const SpectralGrid = @import("../../model/Scene.zig").SpectralGrid;
const metadata_helpers = @import("spectral_ascii_metadata.zig");
const runtime_helpers = @import("spectral_ascii_runtime.zig");

pub const ParseError = metadata_helpers.Error;
pub const OperationalMetadata = metadata_helpers.OperationalMetadata;

pub const ChannelKind = enum {
    irradiance,
    radiance,
};

pub const Sample = struct {
    wavelength_nm: f64,
    snr: f64,
    value: f64,
};

pub const Channel = struct {
    kind: ChannelKind,
    samples: []Sample,
};

pub const LoadedSpectra = struct {
    channels: []Channel,
    metadata: OperationalMetadata = .{},
    legacy_fit_window_mode: bool = false,

    /// Purpose:
    ///   Release the loaded channels and metadata.
    pub fn deinit(self: *LoadedSpectra, allocator: std.mem.Allocator) void {
        for (self.channels) |channel| allocator.free(channel.samples);
        allocator.free(self.channels);
        self.metadata.deinitOwned(allocator);
        self.* = .{
            .channels = &[_]Channel{},
            .metadata = .{},
            .legacy_fit_window_mode = false,
        };
    }

    /// Purpose:
    ///   Count channels of a given kind.
    pub fn channelCount(self: LoadedSpectra, kind: ChannelKind) usize {
        return runtime_helpers.channelCount(self, kind);
    }

    /// Purpose:
    ///   Count samples of a given channel kind.
    pub fn sampleCount(self: LoadedSpectra, kind: ChannelKind) u32 {
        return runtime_helpers.sampleCount(self, kind);
    }

    /// Purpose:
    ///   Build a measurement descriptor for the selected spectral product.
    pub fn measurement(self: LoadedSpectra, product: []const u8) Measurement {
        return runtime_helpers.measurement(self, product, ChannelKind.radiance, ChannelKind.irradiance);
    }

    /// Purpose:
    ///   Derive a spectral grid from the loaded channels.
    pub fn spectralGrid(self: LoadedSpectra) ?SpectralGrid {
        return runtime_helpers.spectralGrid(self, ChannelKind.radiance, ChannelKind.irradiance);
    }

    /// Purpose:
    ///   Convert the loaded spectra into a typed retrieval request.
    pub fn toRequest(
        self: LoadedSpectra,
        allocator: std.mem.Allocator,
        scene_id: []const u8,
        requested_products: []const Request.RequestedProduct,
    ) !Request {
        return runtime_helpers.toRequest(
            allocator,
            self,
            scene_id,
            requested_products,
            ChannelKind.radiance,
            ChannelKind.irradiance,
        );
    }

    /// Purpose:
    ///   Collect the wavelengths for a given channel kind.
    pub fn wavelengthsForKind(
        self: LoadedSpectra,
        allocator: std.mem.Allocator,
        kind: ChannelKind,
    ) ![]const f64 {
        return runtime_helpers.wavelengthsForKind(allocator, self, kind);
    }

    /// Purpose:
    ///   Collect an operational solar spectrum for a given channel kind.
    pub fn solarSpectrumForKind(
        self: LoadedSpectra,
        allocator: std.mem.Allocator,
        kind: ChannelKind,
    ) !OperationalSolarSpectrum {
        return runtime_helpers.solarSpectrumForKind(allocator, self, kind);
    }

    /// Purpose:
    ///   Derive per-sample noise sigma values from the loaded channel SNR.
    ///
    /// Units:
    ///   SNR is dimensionless, so the returned sigma is in the same units as
    ///   the measured values.
    pub fn noiseSigmaForKind(
        self: LoadedSpectra,
        allocator: std.mem.Allocator,
        kind: ChannelKind,
    ) ![]const f64 {
        return runtime_helpers.noiseSigmaForKind(allocator, self, kind);
    }
};

/// Purpose:
///   Parse a spectral ASCII file into a loaded channel bundle.
pub fn parse(allocator: std.mem.Allocator, contents: []const u8) !LoadedSpectra {
    const Builder = struct {
        kind: ChannelKind,
        samples: std.ArrayList(Sample) = .empty,
    };

    var builders = std.ArrayList(Builder).empty;
    defer {
        for (builders.items) |*builder| builder.samples.deinit(allocator);
        builders.deinit(allocator);
    }

    var current_builder_index: ?usize = null;
    var current_kind: ?ChannelKind = null;
    var metadata_state = metadata_helpers.ParseState{};
    defer metadata_state.deinit(allocator);
    var legacy_mode = false;
    var used_legacy_mode = false;
    var saw_channel = false;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = trimWhitespace(raw_line);
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

        if (std.mem.startsWith(u8, line, "meta ")) {
            try metadata_state.parseLine(allocator, line);
            continue;
        }

        if (std.mem.eql(u8, line, "start_channel_irr") or std.mem.eql(u8, line, "start_fit_window_irr")) {
            current_builder_index = try beginChannel(allocator, &builders, .irradiance);
            current_kind = .irradiance;
            saw_channel = true;
            continue;
        }
        if (std.mem.eql(u8, line, "start_channel_rad") or std.mem.eql(u8, line, "start_fit_window_rad")) {
            current_builder_index = try beginChannel(allocator, &builders, .radiance);
            current_kind = .radiance;
            saw_channel = true;
            continue;
        }
        if (std.mem.eql(u8, line, "start_fit_window")) {
            // DECISION:
            //   Preserve the legacy fit-window compatibility path even though
            //   the canonical format prefers explicit channel delimiters.
            legacy_mode = true;
            used_legacy_mode = true;
            current_builder_index = null;
            current_kind = null;
            saw_channel = true;
            continue;
        }
        if (std.mem.eql(u8, line, "end_channel_irr") or
            std.mem.eql(u8, line, "end_fit_window_irr") or
            std.mem.eql(u8, line, "end_channel_rad") or
            std.mem.eql(u8, line, "end_fit_window_rad") or
            std.mem.eql(u8, line, "end_fit_window"))
        {
            current_builder_index = null;
            current_kind = null;
            legacy_mode = false;
            continue;
        }

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        const identifier = tokens.next() orelse return ParseError.InvalidLine;
        const sample_kind = parseSampleKind(identifier) orelse return ParseError.InvalidLine;
        const wavelength_text = tokens.next() orelse return ParseError.InvalidLine;
        const snr_text = tokens.next() orelse return ParseError.InvalidLine;
        const value_text = tokens.next() orelse return ParseError.InvalidLine;
        if (tokens.next() != null) return ParseError.InvalidLine;

        if (current_builder_index == null) {
            if (!legacy_mode) return ParseError.UnexpectedDataLine;
            current_builder_index = try beginChannel(allocator, &builders, sample_kind);
            current_kind = sample_kind;
        } else if (current_kind.? != sample_kind) {
            return ParseError.MixedChannelKinds;
        }

        try builders.items[current_builder_index.?].samples.append(allocator, .{
            .wavelength_nm = std.fmt.parseFloat(f64, wavelength_text) catch return ParseError.InvalidNumber,
            .snr = std.fmt.parseFloat(f64, snr_text) catch return ParseError.InvalidNumber,
            .value = std.fmt.parseFloat(f64, value_text) catch return ParseError.InvalidNumber,
        });
    }

    if (legacy_mode or current_builder_index != null) return ParseError.UnclosedSection;
    if (!saw_channel or builders.items.len == 0) return ParseError.MissingChannels;

    const channels = try allocator.alloc(Channel, builders.items.len);
    errdefer allocator.free(channels);

    for (builders.items, 0..) |*builder, index| {
        channels[index] = .{
            .kind = builder.kind,
            .samples = try builder.samples.toOwnedSlice(allocator),
        };
    }
    const metadata = try metadata_state.intoOwned(allocator);

    return .{
        .channels = channels,
        .metadata = metadata,
        .legacy_fit_window_mode = used_legacy_mode,
    };
}

/// Purpose:
///   Parse a spectral ASCII file from disk.
pub fn parseFile(allocator: std.mem.Allocator, path: []const u8) !LoadedSpectra {
    const contents = try std.fs.cwd().readFileAlloc(allocator, path, 1024 * 1024);
    defer allocator.free(contents);
    return parse(allocator, contents);
}

fn beginChannel(allocator: std.mem.Allocator, builders: anytype, kind: ChannelKind) !usize {
    try builders.append(allocator, .{ .kind = kind });
    return builders.items.len - 1;
}

fn parseSampleKind(identifier: []const u8) ?ChannelKind {
    if (std.mem.eql(u8, identifier, "irr")) return .irradiance;
    if (std.mem.eql(u8, identifier, "rad")) return .radiance;
    return null;
}

fn trimWhitespace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

test "spectral ascii loader parses channelized irradiance and radiance input" {
    const fixture =
        \\# vendor-style spectral input
        \\start_channel_irr
        \\irr 405.0 3000.0 3.402296E+14
        \\irr 406.0 2990.0 3.302296E+14
        \\end_channel_irr
        \\start_channel_rad
        \\rad 405.0 1485.0 1.116153E+13
        \\rad 406.0 1445.0 1.096153E+13
        \\end_channel_rad
    ;

    var loaded = try parse(std.testing.allocator, fixture);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), loaded.channelCount(.irradiance));
    try std.testing.expectEqual(@as(usize, 1), loaded.channelCount(.radiance));
    try std.testing.expectEqual(@as(u32, 2), loaded.sampleCount(.radiance));
    try std.testing.expectEqual(@as(f64, 405.0), loaded.channels[0].samples[0].wavelength_nm);

    const measurement = loaded.measurement("radiance");
    try std.testing.expectEqualStrings("radiance", measurement.resolvedProductName());
    try std.testing.expectEqual(@as(u32, 2), measurement.sample_count);

    const grid = loaded.spectralGrid().?;
    try std.testing.expectEqual(@as(u32, 2), grid.sample_count);

    var request = try loaded.toRequest(std.testing.allocator, "spectral-scene", &[_]Request.RequestedProduct{
        .fromName("radiance"),
    });
    defer request.deinitOwned(std.testing.allocator);
    try std.testing.expectEqualStrings("spectral-scene", request.scene.id);
    try std.testing.expectEqualStrings("radiance", request.requested_products[0].name);
    try std.testing.expectEqual(@as(usize, 2), request.scene.observation_model.ingested_noise_sigma.len);
}

test "spectral ascii loader parses operational geometry and auxiliary metadata" {
    const fixture =
        \\meta solar_zenith_deg 31.5
        \\meta viewing_zenith_deg 8.2
        \\meta relative_azimuth_deg 141.0
        \\meta surface_albedo 0.07
        \\meta cloud_optical_thickness 0.24
        \\meta cloud_top_altitude_km 5.5
        \\meta cloud_thickness_km 1.3
        \\meta aerosol_optical_depth 0.11
        \\meta aerosol_single_scatter_albedo 0.94
        \\meta aerosol_asymmetry_factor 0.71
        \\meta wavelength_shift_nm 0.018
        \\meta isrf_fwhm_nm 0.52
        \\meta hr_grid_step_nm 0.08
        \\meta hr_grid_half_span_nm 0.32
        \\meta isrf_offset_nm_1 -0.32
        \\meta isrf_weight_1 0.08
        \\meta isrf_offset_nm_2 -0.16
        \\meta isrf_weight_2 0.24
        \\meta isrf_offset_nm_3 0.00
        \\meta isrf_weight_3 0.36
        \\meta isrf_offset_nm_4 0.16
        \\meta isrf_weight_4 0.22
        \\meta isrf_offset_nm_5 0.32
        \\meta isrf_weight_5 0.10
        \\meta isrf_table_nominal_nm_1 405.0
        \\meta isrf_table_nominal_nm_2 406.0
        \\meta isrf_table_nominal_nm_3 407.0
        \\meta isrf_table_offset_nm_1 -0.32
        \\meta isrf_table_offset_nm_2 -0.16
        \\meta isrf_table_offset_nm_3 0.00
        \\meta isrf_table_offset_nm_4 0.16
        \\meta isrf_table_offset_nm_5 0.32
        \\meta isrf_table_weight_1_1 0.08
        \\meta isrf_table_weight_1_2 0.24
        \\meta isrf_table_weight_1_3 0.36
        \\meta isrf_table_weight_1_4 0.22
        \\meta isrf_table_weight_1_5 0.10
        \\meta isrf_table_weight_2_1 0.18
        \\meta isrf_table_weight_2_2 0.30
        \\meta isrf_table_weight_2_3 0.30
        \\meta isrf_table_weight_2_4 0.15
        \\meta isrf_table_weight_2_5 0.07
        \\meta isrf_table_weight_3_1 0.05
        \\meta isrf_table_weight_3_2 0.18
        \\meta isrf_table_weight_3_3 0.34
        \\meta isrf_table_weight_3_4 0.26
        \\meta isrf_table_weight_3_5 0.17
        \\start_channel_rad
        \\rad 405.0 1485.0 1.116153E+13
        \\rad 406.0 1445.0 1.096153E+13
        \\end_channel_rad
    ;

    var loaded = try parse(std.testing.allocator, fixture);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(?f64, 31.5), loaded.metadata.solar_zenith_deg);
    try std.testing.expectEqual(@as(?f64, 8.2), loaded.metadata.viewing_zenith_deg);
    try std.testing.expectEqual(@as(?f64, 141.0), loaded.metadata.relative_azimuth_deg);
    try std.testing.expectEqual(@as(?f64, 0.07), loaded.metadata.surface_albedo);
    try std.testing.expect(loaded.metadata.hasClouds());
    try std.testing.expect(loaded.metadata.hasAerosols());
    try std.testing.expectEqual(@as(?f64, 0.24), loaded.metadata.cloud_optical_thickness);
    try std.testing.expectEqual(@as(?f64, 0.11), loaded.metadata.aerosol_optical_depth);
    try std.testing.expectEqual(@as(?f64, 0.018), loaded.metadata.wavelength_shift_nm);
    try std.testing.expectEqual(@as(?f64, 0.52), loaded.metadata.isrf_fwhm_nm);
    try std.testing.expectEqual(@as(?f64, 0.08), loaded.metadata.high_resolution_step_nm);
    try std.testing.expectEqual(@as(?f64, 0.32), loaded.metadata.high_resolution_half_span_nm);
    try std.testing.expect(loaded.metadata.hasInstrumentLineShape());
    try std.testing.expectEqual(@as(u8, 5), loaded.metadata.instrument_line_shape.sample_count);
    try std.testing.expectEqual(@as(f64, -0.32), loaded.metadata.instrument_line_shape.offsets_nm[0]);
    try std.testing.expectEqual(@as(f64, 0.36), loaded.metadata.instrument_line_shape.weights[2]);
    try std.testing.expect(loaded.metadata.hasInstrumentLineShapeTable());
    try std.testing.expectEqual(@as(u16, 3), loaded.metadata.instrument_line_shape_table.nominal_count);
    try std.testing.expectEqual(@as(u8, 5), loaded.metadata.instrument_line_shape_table.sample_count);
    try std.testing.expectEqual(@as(f64, 406.0), loaded.metadata.instrument_line_shape_table.nominal_wavelengths_nm[1]);
    try std.testing.expectEqual(@as(f64, 0.30), loaded.metadata.instrument_line_shape_table.weightAt(1, 1));
}

test "spectral ascii loader parses operational O2 and O2-O2 refspec LUT metadata" {
    const fixture =
        \\meta o2_refspec_ntemperature 2
        \\meta o2_refspec_npressure 2
        \\meta o2_refspec_temperature_min 220.0
        \\meta o2_refspec_temperature_max 320.0
        \\meta o2_refspec_pressure_min 150.0
        \\meta o2_refspec_pressure_max 1000.0
        \\meta o2_refspec_wavelength_1 760.8
        \\meta o2_refspec_wavelength_2 761.0
        \\meta o2_refspec_wavelength_3 761.2
        \\meta o2_refspec_coeff_1_1_1 2.0e-24
        \\meta o2_refspec_coeff_2_1_1 0.3e-24
        \\meta o2_refspec_coeff_1_2_1 0.2e-24
        \\meta o2_refspec_coeff_2_2_1 0.05e-24
        \\meta o2_refspec_coeff_1_1_2 2.6e-24
        \\meta o2_refspec_coeff_2_1_2 0.35e-24
        \\meta o2_refspec_coeff_1_2_2 0.25e-24
        \\meta o2_refspec_coeff_2_2_2 0.06e-24
        \\meta o2_refspec_coeff_1_1_3 2.2e-24
        \\meta o2_refspec_coeff_2_1_3 0.32e-24
        \\meta o2_refspec_coeff_1_2_3 0.22e-24
        \\meta o2_refspec_coeff_2_2_3 0.05e-24
        \\meta o2o2_refspec_ntemperature 2
        \\meta o2o2_refspec_npressure 2
        \\meta o2o2_refspec_temperature_min 220.0
        \\meta o2o2_refspec_temperature_max 320.0
        \\meta o2o2_refspec_pressure_min 150.0
        \\meta o2o2_refspec_pressure_max 1000.0
        \\meta o2o2_refspec_wavelength_1 760.8
        \\meta o2o2_refspec_wavelength_2 761.0
        \\meta o2o2_refspec_wavelength_3 761.2
        \\meta o2o2_refspec_coeff_1_1_1 1.2e-46
        \\meta o2o2_refspec_coeff_2_1_1 0.2e-46
        \\meta o2o2_refspec_coeff_1_2_1 0.1e-46
        \\meta o2o2_refspec_coeff_2_2_1 0.03e-46
        \\meta o2o2_refspec_coeff_1_1_2 1.5e-46
        \\meta o2o2_refspec_coeff_2_1_2 0.2e-46
        \\meta o2o2_refspec_coeff_1_2_2 0.1e-46
        \\meta o2o2_refspec_coeff_2_2_2 0.03e-46
        \\meta o2o2_refspec_coeff_1_1_3 1.1e-46
        \\meta o2o2_refspec_coeff_2_1_3 0.18e-46
        \\meta o2o2_refspec_coeff_1_2_3 0.08e-46
        \\meta o2o2_refspec_coeff_2_2_3 0.02e-46
        \\start_channel_rad
        \\rad 760.8 1485.0 1.116153E+13
        \\rad 761.0 1445.0 1.096153E+13
        \\rad 761.2 1405.0 1.076153E+13
        \\end_channel_rad
    ;

    var loaded = try parse(std.testing.allocator, fixture);
    defer loaded.deinit(std.testing.allocator);

    try std.testing.expect(loaded.metadata.hasOperationalLuts());
    try std.testing.expect(loaded.metadata.o2_operational_lut.enabled());
    try std.testing.expect(loaded.metadata.o2o2_operational_lut.enabled());
    try std.testing.expectEqual(@as(usize, 3), loaded.metadata.o2_operational_lut.wavelengths_nm.len);
    try std.testing.expectEqual(@as(u8, 2), loaded.metadata.o2_operational_lut.temperature_coefficient_count);
    try std.testing.expectEqual(@as(u8, 2), loaded.metadata.o2_operational_lut.pressure_coefficient_count);
    try std.testing.expect(loaded.metadata.o2_operational_lut.sigmaAt(761.0, 260.0, 700.0) > 0.0);
    try std.testing.expect(loaded.metadata.o2o2_operational_lut.sigmaAt(761.0, 260.0, 700.0) > 0.0);
    try std.testing.expect(
        loaded.metadata.o2_operational_lut.sigmaAt(761.0, 280.0, 700.0) >
            loaded.metadata.o2_operational_lut.sigmaAt(761.0, 240.0, 700.0),
    );
}
