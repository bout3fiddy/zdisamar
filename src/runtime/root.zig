//! Runtime cache, reference, and scheduler entrypoints used by the engine surface.
pub const cache = @import("cache/root.zig");
pub const reference = @import("reference/root.zig");
pub const scheduler = @import("scheduler/root.zig");

test {
    _ = @import("cache/root.zig");
    _ = @import("reference/root.zig");
    _ = @import("scheduler/root.zig");
}
