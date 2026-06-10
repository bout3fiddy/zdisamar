const std = @import("std");

// reference_assets_formats.zig -------------------------------------------------------------------------------|
// In-memory parsers for numeric reference-data asset formats.                                                 |
//                                                                                                             |
// called by                                                                                                   |
//   reference asset loading after a manifest row has selected the expected format and columns.                |
//                                                                                                             |
// main paths                                                                                                  |
//   csv            : parse a comma header and numeric rows.                                                   |
//   hitran_160     : parse fixed-width HITRAN lines and optional O2 A branch metadata.                        |
//   bira_cia_poly  : parse BIRA CIA polynomial rows with a file-scoped scale factor.                          |
//   lisa_sdf/rmf   : parse LISA strong-line and relaxation-matrix support files.                              |
//                                                                                                             |
// ownership                                                                                                   |
//   ParsedTable owns duplicated column names and the flat f64 value buffer. Callers release both through      |
//   LoadedAsset.deinit after converting the table into typed reference-data storage.                          |
//                                                                                                             |
// layout                                                                                                      |
//   Parser outputs are compact headers over out-of-line buffers. The value buffer is row-major by the         |
//   manifest column order, so conversion code can use column indexes without carrying per-cell metadata.      |
// ------------------------------------------------------------------------------------------------------------|

