//! Purpose:
//!   Parse reference-asset table formats into numeric rows.
//!
//! Physics:
//!   Convert HITRAN-style lines, BIRA CIA polynomials, and LISA strong-line sidecars into typed
//!   numeric tables with the expected scientific units.
//!
//! Vendor:
//!   `reference asset format parsers`
//!
//! Design:
//!   Keep format-specific parsing separate from manifest resolution so each parser can preserve
//!   its own unit conversions and validation rules.
//!
//! Invariants:
//!   Column names and row shapes must match the declared asset format before hydration succeeds.
//!
//! Validation:
//!   Reference-asset loader tests and the O2A bundled optics tests.

const std = @import("std");
const helpers = @import("reference_assets_formats_helpers.zig");

/// Purpose:
///   Describe the expected format and column contract for one asset.
pub const AssetSpec = struct {
    format: []const u8,
    columns: []const []const u8,
};

/// Purpose:
///   Hold the parsed numeric table and its header names.
pub const ParsedTable = struct {
    column_names: []const []const u8,
    values: []f64,
    row_count: u32,
};

pub const Error = error{
    UnsupportedFormat,
    InvalidCsv,
    InvalidNumber,
    InvalidAssetFormat,
    OutOfMemory,
};

/// Purpose:
///   Parse one asset payload according to its declared format.
///
/// Physics:
///   Dispatch to the format-specific parser while preserving the declared scientific units.
pub fn parseAssetTable(
    allocator: std.mem.Allocator,
    asset: AssetSpec,
    contents: []const u8,
) Error!ParsedTable {
    if (std.mem.eql(u8, asset.format, "csv")) {
        return parseNumericCsv(allocator, contents);
    }
    if (std.mem.eql(u8, asset.format, "hitran_160")) {
        return parseHitran160(allocator, contents, asset.columns);
    }
    if (std.mem.eql(u8, asset.format, "bira_cia_poly")) {
        return parseBiraCiaPolynomial(allocator, contents, asset.columns);
    }
    if (std.mem.eql(u8, asset.format, "lisa_sdf")) {
        return parseLisaSdf(allocator, contents, asset.columns);
    }
    if (std.mem.eql(u8, asset.format, "lisa_rmf")) {
        return parseLisaRmf(allocator, contents, asset.columns);
    }
    return error.UnsupportedFormat;
}

