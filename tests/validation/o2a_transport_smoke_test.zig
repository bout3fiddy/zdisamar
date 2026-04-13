const std = @import("std");
const zdisamar = @import("zdisamar");
const o2a_vendor = zdisamar.vendor_case;

test "exact O2A transport smoke run produces finite spectral products" {
    var vendor_case = try o2a_vendor.runConfiguredVendorO2AReflectanceCase(std.testing.allocator, .{
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 761.0,
            .sample_count = 3,
        },
        .layer_count = 8,
        .sublayer_divisions = 1,
        .include_cia = false,
        .use_vendor_parity_fixture = false,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
    defer vendor_case.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 3), vendor_case.product.summary.sample_count);
    try std.testing.expect(std.math.isFinite(vendor_case.product.summary.mean_radiance));
    try std.testing.expect(std.math.isFinite(vendor_case.product.summary.mean_irradiance));
    try std.testing.expect(std.math.isFinite(vendor_case.product.summary.mean_reflectance));

    for (vendor_case.product.reflectance) |value| {
        try std.testing.expect(std.math.isFinite(value));
        try std.testing.expect(value >= 0.0);
    }
}
