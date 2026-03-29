const std = @import("std");
const builtin = @import("builtin");
const o2a_vendor = @import("o2a_vendor_reflectance_support.zig");

const cached_reference_path = "validation/reference/o2a_with_cia_disamar_reference.csv";

const CompareReport = struct {
    scenario: []const u8,
    cached_reference_path: []const u8,
    optimize_mode: []const u8,
    elapsed_ms: f64,
    sample_count: usize,
    metrics: o2a_vendor.ComparisonMetrics,
};

test "o2a compare emits runtime and compares zig forward spectrum against cached vendor reference" {
    const started_ns = std.time.nanoTimestamp();
    var compare_case = try o2a_vendor.runVendorO2AReflectanceCase(std.testing.allocator);
    defer compare_case.deinit(std.testing.allocator);
    const elapsed_ns = std.time.nanoTimestamp() - started_ns;
    const elapsed_ms = @as(f64, @floatFromInt(@max(elapsed_ns, 0))) /
        @as(f64, @floatFromInt(std.time.ns_per_ms));

    const metrics = o2a_vendor.computeComparisonMetrics(
        &compare_case.product,
        compare_case.reference,
        1.0e-12,
    );

    try std.testing.expectEqual(compare_case.reference.len, compare_case.product.wavelengths.len);
    try std.testing.expectEqual(compare_case.reference.len, compare_case.product.reflectance.len);
    try o2a_vendor.expectBoundedO2AMorphology(
        compare_case.product.wavelengths,
        compare_case.product.reflectance,
    );

    // Keep this lane as a stable compare-and-time smoke check rather than a
    // strict vendor trend gate. The narrower regression assessment stays in the
    // dedicated vendor lane.
    try std.testing.expect(metrics.mean_abs_difference < 0.08);
    try std.testing.expect(metrics.root_mean_square_difference < 0.08);
    try std.testing.expect(metrics.max_abs_difference < 0.10);
    try std.testing.expect(metrics.correlation > 0.985);

    const report: CompareReport = .{
        .scenario = "o2a_compare",
        .cached_reference_path = cached_reference_path,
        .optimize_mode = @tagName(builtin.mode),
        .elapsed_ms = elapsed_ms,
        .sample_count = compare_case.reference.len,
        .metrics = metrics,
    };

    const rendered = try std.fmt.allocPrint(
        std.testing.allocator,
        "{f}\n",
        .{std.json.fmt(report, .{ .whitespace = .indent_2 })},
    );
    defer std.testing.allocator.free(rendered);
    std.debug.print("{s}", .{rendered});
}
