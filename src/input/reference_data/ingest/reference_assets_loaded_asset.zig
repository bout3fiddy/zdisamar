const std = @import("std");
const ReferenceData = @import("../../ReferenceData.zig");
const types = @import("reference_assets_types.zig");

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
            .points = points,
            .scale_factor_cm5_per_molecule2 = self.value(0, 4),
        };
    }

    pub fn toSpectroscopyLineList(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
        if (self.kind != .spectroscopy_line_list) return error.InvalidAssetKind;
        const has_source_cm1_fields = columnNamesContain(self.column_names, "center_wavenumber_cm1");
        const has_vendor_o2a_fields = columnNamesContain(self.column_names, "vendor_filter_metadata_from_source");
        if (has_vendor_o2a_fields and has_source_cm1_fields) {
            try expectColumns(self.column_names, &.{
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
            });
        } else if (has_vendor_o2a_fields) {
            try expectColumns(self.column_names, &.{
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
            });
        } else if (has_source_cm1_fields) {
            try expectColumns(self.column_names, &.{
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
            });
        } else {
            try expectColumns(self.column_names, &.{
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
            });
        }

        const lines = try allocator.alloc(ReferenceData.SpectroscopyLine, self.row_count);
        errdefer allocator.free(lines);

        for (lines, 0..) |*line, row_index| {
            const row = row_index * self.columnCount();
            const line_strength_index: usize = if (has_source_cm1_fields) 5 else 4;
            const air_half_width_nm_index: usize = if (has_source_cm1_fields) 6 else 5;
            const temperature_exponent_index: usize = if (has_source_cm1_fields) 8 else 6;
            const lower_state_energy_index: usize = if (has_source_cm1_fields) 9 else 7;
            const pressure_shift_nm_index: usize = if (has_source_cm1_fields) 10 else 8;
            const line_mixing_index: usize = if (has_source_cm1_fields) 12 else 9;
            const vendor_index: usize = if (has_source_cm1_fields) 13 else 10;
            line.* = .{
                .gas_index = @intFromFloat(self.values[row + 0]),
                .isotope_number = @intFromFloat(self.values[row + 1]),
                .abundance_fraction = self.values[row + 2],
                .center_wavelength_nm = self.values[row + 3],
                .center_wavenumber_cm1 = if (has_source_cm1_fields) self.values[row + 4] else std.math.nan(f64),
                .line_strength_cm2_per_molecule = self.values[row + line_strength_index],
                .air_half_width_nm = self.values[row + air_half_width_nm_index],
                .air_half_width_cm1 = if (has_source_cm1_fields) self.values[row + 7] else std.math.nan(f64),
                .temperature_exponent = self.values[row + temperature_exponent_index],
                .lower_state_energy_cm1 = self.values[row + lower_state_energy_index],
                .pressure_shift_nm = self.values[row + pressure_shift_nm_index],
                .pressure_shift_cm1 = if (has_source_cm1_fields) self.values[row + 11] else std.math.nan(f64),
                .line_mixing_coefficient = self.values[row + line_mixing_index],
                .branch_ic1 = if (has_vendor_o2a_fields) optionalVendorMetadataValue(self.values[row + vendor_index]) else null,
                .branch_ic2 = if (has_vendor_o2a_fields) optionalVendorMetadataValue(self.values[row + vendor_index + 1]) else null,
                .rotational_nf = if (has_vendor_o2a_fields) optionalVendorMetadataValue(self.values[row + vendor_index + 2]) else null,
                .vendor_filter_metadata_from_source = has_vendor_o2a_fields and self.values[row + vendor_index + 3] != 0.0,
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

    pub fn toSpectroscopyRelaxationMatrix(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.RelaxationMatrix {
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

    pub fn toAirmassFactorLut(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.AirmassFactorLut {
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
        for (points, 0..) |*point, row_index| {
            const index = row_index * self.columnCount();
            point.* = .{
                .wavelength_nm = self.values[index + 0],
                .extinction_scale = self.values[index + 1],
                .single_scatter_albedo = self.values[index + 2],
                .phase_coefficients = .{
                    self.values[index + 3],
                    self.values[index + 4],
                    self.values[index + 5],
                    self.values[index + 6],
                },
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

fn expectAirmassFactorColumns(actual: []const []const u8) !void {
    try expectColumns(actual[0..3], &.{
        "solar_zenith_deg",
        "view_zenith_deg",
        "relative_azimuth_deg",
    });
    if (std.mem.eql(u8, actual[3], "air_mass_factor") or std.mem.eql(u8, actual[3], "airmass_factor")) {
        return;
    }
    return error.ColumnMismatch;
}

fn optionalVendorMetadataValue(value: f64) ?u8 {
    if (std.math.isNan(value)) return null;
    return @as(u8, @intFromFloat(value));
}
