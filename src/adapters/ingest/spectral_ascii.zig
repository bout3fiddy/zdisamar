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
const fit_window_compat = @import("../../compat/ingest/fit_window.zig");

pub const ParseError = metadata_helpers.Error;
pub const OperationalMetadata = metadata_helpers.OperationalMetadata;
pub const OperationalArtifacts = runtime_helpers.OperationalArtifacts;

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

    /// Purpose:
    ///   Build typed measured-input and band-support artifacts from the loaded spectra.
    pub fn operationalArtifacts(
        self: LoadedSpectra,
        allocator: std.mem.Allocator,
        source_name: []const u8,
        band_id: []const u8,
    ) !OperationalArtifacts {
        return runtime_helpers.operationalArtifacts(
            allocator,
            self,
            source_name,
            band_id,
            ChannelKind.radiance,
            ChannelKind.irradiance,
        );
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
        if (fit_window_compat.isLegacyStartMarker(line)) {
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
            fit_window_compat.isLegacyEndMarker(line))
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

    const metadata = try metadata_state.intoOwned(allocator);
    errdefer {
        var owned = metadata;
        owned.deinitOwned(allocator);
    }

    const channels = try allocator.alloc(Channel, builders.items.len);
    errdefer allocator.free(channels);

    var built_channels: usize = 0;
    errdefer {
        for (channels[0..built_channels]) |channel| allocator.free(channel.samples);
    }

    for (builders.items, 0..) |*builder, index| {
        channels[index] = .{
            .kind = builder.kind,
            .samples = try builder.samples.toOwnedSlice(allocator),
        };
        built_channels = index + 1;
    }

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
