const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Scene.zig").SpectralGrid;
const Measurement = @import("../../model/Measurement.zig").Measurement;

pub const ParseError = error{
    InvalidLine,
    InvalidNumber,
    UnexpectedDataLine,
    MixedChannelKinds,
    MissingChannels,
    UnclosedSection,
};

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
    legacy_fit_window_mode: bool = false,

    pub fn deinit(self: *LoadedSpectra, allocator: std.mem.Allocator) void {
        for (self.channels) |channel| allocator.free(channel.samples);
        allocator.free(self.channels);
        self.* = .{
            .channels = &[_]Channel{},
            .legacy_fit_window_mode = false,
        };
    }

    pub fn channelCount(self: LoadedSpectra, kind: ChannelKind) usize {
        var count: usize = 0;
        for (self.channels) |channel| {
            if (channel.kind == kind) count += 1;
        }
        return count;
    }

    pub fn sampleCount(self: LoadedSpectra, kind: ChannelKind) u32 {
        var count: u32 = 0;
        for (self.channels) |channel| {
            if (channel.kind == kind) count += @intCast(channel.samples.len);
        }
        return count;
    }

    pub fn measurement(self: LoadedSpectra, product: []const u8) Measurement {
        const radiance_count = self.sampleCount(.radiance);
        const sample_count = if (radiance_count > 0) radiance_count else self.sampleCount(.irradiance);
        return .{
            .product = product,
            .sample_count = sample_count,
        };
    }

    pub fn spectralGrid(self: LoadedSpectra) ?SpectralGrid {
        const preferred_kind = if (self.channelCount(.radiance) > 0) ChannelKind.radiance else ChannelKind.irradiance;

        var start_nm: ?f64 = null;
        var end_nm: ?f64 = null;
        var total_samples: u32 = 0;

        for (self.channels) |channel| {
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

    pub fn toRequest(
        self: LoadedSpectra,
        scene_id: []const u8,
        requested_products: []const []const u8,
    ) Request {
        var scene: Scene = .{ .id = scene_id };
        if (self.spectralGrid()) |grid| scene.spectral_grid = grid;

        var request = Request.init(scene);
        request.requested_products = requested_products;
        return request;
    }
};

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
    var legacy_mode = false;
    var used_legacy_mode = false;
    var saw_channel = false;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = trimWhitespace(raw_line);
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

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

    return .{
        .channels = channels,
        .legacy_fit_window_mode = used_legacy_mode,
    };
}

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
    try std.testing.expectEqualStrings("radiance", measurement.product);
    try std.testing.expectEqual(@as(u32, 2), measurement.sample_count);

    const grid = loaded.spectralGrid().?;
    try std.testing.expectEqual(@as(u32, 2), grid.sample_count);

    const request = loaded.toRequest("spectral-scene", &[_][]const u8{"radiance"});
    try std.testing.expectEqualStrings("spectral-scene", request.scene.id);
    try std.testing.expectEqualStrings("radiance", request.requested_products[0]);
}
