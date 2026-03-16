const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OpticsPrepare = @import("../../kernels/optics/prepare.zig");
const reference_assets = @import("../../adapters/ingest/reference_assets.zig");

const Allocator = std.mem.Allocator;

const climatology_manifest_path = "data/climatologies/bundle_manifest.json";
const cross_section_manifest_path = "data/cross_sections/bundle_manifest.json";
const lut_manifest_path = "data/luts/bundle_manifest.json";

pub fn prepareForScene(allocator: Allocator, scene: Scene) !OpticsPrepare.PreparedOpticalState {
    var profile_asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .climatology_profile,
        climatology_manifest_path,
        "us_standard_1976_profile",
    );
    defer profile_asset.deinit(allocator);

    var profile = try profile_asset.toClimatologyProfile(allocator);
    defer profile.deinit(allocator);

    var cross_sections = try loadContinuumForScene(allocator, scene);
    defer cross_sections.deinit(allocator);

    const collision_induced_absorption = try loadCollisionInducedAbsorptionForScene(allocator, scene);
    defer if (collision_induced_absorption) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    const line_list = try loadSpectroscopyForScene(allocator, scene);
    defer if (line_list) |owned_lines| {
        var owned = owned_lines;
        owned.deinit(allocator);
    };

    var lut_asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .lookup_table,
        lut_manifest_path,
        "airmass_factor_nadir_demo",
    );
    defer lut_asset.deinit(allocator);

    var lut = try lut_asset.toAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    var aerosol_mie: ?ReferenceData.MiePhaseTable = null;
    defer if (aerosol_mie) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (scene.atmosphere.has_aerosols or scene.aerosol.enabled) {
        var mie_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .mie_phase_table,
            lut_manifest_path,
            "mie_dust_phase_subset",
        );
        defer mie_asset.deinit(allocator);
        aerosol_mie = try mie_asset.toMiePhaseTable(allocator);
    }

    return OpticsPrepare.prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        collision_induced_absorption,
        line_list,
        lut,
        aerosol_mie,
        null,
    );
}

fn loadContinuumForScene(allocator: Allocator, scene: Scene) !ReferenceData.CrossSectionTable {
    if (overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0)) {
        var asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .cross_section_table,
            cross_section_manifest_path,
            "no2_405_465_demo",
        );
        defer asset.deinit(allocator);
        return asset.toCrossSectionTable(allocator);
    }

    const midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5;
    const points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
        .{ .wavelength_nm = scene.spectral_grid.start_nm, .sigma_cm2_per_molecule = 0.0 },
        .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
        .{ .wavelength_nm = scene.spectral_grid.end_nm, .sigma_cm2_per_molecule = 0.0 },
    });
    return .{ .points = points };
}

fn loadSpectroscopyForScene(allocator: Allocator, scene: Scene) !?ReferenceData.SpectroscopyLineList {
    if (overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5)) {
        var line_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_line_list,
            cross_section_manifest_path,
            "o2a_hitran_subset_07_hit08_tropomi",
        );
        defer line_asset.deinit(allocator);

        var line_list = try line_asset.toSpectroscopyLineList(allocator);

        var strong_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_strong_line_set,
            cross_section_manifest_path,
            "o2a_lisa_sdf_subset",
        );
        defer strong_asset.deinit(allocator);

        var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
        defer strong_lines.deinit(allocator);

        var rmf_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_relaxation_matrix,
            cross_section_manifest_path,
            "o2a_lisa_rmf_subset",
        );
        defer rmf_asset.deinit(allocator);

        var relaxation_matrix = try rmf_asset.toSpectroscopyRelaxationMatrix(allocator);
        defer relaxation_matrix.deinit(allocator);

        try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
        return line_list;
    }

    if (overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0)) {
        var line_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_line_list,
            cross_section_manifest_path,
            "no2_demo_lines",
        );
        defer line_asset.deinit(allocator);
        return try line_asset.toSpectroscopyLineList(allocator);
    }

    return null;
}

fn loadCollisionInducedAbsorptionForScene(
    allocator: Allocator,
    scene: Scene,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    if (!overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5)) {
        return null;
    }

    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .collision_induced_absorption_table,
        cross_section_manifest_path,
        "o2o2_bira_o2a_subset",
    );
    defer asset.deinit(allocator);
    return try asset.toCollisionInducedAbsorptionTable(allocator);
}

fn overlapsRange(start_nm: f64, end_nm: f64, range_start_nm: f64, range_end_nm: f64) bool {
    return end_nm >= range_start_nm and start_nm <= range_end_nm;
}

test "runtime bundled optics uses NO2 assets in the visible band" {
    const scene: Scene = .{
        .id = "runtime-no2",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 48,
        },
        .observation_model = .{
            .instrument = "unit-test",
            .sampling = "native",
            .noise_model = "shot_noise",
        },
        .atmosphere = .{
            .layer_count = 24,
        },
    };

    var prepared = try prepareForScene(std.testing.allocator, scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines == null);
    try std.testing.expect(prepared.mean_cross_section_cm2_per_molecule > 0.0);
}

test "runtime bundled optics uses O2A sidecars and aerosol Mie tables when requested" {
    const scene: Scene = .{
        .id = "runtime-o2a",
        .spectral_grid = .{
            .start_nm = 760.8,
            .end_nm = 771.5,
            .sample_count = 96,
        },
        .observation_model = .{
            .instrument = "tropomi",
            .sampling = "measured_channels",
            .noise_model = "snr_from_input",
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 4,
            .has_aerosols = true,
        },
        .aerosol = .{
            .enabled = true,
            .optical_depth = 0.18,
            .single_scatter_albedo = 0.94,
            .asymmetry_factor = 0.72,
            .angstrom_exponent = 1.2,
            .reference_wavelength_nm = 550.0,
            .layer_center_km = 2.0,
            .layer_width_km = 2.0,
        },
    };

    var prepared = try prepareForScene(std.testing.allocator, scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.relaxation_matrix != null);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers != null);
    try std.testing.expect(prepared.sublayers.?[0].aerosol_phase_coefficients[1] > scene.aerosol.asymmetry_factor);
}
