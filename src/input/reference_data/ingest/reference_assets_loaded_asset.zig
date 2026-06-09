const std = @import("std");
const ReferenceData = @import("../../ReferenceData.zig");
const types = @import("reference_assets_types.zig");

const spectroscopy_vendor_source_columns = [_][]const u8{
    "gas_index",
    "isotope_number",
    "abundance_fraction",
    "center_wavelength_nm",
    "center_wavenumber_cm1",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "air_half_width_cm1",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "pressure_shift_cm1",
    "line_mixing_coefficient",
    "branch_ic1",
    "branch_ic2",
    "rotational_nf",
    "vendor_filter_metadata_from_source",
};

const spectroscopy_vendor_nm_columns = [_][]const u8{
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
    "branch_ic1",
    "branch_ic2",
    "rotational_nf",
    "vendor_filter_metadata_from_source",
};

const spectroscopy_source_columns = [_][]const u8{
    "gas_index",
    "isotope_number",
    "abundance_fraction",
    "center_wavelength_nm",
    "center_wavenumber_cm1",
    "line_strength_cm2_per_molecule",
    "air_half_width_nm",
    "air_half_width_cm1",
    "temperature_exponent",
    "lower_state_energy_cm1",
    "pressure_shift_nm",
    "pressure_shift_cm1",
    "line_mixing_coefficient",
};

