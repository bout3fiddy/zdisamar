//! Purpose:
//!   Parse and normalize spectral ASCII metadata sidecars.
//!
//! Physics:
//!   The metadata captures operational viewing geometry, instrument response,
//!   and cross-section lookup data that accompany the measured spectra.
//!
//! Vendor:
//!   Spectral ASCII metadata parsing and operational sidecar hydration.
//!
//! Design:
//!   Keep the metadata builders separate from the main file parser so the
//!   structured sidecars can be assembled incrementally from flat key-value
//!   records.
//!
//! Invariants:
//!   Operational LUT dimensions and wavelength indices must remain dense and
//!   self-consistent once materialized.
//!
//! Validation:
//!   Spectral ASCII ingest tests cover metadata parsing, LUT assembly, and
//!   operational sidecar hydration.

const std = @import("std");
const metadata_types = @import("spectral_ascii_metadata_types.zig");
const InstrumentLineShape = @import("../../model/Instrument.zig").InstrumentLineShape;
const InstrumentLineShapeTable = @import("../../model/Instrument.zig").InstrumentLineShapeTable;
pub const Error = metadata_types.Error;
pub const NamedOperationalLut = metadata_types.NamedOperationalLut;
pub const OperationalMetadata = metadata_types.OperationalMetadata;

const OperationalLutBuilder = metadata_types.OperationalLutBuilder;
const NamedOperationalLutBuilder = metadata_types.NamedOperationalLutBuilder;
const IndexedVectorBuilder = metadata_types.IndexedVectorBuilder;
const OperationalReferenceGridBuilder = metadata_types.OperationalReferenceGridBuilder;
const OperationalSolarSpectrumBuilder = metadata_types.OperationalSolarSpectrumBuilder;
const max_line_shape_samples = metadata_types.line_shape_sample_capacity;
const max_line_shape_nominals = metadata_types.line_shape_nominal_capacity;

pub const ParseState = struct {
    metadata: OperationalMetadata = .{},
    operational_refspec_grid_builder: OperationalReferenceGridBuilder = .{},
    operational_solar_spectrum_builder: OperationalSolarSpectrumBuilder = .{},
    operational_lut_builders: std.ArrayList(NamedOperationalLutBuilder) = .empty,

    /// Purpose:
    ///   Release the parse state and any partially built sidecars.
    pub fn deinit(self: *ParseState, allocator: std.mem.Allocator) void {
        self.metadata.deinitOwned(allocator);
        self.operational_refspec_grid_builder.deinit(allocator);
        self.operational_solar_spectrum_builder.deinit(allocator);
        for (self.operational_lut_builders.items) |*builder| builder.deinit(allocator);
        self.operational_lut_builders.deinit(allocator);
        self.* = .{};
    }

    /// Purpose:
    ///   Parse one metadata line from the spectral ASCII sidecar.
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
            &self.operational_lut_builders,
            key,
            value,
        );
    }

    /// Purpose:
    ///   Materialize the accumulated metadata into an owned record.
    pub fn intoOwned(self: *ParseState, allocator: std.mem.Allocator) !OperationalMetadata {
        self.metadata.operational_refspec_grid = try self.operational_refspec_grid_builder.intoOwned(allocator);
        errdefer self.metadata.operational_refspec_grid.deinitOwned(allocator);
        self.metadata.operational_solar_spectrum = try self.operational_solar_spectrum_builder.intoOwned(allocator);
        errdefer self.metadata.operational_solar_spectrum.deinitOwned(allocator);
        var cross_section_operational_luts = std.ArrayList(NamedOperationalLut).empty;
        errdefer {
            for (cross_section_operational_luts.items) |entry| {
                var owned = entry;
                owned.deinitOwned(allocator);
            }
            cross_section_operational_luts.deinit(allocator);
        }

        for (self.operational_lut_builders.items) |*builder| {
            const output_name = try builder.outputName(allocator);
            errdefer allocator.free(output_name);
            var lut = try builder.lut.intoOwned(allocator);
            errdefer lut.deinitOwned(allocator);

            if (std.mem.eql(u8, output_name, "o2_operational_lut")) {
                self.metadata.o2_operational_lut = lut;
                allocator.free(output_name);
                continue;
            }
            if (std.mem.eql(u8, output_name, "o2o2_operational_lut") or
                std.mem.eql(u8, output_name, "o2_o2_operational_lut"))
            {
                self.metadata.o2o2_operational_lut = lut;
                allocator.free(output_name);
                continue;
            }

            try cross_section_operational_luts.append(allocator, .{
                .output_name = output_name,
                .lut = lut,
            });
        }
        self.metadata.cross_section_operational_luts = try cross_section_operational_luts.toOwnedSlice(allocator);

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
    operational_lut_builders: *std.ArrayList(NamedOperationalLutBuilder),
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
    } else if (try parseNamedOperationalLutField(
        allocator,
        operational_lut_builders,
        key,
        value,
    )) {
        return;
    } else {
        return Error.InvalidLine;
    }
}

fn parseNamedOperationalLutField(
    allocator: std.mem.Allocator,
    builders: *std.ArrayList(NamedOperationalLutBuilder),
    key: []const u8,
    value: f64,
) Error!bool {
    const marker = "_refspec_";
    const marker_index = std.mem.indexOf(u8, key, marker) orelse return false;
    const prefix = key[0..marker_index];
    if (prefix.len == 0) return false;

    const builder = try getOrCreateOperationalLutBuilder(allocator, builders, prefix);
    const suffix = key[marker_index + marker.len ..];
    return parseOperationalLutSuffix(allocator, &builder.lut, suffix, value);
}

fn getOrCreateOperationalLutBuilder(
    allocator: std.mem.Allocator,
    builders: *std.ArrayList(NamedOperationalLutBuilder),
    prefix: []const u8,
) !*NamedOperationalLutBuilder {
    for (builders.items, 0..) |*builder, index| {
        if (std.mem.eql(u8, builder.prefix, prefix)) return &builders.items[index];
    }

    const owned_prefix = try allocator.dupe(u8, prefix);
    errdefer allocator.free(owned_prefix);
    try builders.append(allocator, .{ .prefix = owned_prefix });
    return &builders.items[builders.items.len - 1];
}

fn parseOperationalLutSuffix(
    allocator: std.mem.Allocator,
    builder: *OperationalLutBuilder,
    suffix: []const u8,
    value: f64,
) Error!bool {
    // PARITY:
    //   Operational cross-section LUT payloads share one dense layout once the
    //   `<gas>_refspec_` prefix has been stripped from the metadata key.

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