const helpers = struct {
    pub fn dupColumns(allocator: std.mem.Allocator, columns: []const []const u8) ![]const []const u8 {
        const owned_columns = try allocator.alloc([]const u8, columns.len);
        errdefer allocator.free(owned_columns);
        var owned_column_count: usize = 0;
        errdefer for (owned_columns[0..owned_column_count]) |column| allocator.free(column);
        for (columns, 0..) |column, index| {
            owned_columns[index] = try allocator.dupe(u8, column);
            owned_column_count += 1;
        }
        return owned_columns;
    }

    pub fn freeColumns(allocator: std.mem.Allocator, columns: []const []const u8) void {
        for (columns) |column| allocator.free(column);
        allocator.free(columns);
    }

    pub fn columnNamesContain(columns: []const []const u8, expected: []const u8) bool {
        for (columns) |column| {
            if (std.mem.eql(u8, column, expected)) return true;
        }
        return false;
    }

    pub fn parseFixedFloat(slice: []const u8) !f64 {
        return std.fmt.parseFloat(f64, trimWhitespace(slice)) catch error.InvalidNumber;
    }

    pub fn parseFixedInt(slice: []const u8) !u16 {
        return std.fmt.parseInt(u16, trimWhitespace(slice), 10) catch error.InvalidNumber;
    }

    pub fn parseOptionalFixedInt(slice: []const u8) !?u16 {
        const trimmed = trimWhitespace(slice);
        if (trimmed.len == 0) return null;
        return std.fmt.parseInt(u16, trimmed, 10) catch error.InvalidNumber;
    }

    pub fn trimWhitespace(value: []const u8) []const u8 {
        return std.mem.trim(u8, value, " \t\r");
    }

    pub fn trimLineEnding(value: []const u8) []const u8 {
        return std.mem.trimRight(u8, value, "\r");
    }

    pub fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
        return 1.0e7 / @max(wavenumber_cm1, 1.0);
    }

    pub fn spectralWidthCm1ToNm(width_cm1: f64, center_wavenumber_cm1: f64) f64 {
        const safe_center = @max(center_wavenumber_cm1, 1.0);
        return width_cm1 * 1.0e7 / (safe_center * safe_center);
    }

    pub fn deriveLineMixingCoefficient(air_half_width_cm1: f64, pressure_shift_cm1: f64) f64 {
        return std.math.clamp(
            @abs(pressure_shift_cm1) / @max(@abs(air_half_width_cm1), 1.0e-6),
            0.0,
            0.15,
        );
    }

    pub fn optionalU16ToTableValue(value: ?u16) f64 {
        return if (value) |present| @as(f64, @floatFromInt(present)) else std.math.nan(f64);
    }

    pub fn deriveIsotopicAbundanceFraction(gas_index: u16, isotope_number: u16) f64 {
        return switch (gas_index) {
            1 => switch (isotope_number) {
                1 => 0.997317,
                2 => 1.99983e-3,
                3 => 3.71884e-4,
                4 => 3.10693e-4,
                5 => 6.23003e-7,
                6 => 1.15853e-7,
                else => 1.0e-8,
            },

            2 => switch (isotope_number) {
                1 => 0.984204,
                2 => 1.10574e-2,
                3 => 3.94707e-3,
                4 => 7.33989e-4,
                5 => 4.43446e-5,
                6 => 8.24623e-6,
                else => 1.0e-8,
            },

            5 => switch (isotope_number) {
                1 => 0.986544,
                2 => 1.10836e-2,
                3 => 1.97822e-3,
                4 => 3.67867e-4,
                5 => 2.22250e-5,
                6 => 4.13292e-6,
                else => 1.0e-8,
            },

            6 => switch (isotope_number) {
                1 => 0.988274,
                2 => 1.11031e-2,
                3 => 6.15751e-4,
                else => 1.0e-8,
            },

            7 => switch (isotope_number) {
                1 => 0.995262,
                2 => 3.99141e-3,
                3 => 7.42235e-4,
                else => 1.0e-8,
            },

            11 => switch (isotope_number) {
                1 => 0.995872,
                2 => 3.66129e-3,
                else => 1.0e-8,
            },

            10 => switch (isotope_number) {
                1 => 0.991,
                2 => 0.006,
                3 => 0.003,
                else => 1.0e-8,
            },

            else => 1.0,
        };
    }

    pub fn rotationalIndexFromLisaBranch(branch_token: []const u8, nf_token: []const u8) !i32 {
        if (branch_token.len != 1) return error.InvalidAssetFormat;

        const nf = std.fmt.parseInt(i32, nf_token, 10) catch return error.InvalidNumber;

        return switch (branch_token[0]) {
            'P' => -nf,
            'R' => nf + 1,
            else => return error.InvalidAssetFormat,
        };
    }

    pub fn vendorLisaReferenceHalfWidthCm1(branch_token: []const u8, nf_token: []const u8) !f64 {
        if (branch_token.len != 1) return error.InvalidAssetFormat;

        const raw_nf = std.fmt.parseInt(i32, nf_token, 10) catch return error.InvalidNumber;
        const vendor_nf = switch (branch_token[0]) {
            'P' => raw_nf - 1,
            'R' => raw_nf + 1,
            else => return error.InvalidAssetFormat,
        };

        const vendor_nf_f64 = @as(f64, @floatFromInt(vendor_nf));
        const sbhw = 0.02204 + 0.03749 /
            (1.0 + 0.05428 * vendor_nf_f64 - 1.19e-3 * vendor_nf_f64 * vendor_nf_f64 +
                2.073e-6 * std.math.pow(f64, vendor_nf_f64, 4.0));

        return 1.023 * 1.012 * sbhw /
            std.math.sqrt(1.0 + std.math.pow(f64, (vendor_nf_f64 - 5.0) / 55.0, 2.0));
    }

    // VendorO2ABranchMetadata --------------------------------------------------------------------------------|
    // Optional HITRAN O2 A branch metadata recovered from inline vendor fields or the branch token fallback.  |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 6 B (0.006 KiB), align: 2 B                                                                       |
    //                                                                                                         |
    // memory                                                                                                  |
    // [0..1] branch_ic1    : u16                                                                              |
    // [2..3] branch_ic2    : u16                                                                              |
    // [4..5] rotational_nf : u16                                                                              |
    //                                                                                                         |
    // unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                  |
    // footprint: per instance = 6 B (0.006 KiB); total = per instance * live instance count                   |
    pub const VendorO2ABranchMetadata = struct {
        branch_ic1: u16,
        branch_ic2: u16,
        rotational_nf: u16,
    };

    // ParsedVendorO2ABranchMetadata --------------------------------------------------------------------------|
    // Working row used while choosing inline or fallback HITRAN O2 A branch metadata.                         |
    //                                                                                                         |
    // layout(64-bit)                                                                                          |
    // size: 14 B (0.014 KiB), align: 2 B                                                                      |
    //                                                                                                         |
    // memory                                                                                                  |
    // [ 0.. 3] branch_ic1                 : ?u16                                                              |
    // [ 4.. 7] branch_ic2                 : ?u16                                                              |
    // [ 8..11] rotational_nf              : ?u16                                                              |
    // [12..12] from_inline_vendor_fields  : bool                                                              |
    // [13..13] padding                    : 1 B                                                               |
    //                                                                                                         |
    // unused bits: 8 padding + 7 bool-storage slack = 15 bits                                                 |
    // footprint: per instance = 14 B (0.014 KiB); stack/local row                                             |
    pub const ParsedVendorO2ABranchMetadata = struct {
        branch_ic1: ?u16 = null,
        branch_ic2: ?u16 = null,
        rotational_nf: ?u16 = null,
        from_inline_vendor_fields: bool = false,

        pub fn fromBranchMetadata(metadata: VendorO2ABranchMetadata) ParsedVendorO2ABranchMetadata {
            return .{
                .branch_ic1 = metadata.branch_ic1,
                .branch_ic2 = metadata.branch_ic2,
                .rotational_nf = metadata.rotational_nf,
            };
        }
    };

    pub fn inlineVendorO2ABranchMetadata(
        has_inline_vendor_fields: bool,
        line: []const u8,
    ) !ParsedVendorO2ABranchMetadata {
        if (!has_inline_vendor_fields) return .{};

        const branch_ic1 = try parseOptionalFixedInt(line[67..70]);
        const branch_ic2 = try parseOptionalFixedInt(line[70..73]);
        const rotational_nf = try parseOptionalFixedInt(line[83..85]);

        return .{
            .branch_ic1 = branch_ic1,
            .branch_ic2 = branch_ic2,
            .rotational_nf = rotational_nf,
            .from_inline_vendor_fields = branch_ic1 != null and
                branch_ic2 != null and
                rotational_nf != null,
        };
    }

    pub fn fallbackVendorO2ABranchMetadata(line: []const u8, center_wavenumber_cm1: f64) !?VendorO2ABranchMetadata {
        if (center_wavenumber_cm1 < 12800.0 or center_wavenumber_cm1 > 13250.0) return null;

        var tokens = std.mem.tokenizeAny(u8, line, " \t");
        while (tokens.next()) |branch_token| {
            if (branch_token.len != 1 or branch_token[0] != 'P') continue;

            const upper_token = tokens.next() orelse return null;
            const lower_token = tokens.next() orelse return null;

            if (upper_token.len < 2) return null;

            const branch_kind = upper_token[upper_token.len - 1];
            if (branch_kind != 'P' and branch_kind != 'Q') return null;

            const rotational_prefix = upper_token[0 .. upper_token.len - 1];
            if (rotational_prefix.len == 0) return null;

            const upper_nf = std.fmt.parseInt(u16, rotational_prefix, 10) catch return error.InvalidNumber;
            const lower_nf = std.fmt.parseInt(u16, lower_token, 10) catch return error.InvalidNumber;

            if (upper_nf == 0 or upper_nf > 35 or (upper_nf % 2) == 0) return null;
            if (!(lower_nf == upper_nf or lower_nf + 1 == upper_nf)) return null;

            return .{
                .branch_ic1 = 5,
                .branch_ic2 = 1,
                .rotational_nf = upper_nf,
            };
        }
        return null;
    }
};

