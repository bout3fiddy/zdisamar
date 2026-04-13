const data = @import("data.zig");

pub const Optics = @import("../kernels/optics/preparation.zig").PreparedOpticalState;

pub fn build(
    allocator: @import("std").mem.Allocator,
    case: *const @import("case.zig").Case,
    loaded: *data.Data,
) !Optics {
    return data.buildOptics(allocator, case, loaded);
}
