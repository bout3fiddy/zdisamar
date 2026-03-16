const std = @import("std");
const Request = @import("../../core/Request.zig").Request;
const Scene = @import("../../model/Scene.zig").Scene;
const SpectralGrid = @import("../../model/Scene.zig").SpectralGrid;
const Measurement = @import("../../model/Measurement.zig").Measurement;
const InstrumentLineShape = @import("../../model/Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("../../model/Instrument.zig").InstrumentLineShapeTable;
const OperationalReferenceGrid = @import("../../model/Instrument.zig").OperationalReferenceGrid;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;
const max_line_shape_nominals = @import("../../model/Instrument.zig").max_line_shape_nominals;

pub const ParseError = error{
    OutOfMemory,
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

const OperationalLutEntry = struct {
    temperature_index: usize,
    pressure_index: usize,
    wavelength_index: usize,
    value: f64,
};

const OperationalLutBuilder = struct {
    wavelengths: std.ArrayList(struct { index: usize, value: f64 }) = .empty,
    coefficients: std.ArrayList(OperationalLutEntry) = .empty,
    temperature_coefficient_count: ?u8 = null,
    pressure_coefficient_count: ?u8 = null,
    min_temperature_k: ?f64 = null,
    max_temperature_k: ?f64 = null,
    min_pressure_hpa: ?f64 = null,
    max_pressure_hpa: ?f64 = null,

    fn deinit(self: *OperationalLutBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.coefficients.deinit(allocator);
        self.* = .{};
    }

    fn setWavelength(self: *OperationalLutBuilder, allocator: std.mem.Allocator, index: usize, value: f64) !void {
        for (self.wavelengths.items) |*entry| {
            if (entry.index == index) {
                entry.value = value;
                return;
            }
        }
        try self.wavelengths.append(allocator, .{
            .index = index,
            .value = value,
        });
    }

    fn setCoefficient(
        self: *OperationalLutBuilder,
        allocator: std.mem.Allocator,
        temperature_index: usize,
        pressure_index: usize,
        wavelength_index: usize,
        value: f64,
    ) !void {
        for (self.coefficients.items) |*entry| {
            if (entry.temperature_index == temperature_index and
                entry.pressure_index == pressure_index and
                entry.wavelength_index == wavelength_index)
            {
                entry.value = value;
                return;
            }
        }
        try self.coefficients.append(allocator, .{
            .temperature_index = temperature_index,
            .pressure_index = pressure_index,
            .wavelength_index = wavelength_index,
            .value = value,
        });
    }

    fn intoOwned(self: *OperationalLutBuilder, allocator: std.mem.Allocator) !OperationalCrossSectionLut {
        if (self.wavelengths.items.len == 0 and self.coefficients.items.len == 0) {
            return .{};
        }

        const temperature_count = self.temperature_coefficient_count orelse return ParseError.InvalidLine;
        const pressure_count = self.pressure_coefficient_count orelse return ParseError.InvalidLine;
        const min_temperature_k = self.min_temperature_k orelse return ParseError.InvalidLine;
        const max_temperature_k = self.max_temperature_k orelse return ParseError.InvalidLine;
        const min_pressure_hpa = self.min_pressure_hpa orelse return ParseError.InvalidLine;
        const max_pressure_hpa = self.max_pressure_hpa orelse return ParseError.InvalidLine;

        var max_wavelength_index: usize = 0;
        for (self.wavelengths.items) |entry| {
            max_wavelength_index = @max(max_wavelength_index, entry.index);
        }
        if (self.wavelengths.items.len == 0) return ParseError.InvalidLine;

        const wavelength_count = max_wavelength_index + 1;
        const wavelengths_nm = try allocator.alloc(f64, wavelength_count);
        errdefer allocator.free(wavelengths_nm);
        @memset(wavelengths_nm, 0.0);
        for (self.wavelengths.items) |entry| wavelengths_nm[entry.index] = entry.value;

        const coefficient_count = wavelength_count * @as(usize, temperature_count) * @as(usize, pressure_count);
        const coefficients = try allocator.alloc(f64, coefficient_count);
        errdefer allocator.free(coefficients);
        @memset(coefficients, 0.0);

        for (self.coefficients.items) |entry| {
            if (entry.temperature_index >= temperature_count or
                entry.pressure_index >= pressure_count or
                entry.wavelength_index >= wavelength_count)
            {
                return ParseError.InvalidLine;
            }
            const offset = entry.wavelength_index * @as(usize, temperature_count) * @as(usize, pressure_count) +
                entry.pressure_index * @as(usize, temperature_count) +
                entry.temperature_index;
            coefficients[offset] = entry.value;
        }

        return .{
            .wavelengths_nm = wavelengths_nm,
            .coefficients = coefficients,
            .temperature_coefficient_count = temperature_count,
            .pressure_coefficient_count = pressure_count,
            .min_temperature_k = min_temperature_k,
            .max_temperature_k = max_temperature_k,
            .min_pressure_hpa = min_pressure_hpa,
            .max_pressure_hpa = max_pressure_hpa,
        };
    }
};

const IndexedVectorBuilder = struct {
    values: std.ArrayList(struct { index: usize, value: f64 }) = .empty,

    fn deinit(self: *IndexedVectorBuilder, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
        self.* = .{};
    }

    fn set(self: *IndexedVectorBuilder, allocator: std.mem.Allocator, index: usize, value: f64) !void {
        for (self.values.items) |*entry| {
            if (entry.index == index) {
                entry.value = value;
                return;
            }
        }
        try self.values.append(allocator, .{
            .index = index,
            .value = value,
        });
    }

    fn intoOwnedSlice(self: *IndexedVectorBuilder, allocator: std.mem.Allocator) ![]const f64 {
        if (self.values.items.len == 0) return &[_]f64{};

        var max_index: usize = 0;
        for (self.values.items) |entry| max_index = @max(max_index, entry.index);

        const value_count = max_index + 1;
        if (self.values.items.len != value_count) return ParseError.InvalidLine;

        const dense = try allocator.alloc(f64, value_count);
        errdefer allocator.free(dense);
        @memset(dense, 0.0);

        const seen = try allocator.alloc(bool, value_count);
        defer allocator.free(seen);
        @memset(seen, false);

        for (self.values.items) |entry| {
            if (seen[entry.index]) return ParseError.InvalidLine;
            dense[entry.index] = entry.value;
            seen[entry.index] = true;
        }

        for (seen) |was_seen| {
            if (!was_seen) return ParseError.InvalidLine;
        }

        return dense;
    }
};

const OperationalReferenceGridBuilder = struct {
    wavelengths: IndexedVectorBuilder = .{},
    weights: IndexedVectorBuilder = .{},

    fn deinit(self: *OperationalReferenceGridBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.weights.deinit(allocator);
        self.* = .{};
    }

    fn intoOwned(self: *OperationalReferenceGridBuilder, allocator: std.mem.Allocator) !OperationalReferenceGrid {
        if (self.wavelengths.values.items.len == 0 and self.weights.values.items.len == 0) return .{};

        const wavelengths_nm = try self.wavelengths.intoOwnedSlice(allocator);
        errdefer if (wavelengths_nm.len > 0) allocator.free(wavelengths_nm);
        const weights = try self.weights.intoOwnedSlice(allocator);
        errdefer if (weights.len > 0) allocator.free(weights);

        return .{
            .wavelengths_nm = wavelengths_nm,
            .weights = weights,
        };
    }
};

const OperationalSolarSpectrumBuilder = struct {
    wavelengths: IndexedVectorBuilder = .{},
    irradiance: IndexedVectorBuilder = .{},

    fn deinit(self: *OperationalSolarSpectrumBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.irradiance.deinit(allocator);
        self.* = .{};
    }

    fn intoOwned(self: *OperationalSolarSpectrumBuilder, allocator: std.mem.Allocator) !OperationalSolarSpectrum {
        if (self.wavelengths.values.items.len == 0 and self.irradiance.values.items.len == 0) return .{};

        const wavelengths_nm = try self.wavelengths.intoOwnedSlice(allocator);
        errdefer if (wavelengths_nm.len > 0) allocator.free(wavelengths_nm);
        const irradiance = try self.irradiance.intoOwnedSlice(allocator);
        errdefer if (irradiance.len > 0) allocator.free(irradiance);

        return .{
            .wavelengths_nm = wavelengths_nm,
            .irradiance = irradiance,
        };
    }
};

pub const OperationalMetadata = struct {
    solar_zenith_deg: ?f64 = null,
    viewing_zenith_deg: ?f64 = null,
    relative_azimuth_deg: ?f64 = null,
    surface_albedo: ?f64 = null,
    cloud_optical_thickness: ?f64 = null,
    cloud_top_altitude_km: ?f64 = null,
    cloud_thickness_km: ?f64 = null,
    cloud_single_scatter_albedo: ?f64 = null,
    cloud_asymmetry_factor: ?f64 = null,
    cloud_angstrom_exponent: ?f64 = null,
    aerosol_optical_depth: ?f64 = null,
    aerosol_single_scatter_albedo: ?f64 = null,
    aerosol_asymmetry_factor: ?f64 = null,
    aerosol_angstrom_exponent: ?f64 = null,
    aerosol_layer_center_km: ?f64 = null,
    aerosol_layer_width_km: ?f64 = null,
    wavelength_shift_nm: ?f64 = null,
    isrf_fwhm_nm: ?f64 = null,
    high_resolution_step_nm: ?f64 = null,
    high_resolution_half_span_nm: ?f64 = null,
    instrument_line_shape: InstrumentLineShape = .{},
    instrument_line_shape_table: InstrumentLineShapeTable = .{},
    operational_refspec_grid: OperationalReferenceGrid = .{},
    operational_solar_spectrum: OperationalSolarSpectrum = .{},
    o2_operational_lut: OperationalCrossSectionLut = .{},
    o2o2_operational_lut: OperationalCrossSectionLut = .{},

    pub fn hasClouds(self: OperationalMetadata) bool {
        return if (self.cloud_optical_thickness) |value| value > 0.0 else false;
    }

    pub fn hasAerosols(self: OperationalMetadata) bool {
        return if (self.aerosol_optical_depth) |value| value > 0.0 else false;
    }

    pub fn hasInstrumentLineShape(self: OperationalMetadata) bool {
        return self.instrument_line_shape.sample_count > 0;
    }

    pub fn hasInstrumentLineShapeTable(self: OperationalMetadata) bool {
        return self.instrument_line_shape_table.nominal_count > 0 and self.instrument_line_shape_table.sample_count > 0;
    }

    pub fn hasOperationalLuts(self: OperationalMetadata) bool {
        return self.o2_operational_lut.enabled() or self.o2o2_operational_lut.enabled();
    }

    pub fn deinitOwned(self: *OperationalMetadata, allocator: std.mem.Allocator) void {
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
        self.* = .{};
    }
};

pub const LoadedSpectra = struct {
    channels: []Channel,
    metadata: OperationalMetadata = .{},
    legacy_fit_window_mode: bool = false,

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
    var metadata = OperationalMetadata{};
    var operational_refspec_grid_builder = OperationalReferenceGridBuilder{};
    defer operational_refspec_grid_builder.deinit(allocator);
    var operational_solar_spectrum_builder = OperationalSolarSpectrumBuilder{};
    defer operational_solar_spectrum_builder.deinit(allocator);
    var o2_operational_lut_builder = OperationalLutBuilder{};
    defer o2_operational_lut_builder.deinit(allocator);
    var o2o2_operational_lut_builder = OperationalLutBuilder{};
    defer o2o2_operational_lut_builder.deinit(allocator);
    var legacy_mode = false;
    var used_legacy_mode = false;
    var saw_channel = false;

    var lines = std.mem.splitScalar(u8, contents, '\n');
    while (lines.next()) |raw_line| {
        const line = trimWhitespace(raw_line);
        if (line.len == 0 or line[0] == '#' or line[0] == '!') continue;

        if (std.mem.startsWith(u8, line, "meta ")) {
            try parseMetadataLine(
                allocator,
                &metadata,
                &operational_refspec_grid_builder,
                &operational_solar_spectrum_builder,
                &o2_operational_lut_builder,
                &o2o2_operational_lut_builder,
                line,
            );
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

    metadata.operational_refspec_grid = try operational_refspec_grid_builder.intoOwned(allocator);
    errdefer metadata.operational_refspec_grid.deinitOwned(allocator);
    metadata.operational_solar_spectrum = try operational_solar_spectrum_builder.intoOwned(allocator);
    errdefer metadata.operational_solar_spectrum.deinitOwned(allocator);
    metadata.o2_operational_lut = try o2_operational_lut_builder.intoOwned(allocator);
    errdefer metadata.o2_operational_lut.deinitOwned(allocator);
    metadata.o2o2_operational_lut = try o2o2_operational_lut_builder.intoOwned(allocator);
    errdefer metadata.o2o2_operational_lut.deinitOwned(allocator);

    return .{
        .channels = channels,
        .metadata = metadata,
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

fn parseMetadataLine(
    allocator: std.mem.Allocator,
    metadata: *OperationalMetadata,
    operational_refspec_grid_builder: *OperationalReferenceGridBuilder,
    operational_solar_spectrum_builder: *OperationalSolarSpectrumBuilder,
    o2_operational_lut_builder: *OperationalLutBuilder,
    o2o2_operational_lut_builder: *OperationalLutBuilder,
    line: []const u8,
) ParseError!void {
    var tokens = std.mem.tokenizeAny(u8, line, " \t");
    _ = tokens.next() orelse return ParseError.InvalidLine;
    const key = tokens.next() orelse return ParseError.InvalidLine;
    const value_text = tokens.next() orelse return ParseError.InvalidLine;
    if (tokens.next() != null) return ParseError.InvalidLine;

    const value = std.fmt.parseFloat(f64, value_text) catch return ParseError.InvalidNumber;

    if (std.mem.eql(u8, key, "solar_zenith_deg")) {
        metadata.solar_zenith_deg = value;
    } else if (std.mem.eql(u8, key, "viewing_zenith_deg")) {
        metadata.viewing_zenith_deg = value;
    } else if (std.mem.eql(u8, key, "relative_azimuth_deg")) {
        metadata.relative_azimuth_deg = value;
    } else if (std.mem.eql(u8, key, "surface_albedo")) {
        metadata.surface_albedo = value;
    } else if (std.mem.eql(u8, key, "cloud_optical_thickness")) {
        metadata.cloud_optical_thickness = value;
    } else if (std.mem.eql(u8, key, "cloud_top_altitude_km")) {
        metadata.cloud_top_altitude_km = value;
    } else if (std.mem.eql(u8, key, "cloud_thickness_km")) {
        metadata.cloud_thickness_km = value;
    } else if (std.mem.eql(u8, key, "cloud_single_scatter_albedo")) {
        metadata.cloud_single_scatter_albedo = value;
    } else if (std.mem.eql(u8, key, "cloud_asymmetry_factor")) {
        metadata.cloud_asymmetry_factor = value;
    } else if (std.mem.eql(u8, key, "cloud_angstrom_exponent")) {
        metadata.cloud_angstrom_exponent = value;
    } else if (std.mem.eql(u8, key, "aerosol_optical_depth")) {
        metadata.aerosol_optical_depth = value;
    } else if (std.mem.eql(u8, key, "aerosol_single_scatter_albedo")) {
        metadata.aerosol_single_scatter_albedo = value;
    } else if (std.mem.eql(u8, key, "aerosol_asymmetry_factor")) {
        metadata.aerosol_asymmetry_factor = value;
    } else if (std.mem.eql(u8, key, "aerosol_angstrom_exponent")) {
        metadata.aerosol_angstrom_exponent = value;
    } else if (std.mem.eql(u8, key, "aerosol_layer_center_km")) {
        metadata.aerosol_layer_center_km = value;
    } else if (std.mem.eql(u8, key, "aerosol_layer_width_km")) {
        metadata.aerosol_layer_width_km = value;
    } else if (std.mem.eql(u8, key, "wavelength_shift_nm")) {
        metadata.wavelength_shift_nm = value;
    } else if (std.mem.eql(u8, key, "isrf_fwhm_nm")) {
        metadata.isrf_fwhm_nm = value;
    } else if (std.mem.eql(u8, key, "hr_grid_step_nm")) {
        metadata.high_resolution_step_nm = value;
    } else if (std.mem.eql(u8, key, "hr_grid_half_span_nm")) {
        metadata.high_resolution_half_span_nm = value;
    } else if (try parseIndexedShapeField(&metadata.instrument_line_shape, key, value)) {
        return;
    } else if (try parseTableShapeField(&metadata.instrument_line_shape_table, key, value)) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_refspec_grid_builder.wavelengths,
        "refspec_wavelength_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_refspec_grid_builder.weights,
        "refspec_gauss_weight_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_refspec_grid_builder.weights,
        "o2_refspec_weight_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_solar_spectrum_builder.wavelengths,
        "hires_wavelength_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_solar_spectrum_builder.wavelengths,
        "highres_wavelength_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_solar_spectrum_builder.irradiance,
        "hires_solar_",
        key,
        value,
    )) {
        return;
    } else if (try parseIndexedVectorField(
        allocator,
        &operational_solar_spectrum_builder.irradiance,
        "highres_solar_",
        key,
        value,
    )) {
        return;
    } else if (try parseOperationalLutField(
        allocator,
        o2_operational_lut_builder,
        "o2_refspec_",
        key,
        value,
    )) {
        return;
    } else if (try parseOperationalLutField(
        allocator,
        o2o2_operational_lut_builder,
        "o2o2_refspec_",
        key,
        value,
    )) {
        return;
    } else {
        return ParseError.InvalidLine;
    }
}

fn parseOperationalLutField(
    allocator: std.mem.Allocator,
    builder: *OperationalLutBuilder,
    prefix: []const u8,
    key: []const u8,
    value: f64,
) ParseError!bool {
    if (!std.mem.startsWith(u8, key, prefix)) return false;
    const suffix = key[prefix.len..];

    if (std.mem.eql(u8, suffix, "npressure")) {
        if (value <= 0.0 or value != @floor(value)) return ParseError.InvalidLine;
        const count = @as(usize, @intFromFloat(value));
        builder.pressure_coefficient_count = std.math.cast(u8, count) orelse return ParseError.InvalidLine;
        return true;
    }
    if (std.mem.eql(u8, suffix, "ntemperature")) {
        if (value <= 0.0 or value != @floor(value)) return ParseError.InvalidLine;
        const count = @as(usize, @intFromFloat(value));
        builder.temperature_coefficient_count = std.math.cast(u8, count) orelse return ParseError.InvalidLine;
        return true;
    }
    if (std.mem.eql(u8, suffix, "pressure_min")) {
        builder.min_pressure_hpa = value;
        return true;
    }
    if (std.mem.eql(u8, suffix, "pressure_max")) {
        builder.max_pressure_hpa = value;
        return true;
    }
    if (std.mem.eql(u8, suffix, "temperature_min")) {
        builder.min_temperature_k = value;
        return true;
    }
    if (std.mem.eql(u8, suffix, "temperature_max")) {
        builder.max_temperature_k = value;
        return true;
    }
    if (try parseLutSingleIndex(suffix, "wavelength_")) |index| {
        try builder.setWavelength(allocator, index, value);
        return true;
    }
    if (try parseLutTripleIndex(suffix, "coeff_")) |indices| {
        try builder.setCoefficient(allocator, indices[0], indices[1], indices[2], value);
        return true;
    }

    return false;
}

fn parseIndexedVectorField(
    allocator: std.mem.Allocator,
    builder: *IndexedVectorBuilder,
    prefix: []const u8,
    key: []const u8,
    value: f64,
) ParseError!bool {
    const index = try parseLutSingleIndex(key, prefix) orelse return false;
    try builder.set(allocator, index, value);
    return true;
}

fn parseIndexedShapeField(shape: *InstrumentLineShape, key: []const u8, value: f64) ParseError!bool {
    if (try parseShapeIndex(key, "isrf_offset_nm_")) |index| {
        shape.offsets_nm[index] = value;
        if (shape.sample_count < index + 1) shape.sample_count = @intCast(index + 1);
        return true;
    }
    if (try parseShapeIndex(key, "isrf_weight_")) |index| {
        shape.weights[index] = value;
        if (shape.sample_count < index + 1) shape.sample_count = @intCast(index + 1);
        return true;
    }
    return false;
}

fn parseShapeIndex(key: []const u8, prefix: []const u8) ParseError!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return ParseError.InvalidLine;
    if (ordinal == 0 or ordinal > max_line_shape_samples) return ParseError.InvalidLine;
    return ordinal - 1;
}

fn parseTableShapeField(table: *InstrumentLineShapeTable, key: []const u8, value: f64) ParseError!bool {
    if (try parseNominalIndex(key, "isrf_table_nominal_nm_")) |nominal_index| {
        table.nominal_wavelengths_nm[nominal_index] = value;
        if (table.nominal_count < nominal_index + 1) table.nominal_count = @intCast(nominal_index + 1);
        return true;
    }
    if (try parseShapeIndex(key, "isrf_table_offset_nm_")) |sample_index| {
        table.offsets_nm[sample_index] = value;
        if (table.sample_count < sample_index + 1) table.sample_count = @intCast(sample_index + 1);
        return true;
    }
    if (try parseDoubleIndex(key, "isrf_table_weight_")) |indices| {
        const nominal_index, const sample_index = indices;
        table.setWeight(nominal_index, sample_index, value);
        if (table.nominal_count < nominal_index + 1) table.nominal_count = @intCast(nominal_index + 1);
        if (table.sample_count < sample_index + 1) table.sample_count = @intCast(sample_index + 1);
        return true;
    }
    return false;
}

fn parseNominalIndex(key: []const u8, prefix: []const u8) ParseError!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return ParseError.InvalidLine;
    if (ordinal == 0 or ordinal > max_line_shape_nominals) return ParseError.InvalidLine;
    return ordinal - 1;
}

fn parseDoubleIndex(key: []const u8, prefix: []const u8) ParseError!?struct { usize, usize } {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const separator_index = std.mem.indexOfScalar(u8, suffix, '_') orelse return ParseError.InvalidLine;
    const first = std.fmt.parseUnsigned(usize, suffix[0..separator_index], 10) catch return ParseError.InvalidLine;
    const second = std.fmt.parseUnsigned(usize, suffix[separator_index + 1 ..], 10) catch return ParseError.InvalidLine;
    if (first == 0 or first > max_line_shape_nominals or second == 0 or second > max_line_shape_samples) {
        return ParseError.InvalidLine;
    }
    return .{ first - 1, second - 1 };
}

fn parseLutSingleIndex(key: []const u8, prefix: []const u8) ParseError!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return ParseError.InvalidLine;
    if (ordinal == 0) return ParseError.InvalidLine;
    return ordinal - 1;
}

fn parseLutTripleIndex(key: []const u8, prefix: []const u8) ParseError!?[3]usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    var parts = std.mem.splitScalar(u8, key[prefix.len..], '_');
    const first = parts.next() orelse return ParseError.InvalidLine;
    const second = parts.next() orelse return ParseError.InvalidLine;
    const third = parts.next() orelse return ParseError.InvalidLine;
    if (parts.next() != null) return ParseError.InvalidLine;

    const temperature_ordinal = std.fmt.parseUnsigned(usize, first, 10) catch return ParseError.InvalidLine;
    const pressure_ordinal = std.fmt.parseUnsigned(usize, second, 10) catch return ParseError.InvalidLine;
    const wavelength_ordinal = std.fmt.parseUnsigned(usize, third, 10) catch return ParseError.InvalidLine;
    if (temperature_ordinal == 0 or pressure_ordinal == 0 or wavelength_ordinal == 0) {
        return ParseError.InvalidLine;
    }
    return .{
        temperature_ordinal - 1,
        pressure_ordinal - 1,
        wavelength_ordinal - 1,
    };
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
