const std = @import("std");

const readers = @import("../assets/readers.zig");
const scene_input = @import("../input/scene.zig");

const Allocator = std.mem.Allocator;

// LineTable --------------------------------------------------------------------------------------------------|
// O2 line-list setup table parsed from the configured HITRAN and LISA sidecar assets.                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] rows              : []LineAssetRow                                                               |
// [ 16.. 31] strong_lines      : []StrongLineAssetRow                                                         |
// [ 32.. 71] relaxation_matrix : RelaxationMatrixAsset                                                        |
// [ 72.. 87] isotopes_sim      : []const u8                                                                   |
// [ 88.. 95] threshold_line_sim: f64                                                                          |
// [ 96..103] cutoff_sim_cm1    : f64                                                                          |
// [104..111] line_mixing_factor: f64                                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows, strong_lines, and relaxation_matrix own parsed asset rows. isotopes_sim borrows the case controls.  |
pub const LineTable = struct {
    rows: []readers.LineAssetRow,
    strong_lines: []readers.StrongLineAssetRow,
    relaxation_matrix: readers.RelaxationMatrixAsset,
    isotopes_sim: []const u8,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
    line_mixing_factor: f64,

    pub fn deinit(self: *LineTable, allocator: Allocator) void {
        // LineTable.deinit -----------------------------------------------------------------------------------|
        // Release parsed line-list rows and sidecar rows owned by this setup table.                           |
        // ----------------------------------------------------------------------------------------------------|
        self.relaxation_matrix.deinit(allocator);
        allocator.free(self.strong_lines);
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn build(allocator: Allocator, scene: scene_input.Scene) !LineTable {
    // build --------------------------------------------------------------------------------------------------|
    // Load raw O2 HITRAN rows and copy the runtime line-filter controls.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try readers.readLineList(allocator, scene.line_gas.line_list.path);
    errdefer allocator.free(rows);
    const strong_lines = try readers.readStrongLines(allocator, scene.line_gas.strong_lines.path);
    errdefer allocator.free(strong_lines);
    var relaxation_matrix = try readers.readRelaxationMatrix(allocator, scene.line_gas.line_mixing.path);
    errdefer relaxation_matrix.deinit(allocator);

    return .{
        .rows = rows,
        .strong_lines = strong_lines,
        .relaxation_matrix = relaxation_matrix,
        .isotopes_sim = scene.line_gas.isotopes_sim,
        .threshold_line_sim = scene.line_gas.threshold_line_sim,
        .cutoff_sim_cm1 = scene.line_gas.cutoff_sim_cm1,
        .line_mixing_factor = scene.line_gas.line_mixing_factor,
    };
}
