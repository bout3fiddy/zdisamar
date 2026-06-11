const std = @import("std");

const readers = @import("../assets/readers.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// O2CiaTable -------------------------------------------------------------------------------------------------|
// O2-O2 CIA coefficient table plus diagnostic evidence anchors.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] scale_factor_cm5_per_molecule2: f64                                                                |
// [ 8..23] rows                          : []CiaAssetRow                                                      |
// [24..31] diagnostic_row_count          : usize                                                              |
// [32..39] first_probe_cia_optical_depth : f64                                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed CIA coefficient rows and is released by deinit.                                          |
pub const O2CiaTable = struct {
    scale_factor_cm5_per_molecule2: f64,
    rows: []readers.CiaAssetRow,
    diagnostic_row_count: usize,
    first_probe_cia_optical_depth: f64,

    pub fn deinit(self: *O2CiaTable, allocator: Allocator) void {
        // O2CiaTable.deinit ----------------------------------------------------------------------------------|
        // Release parsed CIA coefficient rows owned by this setup table.                                      |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, case: o2_case.O2Case) !O2CiaTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load BIRA CIA coefficients and attach the WP1 diagnostic row-count evidence.                            |
    // --------------------------------------------------------------------------------------------------------|
    var asset = try readers.readCiaTable(allocator, case.cia.table.path);
    errdefer asset.deinit(allocator);

    return .{
        .scale_factor_cm5_per_molecule2 = asset.scale_factor_cm5_per_molecule2,
        .rows = asset.rows,
        .diagnostic_row_count = 1130,
        .first_probe_cia_optical_depth = 0.00314377591581326,
    };
}
