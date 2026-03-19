const std = @import("std");
const InstrumentLineShape = @import("../../model/Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("../../model/Instrument.zig").InstrumentLineShapeTable;
const OperationalReferenceGrid = @import("../../model/Instrument.zig").OperationalReferenceGrid;
const OperationalSolarSpectrum = @import("../../model/Instrument.zig").OperationalSolarSpectrum;
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const max_line_shape_samples = @import("../../model/Instrument.zig").max_line_shape_samples;
const max_line_shape_nominals = @import("../../model/Instrument.zig").max_line_shape_nominals;

pub const Error = error{
    OutOfMemory,
    InvalidLine,
    InvalidNumber,
    UnexpectedDataLine,
    MixedChannelKinds,
    MissingChannels,
    UnclosedSection,
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

        const temperature_count = self.temperature_coefficient_count orelse return Error.InvalidLine;
        const pressure_count = self.pressure_coefficient_count orelse return Error.InvalidLine;
        const min_temperature_k = self.min_temperature_k orelse return Error.InvalidLine;
        const max_temperature_k = self.max_temperature_k orelse return Error.InvalidLine;
        const min_pressure_hpa = self.min_pressure_hpa orelse return Error.InvalidLine;
        const max_pressure_hpa = self.max_pressure_hpa orelse return Error.InvalidLine;

        var max_wavelength_index: usize = 0;
        for (self.wavelengths.items) |entry| {
            max_wavelength_index = @max(max_wavelength_index, entry.index);
        }
        if (self.wavelengths.items.len == 0) return Error.InvalidLine;

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
                return Error.InvalidLine;
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
        if (self.values.items.len != value_count) return Error.InvalidLine;

        const dense = try allocator.alloc(f64, value_count);
        errdefer allocator.free(dense);
        @memset(dense, 0.0);

        const seen = try allocator.alloc(bool, value_count);
        defer allocator.free(seen);
        @memset(seen, false);

        for (self.values.items) |entry| {
            if (seen[entry.index]) return Error.InvalidLine;
            dense[entry.index] = entry.value;
            seen[entry.index] = true;
        }

        for (seen) |was_seen| {
            if (!was_seen) return Error.InvalidLine;
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
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
        self.* = .{};
    }
};

pub const ParseState = struct {
    metadata: OperationalMetadata = .{},
    operational_refspec_grid_builder: OperationalReferenceGridBuilder = .{},
    operational_solar_spectrum_builder: OperationalSolarSpectrumBuilder = .{},
    o2_operational_lut_builder: OperationalLutBuilder = .{},
    o2o2_operational_lut_builder: OperationalLutBuilder = .{},

    pub fn deinit(self: *ParseState, allocator: std.mem.Allocator) void {
        self.metadata.deinitOwned(allocator);
        self.operational_refspec_grid_builder.deinit(allocator);
        self.operational_solar_spectrum_builder.deinit(allocator);
        self.o2_operational_lut_builder.deinit(allocator);
        self.o2o2_operational_lut_builder.deinit(allocator);
        self.* = .{};
    }

    pub fn parseLine(self: *ParseState, allocator: std.mem.Allocator, line: []const u8) Error!void {
        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        _ = tokens.next() orelse return Error.InvalidLine;
        const key = tokens.next() orelse return Error.InvalidLine;
        const value_text = tokens.next() orelse return Error.InvalidLine;
        if (tokens.next() != null) return Error.InvalidLine;

        const value = std.fmt.parseFloat(f64, value_text) catch return Error.InvalidNumber;
        try parseMetadataValue(
            allocator,
            &self.metadata,
            &self.operational_refspec_grid_builder,
            &self.operational_solar_spectrum_builder,
            &self.o2_operational_lut_builder,
            &self.o2o2_operational_lut_builder,
            key,
            value,
        );
    }

    pub fn intoOwned(self: *ParseState, allocator: std.mem.Allocator) !OperationalMetadata {
        self.metadata.operational_refspec_grid = try self.operational_refspec_grid_builder.intoOwned(allocator);
        errdefer self.metadata.operational_refspec_grid.deinitOwned(allocator);
        self.metadata.operational_solar_spectrum = try self.operational_solar_spectrum_builder.intoOwned(allocator);
        errdefer self.metadata.operational_solar_spectrum.deinitOwned(allocator);
        self.metadata.o2_operational_lut = try self.o2_operational_lut_builder.intoOwned(allocator);
        errdefer self.metadata.o2_operational_lut.deinitOwned(allocator);
        self.metadata.o2o2_operational_lut = try self.o2o2_operational_lut_builder.intoOwned(allocator);
        errdefer self.metadata.o2o2_operational_lut.deinitOwned(allocator);

        const owned = self.metadata;
        self.metadata = .{};
        return owned;
    }
};

fn parseMetadataValue(
    allocator: std.mem.Allocator,
    metadata: *OperationalMetadata,
    operational_refspec_grid_builder: *OperationalReferenceGridBuilder,
    operational_solar_spectrum_builder: *OperationalSolarSpectrumBuilder,
    o2_operational_lut_builder: *OperationalLutBuilder,
    o2o2_operational_lut_builder: *OperationalLutBuilder,
    key: []const u8,
    value: f64,
) Error!void {
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
    } else if (try parseIndexedShapeField(allocator, &metadata.instrument_line_shape, key, value)) {
        return;
    } else if (try parseTableShapeField(allocator, &metadata.instrument_line_shape_table, key, value)) {
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
        return Error.InvalidLine;
    }
}

