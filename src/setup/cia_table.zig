const std = @import("std");

const readers = @import("../assets/readers.zig");
const hashing = @import("../common/hashing.zig");
const scene_input = @import("../input/scene.zig");

const Allocator = std.mem.Allocator;

// CiaTable ---------------------------------------------------------------------------------------------------|
// O2-O2 CIA coefficient table parsed from the configured BIRA asset.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scale_factor_cm5_per_molecule2: f64                                                                |
// [ 8..23] rows                          : []CiaAssetRow                                                      |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed CIA coefficient rows and is released by deinit.                                          |
pub const CiaTable = struct {
    scale_factor_cm5_per_molecule2: f64,
    rows: []readers.CiaAssetRow,

    pub fn deinit(self: *CiaTable, allocator: Allocator) void {
        // CiaTable.deinit ------------------------------------------------------------------------------------|
        // Release parsed CIA coefficient rows owned by this setup table.                                      |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn hashAll(hasher: *std.hash.Wyhash, table: CiaTable) void {
    // hashAll ----------------------------------------------------------------------------------------------- |
    // Hash the CIA scale factor and coefficient rows read by per-wavelength optical-depth fills.              |
    // --------------------------------------------------------------------------------------------------------|
    hashing.updateValue(hasher, table.scale_factor_cm5_per_molecule2);
    hasher.update(std.mem.sliceAsBytes(table.rows));
}
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, scene: scene_input.Scene) !CiaTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load BIRA CIA coefficients for later wavelength/profile evaluation.                                     |
    // --------------------------------------------------------------------------------------------------------|
    var asset = try readers.readCiaTable(allocator, scene.cia.table.path);
    errdefer asset.deinit(allocator);

    return .{
        .scale_factor_cm5_per_molecule2 = asset.scale_factor_cm5_per_molecule2,
        .rows = asset.rows,
    };
}
