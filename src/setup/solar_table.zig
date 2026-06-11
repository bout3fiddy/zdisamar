const std = @import("std");

const readers = @import("../assets/readers.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// SolarTable -------------------------------------------------------------------------------------------------|
// Owner for parsed solar irradiance rows.                                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []SolarAssetRow                                                                              |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed solar irradiance rows and is released by deinit.                                         |
pub const SolarTable = struct {
    rows: []readers.SolarAssetRow,

    pub fn deinit(self: *SolarTable, allocator: Allocator) void {
        // SolarTable.deinit ----------------------------------------------------------------------------------|
        // Release parsed solar irradiance rows owned by this setup table.                                     |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, case: o2_case.O2Case) !SolarTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load solar reference rows through the asset reader layer.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .rows = try readers.readSolarReference(allocator, case.observation.solar_reference.path),
    };
}
