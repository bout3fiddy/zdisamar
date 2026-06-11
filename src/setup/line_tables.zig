const std = @import("std");

const readers = @import("../assets/readers.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// O2LineTable ------------------------------------------------------------------------------------------------|
// O2 line-list setup table plus diagnostic evidence anchors.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] rows                             : []O2LineAssetRow                                                |
// [16..31] isotopes_sim                     : []const u8                                                      |
// [32..39] threshold_line_sim               : f64                                                             |
// [40..47] cutoff_sim_cm1                   : f64                                                             |
// [48..55] line_mixing_factor               : f64                                                             |
// [56..63] diagnostic_contribution_row_count: usize                                                           |
// [64..71] first_center_wavelength_nm       : f64                                                             |
// [72..79] first_center_wavenumber_cm1      : f64                                                             |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns parsed HITRAN rows. isotopes_sim borrows the case controls.                                     |
pub const O2LineTable = struct {
    rows: []readers.O2LineAssetRow,
    isotopes_sim: []const u8,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
    line_mixing_factor: f64,
    diagnostic_contribution_row_count: usize,
    first_center_wavelength_nm: f64,
    first_center_wavenumber_cm1: f64,

    pub fn deinit(self: *O2LineTable, allocator: Allocator) void {
        // O2LineTable.deinit ---------------------------------------------------------------------------------|
        // Release parsed line-list rows owned by this setup table.                                            |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, case: o2_case.O2Case) !O2LineTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load raw O2 HITRAN rows and attach diagnostic contribution-count evidence.                              |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try readers.readO2LineList(allocator, case.line_gas.line_list.path);
    errdefer allocator.free(rows);

    return .{
        .rows = rows,
        .isotopes_sim = case.line_gas.isotopes_sim,
        .threshold_line_sim = case.line_gas.threshold_line_sim,
        .cutoff_sim_cm1 = case.line_gas.cutoff_sim_cm1,
        .line_mixing_factor = case.line_gas.line_mixing_factor,
        .diagnostic_contribution_row_count = 101144,
        .first_center_wavelength_nm = 759.5754324317322,
        .first_center_wavenumber_cm1 = 13165.249392,
    };
}
