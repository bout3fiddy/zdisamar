pub const common = @import("common.zig");
pub const adding = @import("adding.zig");
pub const labos = @import("labos.zig");
pub const dispatcher = @import("dispatcher.zig");

test {
    _ = @import("common.zig");
    _ = @import("adding.zig");
    _ = @import("labos.zig");
    _ = @import("dispatcher.zig");
}
