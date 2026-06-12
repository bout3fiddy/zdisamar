const std = @import("std");

const errors = @import("../common/errors.zig");
const units = @import("../common/units.zig");

const Allocator = std.mem.Allocator;

// VendorO2ABranchMetadata ------------------------------------------------------------------------------------|
// Optional O2 A branch metadata used to partition weak lines from LISA strong-line sidecars.                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 7 B (0.007 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..1] branch_ic1 : ?u8                                                                                     |
// [2..3] branch_ic2 : ?u8                                                                                     |
// [4..5] rotational_nf : ?u8                                                                                  |
// [6..6] from_source : bool                                                                                   |
const VendorO2ABranchMetadata = struct {
    branch_ic1: ?u8 = null,
    branch_ic2: ?u8 = null,
    rotational_nf: ?u8 = null,
    from_source: bool = false,

    fn present(self: VendorO2ABranchMetadata) bool {
        // VendorO2ABranchMetadata.present --------------------------------------------------------------------|
        // True when all old O2 A branch fields were recovered from the HITRAN row.                            |
        // ----------------------------------------------------------------------------------------------------|
        return self.branch_ic1 != null and self.branch_ic2 != null and self.rotational_nf != null;
    }
};
// ------------------------------------------------------------------------------------------------------------|

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
//   lisa_sdf            : LISA/DISAMAR O2 strong-line sidecar rows                                            |
//   lisa_rmf            : LISA/DISAMAR O2 relaxation-matrix sidecar rows                                      |
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
// Parsed HITRAN line row fields needed by setup and O2 strong-line partitioning.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 72 B (0.070 KiB), align: 8 B                                                                          |
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
// [59..59] vendor_filter_metadata_from_source : bool                                                          |
// [60..61] branch_ic1                    : ?u8                                                                |
// [62..63] branch_ic2                    : ?u8                                                                |
// [64..65] rotational_nf                 : ?u8                                                                |
// [66..71] trailing padding              : 6 B                                                                |
pub const O2LineAssetRow = struct {
    gas_index: u16,
    isotope_number: u8,
    vendor_filter_metadata_from_source: bool = false,
    center_wavelength_nm: f64,
    center_wavenumber_cm1: f64,
    line_strength_cm2_per_molecule: f64,
    air_half_width_cm1: f64,
    lower_state_energy_cm1: f64,
    temperature_exponent: f64,
    pressure_shift_cm1: f64,
    branch_ic1: ?u8 = null,
    branch_ic2: ?u8 = null,
    rotational_nf: ?u8 = null,
};
// ------------------------------------------------------------------------------------------------------------|

// O2StrongLineAssetRow ---------------------------------------------------------------------------------------|
// Parsed LISA SDF strong-line sidecar row used by the old O2 line-mixing route.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] center_wavenumber_cm1 : f64                                                                        |
// [ 8..15] center_wavelength_nm  : f64                                                                        |
// [16..23] population_t0         : f64                                                                        |
// [24..31] dipole_ratio          : f64                                                                        |
// [32..39] dipole_t0             : f64                                                                        |
// [40..47] lower_state_energy_cm1: f64                                                                        |
// [48..55] air_half_width_cm1    : f64                                                                        |
// [56..63] air_half_width_nm     : f64                                                                        |
// [64..71] temperature_exponent  : f64                                                                        |
// [72..79] pressure_shift_cm1    : f64                                                                        |
// [80..87] pressure_shift_nm     : f64                                                                        |
// [88..91] rotational_index_m1   : i32                                                                        |
// [92..95] trailing padding      : 4 B                                                                        |
pub const O2StrongLineAssetRow = struct {
    center_wavenumber_cm1: f64,
    center_wavelength_nm: f64,
    population_t0: f64,
    dipole_ratio: f64,
    dipole_t0: f64,
    lower_state_energy_cm1: f64,
    air_half_width_cm1: f64,
    air_half_width_nm: f64,
    temperature_exponent: f64,
    pressure_shift_cm1: f64,
    pressure_shift_nm: f64,
    rotational_index_m1: i32,
};
// ------------------------------------------------------------------------------------------------------------|

