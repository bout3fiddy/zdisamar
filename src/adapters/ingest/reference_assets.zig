const std = @import("std");
const ReferenceData = @import("../../model/ReferenceData.zig");

pub const AssetKind = enum {
    climatology_profile,
    cross_section_table,
    collision_induced_absorption_table,
    spectroscopy_line_list,
    spectroscopy_strong_line_set,
    spectroscopy_relaxation_matrix,
    lookup_table,
    mie_phase_table,
};

pub const EmbeddedAsset = struct {
    path: []const u8,
    contents: []const u8,
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

    pub fn registerWithEngine(self: LoadedAsset, engine: anytype) !void {
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

    pub fn toCollisionInducedAbsorptionTable(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.CollisionInducedAbsorptionTable {
        if (self.kind != .collision_induced_absorption_table or self.columnCount() != 5) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "wavelength_nm",
            "a0",
            "a1",
            "a2",
            "scale_factor_cm5_per_molecule2",
        });

        const points = try allocator.alloc(ReferenceData.CollisionInducedAbsorptionPoint, self.row_count);
        errdefer allocator.free(points);

        for (points, 0..) |*point, index| {
            point.* = .{
                .wavelength_nm = self.value(index, 0),
                .a0 = self.value(index, 1),
                .a1 = self.value(index, 2),
                .a2 = self.value(index, 3),
            };
        }

        return .{
            .scale_factor_cm5_per_molecule2 = self.value(0, 4),
            .points = points,
        };
    }

    pub fn toSpectroscopyLineList(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
        const extended_columns = [_][]const u8{
            "gas_index",
            "isotope_number",
            "abundance_fraction",
            "center_wavelength_nm",
            "line_strength_cm2_per_molecule",
            "air_half_width_nm",
            "temperature_exponent",
            "lower_state_energy_cm1",
            "pressure_shift_nm",
            "line_mixing_coefficient",
        };
        const legacy_columns = [_][]const u8{
            "center_wavelength_nm",
            "line_strength_cm2_per_molecule",
            "air_half_width_nm",
            "temperature_exponent",
            "lower_state_energy_cm1",
            "pressure_shift_nm",
            "line_mixing_coefficient",
        };
        if (self.kind != .spectroscopy_line_list or (self.columnCount() != legacy_columns.len and self.columnCount() != extended_columns.len)) {
            return error.InvalidAssetKind;
        }
        if (self.columnCount() == extended_columns.len) {
            try expectColumns(self.column_names, &extended_columns);
        } else {
            try expectColumns(self.column_names, &legacy_columns);
        }

        const lines = try allocator.alloc(ReferenceData.SpectroscopyLine, self.row_count);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line, index| {
            line.* = .{
                .gas_index = if (self.columnCount() == extended_columns.len) @intFromFloat(self.value(index, 0)) else 0,
                .isotope_number = if (self.columnCount() == extended_columns.len) @intFromFloat(self.value(index, 1)) else 1,
                .abundance_fraction = if (self.columnCount() == extended_columns.len) self.value(index, 2) else 1.0,
                .center_wavelength_nm = self.value(index, if (self.columnCount() == extended_columns.len) 3 else 0),
                .line_strength_cm2_per_molecule = self.value(index, if (self.columnCount() == extended_columns.len) 4 else 1),
                .air_half_width_nm = self.value(index, if (self.columnCount() == extended_columns.len) 5 else 2),
                .temperature_exponent = self.value(index, if (self.columnCount() == extended_columns.len) 6 else 3),
                .lower_state_energy_cm1 = self.value(index, if (self.columnCount() == extended_columns.len) 7 else 4),
                .pressure_shift_nm = self.value(index, if (self.columnCount() == extended_columns.len) 8 else 5),
                .line_mixing_coefficient = self.value(index, if (self.columnCount() == extended_columns.len) 9 else 6),
            };
        }

        return .{ .lines = lines };
    }

    pub fn toSpectroscopyStrongLineSet(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.SpectroscopyStrongLineSet {
        if (self.kind != .spectroscopy_strong_line_set or self.columnCount() != 12) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "center_wavenumber_cm1",
            "center_wavelength_nm",
            "population_t0",
            "dipole_ratio",
            "dipole_t0",
            "lower_state_energy_cm1",
            "air_half_width_cm1",
            "air_half_width_nm",
            "temperature_exponent",
            "pressure_shift_cm1",
            "pressure_shift_nm",
            "rotational_index_m1",
        });

        const lines = try allocator.alloc(ReferenceData.SpectroscopyStrongLine, self.row_count);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line, index| {
            line.* = .{
                .center_wavenumber_cm1 = self.value(index, 0),
                .center_wavelength_nm = self.value(index, 1),
                .population_t0 = self.value(index, 2),
                .dipole_ratio = self.value(index, 3),
                .dipole_t0 = self.value(index, 4),
                .lower_state_energy_cm1 = self.value(index, 5),
                .air_half_width_cm1 = self.value(index, 6),
                .air_half_width_nm = self.value(index, 7),
                .temperature_exponent = self.value(index, 8),
                .pressure_shift_cm1 = self.value(index, 9),
                .pressure_shift_nm = self.value(index, 10),
                .rotational_index_m1 = @intFromFloat(self.value(index, 11)),
            };
        }

        return .{ .lines = lines };
    }

    pub fn toSpectroscopyRelaxationMatrix(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.RelaxationMatrix {
        if (self.kind != .spectroscopy_relaxation_matrix or self.columnCount() != 2) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "wt0",
            "temperature_exponent_bw",
        });

        const line_count = inferSquareDimension(self.row_count) catch return error.InvalidMatrixShape;
        const wt0 = try allocator.alloc(f64, self.row_count);
        errdefer allocator.free(wt0);
        const bw = try allocator.alloc(f64, self.row_count);
        errdefer allocator.free(bw);

        for (0..self.row_count) |index| {
            wt0[index] = self.value(index, 0);
            bw[index] = self.value(index, 1);
        }

        return .{
            .line_count = line_count,
            .wt0 = wt0,
            .bw = bw,
        };
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

    pub fn toMiePhaseTable(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.MiePhaseTable {
        if (self.kind != .mie_phase_table or self.columnCount() != 7) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "wavelength_nm",
            "extinction_scale",
            "single_scatter_albedo",
            "phase_coeff_0",
            "phase_coeff_1",
            "phase_coeff_2",
            "phase_coeff_3",
        });

        const points = try allocator.alloc(ReferenceData.MiePhasePoint, self.row_count);
        errdefer allocator.free(points);

        for (points, 0..) |*point, index| {
            point.* = .{
                .wavelength_nm = self.value(index, 0),
                .extinction_scale = self.value(index, 1),
                .single_scatter_albedo = self.value(index, 2),
                .phase_coefficients = .{
                    self.value(index, 3),
                    self.value(index, 4),
                    self.value(index, 5),
                    self.value(index, 6),
                },
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

    return initLoadedAsset(allocator, kind, bundle_manifest_path, manifest, manifest_asset, asset_bytes);
}

pub fn loadCsvBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    asset_id: []const u8,
) !LoadedAsset {
    return loadBundleAsset(allocator, kind, bundle_manifest_path, asset_id);
}

