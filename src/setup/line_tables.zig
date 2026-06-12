const std = @import("std");

const readers = @import("../assets/readers.zig");
const o2_case = @import("../input/o2_case.zig");

const Allocator = std.mem.Allocator;

// O2LineTable ------------------------------------------------------------------------------------------------|
// O2 line-list setup table parsed from the configured HITRAN and LISA sidecar assets.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] rows              : []O2LineAssetRow                                                             |
// [ 16.. 31] strong_lines      : []O2StrongLineAssetRow                                                       |
// [ 32.. 71] relaxation_matrix : O2RelaxationMatrixAsset                                                      |
// [ 72.. 87] isotopes_sim      : []const u8                                                                   |
// [ 88.. 95] threshold_line_sim: f64                                                                          |
// [ 96..103] cutoff_sim_cm1    : f64                                                                          |
// [104..111] line_mixing_factor: f64                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows, strong_lines, and relaxation_matrix own parsed asset rows. isotopes_sim borrows the case controls.  |
pub const O2LineTable = struct {
    rows: []readers.O2LineAssetRow,
    strong_lines: []readers.O2StrongLineAssetRow,
    relaxation_matrix: readers.O2RelaxationMatrixAsset,
    isotopes_sim: []const u8,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
    line_mixing_factor: f64,

    pub fn deinit(self: *O2LineTable, allocator: Allocator) void {
        // O2LineTable.deinit ---------------------------------------------------------------------------------|
        // Release parsed line-list rows and sidecar rows owned by this setup table.                           |
        // ----------------------------------------------------------------------------------------------------|
        self.relaxation_matrix.deinit(allocator);
        allocator.free(self.strong_lines);
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, case: o2_case.O2Case) !O2LineTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load raw O2 HITRAN rows and copy the runtime line-filter controls.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try readers.readO2LineList(allocator, case.line_gas.line_list.path);
    errdefer allocator.free(rows);
    const strong_lines = try readers.readO2StrongLines(allocator, case.line_gas.strong_lines.path);
    errdefer allocator.free(strong_lines);
    var relaxation_matrix = try readers.readO2RelaxationMatrix(allocator, case.line_gas.line_mixing.path);
    errdefer relaxation_matrix.deinit(allocator);

    return .{
        .rows = rows,
        .strong_lines = strong_lines,
        .relaxation_matrix = relaxation_matrix,
        .isotopes_sim = case.line_gas.isotopes_sim,
        .threshold_line_sim = case.line_gas.threshold_line_sim,
        .cutoff_sim_cm1 = case.line_gas.cutoff_sim_cm1,
        .line_mixing_factor = case.line_gas.line_mixing_factor,
    };
}
