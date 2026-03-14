pub const common = @import("common/root.zig");
pub const oe = @import("oe/root.zig");
pub const doas = @import("doas/root.zig");
pub const dismas = @import("dismas/root.zig");

test {
    _ = @import("common/root.zig");
    _ = @import("oe/root.zig");
    _ = @import("doas/root.zig");
    _ = @import("dismas/root.zig");
}
