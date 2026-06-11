const std = @import("std");

const profile_line_memory = @import("../cache/profile_line_memory.zig");
const o2_case = @import("../input/o2_case.zig");

pub fn rebuildReferenceProfileLineValues(
    allocator: std.mem.Allocator,
    case: o2_case.O2Case,
) !profile_line_memory.ProfileLineValues {
    // rebuildReferenceProfileLineValues ----------------------------------------------------------------------|
    // Rebuild the retained profile-line rows for the exact reference wavelength route.                        |
    // --------------------------------------------------------------------------------------------------------|
    return profile_line_memory.buildReferenceProfileLineValues(allocator, case);
}
