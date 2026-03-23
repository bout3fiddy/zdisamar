pub const prepare = @import("prepare.zig");
pub const preparation = @import("preparation.zig");

test "optics package includes preparation pipeline" {
    _ = @import("prepare.zig");
    _ = @import("preparation.zig");
}
