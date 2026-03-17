const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OpticsPrepare = @import("../../kernels/optics/prepare.zig");
const reference_assets = @import("../../adapters/ingest/reference_assets.zig");

const Allocator = std.mem.Allocator;

const climatology_manifest_path = "data/climatologies/bundle_manifest.json";
const cross_section_manifest_path = "data/cross_sections/bundle_manifest.json";
const lut_manifest_path = "data/luts/bundle_manifest.json";

pub fn prepareForScene(allocator: Allocator, scene: *const Scene) !OpticsPrepare.PreparedOpticalState {
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

    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = if (collision_induced_absorption) |*table| table else null;
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = if (line_list) |*table| table else null;
    const aerosol_mie_ptr: ?*const ReferenceData.MiePhaseTable = if (aerosol_mie) |*table| table else null;

    return OpticsPrepare.prepareWithParticleTables(
        allocator,
        scene,
        &profile,
        &cross_sections,
        cia_ptr,
        line_list_ptr,
        &lut,
        aerosol_mie_ptr,
        null,
    );
}

fn loadContinuumForScene(allocator: Allocator, scene: *const Scene) !ReferenceData.CrossSectionTable {
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

fn loadSpectroscopyForScene(allocator: Allocator, scene: *const Scene) !?ReferenceData.SpectroscopyLineList {
    if (resolvedSpectroscopyLineList(scene)) |line_list| {
        return try line_list.clone(allocator);
    }
    if (hasExplicitSpectroscopyBindings(scene)) {
        return error.UnresolvedSpectroscopyBinding;
    }

    if (overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5)) {
        var line_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_line_list,
            cross_section_manifest_path,
            "o2a_hitran_07_hit08_tropomi",
        );
        defer line_asset.deinit(allocator);

        var line_list = try line_asset.toSpectroscopyLineList(allocator);

        var strong_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_strong_line_set,
            cross_section_manifest_path,
            "o2a_lisa_sdf",
        );
        defer strong_asset.deinit(allocator);

        var strong_lines = try strong_asset.toSpectroscopyStrongLineSet(allocator);
        defer strong_lines.deinit(allocator);

        var rmf_asset = try reference_assets.loadCsvBundleAsset(
            allocator,
            .spectroscopy_relaxation_matrix,
            cross_section_manifest_path,
            "o2a_lisa_rmf",
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
    scene: *const Scene,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    if (resolvedCollisionInducedAbsorptionTable(scene)) |table| {
        return try table.clone(allocator);
    }
    if (hasExplicitCiaBindings(scene)) {
        return error.UnresolvedCollisionInducedAbsorptionBinding;
    }

    if (!overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5)) {
        return null;
    }

    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .collision_induced_absorption_table,
        cross_section_manifest_path,
        "o2o2_bira_o2a",
    );
    defer asset.deinit(allocator);
    return try asset.toCollisionInducedAbsorptionTable(allocator);
}

fn overlapsRange(start_nm: f64, end_nm: f64, range_start_nm: f64, range_end_nm: f64) bool {
    return end_nm >= range_start_nm and start_nm <= range_end_nm;
}

fn resolvedSpectroscopyLineList(scene: *const Scene) ?*const ReferenceData.SpectroscopyLineList {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_line_list) |*line_list| return line_list;
    }
    return null;
}

fn resolvedCollisionInducedAbsorptionTable(scene: *const Scene) ?*const ReferenceData.CollisionInducedAbsorptionTable {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_cia_table) |*cia_table| return cia_table;
    }
    return null;
}

fn hasExplicitSpectroscopyBindings(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.line_list.kind == .asset or
            absorber.spectroscopy.strong_lines.kind == .asset or
            absorber.spectroscopy.line_mixing.kind == .asset)
        {
            return true;
        }
    }
    return false;
}

fn hasExplicitCiaBindings(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.cia_table.kind == .asset) return true;
    }
    return false;
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

    var prepared = try prepareForScene(std.testing.allocator, &scene);
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

    var prepared = try prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expect(prepared.spectroscopy_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.relaxation_matrix != null);
    try std.testing.expect(prepared.spectroscopy_lines.?.lines.len >= 1300);
    try std.testing.expect(prepared.spectroscopy_lines.?.strong_lines.?.len >= 70);
    try std.testing.expect(prepared.spectroscopy_lines.?.relaxation_matrix.?.line_count >= 70);
    try std.testing.expect(prepared.collision_induced_absorption != null);
    try std.testing.expect(prepared.collision_induced_absorption.?.points.len >= 18000);
    try std.testing.expect(prepared.cia_optical_depth > 0.0);
    try std.testing.expect(prepared.sublayers != null);
    try std.testing.expect(prepared.sublayers.?[0].aerosol_phase_coefficients[1] > scene.aerosol.asymmetry_factor);
}

test "runtime bundled optics honors resolved scene spectroscopy assets before range defaults" {
    const lines = try std.testing.allocator.dupe(ReferenceData.SpectroscopyLine, &.{
        .{
            .center_wavelength_nm = 760.7,
            .line_strength_cm2_per_molecule = 1.0e-24,
            .air_half_width_nm = 0.01,
            .temperature_exponent = 0.7,
            .lower_state_energy_cm1 = 10.0,
            .pressure_shift_nm = 0.0,
            .line_mixing_coefficient = 0.0,
        },
    });
    errdefer std.testing.allocator.free(lines);

    const cia_points = try std.testing.allocator.dupe(ReferenceData.CollisionInducedAbsorptionPoint, &.{
        .{
            .wavelength_nm = 760.7,
            .a0 = 1.0e-46,
            .a1 = 0.0,
            .a2 = 0.0,
        },
    });
    errdefer std.testing.allocator.free(cia_points);

    const scene: Scene = .{
        .id = "runtime-explicit-assets",
        .spectral_grid = .{
            .start_nm = 760.6,
            .end_nm = 760.8,
            .sample_count = 8,
        },
        .absorbers = .{
            .items = &[_]@import("../../model/Absorber.zig").Absorber{
                .{
                    .id = "o2",
                    .species = "o2",
                    .profile_source = .{ .kind = .atmosphere },
                    .spectroscopy = .{
                        .mode = .line_by_line,
                        .line_list = .{ .kind = .asset, .name = "explicit_line_list" },
                        .resolved_line_list = .{ .lines = lines },
                    },
                },
                .{
                    .id = "o2o2",
                    .species = "o2o2",
                    .profile_source = .{ .kind = .atmosphere },
                    .spectroscopy = .{
                        .mode = .cia,
                        .cia_table = .{ .kind = .asset, .name = "explicit_cia" },
                        .resolved_cia_table = .{
                            .scale_factor_cm5_per_molecule2 = 1.0,
                            .points = cia_points,
                        },
                    },
                },
            },
        },
        .observation_model = .{
            .instrument = "unit-test",
            .sampling = "native",
            .noise_model = "none",
        },
        .atmosphere = .{
            .layer_count = 4,
        },
    };

    var prepared = try prepareForScene(std.testing.allocator, &scene);
    defer prepared.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), prepared.spectroscopy_lines.?.lines.len);
    try std.testing.expectEqual(@as(usize, 1), prepared.collision_induced_absorption.?.points.len);
}
