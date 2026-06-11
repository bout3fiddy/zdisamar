const std = @import("std");

const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

const Allocator = std.mem.Allocator;

// readers.zig ------------------------------------------------------------------------------------------------|
// Asset readers for WP2 setup tables.                                                                         |
//                                                                                                             |
// file boundary                                                                                               |
//   Runtime file I/O and text parsing live here. Setup builders call these functions before table assembly.   |
//   on typed rows.                                                                                            |
//                                                                                                             |
// supported formats                                                                                           |
//   profile_csv         : altitude, pressure, temperature, air-number-density CSV rows                        |
//   hitran_par_o2a      : fixed-width HITRAN line rows for the O2 A line list                                 |
//   bira_cia            : BIRA O2-O2 polynomial table with scale/header rows                                  |
//   solar_reference_csv : wavelength, irradiance CSV rows                                                     |
// ------------------------------------------------------------------------------------------------------------|

// AtmosphereProfileRow ---------------------------------------------------------------------------------------|
// One parsed vertical profile support row.                                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km            : f64                                                                       |
// [ 8..15] pressure_hpa           : f64                                                                       |
// [16..23] temperature_k          : f64                                                                       |
// [24..31] air_number_density_cm3 : f64                                                                       |
pub const AtmosphereProfileRow = struct {
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    air_number_density_cm3: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// O2LineAssetRow ---------------------------------------------------------------------------------------------|
// Parsed HITRAN line row fields needed by WP2 setup.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.063 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] center_wavelength_nm          : f64                                                                |
// [ 8..15] center_wavenumber_cm1         : f64                                                                |
// [16..23] line_strength_cm2_per_molecule: f64                                                                |
// [24..31] air_half_width_cm1            : f64                                                                |
// [32..39] lower_state_energy_cm1        : f64                                                                |
// [40..47] temperature_exponent          : f64                                                                |
// [48..55] pressure_shift_cm1            : f64                                                                |
// [56..57] gas_index                     : u16                                                                |
// [58..58] isotope_number                : u8                                                                 |
// [59..63] trailing padding              : 5 B                                                                |
pub const O2LineAssetRow = struct {
    gas_index: u16,
    isotope_number: u8,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_cm1: f64,
    lower_state_energy_cm1: f64,
    temperature_exponent: f64,
    pressure_shift_cm1: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// CiaAsset ---------------------------------------------------------------------------------------------------|
// Owner for the BIRA CIA coefficient table returned by the reader.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scale_factor_cm5_per_molecule2 : f64                                                               |
// [ 8..23] rows                           : []CiaAssetRow                                                     |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed coefficient rows and is released by deinit.                                              |
pub const CiaAsset = struct {
    scale_factor_cm5_per_molecule2: f64,
    rows: []CiaAssetRow,

    pub fn deinit(self: *CiaAsset, allocator: Allocator) void {
        // CiaAsset.deinit ------------------------------------------------------------------------------------|
        // Release parsed CIA rows owned by this reader result.                                                |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// CiaAssetRow ------------------------------------------------------------------------------------------------|
// One CIA polynomial coefficient row.                                                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm : f64                                                                                |
// [ 8..15] a0            : f64                                                                                |
// [16..23] a1            : f64                                                                                |
// [24..31] a2            : f64                                                                                |
pub const CiaAssetRow = struct {
    wavelength_nm: f64,
    a0: f64,
    a1: f64,
    a2: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// SolarAssetRow ----------------------------------------------------------------------------------------------|
// One solar irradiance row.                                                                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm : f64                                                                                 |
// [8..15] irradiance    : f64                                                                                 |
pub const SolarAssetRow = struct {
    wavelength_nm: f64,
    irradiance: f64,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn readAtmosphereProfile(allocator: Allocator, path: []const u8) ![]AtmosphereProfileRow {
    // readAtmosphereProfile ----------------------------------------------------------------------------------|
    // Load altitude, pressure, temperature, and air-density CSV rows into one owned slice.                    |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 1 << 20);
    defer allocator.free(bytes);

    var rows = std.ArrayList(AtmosphereProfileRow).empty;
    errdefer rows.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = trimLine(line);
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        try rows.append(allocator, .{
            .altitude_km = try parseCsvFloat(columns.next()),
            .pressure_hpa = try parseCsvFloat(columns.next()),
            .temperature_k = try parseCsvFloat(columns.next()),
            .air_number_density_cm3 = try parseCsvFloat(columns.next()),
        });
    }

    if (rows.items.len == 0) return errors.Error.EmptyAsset;
    return rows.toOwnedSlice(allocator);
}

pub fn readO2LineList(allocator: Allocator, path: []const u8) ![]O2LineAssetRow {
    // readO2LineList -----------------------------------------------------------------------------------------|
    // Parse fixed-width HITRAN rows while preserving leading spaces for gas/isotope columns.                  |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 4 << 20);
    defer allocator.free(bytes);

    var rows = std.ArrayList(O2LineAssetRow).empty;
    errdefer rows.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const row = std.mem.trimRight(u8, line, "\r");
        if (trimLine(row).len == 0) continue;
        if (row.len < 67) return errors.Error.InvalidAssetFormat;

        const gas_index = try parseFixedInt(u16, row[0..2]);
        const isotope_number = try parseFixedInt(u8, row[2..3]);
        const center_wavenumber_cm1 = try parseFixedFloat(row[3..15]);
        const air_half_width_cm1 = try parseFixedFloat(row[35..40]);
        const pressure_shift_cm1 = try parseFixedFloat(row[59..67]);

        try rows.append(allocator, .{
            .gas_index = gas_index,
            .isotope_number = isotope_number,
            .center_wavelength_nm = units.wavenumberToWavelengthNm(center_wavenumber_cm1),
            .center_wavenumber_cm1 = center_wavenumber_cm1,
            .line_strength_cm2_per_molecule = try parseFixedFloat(row[15..25]),
            .air_half_width_cm1 = air_half_width_cm1,
            .lower_state_energy_cm1 = try parseFixedFloat(row[45..55]),
            .temperature_exponent = try parseFixedFloat(row[55..59]),
            .pressure_shift_cm1 = pressure_shift_cm1,
        });
    }

    if (rows.items.len == 0) return errors.Error.EmptyAsset;
    return rows.toOwnedSlice(allocator);
}

pub fn readCiaTable(allocator: Allocator, path: []const u8) !CiaAsset {
    // readCiaTable -------------------------------------------------------------------------------------------|
    // Parse the BIRA header scale and every numeric polynomial coefficient row into an owned table.           |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors main:`src/input/reference_data/ingest/reference_assets_formats.zig`                           |
    //   parseBiraCiaPolynomial: the vendor count is a lower-bound check, while appended O2 A rows after the   |
    //   nominal count are retained because the old optical route samples them at 758-776 nm.                  |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 4 << 20);
    defer allocator.free(bytes);

    var lines = std.mem.splitScalar(u8, bytes, '\n');

    var rows = std.ArrayList(CiaAssetRow).empty;
    defer rows.deinit(allocator);

    var numeric_header_index: usize = 0;
    var scale_factor: f64 = 0.0;
    var expected_data_rows: ?usize = null;

    while (lines.next()) |raw_line| {
        const line = trimLine(raw_line);
        if (line.len == 0 or line[0] == '#') continue;

        var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
        const first_token = tokens.next() orelse continue;
        if (first_token[0] == '!') continue;

        if (numeric_header_index < 3) {
            switch (numeric_header_index) {
                0 => scale_factor = try parseTokenFloat(first_token),
                1 => {},
                2 => expected_data_rows = try std.fmt.parseInt(usize, first_token, 10),
                else => unreachable,
            }
            numeric_header_index += 1;
            continue;
        }

        try rows.append(allocator, .{
            .wavelength_nm = try parseTokenFloat(first_token),
            .a0 = try parseTokenFloat(tokens.next()),
            .a1 = try parseTokenFloat(tokens.next()),
            .a2 = try parseTokenFloat(tokens.next()),
        });
    }

    if (numeric_header_index < 3 or rows.items.len == 0) return errors.Error.InvalidAssetFormat;
    if (expected_data_rows) |expected| {
        if (rows.items.len < expected) return errors.Error.InvalidAssetFormat;
    }

    return .{
        .scale_factor_cm5_per_molecule2 = scale_factor,
        .rows = try rows.toOwnedSlice(allocator),
    };
}

pub fn readSolarReference(allocator: Allocator, path: []const u8) ![]SolarAssetRow {
    // readSolarReference -------------------------------------------------------------------------------------|
    // Load wavelength and irradiance CSV rows for setup-time solar tables.                                    |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 1 << 20);
    defer allocator.free(bytes);

    var rows = std.ArrayList(SolarAssetRow).empty;
    errdefer rows.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    _ = lines.next();
    while (lines.next()) |line| {
        const trimmed = trimLine(line);
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        try rows.append(allocator, .{
            .wavelength_nm = try parseCsvFloat(columns.next()),
            .irradiance = try parseCsvFloat(columns.next()),
        });
    }

    if (rows.items.len == 0) return errors.Error.EmptyAsset;
    return rows.toOwnedSlice(allocator);
}

fn readSmallFile(allocator: Allocator, path: []const u8, max_size: usize) ![]u8 {
    // readSmallFile ------------------------------------------------------------------------------------------|
    // Read a bounded reference-data asset from the process working directory.                                 |
    // --------------------------------------------------------------------------------------------------------|
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return file.readToEndAlloc(allocator, max_size);
}

fn trimLine(line: []const u8) []const u8 {
    // trimLine -----------------------------------------------------------------------------------------------|
    // Remove CSV/free-text whitespace while fixed-width readers keep their own leading columns.               |
    // --------------------------------------------------------------------------------------------------------|
    return std.mem.trim(u8, line, " \t\r");
}

fn parseCsvFloat(value: ?[]const u8) !f64 {
    // parseCsvFloat ------------------------------------------------------------------------------------------|
    // Parse a required CSV numeric column.                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    return parseTokenFloat(value orelse return errors.Error.InvalidAssetFormat);
}

fn parseTokenFloat(value: ?[]const u8) !f64 {
    // parseTokenFloat ----------------------------------------------------------------------------------------|
    // Parse a required whitespace token as f64.                                                               |
    // --------------------------------------------------------------------------------------------------------|
    return std.fmt.parseFloat(f64, value orelse return errors.Error.InvalidAssetFormat) catch {
        return errors.Error.InvalidNumber;
    };
}

fn parseFixedFloat(value: []const u8) !f64 {
    // parseFixedFloat ----------------------------------------------------------------------------------------|
    // Parse a fixed-width numeric field after trimming field-local whitespace.                                |
    // --------------------------------------------------------------------------------------------------------|
    return std.fmt.parseFloat(f64, std.mem.trim(u8, value, " \t\r")) catch {
        return errors.Error.InvalidNumber;
    };
}

fn parseFixedInt(comptime T: type, value: []const u8) !T {
    // parseFixedInt ------------------------------------------------------------------------------------------|
    // Parse a fixed-width integer field into the caller-requested integer type.                               |
    // --------------------------------------------------------------------------------------------------------|
    return std.fmt.parseInt(T, std.mem.trim(u8, value, " \t\r"), 10) catch {
        return errors.Error.InvalidNumber;
    };
}

fn parseFirstFloat(line: []const u8) !f64 {
    // parseFirstFloat ----------------------------------------------------------------------------------------|
    // Parse the first token from a BIRA header row.                                                           |
    // --------------------------------------------------------------------------------------------------------|
    var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
    return parseTokenFloat(tokens.next());
}

fn parseFirstInteger(line: []const u8) !usize {
    // parseFirstInteger --------------------------------------------------------------------------------------|
    // Parse the first token from a BIRA count header row.                                                     |
    // --------------------------------------------------------------------------------------------------------|
    var tokens = std.mem.tokenizeAny(u8, line, " \t\r");
    return std.fmt.parseInt(usize, tokens.next() orelse return errors.Error.InvalidAssetFormat, 10) catch {
        return errors.Error.InvalidNumber;
    };
}
