const std = @import("std");
const Engine = @import("../../core/Engine.zig").Engine;
const ReferenceData = @import("../../model/ReferenceData.zig");

pub const AssetKind = enum {
    climatology_profile,
    cross_section_table,
    spectroscopy_line_list,
    lookup_table,
};

pub const LoadedAsset = struct {
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    bundle_id: []const u8,
    owner_package: []const u8,
    asset_id: []const u8,
    asset_path: []const u8,
    dataset_id: []const u8,
    dataset_hash: []const u8,
    column_names: []const []const u8,
    values: []f64,
    row_count: u32,

    pub fn deinit(self: *LoadedAsset, allocator: std.mem.Allocator) void {
        allocator.free(self.bundle_manifest_path);
        allocator.free(self.bundle_id);
        allocator.free(self.owner_package);
        allocator.free(self.asset_id);
        allocator.free(self.asset_path);
        allocator.free(self.dataset_id);
        allocator.free(self.dataset_hash);
        for (self.column_names) |column_name| allocator.free(column_name);
        allocator.free(self.column_names);
        allocator.free(self.values);
        self.* = undefined;
    }

    pub fn columnCount(self: LoadedAsset) usize {
        return self.column_names.len;
    }

    pub fn value(self: LoadedAsset, row_index: usize, column_index: usize) f64 {
        return self.values[row_index * self.column_names.len + column_index];
    }

    pub fn registerWithEngine(self: LoadedAsset, engine: *Engine) !void {
        try engine.registerDatasetArtifact(self.dataset_id, self.dataset_hash);
        if (self.kind == .lookup_table) {
            try engine.registerLUTArtifact(self.dataset_id, self.asset_id, .{
                .spectral_bins = self.row_count,
                .layer_count = 0,
                .coefficient_count = @intCast(if (self.columnCount() > 0) self.columnCount() - 1 else 0),
            });
        }
    }

    pub fn toClimatologyProfile(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.ClimatologyProfile {
        if (self.kind != .climatology_profile or self.columnCount() != 4) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "altitude_km",
            "pressure_hpa",
            "temperature_k",
            "air_number_density_cm3",
        });

        const rows = try allocator.alloc(ReferenceData.ClimatologyPoint, self.row_count);
        errdefer allocator.free(rows);

        for (rows, 0..) |*row, index| {
            row.* = .{
                .altitude_km = self.value(index, 0),
                .pressure_hpa = self.value(index, 1),
                .temperature_k = self.value(index, 2),
                .air_number_density_cm3 = self.value(index, 3),
            };
        }

        return .{ .rows = rows };
    }

    pub fn toCrossSectionTable(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.CrossSectionTable {
        if (self.kind != .cross_section_table or self.columnCount() != 2) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "wavelength_nm",
            "no2_sigma_cm2_per_molecule",
        });

        const points = try allocator.alloc(ReferenceData.CrossSectionPoint, self.row_count);
        errdefer allocator.free(points);

        for (points, 0..) |*point, index| {
            point.* = .{
                .wavelength_nm = self.value(index, 0),
                .sigma_cm2_per_molecule = self.value(index, 1),
            };
        }

        return .{ .points = points };
    }

    pub fn toSpectroscopyLineList(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
        if (self.kind != .spectroscopy_line_list or self.columnCount() != 7) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "center_wavelength_nm",
            "line_strength_cm2_per_molecule",
            "air_half_width_nm",
            "temperature_exponent",
            "lower_state_energy_cm1",
            "pressure_shift_nm",
            "line_mixing_coefficient",
        });

        const lines = try allocator.alloc(ReferenceData.SpectroscopyLine, self.row_count);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line, index| {
            line.* = .{
                .center_wavelength_nm = self.value(index, 0),
                .line_strength_cm2_per_molecule = self.value(index, 1),
                .air_half_width_nm = self.value(index, 2),
                .temperature_exponent = self.value(index, 3),
                .lower_state_energy_cm1 = self.value(index, 4),
                .pressure_shift_nm = self.value(index, 5),
                .line_mixing_coefficient = self.value(index, 6),
            };
        }

        return .{ .lines = lines };
    }

    pub fn toAirmassFactorLut(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.AirmassFactorLut {
        if (self.kind != .lookup_table or self.columnCount() != 4) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "solar_zenith_deg",
            "view_zenith_deg",
            "relative_azimuth_deg",
            "airmass_factor",
        });

        const points = try allocator.alloc(ReferenceData.AirmassFactorPoint, self.row_count);
        errdefer allocator.free(points);

        for (points, 0..) |*point, index| {
            point.* = .{
                .solar_zenith_deg = self.value(index, 0),
                .view_zenith_deg = self.value(index, 1),
                .relative_azimuth_deg = self.value(index, 2),
                .airmass_factor = self.value(index, 3),
            };
        }

        return .{ .points = points };
    }
};

