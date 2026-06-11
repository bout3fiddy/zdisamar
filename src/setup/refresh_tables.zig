const std = @import("std");

const o2_case = @import("../input/o2_case.zig");
const o2_run_tables = @import("o2_run_tables.zig");

pub fn rebuildReferenceTables(
    allocator: std.mem.Allocator,
    case: o2_case.O2Case,
) !o2_run_tables.O2RunTables {
    // rebuildReferenceTables ---------------------------------------------------------------------------------|
    // Rebuild all setup table families for a reference case.                                                  |
    // --------------------------------------------------------------------------------------------------------|
    return o2_run_tables.buildReferenceO2RunTables(allocator, case);
}