// O2RelaxationMatrixAsset ------------------------------------------------------------------------------------|
// Parsed LISA RMF relaxation matrix used by the old O2 line-mixing route.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] line_count : usize                                                                                 |
// [ 8..23] wt0        : []f64                                                                                 |
// [24..39] bw         : []f64                                                                                 |
//                                                                                                             |
// referenced storage                                                                                          |
//   wt0 and bw own line_count * line_count f64 values and are released by deinit.                             |
pub const O2RelaxationMatrixAsset = struct {
    line_count: usize,
    wt0: []f64,
    bw: []f64,

    pub fn deinit(self: *O2RelaxationMatrixAsset, allocator: Allocator) void {
        // O2RelaxationMatrixAsset.deinit ---------------------------------------------------------------------|
        // Release parsed RMF matrices owned by this reader result.                                            |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.wt0);
        allocator.free(self.bw);
        self.* = undefined;
    }

    pub fn weightAt(self: O2RelaxationMatrixAsset, row: usize, column: usize) f64 {
        // O2RelaxationMatrixAsset.weightAt -------------------------------------------------------------------|
        // Return the row-major W(T0) relaxation weight.                                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.wt0[row * self.line_count + column];
    }

    pub fn temperatureExponentAt(self: O2RelaxationMatrixAsset, row: usize, column: usize) f64 {
        // O2RelaxationMatrixAsset.temperatureExponentAt ------------------------------------------------------|
        // Return the row-major BW temperature exponent.                                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.bw[row * self.line_count + column];
    }
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
        const inline_metadata = try inlineVendorO2ABranchMetadata(row);
        const fallback_metadata = if (!inline_metadata.present())
            try fallbackVendorO2ABranchMetadata(row, center_wavenumber_cm1)
        else
            null;
        const vendor_metadata = fallback_metadata orelse inline_metadata;

        try rows.append(allocator, .{
            .gas_index = gas_index,
            .isotope_number = isotope_number,
            .vendor_filter_metadata_from_source = vendor_metadata.from_source,
            .center_wavelength_nm = units.wavenumberToWavelengthNm(center_wavenumber_cm1),
            .center_wavenumber_cm1 = center_wavenumber_cm1,
            .line_strength_cm2_per_molecule = try parseFixedFloat(row[15..25]),
            .air_half_width_cm1 = air_half_width_cm1,
            .lower_state_energy_cm1 = try parseFixedFloat(row[45..55]),
            .temperature_exponent = try parseFixedFloat(row[55..59]),
            .pressure_shift_cm1 = pressure_shift_cm1,
            .branch_ic1 = vendor_metadata.branch_ic1,
            .branch_ic2 = vendor_metadata.branch_ic2,
            .rotational_nf = vendor_metadata.rotational_nf,
        });
    }

    if (rows.items.len == 0) return errors.Error.EmptyAsset;
    return rows.toOwnedSlice(allocator);
}

