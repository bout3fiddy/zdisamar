//! Purpose:
//!   Cache lookup-table metadata by dataset id and LUT id.
//!
//! Physics:
//!   Preserve the reusable shape information for reference LUTs without changing the table
//!   values themselves.
//!
//! Vendor:
//!   `lookup-table cache`
//!
//! Design:
//!   Key entries by the composite `(dataset_id, lut_id)` pair and refresh revisions in place.
//!
//! Invariants:
//!   The dataset/LUT pair uniquely identifies each cached entry.
//!
//! Validation:
//!   Cache package unit tests.

const std = @import("std");
const LutControls = @import("../../core/lut_controls.zig");

const Allocator = std.mem.Allocator;

/// Purpose:
///   Store the reusable LUT shape summary.
pub const LUTShape = struct {
    spectral_bins: u32 = 0,
    layer_count: u32 = 0,
    coefficient_count: u32 = 0,
};

/// Purpose:
///   Store one cached LUT entry.
pub const Entry = struct {
    dataset_id: []const u8,
    lut_id: []const u8,
    shape: LUTShape = .{},
    compatibility: LutControls.CompatibilityKey = .{},
    revision: u64 = 0,
};

/// Purpose:
///   Retain LUT metadata for repeated execution.
///
/// Invariants:
///   The same `(dataset_id, lut_id)` pair always resolves to the same cache slot.
pub const LUTCache = struct {
    pub const Shape = LUTShape;

    allocator: Allocator,
    entries: std.ArrayListUnmanaged(Entry) = .{},
    generation: u64 = 0,

    /// Purpose:
    ///   Construct an empty LUT cache.
    pub fn init(allocator: Allocator) LUTCache {
        return .{ .allocator = allocator };
    }

    /// Purpose:
    ///   Release all owned LUT identifiers.
    pub fn deinit(self: *LUTCache) void {
        for (self.entries.items) |entry| {
            self.allocator.free(entry.dataset_id);
            self.allocator.free(entry.lut_id);
        }
        self.entries.deinit(self.allocator);
    }

    /// Purpose:
    ///   Insert or refresh one LUT metadata entry.
    pub fn upsert(self: *LUTCache, dataset_id: []const u8, lut_id: []const u8, shape: LUTShape) !void {
        return self.upsertWithCompatibility(dataset_id, lut_id, shape, .{});
    }

    /// Purpose:
    ///   Insert or refresh one LUT metadata entry together with its compatibility key.
    pub fn upsertWithCompatibility(
        self: *LUTCache,
        dataset_id: []const u8,
        lut_id: []const u8,
        shape: LUTShape,
        compatibility: LutControls.CompatibilityKey,
    ) !void {
        if (dataset_id.len == 0 or lut_id.len == 0) {
            return error.InvalidLUTRecord;
        }
        try compatibility.validate();

        for (self.entries.items) |*entry| {
            if (std.mem.eql(u8, entry.dataset_id, dataset_id) and std.mem.eql(u8, entry.lut_id, lut_id)) {
                entry.shape = shape;
                entry.compatibility = compatibility;
                entry.revision += 1;
                self.generation += 1;
                return;
            }
        }

        const dataset_copy = try self.allocator.dupe(u8, dataset_id);
        errdefer self.allocator.free(dataset_copy);
        const lut_copy = try self.allocator.dupe(u8, lut_id);
        errdefer self.allocator.free(lut_copy);

        try self.entries.append(self.allocator, .{
            .dataset_id = dataset_copy,
            .lut_id = lut_copy,
            .shape = shape,
            .compatibility = compatibility,
        });
        self.generation += 1;
    }

    /// Purpose:
    ///   Look up the cached LUT metadata for a dataset/LUT pair.
    pub fn get(self: *const LUTCache, dataset_id: []const u8, lut_id: []const u8) ?Entry {
        for (self.entries.items) |entry| {
            if (std.mem.eql(u8, entry.dataset_id, dataset_id) and std.mem.eql(u8, entry.lut_id, lut_id)) {
                return entry;
            }
        }
        return null;
    }

    /// Purpose:
    ///   Look up a cached LUT entry only when its compatibility key matches exactly.
    pub fn getCompatible(
        self: *const LUTCache,
        dataset_id: []const u8,
        lut_id: []const u8,
        compatibility: LutControls.CompatibilityKey,
    ) ?Entry {
        const entry = self.get(dataset_id, lut_id) orelse return null;
        return if (entry.compatibility.matches(compatibility)) entry else null;
    }

    /// Purpose:
    ///   Report how many LUT entries are cached.
    pub fn count(self: *const LUTCache) usize {
        return self.entries.items.len;
    }
};

test "lut cache keys records by dataset and lut id" {
    var cache = LUTCache.init(std.testing.allocator);
    defer cache.deinit();

    try cache.upsert("cross_sections.o3", "temperature_273", .{
        .spectral_bins = 600,
        .layer_count = 40,
        .coefficient_count = 8,
    });
    try cache.upsert("cross_sections.o3", "temperature_273", .{
        .spectral_bins = 620,
        .layer_count = 40,
        .coefficient_count = 8,
    });
    try cache.upsert("cross_sections.o3", "temperature_280", .{
        .spectral_bins = 620,
        .layer_count = 40,
        .coefficient_count = 8,
    });

    try std.testing.expectEqual(@as(usize, 2), cache.count());
    try std.testing.expectEqual(@as(u64, 3), cache.generation);

    const updated = cache.get("cross_sections.o3", "temperature_273").?;
    try std.testing.expectEqual(@as(u32, 620), updated.shape.spectral_bins);
    try std.testing.expectEqual(@as(u64, 1), updated.revision);
}

test "lut cache compatibility rejects mismatched geometry reuse" {
    var cache = LUTCache.init(std.testing.allocator);
    defer cache.deinit();

    const compatibility: LutControls.CompatibilityKey = .{
        .controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
        .spectral_start_nm = 758.0,
        .spectral_end_nm = 770.0,
        .solar_zenith_deg = 60.0,
        .viewing_zenith_deg = 30.0,
        .relative_azimuth_deg = 120.0,
        .surface_albedo = 0.2,
        .instrument_line_fwhm_nm = 0.38,
        .high_resolution_step_nm = 0.01,
        .high_resolution_half_span_nm = 1.14,
    };
    var mismatched = compatibility;
    mismatched.relative_azimuth_deg = 90.0;

    try cache.upsertWithCompatibility("generated.xsec.o2", "o2a", .{
        .spectral_bins = 121,
        .layer_count = 48,
        .coefficient_count = 50,
    }, compatibility);

    try std.testing.expect(cache.getCompatible("generated.xsec.o2", "o2a", compatibility) != null);
    try std.testing.expect(cache.getCompatible("generated.xsec.o2", "o2a", mismatched) == null);
}
