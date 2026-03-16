pub const gauss_legendre = @import("gauss_legendre.zig");
pub const composite_trapezoid = @import("composite_trapezoid.zig");
pub const source_integration = @import("source_integration.zig");

test {
    _ = @import("gauss_legendre.zig");
    _ = @import("composite_trapezoid.zig");
    _ = @import("source_integration.zig");
}
