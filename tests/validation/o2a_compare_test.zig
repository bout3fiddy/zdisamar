const std = @import("std");
const builtin = @import("builtin");
const o2a_vendor = @import("o2a_vendor_reflectance_support.zig");

const cached_reference_path = "validation/reference/o2a_with_cia_disamar_reference.csv";

const ParityReport = struct {
    transport_family: []const u8,
    n_streams: u16,
    num_orders_max: u16,
    use_adding: bool,
    fit_interval_index_1based: u32,
    interval_count: usize,
    aerosol_interval_index_1based: u32,
};

const CompareReport = struct {
    scenario: []const u8,
    cached_reference_path: []const u8,
    optimize_mode: []const u8,
    elapsed_ms: f64,
    sample_count: usize,
    parity: ParityReport,
    metrics: o2a_vendor.ComparisonMetrics,
};

test "o2a compare emits runtime for the vendor parity fixture and compares against cached vendor reference" {
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
    try std.testing.expectEqualStrings("baseline_labos", compare_case.transport_route.family.provenanceLabel());
    try std.testing.expectEqual(@as(u16, 20), compare_case.transport_route.rtm_controls.n_streams);
    try std.testing.expectEqual(@as(u16, 0), compare_case.transport_route.rtm_controls.num_orders_max);
    try std.testing.expect(!compare_case.transport_route.rtm_controls.use_adding);
    try std.testing.expect(compare_case.transport_route.rtm_controls.use_spherical_correction);
    try std.testing.expect(compare_case.transport_route.rtm_controls.integrate_source_function);
    try std.testing.expect(compare_case.transport_route.rtm_controls.renorm_phase_function);
    try std.testing.expectEqual(.explicit_pressure_bounds, compare_case.prepared.interval_semantics);
    try std.testing.expectEqual(@as(u32, 2), compare_case.prepared.fit_interval_index_1based);
    try std.testing.expectEqual(@as(u32, 2), compare_case.prepared.layers[1].interval_index_1based);
    try std.testing.expectApproxEqAbs(@as(f64, 500.0), compare_case.prepared.layers[1].top_pressure_hpa, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 520.0), compare_case.prepared.layers[1].bottom_pressure_hpa, 1.0e-12);

    // Keep this lane as a stable compare-and-time smoke check rather than a
    // strict zero-residual gate. The goal here is a vendor-equivalent scene and
    // transport path with a reproducible residual report.
    try std.testing.expect(metrics.mean_abs_difference < 0.08);
    try std.testing.expect(metrics.root_mean_square_difference < 0.08);
    try std.testing.expect(metrics.max_abs_difference < 0.10);
    try std.testing.expect(metrics.correlation > 0.985);

    const report: CompareReport = .{
        .scenario = "o2a_vendor_parity_compare",
        .cached_reference_path = cached_reference_path,
        .optimize_mode = @tagName(builtin.mode),
        .elapsed_ms = elapsed_ms,
        .sample_count = compare_case.reference.len,
        .parity = .{
            .transport_family = compare_case.transport_route.family.provenanceLabel(),
            .n_streams = compare_case.transport_route.rtm_controls.n_streams,
            .num_orders_max = compare_case.transport_route.rtm_controls.num_orders_max,
            .use_adding = compare_case.transport_route.rtm_controls.use_adding,
            .fit_interval_index_1based = compare_case.prepared.fit_interval_index_1based,
            .interval_count = compare_case.prepared.layers.len,
            .aerosol_interval_index_1based = compare_case.prepared.layers[1].interval_index_1based,
        },
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
