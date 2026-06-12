const std = @import("std");

const profile_line_memory = @import("../cache/profile_line_memory.zig");
const o2_case = @import("../input/o2_case.zig");

pub fn rebuildO2ProfileLineValues(
    allocator: std.mem.Allocator,
    case: o2_case.O2Case,
) !profile_line_memory.ProfileLineValues {
    // rebuildO2ProfileLineValues -----------------------------------------------------------------------------|
    // Rebuild the retained profile-line rows for the exact O2 A wavelength route.                             |
    // --------------------------------------------------------------------------------------------------------|
    return profile_line_memory.buildO2ProfileLineValues(allocator, case);
}