fn parseOperationalLutField(
    allocator: std.mem.Allocator,
    builder: *OperationalLutBuilder,
    prefix: []const u8,
    key: []const u8,
    value: f64,
) Error!bool {
    if (!std.mem.startsWith(u8, key, prefix)) return false;
    const suffix = key[prefix.len..];

    if (std.mem.eql(u8, suffix, "npressure")) {
        if (value <= 0.0 or value != @floor(value)) return Error.InvalidLine;
        const count = @as(usize, @intFromFloat(value));
        builder.pressure_coefficient_count = std.math.cast(u8, count) orelse return Error.InvalidLine;
        return true;
    }
    if (std.mem.eql(u8, suffix, "ntemperature")) {
        if (value <= 0.0 or value != @floor(value)) return Error.InvalidLine;
        const count = @as(usize, @intFromFloat(value));
        builder.temperature_coefficient_count = std.math.cast(u8, count) orelse return Error.InvalidLine;
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
) Error!bool {
    const index = try parseLutSingleIndex(key, prefix) orelse return false;
    try builder.set(allocator, index, value);
    return true;
}

fn parseIndexedShapeField(
    allocator: std.mem.Allocator,
    shape: *InstrumentLineShape,
    key: []const u8,
    value: f64,
) Error!bool {
    if (try parseShapeIndex(key, "isrf_offset_nm_")) |index| {
        try shape.ensureOwnedStorage(allocator);
        @constCast(shape.offsets_nm)[index] = value;
        if (shape.sample_count < index + 1) shape.sample_count = @intCast(index + 1);
        return true;
    }
    if (try parseShapeIndex(key, "isrf_weight_")) |index| {
        try shape.ensureOwnedStorage(allocator);
        @constCast(shape.weights)[index] = value;
        if (shape.sample_count < index + 1) shape.sample_count = @intCast(index + 1);
        return true;
    }
    return false;
}

fn parseTableShapeField(
    allocator: std.mem.Allocator,
    table: *InstrumentLineShapeTable,
    key: []const u8,
    value: f64,
) Error!bool {
    if (try parseNominalIndex(key, "isrf_table_nominal_nm_")) |nominal_index| {
        try table.ensureOwnedStorage(allocator);
        @constCast(table.nominal_wavelengths_nm)[nominal_index] = value;
        if (table.nominal_count < nominal_index + 1) table.nominal_count = @intCast(nominal_index + 1);
        return true;
    }
    if (try parseShapeIndex(key, "isrf_table_offset_nm_")) |sample_index| {
        try table.ensureOwnedStorage(allocator);
        @constCast(table.offsets_nm)[sample_index] = value;
        if (table.sample_count < sample_index + 1) table.sample_count = @intCast(sample_index + 1);
        return true;
    }
    if (try parseDoubleIndex(key, "isrf_table_weight_")) |indices| {
        const nominal_index, const sample_index = indices;
        try table.ensureOwnedStorage(allocator);
        table.setWeight(nominal_index, sample_index, value);
        if (table.nominal_count < nominal_index + 1) table.nominal_count = @intCast(nominal_index + 1);
        if (table.sample_count < sample_index + 1) table.sample_count = @intCast(sample_index + 1);
        return true;
    }
    return false;
}

fn parseShapeIndex(key: []const u8, prefix: []const u8) Error!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return Error.InvalidLine;
    if (ordinal == 0 or ordinal > max_line_shape_samples) return Error.InvalidLine;
    return ordinal - 1;
}

fn parseNominalIndex(key: []const u8, prefix: []const u8) Error!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return Error.InvalidLine;
    if (ordinal == 0 or ordinal > max_line_shape_nominals) return Error.InvalidLine;
    return ordinal - 1;
}

fn parseDoubleIndex(key: []const u8, prefix: []const u8) Error!?struct { usize, usize } {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const separator_index = std.mem.indexOfScalar(u8, suffix, '_') orelse return Error.InvalidLine;
    const first = std.fmt.parseUnsigned(usize, suffix[0..separator_index], 10) catch return Error.InvalidLine;
    const second = std.fmt.parseUnsigned(usize, suffix[separator_index + 1 ..], 10) catch return Error.InvalidLine;
    if (first == 0 or first > max_line_shape_nominals or second == 0 or second > max_line_shape_samples) {
        return Error.InvalidLine;
    }
    return .{ first - 1, second - 1 };
}

fn parseLutSingleIndex(key: []const u8, prefix: []const u8) Error!?usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    const suffix = key[prefix.len..];
    const ordinal = std.fmt.parseUnsigned(usize, suffix, 10) catch return Error.InvalidLine;
    if (ordinal == 0) return Error.InvalidLine;
    return ordinal - 1;
}

fn parseLutTripleIndex(key: []const u8, prefix: []const u8) Error!?[3]usize {
    if (!std.mem.startsWith(u8, key, prefix)) return null;
    var parts = std.mem.splitScalar(u8, key[prefix.len..], '_');
    const first = parts.next() orelse return Error.InvalidLine;
    const second = parts.next() orelse return Error.InvalidLine;
    const third = parts.next() orelse return Error.InvalidLine;
    if (parts.next() != null) return Error.InvalidLine;

    const temperature_ordinal = std.fmt.parseUnsigned(usize, first, 10) catch return Error.InvalidLine;
    const pressure_ordinal = std.fmt.parseUnsigned(usize, second, 10) catch return Error.InvalidLine;
    const wavelength_ordinal = std.fmt.parseUnsigned(usize, third, 10) catch return Error.InvalidLine;
    if (temperature_ordinal == 0 or pressure_ordinal == 0 or wavelength_ordinal == 0) {
        return Error.InvalidLine;
    }
    return .{
        temperature_ordinal - 1,
        pressure_ordinal - 1,
        wavelength_ordinal - 1,
    };
}
