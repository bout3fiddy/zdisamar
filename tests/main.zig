comptime {
    _ = @import("unit/main.zig");
    _ = @import("integration/main.zig");
    _ = @import("golden/main.zig");
    _ = @import("perf/main.zig");
    _ = @import("validation/main.zig");
}