const spectroscopy_nm_columns = [_][]const u8{
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

// LoadedAsset ------------------------------------------------------------------------------------------------|
// Owned metadata and numeric table storage for one hydrated reference asset.                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 152 B (0.148 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] bundle_manifest_path : []const u8                                                                |
// [ 16.. 31] bundle_id            : []const u8                                                                |
// [ 32.. 47] owner_package        : []const u8                                                                |
// [ 48.. 63] asset_id             : []const u8                                                                |
// [ 64.. 79] asset_path           : []const u8                                                                |
// [ 80.. 95] dataset_id           : []const u8                                                                |
// [ 96..111] dataset_hash         : []const u8                                                                |
// [112..127] column_names         : []const []const u8                                                        |
// [128..143] values               : []f64                                                                     |
// [144..147] row_count            : u32                                                                       |
// [148..148] kind                 : types.AssetKind                                                           |
// [149..151] trailing padding     : 3 B                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   String, column-name, and values slices are owned by this row and released by deinit.                      |
//                                                                                                             |
// unused bits: 24 padding + 0 bool-storage slack = 24 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 152 B (0.148 KiB); total also includes owned metadata and numeric arrays          |
pub const LoadedAsset = struct {
    kind: types.AssetKind,
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
        for (self.column_names) |column_name| {
            allocator.free(column_name);
        }
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

    pub fn toClimatologyProfile(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.ClimatologyProfile {
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

    pub fn toCrossSectionTable(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.CrossSectionTable {
        if (self.kind != .cross_section_table or self.columnCount() != 2) return error.InvalidAssetKind;
        if (!std.mem.eql(u8, self.column_names[0], "wavelength_nm")) return error.InvalidColumns;
        if (!std.mem.endsWith(u8, self.column_names[1], "_sigma_cm2_per_molecule")) return error.InvalidColumns;

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

    pub fn toCollisionInducedAbsorptionTable(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.CollisionInducedAbsorptionTable {
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
            .points = points,
            .scale_factor_cm5_per_molecule2 = self.value(0, 4),
        };
    }

    pub fn toSpectroscopyLineList(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.SpectroscopyLineList {
        if (self.kind != .spectroscopy_line_list) return error.InvalidAssetKind;
        const has_source_cm1_fields = columnNamesContain(self.column_names, "center_wavenumber_cm1");
        const has_vendor_o2a_fields = columnNamesContain(self.column_names, "vendor_filter_metadata_from_source");
        try expectColumns(
            self.column_names,
            spectroscopyLineColumns(has_source_cm1_fields, has_vendor_o2a_fields),
        );

        const lines = try allocator.alloc(ReferenceData.SpectroscopyLine, self.row_count);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line, row_index| {
            const row = row_index * self.columnCount();
            var line_strength_index: usize = 4;
            var air_half_width_nm_index: usize = 5;
            var temperature_exponent_index: usize = 6;
            var lower_state_energy_index: usize = 7;
            var pressure_shift_nm_index: usize = 8;
            var line_mixing_index: usize = 9;
            var vendor_index: usize = 10;
            var center_wavenumber_cm1 = std.math.nan(f64);
            var air_half_width_cm1 = std.math.nan(f64);
            var pressure_shift_cm1 = std.math.nan(f64);

            if (has_source_cm1_fields) {
                line_strength_index = 5;
                air_half_width_nm_index = 6;
                temperature_exponent_index = 8;
                lower_state_energy_index = 9;
                pressure_shift_nm_index = 10;
                line_mixing_index = 12;
                vendor_index = 13;
                center_wavenumber_cm1 = self.values[row + 4];
                air_half_width_cm1 = self.values[row + 7];
                pressure_shift_cm1 = self.values[row + 11];
            }

            var branch_ic1: ?u8 = null;
            var branch_ic2: ?u8 = null;
            var rotational_nf: ?u8 = null;
            var vendor_filter_metadata_from_source = false;

            if (has_vendor_o2a_fields) {
                branch_ic1 = optionalVendorMetadataValue(self.values[row + vendor_index]);
                branch_ic2 = optionalVendorMetadataValue(self.values[row + vendor_index + 1]);
                rotational_nf = optionalVendorMetadataValue(self.values[row + vendor_index + 2]);
                vendor_filter_metadata_from_source = self.values[row + vendor_index + 3] != 0.0;
            }

            line.* = .{
                .gas_index = @intFromFloat(self.values[row + 0]),
                .isotope_number = @intFromFloat(self.values[row + 1]),
                .abundance_fraction = self.values[row + 2],
                .center_wavelength_nm = self.values[row + 3],
                .center_wavenumber_cm1 = center_wavenumber_cm1,
                .line_strength_cm2_per_molecule = self.values[row + line_strength_index],
                .air_half_width_nm = self.values[row + air_half_width_nm_index],
                .air_half_width_cm1 = air_half_width_cm1,
                .temperature_exponent = self.values[row + temperature_exponent_index],
                .lower_state_energy_cm1 = self.values[row + lower_state_energy_index],
                .pressure_shift_nm = self.values[row + pressure_shift_nm_index],
                .pressure_shift_cm1 = pressure_shift_cm1,
                .line_mixing_coefficient = self.values[row + line_mixing_index],
                .branch_ic1 = branch_ic1,
                .branch_ic2 = branch_ic2,
                .rotational_nf = rotational_nf,
                .vendor_filter_metadata_from_source = vendor_filter_metadata_from_source,
            };
        }

        return .{ .lines = lines };
    }

    pub fn toSpectroscopyStrongLineSet(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.SpectroscopyStrongLineSet {
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

        for (lines, 0..) |*line, row_index| {
            const row = row_index * self.columnCount();
            line.* = .{
                .center_wavenumber_cm1 = self.values[row + 0],
                .center_wavelength_nm = self.values[row + 1],
                .population_t0 = self.values[row + 2],
                .dipole_ratio = self.values[row + 3],
                .dipole_t0 = self.values[row + 4],
                .lower_state_energy_cm1 = self.values[row + 5],
                .air_half_width_cm1 = self.values[row + 6],
                .air_half_width_nm = self.values[row + 7],
                .temperature_exponent = self.values[row + 8],
                .pressure_shift_cm1 = self.values[row + 9],
                .pressure_shift_nm = self.values[row + 10],
                .rotational_index_m1 = @intFromFloat(self.values[row + 11]),
            };
        }

        return .{ .lines = lines };
    }

    pub fn toSpectroscopyRelaxationMatrix(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.RelaxationMatrix {
        if (self.kind != .spectroscopy_relaxation_matrix or self.columnCount() != 2) return error.InvalidAssetKind;
        try expectColumns(self.column_names, &.{
            "wt0",
            "temperature_exponent_bw",
        });
        const line_count_f = std.math.sqrt(@as(f64, @floatFromInt(self.row_count)));
        const line_count: usize = @intFromFloat(std.math.round(line_count_f));
        if (line_count * line_count != @as(usize, self.row_count)) return error.InvalidColumns;

        const wt0 = try allocator.alloc(f64, self.row_count);
        errdefer allocator.free(wt0);
        const bw = try allocator.alloc(f64, self.row_count);
        errdefer allocator.free(bw);

        for (0..self.row_count) |row_index| {
            const index = row_index * self.columnCount();
            wt0[row_index] = self.values[index + 0];
            bw[row_index] = self.values[index + 1];
        }

        return .{
            .line_count = line_count,
            .wt0 = wt0,
            .bw = bw,
        };
    }

    pub fn toAirmassFactorLut(
        self: LoadedAsset,
        allocator: std.mem.Allocator,
    ) !ReferenceData.AirmassFactorLut {
        if (self.kind != .lookup_table or self.columnCount() != 4) return error.InvalidAssetKind;
        try expectAirmassFactorColumns(self.column_names);

        const points = try allocator.alloc(ReferenceData.AirmassFactorPoint, self.row_count);
        errdefer allocator.free(points);

        for (points, 0..) |*point, row_index| {
            const index = row_index * self.columnCount();
            point.* = .{
                .solar_zenith_deg = self.values[index + 0],
                .view_zenith_deg = self.values[index + 1],
                .relative_azimuth_deg = self.values[index + 2],
                .airmass_factor = self.values[index + 3],
            };
        }

        return .{ .points = points };
    }
};

fn expectColumns(actual: []const []const u8, expected: []const []const u8) !void {
    if (actual.len != expected.len) return error.ColumnMismatch;
    for (actual, expected) |actual_name, expected_name| {
        if (!std.mem.eql(u8, actual_name, expected_name)) return error.ColumnMismatch;
    }
}

fn columnNamesContain(actual: []const []const u8, expected: []const u8) bool {
    for (actual) |actual_name| {
        if (std.mem.eql(u8, actual_name, expected)) return true;
    }
    return false;
}

fn spectroscopyLineColumns(
    has_source_cm1_fields: bool,
    has_vendor_o2a_fields: bool,
) []const []const u8 {
    if (has_vendor_o2a_fields and has_source_cm1_fields) return &spectroscopy_vendor_source_columns;
    if (has_vendor_o2a_fields) return &spectroscopy_vendor_nm_columns;
    if (has_source_cm1_fields) return &spectroscopy_source_columns;
    return &spectroscopy_nm_columns;
}

fn expectAirmassFactorColumns(actual: []const []const u8) !void {
    try expectColumns(actual[0..3], &.{
        "solar_zenith_deg",
        "view_zenith_deg",
        "relative_azimuth_deg",
    });
    const has_spelled_air_mass_factor = std.mem.eql(u8, actual[3], "air_mass_factor");
    const has_compact_airmass_factor = std.mem.eql(u8, actual[3], "airmass_factor");
    if (has_spelled_air_mass_factor or has_compact_airmass_factor) {
        return;
    }
    return error.ColumnMismatch;
}

fn optionalVendorMetadataValue(value: f64) ?u8 {
    if (std.math.isNan(value)) return null;
    return @as(u8, @intFromFloat(value));
}
