const std = @import("std");

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

pub const VendorO2ABranchMetadata = struct {
    branch_ic1: u16,
    branch_ic2: u16,
    rotational_nf: u16,
};

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