pub fn readO2StrongLines(allocator: Allocator, path: []const u8) ![]O2StrongLineAssetRow {
    // readO2StrongLines --------------------------------------------------------------------------------------|
    // Parse LISA SDF rows into old O2 strong-line sidecar fields.                                             |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors main:`src/input/reference_data/ingest/reference_assets_formats.zig` parseLisaSdf.             |
    //   The vendor HWT0 column is syntax-checked. The reference half-width is reconstructed from the LISA     |
    //   branch token and Nf value, matching old HITRANModule::readSDF behavior.                               |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 1 << 20);
    defer allocator.free(bytes);

    var rows = std.ArrayList(O2StrongLineAssetRow).empty;
    errdefer rows.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        const stripped = trimLine(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 87) return errors.Error.InvalidAssetFormat;

        const center_wavenumber_cm1 = try parseFixedFloat(line[0..12]);
        const branch_token = trimLine(line[83..84]);
        const nf_token = trimLine(line[84..87]);
        const air_half_width_cm1 = try vendorLisaReferenceHalfWidthCm1(branch_token, nf_token);
        const pressure_shift_cm1 = try parseFixedFloat(line[71..79]);

        _ = try parseFixedFloat(line[58..63]);

        try rows.append(allocator, .{
            .center_wavenumber_cm1 = center_wavenumber_cm1,
            .center_wavelength_nm = units.wavenumberToWavelengthNm(center_wavenumber_cm1),
            .population_t0 = try parseFixedFloat(line[14..23]),
            .dipole_ratio = try parseFixedFloat(line[25..34]),
            .dipole_t0 = try parseFixedFloat(line[35..44]),
            .lower_state_energy_cm1 = try parseFixedFloat(line[46..56]),
            .air_half_width_cm1 = air_half_width_cm1,
            .air_half_width_nm = units.spectralWidthCm1ToNm(air_half_width_cm1, center_wavenumber_cm1),
            .temperature_exponent = try parseFixedFloat(line[65..69]),
            .pressure_shift_cm1 = pressure_shift_cm1,
            .pressure_shift_nm = -units.spectralWidthCm1ToNm(pressure_shift_cm1, center_wavenumber_cm1),
            .rotational_index_m1 = try rotationalIndexFromLisaBranch(branch_token, nf_token),
        });
    }

    if (rows.items.len == 0) return errors.Error.EmptyAsset;
    return rows.toOwnedSlice(allocator);
}

pub fn readO2RelaxationMatrix(allocator: Allocator, path: []const u8) !O2RelaxationMatrixAsset {
    // readO2RelaxationMatrix ---------------------------------------------------------------------------------|
    // Parse the LISA RMF sidecar into row-major W(T0) and BW matrices.                                        |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Mirrors main:`src/input/reference_data/ingest/reference_assets_formats.zig` parseLisaRmf and          |
    //   LoadedAsset.toSpectroscopyRelaxationMatrix. The row count must form a square dense matrix.            |
    // --------------------------------------------------------------------------------------------------------|
    const bytes = try readSmallFile(allocator, path, 1 << 20);
    defer allocator.free(bytes);

    var wt0 = std.ArrayList(f64).empty;
    errdefer wt0.deinit(allocator);
    var bw = std.ArrayList(f64).empty;
    errdefer bw.deinit(allocator);

    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |raw_line| {
        const line = std.mem.trimRight(u8, raw_line, "\r");
        const stripped = trimLine(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 31) return errors.Error.InvalidAssetFormat;

        try wt0.append(allocator, try parseFixedFloat(line[0..15]));
        try bw.append(allocator, try parseFixedFloat(line[15..31]));
    }

    if (wt0.items.len == 0 or wt0.items.len != bw.items.len) return errors.Error.EmptyAsset;

    const line_count_f = @sqrt(@as(f64, @floatFromInt(wt0.items.len)));
    const line_count: usize = @intFromFloat(@round(line_count_f));
    if (line_count * line_count != wt0.items.len) return errors.Error.InvalidAssetFormat;

    const owned_wt0 = try wt0.toOwnedSlice(allocator);
    errdefer allocator.free(owned_wt0);
    const owned_bw = try bw.toOwnedSlice(allocator);

    return .{
        .line_count = line_count,
        .wt0 = owned_wt0,
        .bw = owned_bw,
    };
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

fn parseOptionalFixedInt(comptime T: type, value: []const u8) !?T {
    // parseOptionalFixedInt ----------------------------------------------------------------------------------|
    // Parse an optional fixed-width integer field, returning null for blank vendor fields.                    |
    // --------------------------------------------------------------------------------------------------------|
    const trimmed = std.mem.trim(u8, value, " \t\r");
    if (trimmed.len == 0) return null;
    return std.fmt.parseInt(T, trimmed, 10) catch {
        return errors.Error.InvalidNumber;
    };
}

fn inlineVendorO2ABranchMetadata(line: []const u8) !VendorO2ABranchMetadata {
    // inlineVendorO2ABranchMetadata --------------------------------------------------------------------------|
    // Recover optional old O2 A branch metadata from fixed HITRAN vendor columns when present.                |
    // --------------------------------------------------------------------------------------------------------|
    if (line.len < 85) return .{};

    const branch_ic1 = try parseOptionalFixedInt(u8, line[67..70]);
    const branch_ic2 = try parseOptionalFixedInt(u8, line[70..73]);
    const rotational_nf = try parseOptionalFixedInt(u8, line[83..85]);
    return .{
        .branch_ic1 = branch_ic1,
        .branch_ic2 = branch_ic2,
        .rotational_nf = rotational_nf,
        .from_source = branch_ic1 != null and branch_ic2 != null and rotational_nf != null,
    };
}

fn fallbackVendorO2ABranchMetadata(line: []const u8, center_wavenumber_cm1: f64) !?VendorO2ABranchMetadata {
    // fallbackVendorO2ABranchMetadata ------------------------------------------------------------------------|
    // Reconstruct old O2 A P-branch metadata from trailing branch tokens when fixed fields are absent.        |
    // --------------------------------------------------------------------------------------------------------|
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

        const upper_nf = std.fmt.parseInt(u8, rotational_prefix, 10) catch return errors.Error.InvalidNumber;
        const lower_nf = std.fmt.parseInt(u8, lower_token, 10) catch return errors.Error.InvalidNumber;
        if (upper_nf == 0 or upper_nf > 35 or (upper_nf % 2) == 0) return null;
        if (!(lower_nf == upper_nf or lower_nf + 1 == upper_nf)) return null;

        return .{
            .branch_ic1 = 5,
            .branch_ic2 = 1,
            .rotational_nf = upper_nf,
            .from_source = false,
        };
    }
    return null;
}

