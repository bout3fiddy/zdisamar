const std = @import("std");
const zdisamar = @import("zdisamar");
const disamar_reference = zdisamar.disamar_reference;

const meanVectorInRange = disamar_reference.meanVectorInRange;
const minVectorInRange = disamar_reference.minVectorInRange;

test "o2a forward reflectance tracks vendor reference morphology" {
    var disamar_case = try disamar_reference.runDefaultReflectanceCase(std.testing.allocator, .{
        .spectral_grid = .{
            .start_nm = 755.0,
            .end_nm = 776.0,
            .sample_count = 61,
        },
        .adaptive_points_per_fwhm = 20,
        .adaptive_strong_line_min_divisions = 8,
        .adaptive_strong_line_max_divisions = 40,
        .line_mixing_factor = 1.0,
        .isotopes_sim = &.{ 1, 2, 3 },
        .threshold_line_sim = 3.0e-5,
        .cutoff_sim_cm1 = 200.0,
    });
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

    const metrics = disamar_reference.computeComparisonMetrics(product, disamar_case.reference, 0.0);
    const blue_wing_mean = meanVectorInRange(product.wavelengths, product.reflectance, 755.0, 758.5);
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
