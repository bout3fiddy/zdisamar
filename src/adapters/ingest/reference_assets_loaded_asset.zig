//! Purpose:
//!   Represent a hydrated reference asset and convert it into typed reference
//!   data.
//!
//! Physics:
//!   Preserve the manifest provenance, numeric payload, and table-to-typed
//!   conversion rules for bundled climatology, spectroscopy, CIA, LUT, and
//!   Mie assets.
//!
//! Vendor:
//!   `reference asset hydration and typed conversion`
//!
//! Design:
//!   Keep the loaded-asset carrier and its conversion methods together so the
//!   root loader can stay focused on file resolution and hashing.
//!
//! Invariants:
//!   Owned strings and buffers are released exactly once, and typed outputs
//!   preserve the original row order and column contracts.
//!
//! Validation:
//!   Reference-asset loader tests.

const std = @import("std");
const ReferenceData = @import("../../model/ReferenceData.zig");
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

    /// Purpose:
    ///   Release all owned strings and numeric buffers for a loaded asset.
    ///
    /// Invariants:
    ///   Every allocation in the asset must be freed exactly once before the
    ///   struct is reused.
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

    /// Purpose:
    ///   Report how many numeric columns the asset contains.
    pub fn columnCount(self: LoadedAsset) usize {
        return self.column_names.len;
    }

    /// Purpose:
    ///   Read one numeric cell from the loaded table.
    pub fn value(self: LoadedAsset, row_index: usize, column_index: usize) f64 {
        return self.values[row_index * self.column_names.len + column_index];
    }

    /// Purpose:
    ///   Register the loaded asset with the engine caches.
    ///
    /// Physics:
    ///   Publish the dataset hash and, for LUTs, the derived shape metadata.
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

    /// Purpose:
    ///   Materialize a climatology profile from the generic loaded table.
    ///
    /// Physics:
    ///   Convert the table rows into typed atmospheric profile points.
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

    /// Purpose:
    ///   Materialize a cross-section table from the generic loaded table.
    ///
    /// Physics:
    ///   Convert wavelength and cross-section columns into typed interpolation
    ///   points.
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

    /// Purpose:
    ///   Materialize a CIA table from the generic loaded table.
    ///
    /// Physics:
    ///   Convert the fixed CIA polynomial coefficients into typed absorption
    ///   points.
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

    /// Purpose:
    ///   Materialize a spectroscopy line list from the generic loaded table.
    ///
    /// Physics:
    ///   Convert HITRAN-style line rows into typed spectroscopy lines.
    pub fn toSpectroscopyLineList(self: LoadedAsset, allocator: std.mem.Allocator) !ReferenceData.SpectroscopyLineList {
        if (self.kind != .spectroscopy_line_list) return error.InvalidAssetKind;
        const has_vendor_o2a_fields = self.columnCount() == 13;
        if (has_vendor_o2a_fields) {
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
            line.* = .{
                .gas_index = @intFromFloat(self.values[row + 0]),
                .isotope_number = @intFromFloat(self.values[row + 1]),
                .abundance_fraction = self.values[row + 2],
                .center_wavelength_nm = self.values[row + 3],
                .line_strength_cm2_per_molecule = self.values[row + 4],
                .air_half_width_nm = self.values[row + 5],
                .temperature_exponent = self.values[row + 6],
                .lower_state_energy_cm1 = self.values[row + 7],
                .pressure_shift_nm = self.values[row + 8],
                .line_mixing_coefficient = self.values[row + 9],
                .branch_ic1 = if (has_vendor_o2a_fields) @as(u8, @intFromFloat(self.values[row + 10])) else null,
                .branch_ic2 = if (has_vendor_o2a_fields) @as(u8, @intFromFloat(self.values[row + 11])) else null,
                .rotational_nf = if (has_vendor_o2a_fields) @as(u8, @intFromFloat(self.values[row + 12])) else null,
            };
        }

        return .{ .lines = lines };
    }

    /// Purpose:
    ///   Materialize a strong-line sidecar set from the generic loaded table.
    ///
    /// Physics:
    ///   Preserve the O2A strong-line augmentation rows and the relaxation
    ///   metadata used by the reference line-selection path.
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

    /// Purpose:
    ///   Materialize a relaxation matrix from the generic loaded table.
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

    /// Purpose:
    ///   Materialize an airmass-factor LUT from the generic loaded table.
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

    /// Purpose:
    ///   Materialize a Mie phase table from the generic loaded table.
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