pub fn loadEmbeddedBundleAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    manifest_bytes: []const u8,
    asset_id: []const u8,
    embedded_assets: []const EmbeddedAsset,
) !LoadedAsset {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const manifest = try std.json.parseFromSliceLeaky(BundleManifest, arena.allocator(), manifest_bytes, .{
        .ignore_unknown_fields = true,
    });

    const manifest_asset = findAsset(manifest.assets, asset_id) orelse return error.AssetNotFound;
    const asset_bytes = findEmbeddedAssetBytes(embedded_assets, manifest_asset.path) orelse return error.AssetNotFound;

    return initLoadedAsset(allocator, kind, bundle_manifest_path, manifest, manifest_asset, asset_bytes);
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
) !ParsedTable {
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
        if (expected != row_count) return error.InvalidAssetFormat;
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
) !ParsedTable {
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
) !ParsedTable {
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

fn findAsset(assets: []const BundleManifest.Asset, asset_id: []const u8) ?BundleManifest.Asset {
    for (assets) |asset| {
        if (std.mem.eql(u8, asset.id, asset_id)) return asset;
    }
    return null;
}

fn findEmbeddedAssetBytes(embedded_assets: []const EmbeddedAsset, path: []const u8) ?[]const u8 {
    for (embedded_assets) |asset| {
        if (std.mem.eql(u8, asset.path, path)) return asset.contents;
    }
    return null;
}

fn initLoadedAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    bundle_manifest_path: []const u8,
    manifest: BundleManifest,
    manifest_asset: BundleManifest.Asset,
    asset_bytes: []const u8,
) !LoadedAsset {
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

fn dupColumns(allocator: std.mem.Allocator, columns: []const []const u8) ![]const []const u8 {
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

fn parseFixedInt(slice: []const u8) !u16 {
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

fn inferSquareDimension(row_count: u32) !usize {
    const dimension_float = std.math.sqrt(@as(f64, @floatFromInt(row_count)));
    const dimension: usize = @intFromFloat(@round(dimension_float));
    if (dimension * dimension != row_count) return error.InvalidAssetFormat;
    return dimension;
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

test "reference asset loader validates hashes and parses numeric tables" {
    const Engine = @import("../../core/Engine.zig").Engine;

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
    try std.testing.expectEqual(@as(usize, 10), asset.columnCount());

    var lines = try asset.toSpectroscopyLineList(std.testing.allocator);
    defer lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u16, 10), lines.lines[0].gas_index);
    try std.testing.expectEqual(@as(u8, 1), lines.lines[0].isotope_number);
    try std.testing.expect(lines.lines[0].abundance_fraction > 0.9);
    const near_line = lines.evaluateAt(434.6, 250.0, 800.0);
    const off_line = lines.evaluateAt(420.0, 250.0, 800.0);
    try std.testing.expect(near_line.total_sigma_cm2_per_molecule > off_line.total_sigma_cm2_per_molecule);
    try std.testing.expectEqual(@as(f64, 0.0), near_line.line_mixing_sigma_cm2_per_molecule);
}

test "reference asset loader parses vendor strong-line and relaxation sidecars" {
    var sdf_asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_strong_line_set,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_sdf_subset",
    );
    defer sdf_asset.deinit(std.testing.allocator);

    var strong_lines = try sdf_asset.toSpectroscopyStrongLineSet(std.testing.allocator);
    defer strong_lines.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 8), sdf_asset.row_count);
    try std.testing.expectEqual(@as(usize, 12), sdf_asset.columnCount());
    try std.testing.expect(strong_lines.lines[0].center_wavenumber_cm1 > 12000.0);
    try std.testing.expect(strong_lines.lines[0].rotational_index_m1 < 0);
    try std.testing.expect(strong_lines.lines[0].air_half_width_nm > 0.0);

    var rmf_asset = try loadBundleAsset(
        std.testing.allocator,
        .spectroscopy_relaxation_matrix,
        "data/cross_sections/bundle_manifest.json",
        "o2a_lisa_rmf_subset",
    );
    defer rmf_asset.deinit(std.testing.allocator);

    var relaxation = try rmf_asset.toSpectroscopyRelaxationMatrix(std.testing.allocator);
    defer relaxation.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 64), rmf_asset.row_count);
    try std.testing.expectEqual(@as(usize, 8), relaxation.line_count);
    try std.testing.expect(relaxation.weightAt(0, 0) > 0.0);
    try std.testing.expect(relaxation.temperatureExponentAt(0, 1) != 0.0);
}

test "reference asset loader parses bounded O2-O2 CIA tables without collapsing units" {
    var asset = try loadBundleAsset(
        std.testing.allocator,
        .collision_induced_absorption_table,
        "data/cross_sections/bundle_manifest.json",
        "o2o2_bira_o2a_subset",
    );
    defer asset.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), asset.columnCount());
    try std.testing.expectEqual(@as(u32, 378), asset.row_count);

    var table = try asset.toCollisionInducedAbsorptionTable(std.testing.allocator);
    defer table.deinit(std.testing.allocator);

    const sigma_761 = table.sigmaAt(761.0, 294.0);
    const sigma_770 = table.sigmaAt(770.0, 294.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.0e-46), table.scale_factor_cm5_per_molecule2, 1e-60);
    try std.testing.expect(sigma_761 > 0.0);
    try std.testing.expect(sigma_761 > sigma_770);
    try std.testing.expectEqual(@as(f64, 0.0), table.dSigmaDTemperatureAt(761.0, 294.0));
}
