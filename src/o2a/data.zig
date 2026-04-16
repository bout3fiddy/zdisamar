const load = @import("data/load.zig");

pub const Data = load.Data;

pub fn loadData(
    allocator: @import("std").mem.Allocator,
    case: *const @import("case.zig").Case,
) !Data {
    return load.load(allocator, case);
}

pub fn buildOptics(
    allocator: @import("std").mem.Allocator,
    case: *const @import("case.zig").Case,
    data: *Data,
) !@import("../kernels/optics/preparation.zig").PreparedOpticalState {
    return load.buildOptics(allocator, case, data);
}