// AssetSpec --------------------------------------------------------------------------------------------------|
// Borrowed manifest instruction for one parser call.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] format  : []const u8                                                                               |
// [16..31] columns : []const []const u8                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   format and columns point at manifest-owned strings.                                                       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total also includes referenced storage above                    |
pub const AssetSpec = struct {
    format: []const u8,
    columns: []const []const u8,
};

// ParsedTable ------------------------------------------------------------------------------------------------|
// Owned row-major numeric table emitted by a format parser.                                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] column_names : []const []const u8                                                                  |
// [16..31] values       : []f64                                                                               |
// [32..35] row_count    : u32                                                                                 |
// [36..39] padding      : 4 B                                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   column_names and values are owned out-of-line buffers returned to the caller.                             |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 40 B (0.039 KiB); total also includes referenced storage above                    |
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

            const trimmed_token = helpers.trimWhitespace(token);
            const value = std.fmt.parseFloat(f64, trimmed_token) catch return error.InvalidNumber;
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

fn parseHitran160(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const emit_source_cm1_fields = helpers.columnNamesContain(columns, "center_wavenumber_cm1");
    const has_vendor_o2a_fields = helpers.columnNamesContain(columns, "vendor_filter_metadata_from_source");
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

        // The fixed-width cm^-1 fields are converted to the nm values expected by the typed
        // spectroscopy loader.
        const center_wavelength_nm = helpers.wavenumberToWavelengthNm(center_wavenumber_cm1);
        const air_half_width_nm = helpers.spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1);
        const pressure_shift_nm = -helpers.spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1);
        const line_mixing_coefficient = helpers.deriveLineMixingCoefficient(
            air_half_width_cm1,
            pressure_shift_cm1,
        );

        const inline_vendor_metadata = try helpers.inlineVendorO2ABranchMetadata(
            has_inline_vendor_fields,
            line,
        );
        const inline_vendor_metadata_absent = inline_vendor_metadata.branch_ic1 == null and
            inline_vendor_metadata.branch_ic2 == null and
            inline_vendor_metadata.rotational_nf == null;

        const fallback_vendor_metadata = if (has_vendor_o2a_fields and inline_vendor_metadata_absent)
            try helpers.fallbackVendorO2ABranchMetadata(line, center_wavenumber_cm1)
        else
            null;

        const vendor_metadata = if (fallback_vendor_metadata) |metadata|
            helpers.ParsedVendorO2ABranchMetadata.fromBranchMetadata(metadata)
        else
            inline_vendor_metadata;

        try values.appendSlice(allocator, &.{
            @as(f64, @floatFromInt(gas_index)),
            @as(f64, @floatFromInt(isotope_number)),
            helpers.deriveIsotopicAbundanceFraction(gas_index, isotope_number),
            center_wavelength_nm,
        });

        if (emit_source_cm1_fields) {
            try values.append(allocator, center_wavenumber_cm1);
        }

        try values.appendSlice(allocator, &.{
            line_strength,
            air_half_width_nm,
        });

        if (emit_source_cm1_fields) {
            try values.append(allocator, air_half_width_cm1);
        }

        try values.appendSlice(allocator, &.{
            temperature_exponent,
            lower_state_energy_cm1,
            pressure_shift_nm,
        });

        if (emit_source_cm1_fields) {
            try values.append(allocator, pressure_shift_cm1);
        }

        try values.appendSlice(allocator, &.{
            line_mixing_coefficient,
        });

        if (has_vendor_o2a_fields) {
            try values.appendSlice(allocator, &.{
                helpers.optionalU16ToTableValue(vendor_metadata.branch_ic1),
                helpers.optionalU16ToTableValue(vendor_metadata.branch_ic2),
                helpers.optionalU16ToTableValue(vendor_metadata.rotational_nf),
                if (vendor_metadata.from_inline_vendor_fields) 1.0 else 0.0,
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
        const a0_token = token_iter.next() orelse return error.InvalidAssetFormat;
        const a1_token = token_iter.next() orelse return error.InvalidAssetFormat;
        const a2_token = token_iter.next() orelse return error.InvalidAssetFormat;

        const a0 = std.fmt.parseFloat(f64, a0_token) catch return error.InvalidNumber;
        const a1 = std.fmt.parseFloat(f64, a1_token) catch return error.InvalidNumber;
        const a2 = std.fmt.parseFloat(f64, a2_token) catch return error.InvalidNumber;

        // Preserve the vendor row layout exactly by carrying the file-scoped scale factor with each row.
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
        const rotational_index_m1 = helpers.rotationalIndexFromLisaBranch(
            branch_token,
            nf_token,
        ) catch return error.InvalidAssetFormat;

        // Parse HWT0 only to reject malformed rows. HITRANModule::readSDF reconstructs the reference
        // half-width from the LISA branch/Nf numbers before any temperature scaling happens.
        _ = try helpers.parseFixedFloat(line[58..63]);
        const air_half_width_cm1 = helpers.vendorLisaReferenceHalfWidthCm1(
            branch_token,
            nf_token,
        ) catch return error.InvalidAssetFormat;

        // Strong-line fields are stored in cm^-1 and converted to nm where the typed loader expects
        // wavelength-like values.
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