pub fn loadBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    const manifest_bytes = try std.fs.cwd().readFileAlloc(allocator, bundle_manifest_path, 1024 * 1024);
    defer allocator.free(manifest_bytes);

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const manifest = try std.json.parseFromSliceLeaky(BundleManifest, arena.allocator(), manifest_bytes, .{
        .ignore_unknown_fields = true,
    });

    const manifest_asset = findAsset(manifest.assets, asset_id) orelse return error.AssetNotFound;

    const asset_bytes = try std.fs.cwd().readFileAlloc(allocator, manifest_asset.path, 1024 * 1024);
    defer allocator.free(asset_bytes);

    const dataset_hash = try renderSha256(allocator, asset_bytes);
    errdefer allocator.free(dataset_hash);
    if (!std.mem.eql(u8, dataset_hash, manifest_asset.sha256)) return error.HashMismatch;

    const parsed_table = try parseAssetTable(allocator, manifest_asset, asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    if (parsed_table.column_names.len != manifest_asset.columns.len) return error.ColumnMismatch;
    for (parsed_table.column_names, manifest_asset.columns) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.ColumnMismatch;
    }

    return .{
        .kind = kind,
        .bundle_manifest_path = try allocator.dupe(u8, bundle_manifest_path),
        .bundle_id = try allocator.dupe(u8, manifest.bundle_id),
        .owner_package = try allocator.dupe(u8, manifest.owner_package),
        .asset_id = try allocator.dupe(u8, manifest_asset.id),
        .asset_path = try allocator.dupe(u8, manifest_asset.path),
        .dataset_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ manifest.bundle_id, manifest_asset.id }),
        .dataset_hash = dataset_hash,
        .column_names = parsed_table.column_names,
        .values = parsed_table.values,
        .row_count = parsed_table.row_count,
    };
}

pub fn loadCsvBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    return loadBundleAsset(allocator, kind, bundle_manifest_path, asset_id);
}

const ParsedTable = struct {
    column_names: []const []const u8,
    values: []f64,
    row_count: u32,
};

const BundleManifest = struct {
    version: u32,
    bundle_id: []const u8,
    owner_package: []const u8,
    description: []const u8,
    upstream: Upstream,
    assets: []const Asset,

    const Upstream = struct {
        vendor_root: []const u8,
        source_paths: []const []const u8,
        reference_snapshot: []const u8,
    };

    const Asset = struct {
        id: []const u8,
        path: []const u8,
        format: []const u8,
        sha256: []const u8,
        columns: []const []const u8,
    };
};

fn parseNumericCsv(allocator: std.mem.Allocator, contents: []const u8) !ParsedTable {
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

    while (header_tokens.next()) |token| {
        try header_names.append(allocator, try allocator.dupe(u8, trimWhitespace(token)));
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
    for (header_names.items, 0..) |name, index| columns[index] = name;
    header_names.clearRetainingCapacity();

    return .{
        .column_names = columns,
        .values = try values.toOwnedSlice(allocator),
        .row_count = row_count,
    };
}

fn parseAssetTable(
    allocator: std.mem.Allocator,
    asset: BundleManifest.Asset,
    contents: []const u8,
) !ParsedTable {
    if (std.mem.eql(u8, asset.format, "csv")) {
        return parseNumericCsv(allocator, contents);
    }
    if (std.mem.eql(u8, asset.format, "hitran_160")) {
        return parseHitran160(allocator, contents, asset.columns);
    }
    return error.UnsupportedFormat;
}

fn parseHitran160(
    allocator: std.mem.Allocator,
    contents: []const u8,
    columns: []const []const u8,
) !ParsedTable {
    const owned_columns = try allocator.alloc([]const u8, columns.len);
    errdefer allocator.free(owned_columns);
    var owned_column_count: usize = 0;
    errdefer for (owned_columns[0..owned_column_count]) |column| allocator.free(column);
    for (columns, 0..) |column, index| {
        owned_columns[index] = try allocator.dupe(u8, column);
        owned_column_count += 1;
    }

    var values = std.ArrayList(f64).empty;
    defer values.deinit(allocator);

    var row_count: u32 = 0;
    var line_iter = std.mem.splitScalar(u8, contents, '\n');
    while (line_iter.next()) |raw_line| {
        const line = trimLineEnding(raw_line);
        const stripped = trimWhitespace(line);
        if (stripped.len == 0 or stripped[0] == '#' or stripped[0] == '!') continue;
        if (line.len < 67) return error.InvalidAssetFormat;

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

fn findAsset(assets: []const BundleManifest.Asset, asset_id: []const u8) ?BundleManifest.Asset {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.id, asset_id)) return asset;
    }
    return null;
}

fn renderSha256(allocator: std.mem.Allocator, contents: []const u8) ![]u8 {
    var digest: [std.crypto.hash.sha2.Sha256.digest_length]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(contents, &digest, .{});
    const digest_hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(allocator, "sha256:{s}", .{digest_hex[0..]});
}

fn expectColumns(actual: []const []const u8, expected: []const []const u8) !void {
    if (actual.len != expected.len) return error.ColumnMismatch;
    for (actual, expected) |actual_name, expected_name| {
        if (!std.mem.eql(u8, actual_name, expected_name)) return error.ColumnMismatch;
    }
}

fn parseFixedFloat(slice: []const u8) !f64 {
    return std.fmt.parseFloat(f64, trimWhitespace(slice)) catch error.InvalidNumber;
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

test "reference asset loader validates hashes and parses numeric tables" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("disamar_standard", asset.owner_package);
    try std.testing.expectEqual(@as(u32, 5), asset.row_count);
    try std.testing.expectEqual(@as(usize, 2), asset.columnCount());
    try std.testing.expectApproxEqAbs(@as(f64, 405.0), asset.value(0, 0), 1e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 4.17e-19), asset.value(4, 1), 1e-25);

    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try asset.registerWithEngine(&engine);

    const cached = engine.dataset_cache.get(asset.dataset_id).?;
    try std.testing.expectEqualStrings(asset.dataset_hash, cached.dataset_hash);

    var cross_sections = try asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    try std.testing.expectApproxEqAbs(@as(f64, 5.02e-19), cross_sections.interpolateSigma(440.0), 1e-25);
}

test "reference asset loader parses HITRAN-style line lists into spectroscopy rows" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 5), asset.row_count);
    try std.testing.expectEqual(@as(usize, 7), asset.columnCount());

    var lines = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    const near_line = lines.evaluateAt(434.6, 250.0, 800.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 800.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expect(@abs(near_line.line_mixing_sigma_cm2_per_molecule) > 0.0);
}
