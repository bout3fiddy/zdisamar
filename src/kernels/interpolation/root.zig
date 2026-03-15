pub const linear = @import("linear.zig");
pub const spline = @import("spline.zig");
pub const resample = @import("resample.zig");

test {
    _ = @import("linear.zig");
    _ = @import("spline.zig");
    _ = @import("resample.zig");
}
