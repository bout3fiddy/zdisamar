const std = @import("std");
const ReferenceData = @import("../../model/ReferenceData.zig");
const formats = @import("reference_assets_formats.zig");

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

pub fn loadExternalAsset(
    allocator: std.mem.Allocator,
    kind: AssetKind,
    asset_id: []const u8,
    asset_path: []const u8,
    asset_format: []const u8,
) !LoadedAsset {
    const asset_bytes = try std.fs.cwd().readFileAlloc(allocator, asset_path, 16 * 1024 * 1024);
    defer allocator.free(asset_bytes);

    const dataset_hash = try renderSha256(allocator, asset_bytes);
    errdefer allocator.free(dataset_hash);

    const parsed_table = try formats.parseAssetTable(allocator, externalAssetSpec(kind, asset_format), asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    return .{
        .kind = kind,
        .bundle_manifest_path = try allocator.dupe(u8, asset_path),
        .bundle_id = try allocator.dupe(u8, "external_asset"),
        .owner_package = try allocator.dupe(u8, "canonical_config"),
        .asset_id = try allocator.dupe(u8, asset_id),
        .asset_path = try allocator.dupe(u8, asset_path),
        .dataset_id = try allocator.dupe(u8, asset_id),
        .dataset_hash = dataset_hash,
        .column_names = parsed_table.column_names,
        .values = parsed_table.values,
        .row_count = parsed_table.row_count,
    };
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

const ParsedTable = formats.ParsedTable;

fn externalAssetSpec(kind: AssetKind, asset_format: []const u8) formats.AssetSpec {
    if (std.mem.eql(u8, asset_format, "profile_csv")) {
        return .{
            .format = "csv",
            .columns = &.{ "altitude_km", "pressure_hpa", "temperature_k", "air_number_density_cm3" },
        };
    }
    if (std.mem.eql(u8, asset_format, "hitran_par")) {
        return .{
            .format = "hitran_160",
            .columns = &.{
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
            },
        };
    }
    if (std.mem.eql(u8, asset_format, "bira_cia")) {
        return .{
            .format = "bira_cia_poly",
            .columns = &.{
                "wavelength_nm",
                "a0",
                "a1",
                "a2",
                "scale_factor_cm5_per_molecule2",
            },
        };
    }
    if (std.mem.eql(u8, asset_format, "lisa_sdf")) {
        return .{
            .format = "lisa_sdf",
            .columns = &.{
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
            },
        };
    }
    if (std.mem.eql(u8, asset_format, "lisa_rmf")) {
        return .{
            .format = "lisa_rmf",
            .columns = &.{ "wt0", "temperature_exponent_bw" },
        };
    }

    return switch (kind) {
        .climatology_profile => .{
            .format = "csv",
            .columns = &.{ "altitude_km", "pressure_hpa", "temperature_k", "air_number_density_cm3" },
        },
        .cross_section_table => .{
            .format = "csv",
            .columns = &.{ "wavelength_nm", "no2_sigma_cm2_per_molecule" },
        },
        .collision_induced_absorption_table => .{
            .format = "bira_cia_poly",
            .columns = &.{
                "wavelength_nm",
                "a0",
                "a1",
                "a2",
                "scale_factor_cm5_per_molecule2",
            },
        },
        .spectroscopy_line_list => .{
            .format = "hitran_160",
            .columns = &.{
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
            },
        },
        .spectroscopy_strong_line_set => .{
            .format = "lisa_sdf",
            .columns = &.{
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
            },
        },
        .spectroscopy_relaxation_matrix => .{
            .format = "lisa_rmf",
            .columns = &.{ "wt0", "temperature_exponent_bw" },
        },
        .lookup_table => .{
            .format = "csv",
            .columns = &.{ "solar_zenith_deg", "view_zenith_deg", "relative_azimuth_deg", "air_mass_factor" },
        },
        .mie_phase_table => .{
            .format = "csv",
            .columns = &.{
                "wavelength_nm",
                "single_scatter_albedo",
                "extinction_scale",
                "phase0",
                "phase1",
                "phase2",
                "phase3",
            },
        },
    };
}

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

    const parsed_table = try formats.parseAssetTable(allocator, .{
        .format = manifest_asset.format,
        .columns = manifest_asset.columns,
    }, asset_bytes);
    errdefer {
        for (parsed_table.column_names) |column_name| allocator.free(column_name);
        allocator.free(parsed_table.column_names);
        allocator.free(parsed_table.values);
    }

    if (parsed_table.column_names.len != manifest_asset.columns.len) return error.ColumnMismatch;
    for (parsed_table.column_names, manifest_asset.columns) |actual, expected| {
        if (!std.mem.eql(u8, actual, expected)) return error.ColumnMismatch;
    }

    const owned_bundle_manifest_path = try allocator.dupe(u8, bundle_manifest_path);
    errdefer allocator.free(owned_bundle_manifest_path);
    const owned_bundle_id = try allocator.dupe(u8, manifest.bundle_id);
    errdefer allocator.free(owned_bundle_id);
    const owned_owner_package = try allocator.dupe(u8, manifest.owner_package);
    errdefer allocator.free(owned_owner_package);
    const owned_asset_id = try allocator.dupe(u8, manifest_asset.id);
    errdefer allocator.free(owned_asset_id);
    const owned_asset_path = try allocator.dupe(u8, manifest_asset.path);
    errdefer allocator.free(owned_asset_path);
    const owned_dataset_id = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ manifest.bundle_id, manifest_asset.id });
    errdefer allocator.free(owned_dataset_id);

    return .{
        .kind = kind,
        .bundle_manifest_path = owned_bundle_manifest_path,
        .bundle_id = owned_bundle_id,
        .owner_package = owned_owner_package,
        .asset_id = owned_asset_id,
        .asset_path = owned_asset_path,
        .dataset_id = owned_dataset_id,
        .dataset_hash = dataset_hash,
        .column_names = parsed_table.column_names,
        .values = parsed_table.values,
        .row_count = parsed_table.row_count,
    };
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

fn inferSquareDimension(row_count: u32) !usize {
    const dimension_float = std.math.sqrt(@as(f64, @floatFromInt(row_count)));
    const dimension: usize = @intFromFloat(@round(dimension_float));
    if (dimension * dimension != row_count) return error.InvalidAssetFormat;
    return dimension;
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
