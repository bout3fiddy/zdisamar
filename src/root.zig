const std = @import("std");

const defaults = @import("input/defaults.zig");
const o2_case = @import("input/o2_case.zig");
const setup_tables = @import("setup/o2_run_tables.zig");
const profile_lines = @import("cache/profile_line_memory.zig");

// root.zig ---------------------------------------------------------------------------------------------------|
// Public WP2 surface for setup data below radiance math.                                                      |
//                                                                                                             |
// public flow                                                                                                 |
//   defaultO2Case -> buildReferenceO2RunTables -> buildReferenceProfileLineValues                             |
//                                                                                                             |
// boundary                                                                                                    |
//   This package stops before optics, transport, spectrum, retrieval, API, and output code. The public names  |
//   describe typed input and setup data only, so later packages can consume explicit table families.          |
// ------------------------------------------------------------------------------------------------------------|

pub const O2Case = o2_case.O2Case;
pub const O2RunTables = setup_tables.O2RunTables;
pub const ProfileLineValues = profile_lines.ProfileLineValues;

pub const defaultO2Case = defaults.referenceCase;
pub const buildReferenceO2RunTables = setup_tables.buildReferenceO2RunTables;
pub const buildReferenceProfileLineValues = profile_lines.buildReferenceProfileLineValues;

pub fn deinitReferenceO2RunTables(allocator: std.mem.Allocator, tables: *O2RunTables) void {
    // deinitReferenceO2RunTables -----------------------------------------------------------------------------|
    // Public teardown wrapper for callers that own reference setup tables.                                    |
    // --------------------------------------------------------------------------------------------------------|
    tables.deinit(allocator);
}
