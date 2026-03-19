const std = @import("std");

pub const AssetSpec = struct {
    format: []const u8,
    columns: []const []const u8,
};

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
        const line = trimWhitespace(raw_line);
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
        const name = try allocator.dupe(u8, trimWhitespace(token));
        errdefer allocator.free(name);
        try header_names.append(allocator, name);
    }
    if (header_names.items.len == 0) return error.InvalidCsv;

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    while (line_iter.next()) |raw_line| {
        const line = trimWhitespace(raw_line);
        if (line.len == 0) continue;

        var token_iter = std.mem.splitScalar(u8, line, ',');
        var column_index: usize = 0;
        while (token_iter.next()) |token| {
            if (column_index >= header_names.items.len) return error.InvalidCsv;
            const value = std.fmt.parseFloat(f64, trimWhitespace(token)) catch return error.InvalidNumber;
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
    const owned_columns = try dupColumns(allocator, columns);
    errdefer freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const stripped = trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 67) return error.InvalidAssetFormat;

        const gas_index = try parseFixedInt(line[0..2]);
        const isotope_number = try parseFixedInt(line[2..3]);
        const center_wavenumber_cm1 = try parseFixedFloat(line[3..15]);
        const line_strength = try parseFixedFloat(line[15..25]);
        const air_half_width_cm1 = try parseFixedFloat(line[35..40]);
        const lower_state_energy_cm1 = try parseFixedFloat(line[45..55]);
        const temperature_exponent = try parseFixedFloat(line[55..59]);
        const pressure_shift_cm1 = try parseFixedFloat(line[59..67]);

        const center_wavelength_nm = wavenumberToWavelengthNm(center_wavenumber_cm1);
        const air_half_width_nm = spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1);
        const pressure_shift_nm = -spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1);
        const line_mixing_coefficient = deriveLineMixingCoefficient(air_half_width_cm1, pressure_shift_cm1);

        try values.appendSlice(allocator, &.{
            @as(f64, @floatFromInt(gas_index)),
            @as(f64, @floatFromInt(isotope_number)),
            deriveIsotopicAbundanceFraction(gas_index, isotope_number),
            center_wavelength_nm,
            line_strength,
            air_half_width_nm,
            temperature_exponent,
            lower_state_energy_cm1,
            pressure_shift_nm,
            line_mixing_coefficient,
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

fn parseBiraCiaPolynomial(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) Error!ParsedTable {
    const owned_columns = try dupColumns(allocator, columns);
    errdefer freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    var numeric_header_index: usize = 0;
    var scale_factor: f64 = 0.0;
    var expected_data_rows: ?u32 = null;
    var row_count: u32 = 0;

    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const stripped = trimWhitespace(line);
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
    const owned_columns = try dupColumns(allocator, columns);
    errdefer freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const stripped = trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 87) return error.InvalidAssetFormat;

        const center_wavenumber_cm1 = try parseFixedFloat(line[0..12]);
        const population_t0 = try parseFixedFloat(line[14..23]);
        const dipole_ratio = try parseFixedFloat(line[25..34]);
        const dipole_t0 = try parseFixedFloat(line[35..44]);
        const lower_state_energy_cm1 = try parseFixedFloat(line[46..56]);
        const air_half_width_cm1 = try parseFixedFloat(line[58..63]);
        const temperature_exponent = try parseFixedFloat(line[65..69]);
        const pressure_shift_cm1 = try parseFixedFloat(line[71..79]);
        const rotational_index_m1 = rotationalIndexFromLisaBranch(
            trimWhitespace(line[83..84]),
            trimWhitespace(line[84..87]),
        ) catch return error.InvalidAssetFormat;

        const center_wavelength_nm = wavenumberToWavelengthNm(center_wavenumber_cm1);
        const air_half_width_nm = spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1);
        const pressure_shift_nm = -spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1);

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
    const owned_columns = try dupColumns(allocator, columns);
    errdefer freeColumns(allocator, owned_columns);

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const stripped = trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 31) return error.InvalidAssetFormat;

        try values.append(allocator, try parseFixedFloat(line[0..15]));
        try values.append(allocator, try parseFixedFloat(line[15..31]));
        row_count += 1;
    }
    if (row_count == 0) return error.InvalidAssetFormat;

    return .{
        .column_names = owned_columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

fn dupColumns(allocator: std.mem.Allocator, columns: []const []const u8) Error![]const []const u8 {
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

fn freeColumns(allocator: std.mem.Allocator, columns: []const []const u8) void {
    for (columns) |column| allocator.free(column);
    allocator.free(columns);
}

fn parseFixedFloat(slice: []const u8) Error!f64 {
    return std.fmt.parseFloat(f64, trimWhitespace(slice)) catch error.InvalidNumber;
}

fn parseFixedInt(slice: []const u8) Error!u16 {
    return std.fmt.parseInt(u16, trimWhitespace(slice), 10) catch error.InvalidNumber;
}

fn trimWhitespace(value: []const u8) []const u8 {
    return std.mem.trim(u8, value, " \t\r");
}

fn trimLineEnding(value: []const u8) []const u8 {
    return std.mem.trimRight(u8, value, "\r");
}

fn wavenumberToWavelengthNm(wavenumber_cm1: f64) f64 {
    return 1.0e7 / @max(wavenumber_cm1, 1.0);
}

fn spectralWidthCm1ToNm(width_cm1: f64, center_wavenumber_cm1: f64) f64 {
    const safe_center = @max(center_wavenumber_cm1, 1.0);
    return width_cm1 * 1.0e7 / (safe_center * safe_center);
}

fn deriveLineMixingCoefficient(air_half_width_cm1: f64, pressure_shift_cm1: f64) f64 {
    return std.math.clamp(
        @abs(pressure_shift_cm1) / @max(@abs(air_half_width_cm1), 1.0e-6),
        0.0,
        0.15,
    );
}

fn deriveIsotopicAbundanceFraction(gas_index: u16, isotope_number: u16) f64 {
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

fn rotationalIndexFromLisaBranch(branch_token: []const u8, nf_token: []const u8) !i32 {
    if (branch_token.len != 1) return error.InvalidAssetFormat;
    const nf = std.fmt.parseInt(i32, nf_token, 10) catch return error.InvalidNumber;
    return switch (branch_token[0]) {
        'P' => -nf,
        'R' => nf + 1,
        else => return error.InvalidAssetFormat,
    };
}
