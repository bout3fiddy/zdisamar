const std = @import("std");
const zdisamar = @import("zdisamar");

test "integration lifecycle rejects unsupported derivative-enabled execution modes explicitly" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();

    try engine.bootstrapBuiltinCatalog();

    try std.testing.expectError(
        error.UnsupportedExecutionMode,
        engine.preparePlan(.{
            .model_family = "disamar_standard",
            .solver_mode = .derivative_enabled,
        }),
    );
}