fn rotationalIndexFromLisaBranch(branch_token: []const u8, nf_token: []const u8) !i32 {
    // rotationalIndexFromLisaBranch --------------------------------------------------------------------------|
    // Reconstruct the signed LISA branch index: P(Nf) stores -Nf, R(Nf) stores Nf + 1.                        |
    // --------------------------------------------------------------------------------------------------------|
    if (branch_token.len != 1) return errors.Error.InvalidAssetFormat;

    const nf = std.fmt.parseInt(i32, nf_token, 10) catch return errors.Error.InvalidNumber;
    return switch (branch_token[0]) {
        'P' => -nf,
        'R' => nf + 1,
        else => return errors.Error.InvalidAssetFormat,
    };
}

fn vendorLisaReferenceHalfWidthCm1(branch_token: []const u8, nf_token: []const u8) !f64 {
    // vendorLisaReferenceHalfWidthCm1 ------------------------------------------------------------------------|
    // Port the old LISA SDF half-width reconstruction before strong-line temperature scaling.                 |
    // --------------------------------------------------------------------------------------------------------|
    if (branch_token.len != 1) return errors.Error.InvalidAssetFormat;

    const raw_nf = std.fmt.parseInt(i32, nf_token, 10) catch return errors.Error.InvalidNumber;
    const vendor_nf = switch (branch_token[0]) {
        'P' => raw_nf - 1,
        'R' => raw_nf + 1,
        else => return errors.Error.InvalidAssetFormat,
    };

    const vendor_nf_f64 = @as(f64, @floatFromInt(vendor_nf));
    const sbhw = 0.02204 + 0.03749 /
        (1.0 + 0.05428 * vendor_nf_f64 - 1.19e-3 * vendor_nf_f64 * vendor_nf_f64 +
            2.073e-6 * std.math.pow(f64, vendor_nf_f64, 4.0));

    return 1.023 * 1.012 * sbhw /
        @sqrt(1.0 + std.math.pow(f64, (vendor_nf_f64 - 5.0) / 55.0, 2.0));
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
