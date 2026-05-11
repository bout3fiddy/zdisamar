const std = @import("std");
const zdisamar = @import("zdisamar");

test "typed baseline O2A transport smoke run produces finite spectral products" {
    var input = zdisamar.defaultO2AInput();
    input.spectral_grid = .{
        .start_nm = 760.0,
        .end_nm = 761.0,
        .sample_count = 3,
    };

    var disamar_case = try zdisamar.o2a.runResolvedVendorO2AReflectanceCase(std.testing.allocator, &input);
    defer disamar_case.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 3), disamar_case.product.summary.sample_count);
    try std.testing.expect(std.math.isFinite(disamar_case.product.summary.mean_radiance));
    try std.testing.expect(std.math.isFinite(disamar_case.product.summary.mean_irradiance));
    try std.testing.expect(std.math.isFinite(disamar_case.product.summary.mean_reflectance));

    for (disamar_case.product.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value >= 0.0);
    }
}