/// Purpose:
///   Parse a plain numeric CSV payload.
fn parseNumericCsv(allocator: std.mem.Allocator, contents: []const u8) Error!ParsedTable {
    var line_iter = std.mem.splitScalar(u8, contents, '\n');

    var header_line: ?[]const u8 = null;
    while (line_iter.next()) |raw_line| {
        const line = helpers.trimWhitespace(raw_line);
        if (line.len == 0) continue;
        header_line = line;
        break;
    }
    const header = header_line orelse return error.InvalidCsv;

    var header_tokens = std.mem.splitScalar(u8, header, ',');
    var header_names = std.ArrayList([]const u8).empty;
    defer header_names.deinit(allocator);
    errdefer {
        for (header_names.items) |name| allocator.free(name);
    }

    while (header_tokens.next()) |token| {
        const name = try allocator.dupe(u8, helpers.trimWhitespace(token));
        errdefer allocator.free(name);
        try header_names.append(allocator, name);
    }
    if (header_names.items.len == 0) return error.InvalidCsv;

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    while (line_iter.next()) |raw_line| {
        const line = helpers.trimWhitespace(raw_line);
        if (line.len == 0) continue;

        var token_iter = std.mem.splitScalar(u8, line, ',');
        var column_index: usize = 0;
        while (token_iter.next()) |token| {
            if (column_index >= header_names.items.len) return error.InvalidCsv;
            const value = std.fmt.parseFloat(f64, helpers.trimWhitespace(token)) catch return error.InvalidNumber;
            try values.append(allocator, value);
            column_index += 1;
        }
        if (column_index != header_names.items.len) return error.InvalidCsv;
        row_count += 1;
    }
    if (row_count == 0) return error.InvalidCsv;

    const columns = try allocator.alloc([]const u8, header_names.items.len);
    var copied_columns: usize = 0;
    errdefer {
        for (columns[0..copied_columns]) |name| allocator.free(name);
        allocator.free(columns);
    }
    for (header_names.items, 0..) |name, index| {
        columns[index] = name;
        copied_columns = index + 1;
    }
    header_names.clearRetainingCapacity();

    return .{
        .column_names = columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

/// Purpose:
///   Parse a fixed-width HITRAN-style spectroscopy table.
///
/// Units:
///   Wavenumbers are read in cm^-1 and converted to wavelengths in nm.
fn parseHitran160(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const has_vendor_o2a_fields = columns.len == 13;
    const minimum_line_length: usize = 67;
    const owned_columns = try helpers.dupColumns(allocator, columns);
    errdefer helpers.freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = helpers.trimLineEnding(raw_line);
        const stripped = helpers.trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < minimum_line_length) return error.InvalidAssetFormat;

        const gas_index = try helpers.parseFixedInt(line[0..2]);
        const isotope_number = try helpers.parseFixedInt(line[2..3]);
        const center_wavenumber_cm1 = try helpers.parseFixedFloat(line[3..15]);
        const line_strength = try helpers.parseFixedFloat(line[15..25]);
        const air_half_width_cm1 = try helpers.parseFixedFloat(line[35..40]);
        const lower_state_energy_cm1 = try helpers.parseFixedFloat(line[45..55]);
        const temperature_exponent = try helpers.parseFixedFloat(line[55..59]);
        const pressure_shift_cm1 = try helpers.parseFixedFloat(line[59..67]);
        const has_inline_vendor_fields = has_vendor_o2a_fields and line.len >= 85;

        // UNITS:
        //   The fixed-width cm^-1 fields are converted to the nm values expected by the typed
        //   spectroscopy loader.
        const center_wavelength_nm = helpers.wavenumberToWavelengthNm(center_wavenumber_cm1);
        const air_half_width_nm = helpers.spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1);
        const pressure_shift_nm = -helpers.spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1);
        const line_mixing_coefficient = helpers.deriveLineMixingCoefficient(air_half_width_cm1, pressure_shift_cm1);
        const inline_branch_ic1 = if (has_inline_vendor_fields) try helpers.parseOptionalFixedInt(line[67..70]) else null;
        const inline_branch_ic2 = if (has_inline_vendor_fields) try helpers.parseOptionalFixedInt(line[70..73]) else null;
        const inline_rotational_nf = if (has_inline_vendor_fields) try helpers.parseOptionalFixedInt(line[83..85]) else null;
        const fallback_vendor_metadata = if (has_vendor_o2a_fields and
            inline_branch_ic1 == null and
            inline_branch_ic2 == null and
            inline_rotational_nf == null)
            try helpers.fallbackVendorO2ABranchMetadata(line, center_wavenumber_cm1)
        else
            null;
        const branch_ic1 = if (inline_branch_ic1) |value|
            value
        else if (fallback_vendor_metadata) |metadata|
            metadata.branch_ic1
        else
            null;
        const branch_ic2 = if (inline_branch_ic2) |value|
            value
        else if (fallback_vendor_metadata) |metadata|
            metadata.branch_ic2
        else
            null;
        const rotational_nf = if (inline_rotational_nf) |value|
            value
        else if (fallback_vendor_metadata) |metadata|
            metadata.rotational_nf
        else
            null;

        try values.appendSlice(allocator, &.{
            @as(f64, @floatFromInt(gas_index)),
            @as(f64, @floatFromInt(isotope_number)),
            helpers.deriveIsotopicAbundanceFraction(gas_index, isotope_number),
            center_wavelength_nm,
            line_strength,
            air_half_width_nm,
            temperature_exponent,
            lower_state_energy_cm1,
            pressure_shift_nm,
            line_mixing_coefficient,
        });
        if (has_vendor_o2a_fields) {
            try values.appendSlice(allocator, &.{
                if (branch_ic1) |value| @as(f64, @floatFromInt(value)) else std.math.nan(f64),
                if (branch_ic2) |value| @as(f64, @floatFromInt(value)) else std.math.nan(f64),
                if (rotational_nf) |value| @as(f64, @floatFromInt(value)) else std.math.nan(f64),
            });
        }
        row_count += 1;
    }
    if (row_count == 0) return error.InvalidAssetFormat;

    return .{
        .column_names = owned_columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

/// Purpose:
///   Parse a BIRA CIA polynomial table.
///
/// Units:
///   The scale factor is stored in cm^5/molecule^2 and remains attached to the whole table.
fn parseBiraCiaPolynomial(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const owned_columns = try helpers.dupColumns(allocator, columns);
    errdefer helpers.freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    var numeric_header_index: usize = 0;
    var scale_factor: f64 = 0.0;
    var expected_data_rows: ?u32 = null;
    var row_count: u32 = 0;

    while (line_iter.next()) |raw_line| {
        const line = helpers.trimLineEnding(raw_line);
        const stripped = helpers.trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#') continue;

        var token_iter = std.mem.tokenizeAny(u8, stripped, " \t");
        const first_token = token_iter.next() orelse continue;
        if (first_token[0] == '!') continue;

        if (numeric_header_index < 3) {
            const numeric_value = std.fmt.parseFloat(f64, first_token) catch return error.InvalidNumber;
            switch (numeric_header_index) {
                0 => scale_factor = numeric_value,
                1 => {},
                2 => expected_data_rows = @intFromFloat(numeric_value),
                else => unreachable,
            }
            numeric_header_index += 1;
            continue;
        }

        const wavelength_nm = std.fmt.parseFloat(f64, first_token) catch return error.InvalidNumber;
        const a0 = std.fmt.parseFloat(f64, token_iter.next() orelse return error.InvalidAssetFormat) catch return error.InvalidNumber;
        const a1 = std.fmt.parseFloat(f64, token_iter.next() orelse return error.InvalidAssetFormat) catch return error.InvalidNumber;
        const a2 = std.fmt.parseFloat(f64, token_iter.next() orelse return error.InvalidAssetFormat) catch return error.InvalidNumber;

        // DECISION:
        //   Preserve the vendor row layout exactly so the scale factor stays table-scoped.
        try values.appendSlice(allocator, &.{
            wavelength_nm,
            a0,
            a1,
            a2,
            scale_factor,
        });
        row_count += 1;
    }

    if (numeric_header_index < 3 or row_count == 0) return error.InvalidAssetFormat;
    if (expected_data_rows) |expected| {
        if (row_count < expected) return error.InvalidAssetFormat;
    }

    return .{
        .column_names = owned_columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

/// Purpose:
///   Parse a LISA strong-line sidecar table.
///
/// Physics:
///   Preserve the sidecar fields that augment the O2A strong-line path.
fn parseLisaSdf(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const owned_columns = try helpers.dupColumns(allocator, columns);
    errdefer helpers.freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = helpers.trimLineEnding(raw_line);
        const stripped = helpers.trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 87) return error.InvalidAssetFormat;

        const center_wavenumber_cm1 = try helpers.parseFixedFloat(line[0..12]);
        const population_t0 = try helpers.parseFixedFloat(line[14..23]);
        const dipole_ratio = try helpers.parseFixedFloat(line[25..34]);
        const dipole_t0 = try helpers.parseFixedFloat(line[35..44]);
        const lower_state_energy_cm1 = try helpers.parseFixedFloat(line[46..56]);
        const temperature_exponent = try helpers.parseFixedFloat(line[65..69]);
        const pressure_shift_cm1 = try helpers.parseFixedFloat(line[71..79]);
        const branch_token = helpers.trimWhitespace(line[83..84]);
        const nf_token = helpers.trimWhitespace(line[84..87]);
        const rotational_index_m1 = helpers.rotationalIndexFromLisaBranch(branch_token, nf_token) catch return error.InvalidAssetFormat;

        // PARITY:
        //   `HITRANModule::readSDF` does not trust the tabulated `HWT0` field. It reconstructs
        //   the reference half-width from the LISA branch/Nf quantum numbers using the
        //   Tran/Hartmann-Yang parameterization before any temperature scaling happens.
        _ = try helpers.parseFixedFloat(line[58..63]);
        const air_half_width_cm1 = helpers.vendorLisaReferenceHalfWidthCm1(branch_token, nf_token) catch return error.InvalidAssetFormat;

        // UNITS:
        //   Strong-line fields are stored in cm^-1 and converted to nm where the typed loader
        //   expects wavelength-like values.
        const center_wavelength_nm = helpers.wavenumberToWavelengthNm(center_wavenumber_cm1);
        const air_half_width_nm = helpers.spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1);
        const pressure_shift_nm = -helpers.spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1);

        try values.appendSlice(allocator, &.{
            center_wavenumber_cm1,
            center_wavelength_nm,
            population_t0,
            dipole_ratio,
            dipole_t0,
            lower_state_energy_cm1,
            air_half_width_cm1,
            air_half_width_nm,
            temperature_exponent,
            pressure_shift_cm1,
            pressure_shift_nm,
            @floatFromInt(rotational_index_m1),
        });
        row_count += 1;
    }
    if (row_count == 0) return error.InvalidAssetFormat;

    return .{
        .column_names = owned_columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

/// Purpose:
///   Parse a LISA relaxation matrix table.
fn parseLisaRmf(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const owned_columns = try helpers.dupColumns(allocator, columns);
    errdefer helpers.freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = helpers.trimLineEnding(raw_line);
        const stripped = helpers.trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 31) return error.InvalidAssetFormat;

        try values.append(allocator, try helpers.parseFixedFloat(line[0..15]));
        try values.append(allocator, try helpers.parseFixedFloat(line[15..31]));
        row_count += 1;
    }
    if (row_count == 0) return error.InvalidAssetFormat;

    return .{
        .column_names = owned_columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}
