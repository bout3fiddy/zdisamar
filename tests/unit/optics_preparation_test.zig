const std = @import("std");
const zdisamar = @import("zdisamar");

test "optical preparation bridges tracked assets into transport-ready state" {
    var climatology_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .climatology_profile,
        "data/climatologies/bundle_manifest.json",
        "us_standard_1976_profile",
    );
    defer climatology_asset.deinit(std.testing.allocator);

    var cross_section_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .cross_section_table,
        "data/cross_sections/bundle_manifest.json",
        "no2_405_465_demo",
    );
    defer cross_section_asset.deinit(std.testing.allocator);
    var spectroscopy_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .spectroscopy_line_list,
        "data/cross_sections/bundle_manifest.json",
        "no2_demo_lines",
    );
    defer spectroscopy_asset.deinit(std.testing.allocator);

    var lut_asset = try zdisamar.ingest.reference_assets.loadCsvBundleAsset(
        std.testing.allocator,
        .lookup_table,
        "data/luts/bundle_manifest.json",
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(std.testing.allocator);

    var profile = try climatology_asset.toClimatologyProfile(std.testing.allocator);
    defer profile.deinit(std.testing.allocator);
    var cross_sections = try cross_section_asset.toCrossSectionTable(std.testing.allocator);
    defer cross_sections.deinit(std.testing.allocator);
    var spectroscopy = try spectroscopy_asset.toSpectroscopyLineList(std.testing.allocator);
    defer spectroscopy.deinit(std.testing.allocator);
    var lut = try lut_asset.toAirmassFactorLut(std.testing.allocator);
    defer lut.deinit(std.testing.allocator);

    const scene: zdisamar.Scene = .{
        .id = "optics-from-assets",
        .atmosphere = .{
            .layer_count = 5,
            .has_clouds = true,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.18,
            .single_scatter_albedo = 0.95,
            .asymmetry_factor = 0.68,
            .angstrom_exponent = 1.35,
            .reference_wavelength_nm = 550.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.5,
        },
        .cloud = .{
            .enabled = true,
            .optical_thickness = 0.22,
            .single_scatter_albedo = 0.999,
            .asymmetry_factor = 0.85,
            .angstrom_exponent = 0.25,
            .reference_wavelength_nm = 550.0,
            .top_altitude_km = 3.5,
            .thickness_km = 1.5,
        },
        .geometry = .{
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 20.0,
            .relative_azimuth_deg = 60.0,
        },
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 121,
        },
    };

    var prepared = try zdisamar.optics.prepare.prepareWithSpectroscopy(
        std.testing.allocator,
        scene,
        profile,
        cross_sections,
        spectroscopy,
        lut,
    );
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), prepared.layers.len);
    try std.testing.expect(prepared.mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.line_mean_cross_section_cm2_per_molecule > 0.0);
    try std.testing.expect(prepared.line_mixing_mean_cross_section_cm2_per_molecule != 0.0);
    try std.testing.expect(prepared.total_optical_depth > 0.0);
    try std.testing.expect(prepared.gas_optical_depth > 0.0);
    try std.testing.expect(prepared.aerosol_optical_depth > 0.0);
    try std.testing.expect(prepared.d_optical_depth_d_temperature != 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 1.756), prepared.effective_air_mass_factor, 1e-9);
    try std.testing.expect(prepared.totalCrossSectionAtWavelength(434.6) > prepared.totalCrossSectionAtWavelength(420.0));
    try std.testing.expect(prepared.aerosolOpticalDepthAtWavelength(405.0) > prepared.aerosolOpticalDepthAtWavelength(465.0));
    try std.testing.expect(prepared.totalOpticalDepthAtWavelength(405.0) > prepared.totalOpticalDepthAtWavelength(465.0));

    const route = try zdisamar.transport.dispatcher.prepare(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    const result = try zdisamar.transport.dispatcher.executePrepared(
        route,
        prepared.toForwardInput(scene),
    );

    try std.testing.expect(result.toa_radiance > 0.0);
    try std.testing.expect(result.jacobian_column != null);
}
