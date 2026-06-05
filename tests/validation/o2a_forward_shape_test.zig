const std = @import("std");
const zdisamar = @import("zdisamar");
const o2a = zdisamar.o2a;

const meanVectorInRange = o2a.meanVectorInRange;
const minVectorInRange = o2a.minVectorInRange;

test "tracked O2A DISAMAR reflectance jacobian fixture exposes the requested state columns" {
    const fixture_path = "validation/reference_data/spectra/o2a_jacobian_simulation_instrument_reflectance.csv";
    const simulation_reflectance = try readFixture(fixture_path);
    defer std.testing.allocator.free(simulation_reflectance);

    try expectJacobianFixtureShape(simulation_reflectance, 301);
}

fn readFixture(path: []const u8) ![]u8 {
    return try std.Io.Dir.cwd().readFileAlloc(
        std.testing.io,
        path,
        std.testing.allocator,
        .limited(512 * 1024),
    );
}

test "o2a forward reflectance tracks vendor reference morphology" {
    var input = zdisamar.defaultO2AInput();
    input.spectral_grid = .{
        .start_nm = 758.0,
        .end_nm = 770.0,
        .sample_count = 61,
    };
    input.observation.adaptive_reference_grid.points_per_fwhm = 30;
    input.observation.adaptive_reference_grid.strong_line_min_divisions = 6;
    input.observation.adaptive_reference_grid.strong_line_max_divisions = 30;

    var disamar_case = try o2a.runResolvedVendorO2AReflectanceCase(std.testing.allocator, &input);
    defer disamar_case.deinit(std.testing.allocator);

    const prepared = &disamar_case.prepared;
    const product = &disamar_case.product;

    const left_wing_tau = prepared.totalOpticalDepthAtWavelength(758.8);
    const trough_tau = prepared.totalOpticalDepthAtWavelength(760.8);
    const rebound_tau = prepared.totalOpticalDepthAtWavelength(762.0);
    const shoulder_tau = prepared.totalOpticalDepthAtWavelength(767.0);
    const red_wing_tau = prepared.totalOpticalDepthAtWavelength(770.4);

    try std.testing.expect(prepared.column_density_factor > 1.0e24);
    try std.testing.expect(trough_tau > left_wing_tau);
    try std.testing.expect(trough_tau > rebound_tau);
    try std.testing.expect(trough_tau > shoulder_tau);
    try std.testing.expect(trough_tau > red_wing_tau);

    const metrics = o2a.computeComparisonMetrics(product, disamar_case.reference, 0.0);
    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 758.0, 758.5);
    const trough = minVectorInRange(product.wavelengths, product.reflectance, 760.2, 761.1);
    const trough_ratio = trough.value / @max(blue_wing_mean, 1.0e-12);

    try std.testing.expect(metrics.root_mean_square_difference < 0.060);
    try std.testing.expect(metrics.correlation > 0.985);
    try std.testing.expect(@abs(metrics.blue_wing_mean_difference) < 0.060);
    try std.testing.expect(@abs(metrics.trough_wavelength_difference_nm) < 0.60);
    try std.testing.expect(trough_ratio > 0.01);
    try std.testing.expect(trough_ratio < 0.18);
    try std.testing.expect(@abs(metrics.rebound_peak_difference) < 0.10);
    try std.testing.expect(@abs(metrics.mid_band_mean_difference) < 0.075);
    try std.testing.expect(@abs(metrics.red_wing_mean_difference) < 0.060);
}

fn expectJacobianFixtureShape(bytes: []const u8, expected_rows: usize) !void {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const header = std.mem.trim(u8, lines.next() orelse return error.InvalidData, "\r \t");
    try std.testing.expectEqualStrings("wavelength_nm,aerosolTau,intervalDP", header);

    var row_count: usize = 0;
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, "\r \t");
        if (trimmed.len == 0) continue;

        var columns = std.mem.splitScalar(u8, trimmed, ',');
        var column_count: usize = 0;
        while (columns.next()) |column| {
            _ = try std.fmt.parseFloat(f64, std.mem.trim(u8, column, " \t"));
            column_count += 1;
        }
        try std.testing.expectEqual(@as(usize, 3), column_count);
        row_count += 1;
    }
    try std.testing.expectEqual(expected_rows, row_count);
}
