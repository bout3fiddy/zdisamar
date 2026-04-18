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

pub const OperationalLutEntry = struct {
    temperature_index: usize,
    pressure_index: usize,
    wavelength_index: usize,
    value: f64,
};

pub const OperationalLutBuilder = struct {
    wavelengths: std.ArrayList(struct { index: usize, value: f64 }) = .empty,
    coefficients: std.ArrayList(OperationalLutEntry) = .empty,
    temperature_coefficient_count: ?u8 = null,
    pressure_coefficient_count: ?u8 = null,
    min_temperature_k: ?f64 = null,
    max_temperature_k: ?f64 = null,
    min_pressure_hpa: ?f64 = null,
    max_pressure_hpa: ?f64 = null,

    pub fn deinit(self: *OperationalLutBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.coefficients.deinit(allocator);
        self.* = .{};
    }

    pub fn setWavelength(self: *OperationalLutBuilder, allocator: std.mem.Allocator, index: usize, value: f64) !void {
        for (self.wavelengths.items) |*entry| {
            if (entry.index == index) {
                entry.value = value;
                return;
            }
        }
        try self.wavelengths.append(allocator, .{ .index = index, .value = value });
    }

    pub fn setCoefficient(
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

    pub fn intoOwned(self: *OperationalLutBuilder, allocator: std.mem.Allocator) !OperationalCrossSectionLut {
        if (self.wavelengths.items.len == 0 and self.coefficients.items.len == 0) return .{};

        const temperature_count = self.temperature_coefficient_count orelse return Error.InvalidLine;
        const pressure_count = self.pressure_coefficient_count orelse return Error.InvalidLine;
        const min_temperature_k = self.min_temperature_k orelse return Error.InvalidLine;
        const max_temperature_k = self.max_temperature_k orelse return Error.InvalidLine;
        const min_pressure_hpa = self.min_pressure_hpa orelse return Error.InvalidLine;
        const max_pressure_hpa = self.max_pressure_hpa orelse return Error.InvalidLine;

        var max_wavelength_index: usize = 0;
        for (self.wavelengths.items) |entry| max_wavelength_index = @max(max_wavelength_index, entry.index);
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

pub const NamedOperationalLut = struct {
    output_name: []const u8,
    lut: OperationalCrossSectionLut = .{},

    pub fn deinitOwned(self: *NamedOperationalLut, allocator: std.mem.Allocator) void {
        allocator.free(self.output_name);
        self.lut.deinitOwned(allocator);
        self.* = undefined;
    }
};

pub const NamedOperationalLutBuilder = struct {
    prefix: []const u8 = "",
    lut: OperationalLutBuilder = .{},

    pub fn deinit(self: *NamedOperationalLutBuilder, allocator: std.mem.Allocator) void {
        if (self.prefix.len != 0) allocator.free(self.prefix);
        self.lut.deinit(allocator);
        self.* = .{};
    }

    pub fn outputName(self: *const NamedOperationalLutBuilder, allocator: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}_operational_lut", .{self.prefix});
    }
};

pub const IndexedVectorBuilder = struct {
    values: std.ArrayList(struct { index: usize, value: f64 }) = .empty,

    pub fn deinit(self: *IndexedVectorBuilder, allocator: std.mem.Allocator) void {
        self.values.deinit(allocator);
        self.* = .{};
    }

    pub fn set(self: *IndexedVectorBuilder, allocator: std.mem.Allocator, index: usize, value: f64) !void {
        for (self.values.items) |*entry| {
            if (entry.index == index) {
                entry.value = value;
                return;
            }
        }
        try self.values.append(allocator, .{ .index = index, .value = value });
    }

    pub fn intoOwnedSlice(self: *IndexedVectorBuilder, allocator: std.mem.Allocator) ![]const f64 {
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
        for (seen) |was_seen| if (!was_seen) return Error.InvalidLine;
        return dense;
    }
};

pub const OperationalReferenceGridBuilder = struct {
    wavelengths: IndexedVectorBuilder = .{},
    weights: IndexedVectorBuilder = .{},

    pub fn deinit(self: *OperationalReferenceGridBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.weights.deinit(allocator);
        self.* = .{};
    }

    pub fn intoOwned(self: *OperationalReferenceGridBuilder, allocator: std.mem.Allocator) !OperationalReferenceGrid {
        if (self.wavelengths.values.items.len == 0 and self.weights.values.items.len == 0) return .{};
        const wavelengths_nm = try self.wavelengths.intoOwnedSlice(allocator);
        errdefer if (wavelengths_nm.len > 0) allocator.free(wavelengths_nm);
        const weights = try self.weights.intoOwnedSlice(allocator);
        errdefer if (weights.len > 0) allocator.free(weights);
        return .{ .wavelengths_nm = wavelengths_nm, .weights = weights };
    }
};

pub const OperationalSolarSpectrumBuilder = struct {
    wavelengths: IndexedVectorBuilder = .{},
    irradiance: IndexedVectorBuilder = .{},

    pub fn deinit(self: *OperationalSolarSpectrumBuilder, allocator: std.mem.Allocator) void {
        self.wavelengths.deinit(allocator);
        self.irradiance.deinit(allocator);
        self.* = .{};
    }

    pub fn intoOwned(self: *OperationalSolarSpectrumBuilder, allocator: std.mem.Allocator) !OperationalSolarSpectrum {
        if (self.wavelengths.values.items.len == 0 and self.irradiance.values.items.len == 0) return .{};
        const wavelengths_nm = try self.wavelengths.intoOwnedSlice(allocator);
        errdefer if (wavelengths_nm.len > 0) allocator.free(wavelengths_nm);
        const irradiance = try self.irradiance.intoOwnedSlice(allocator);
        errdefer if (irradiance.len > 0) allocator.free(irradiance);
        return .{ .wavelengths_nm = wavelengths_nm, .irradiance = irradiance };
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
    cross_section_operational_luts: []const NamedOperationalLut = &.{},

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
        return self.o2_operational_lut.enabled() or
            self.o2o2_operational_lut.enabled() or
            self.cross_section_operational_luts.len != 0;
    }

    pub fn operationalLut(self: *const OperationalMetadata, output_name: []const u8) ?*const OperationalCrossSectionLut {
        if (std.mem.eql(u8, output_name, "o2_operational_lut")) {
            return if (self.o2_operational_lut.enabled()) &self.o2_operational_lut else null;
        }
        if (std.mem.eql(u8, output_name, "o2o2_operational_lut") or
            std.mem.eql(u8, output_name, "o2_o2_operational_lut"))
        {
            return if (self.o2o2_operational_lut.enabled()) &self.o2o2_operational_lut else null;
        }
        for (self.cross_section_operational_luts) |*entry| {
            if (std.mem.eql(u8, entry.output_name, output_name)) {
                return if (entry.lut.enabled()) &entry.lut else null;
            }
        }
        return null;
    }

    pub fn deinitOwned(self: *OperationalMetadata, allocator: std.mem.Allocator) void {
        self.instrument_line_shape.deinitOwned(allocator);
        self.instrument_line_shape_table.deinitOwned(allocator);
        self.operational_refspec_grid.deinitOwned(allocator);
        self.operational_solar_spectrum.deinitOwned(allocator);
        self.o2_operational_lut.deinitOwned(allocator);
        self.o2o2_operational_lut.deinitOwned(allocator);
        for (self.cross_section_operational_luts) |entry| {
            var owned = entry;
            owned.deinitOwned(allocator);
        }
        if (self.cross_section_operational_luts.len != 0) allocator.free(self.cross_section_operational_luts);
        self.* = .{};
    }
};

pub const ParseState = struct {
    metadata: OperationalMetadata = .{},
    operational_refspec_grid_builder: OperationalReferenceGridBuilder = .{},
    operational_solar_spectrum_builder: OperationalSolarSpectrumBuilder = .{},
    operational_lut_builders: std.ArrayList(NamedOperationalLutBuilder) = .empty,

    pub fn deinit(self: *ParseState, allocator: std.mem.Allocator) void {
        self.metadata.deinitOwned(allocator);
        self.operational_refspec_grid_builder.deinit(allocator);
        self.operational_solar_spectrum_builder.deinit(allocator);
        for (self.operational_lut_builders.items) |*builder| builder.deinit(allocator);
        self.operational_lut_builders.deinit(allocator);
        self.* = .{};
    }
};

pub const line_shape_sample_capacity = max_line_shape_samples;
pub const line_shape_nominal_capacity = max_line_shape_nominals;
