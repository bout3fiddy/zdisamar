const std = @import("std");

const o2_case = @import("../input/o2_case.zig");
const o2_run_tables = @import("o2_run_tables.zig");

pub fn rebuildO2RunTables(
    allocator: std.mem.Allocator,
    case: o2_case.O2Case,
) !o2_run_tables.O2RunTables {
    // rebuildO2RunTables -------------------------------------------------------------------------------------|
    // Rebuild all setup table families for an O2 A case.                                                      |
    // --------------------------------------------------------------------------------------------------------|
    return o2_run_tables.buildO2RunTables(allocator, case);
}
