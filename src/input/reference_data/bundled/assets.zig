const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const reference_assets = @import("../ingest/reference_assets.zig");

pub const bundle_manifest_paths = struct {
    pub const climatology = "data/climatologies/bundle_manifest.json";
    pub const cross_sections = "data/cross_sections/bundle_manifest.json";
    pub const luts = "data/luts/bundle_manifest.json";
};

pub const asset_ids = struct {
    pub const standard_climatology_profile = "us_standard_1976_profile";
    pub const visible_band_continuum = "no2_405_465_demo";
    pub const visible_band_line_list = "no2_demo_lines";
    pub const o2a_line_list = "o2a_hitran_07_hit08_tropomi";
    pub const o2a_strong_line_set = "o2a_lisa_sdf";
    pub const o2a_relaxation_matrix = "o2a_lisa_rmf";
    pub const o2a_cia = "o2o2_bira_o2a";
    pub const airmass_factor_lut = "airmass_factor_nadir_demo";
    pub const mie_phase_table = "mie_dust_phase_subset";
};

const Allocator = std.mem.Allocator;
const AbsorberSpecies = AbsorberModel.AbsorberSpecies;

pub fn overlapsRange(start_nm: f64, end_nm: f64, range_start_nm: f64, range_end_nm: f64) bool {
    return end_nm >= range_start_nm and start_nm <= range_end_nm;
}

pub fn zeroContinuumTable(
    allocator: Allocator,
    start_nm: f64,
    end_nm: f64,
) !ReferenceData.CrossSectionTable {
    const midpoint_nm = (start_nm + end_nm) * 0.5;
    // UNITS:
    //   The continuum grid is kept in nanometers so downstream interpolation sees the same
    //   spectral support even when the coefficient values are zero.
    return .{
        .points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = start_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = midpoint_nm, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = end_nm, .sigma_cm2_per_molecule = 0.0 },
        }),
    };
}

pub fn loadStandardClimatologyProfile(
    allocator: Allocator,
) !ReferenceData.ClimatologyProfile {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .climatology_profile,
        bundle_manifest_paths.climatology,
        asset_ids.standard_climatology_profile,
    );
    defer asset.deinit(allocator);
    return try asset.toClimatologyProfile(allocator);
}

pub fn loadVisibleBandContinuumTable(
    allocator: Allocator,
) !ReferenceData.CrossSectionTable {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .cross_section_table,
        bundle_manifest_paths.cross_sections,
        asset_ids.visible_band_continuum,
    );
    defer asset.deinit(allocator);
    return try asset.toCrossSectionTable(allocator);
}

pub fn loadVisibleBandLineList(
    allocator: Allocator,
) !ReferenceData.SpectroscopyLineList {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_line_list,
        bundle_manifest_paths.cross_sections,
        asset_ids.visible_band_line_list,
    );
    defer asset.deinit(allocator);
    return try asset.toSpectroscopyLineList(allocator);
}

pub fn loadO2ALineList(
    allocator: Allocator,
) !ReferenceData.SpectroscopyLineList {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_line_list,
        bundle_manifest_paths.cross_sections,
        asset_ids.o2a_line_list,
    );
    defer asset.deinit(allocator);
    return try asset.toSpectroscopyLineList(allocator);
}

pub fn loadO2AStrongLineSet(
    allocator: Allocator,
) !ReferenceData.SpectroscopyStrongLineSet {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_strong_line_set,
        bundle_manifest_paths.cross_sections,
        asset_ids.o2a_strong_line_set,
    );
    defer asset.deinit(allocator);
    return try asset.toSpectroscopyStrongLineSet(allocator);
}

pub fn loadO2ARelaxationMatrix(
    allocator: Allocator,
) !ReferenceData.RelaxationMatrix {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .spectroscopy_relaxation_matrix,
        bundle_manifest_paths.cross_sections,
        asset_ids.o2a_relaxation_matrix,
    );
    defer asset.deinit(allocator);
    return try asset.toSpectroscopyRelaxationMatrix(allocator);
}

pub fn loadO2aSpectroscopyLineList(
    allocator: Allocator,
) !ReferenceData.SpectroscopyLineList {
    var line_list = try loadO2ALineList(allocator);
    errdefer line_list.deinit(allocator);

    var strong_lines = try loadO2AStrongLineSet(allocator);
    defer strong_lines.deinit(allocator);

    var relaxation_matrix = try loadO2ARelaxationMatrix(allocator);
    defer relaxation_matrix.deinit(allocator);

    try line_list.attachStrongLineSidecars(allocator, strong_lines, relaxation_matrix);
    return line_list;
}

pub fn loadO2ACollisionInducedAbsorptionTable(
    allocator: Allocator,
) !ReferenceData.CollisionInducedAbsorptionTable {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .collision_induced_absorption_table,
        bundle_manifest_paths.cross_sections,
        asset_ids.o2a_cia,
    );
    defer asset.deinit(allocator);
    return try asset.toCollisionInducedAbsorptionTable(allocator);
}

pub fn loadAirmassFactorLut(
    allocator: Allocator,
) !ReferenceData.AirmassFactorLut {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .lookup_table,
        bundle_manifest_paths.luts,
        asset_ids.airmass_factor_lut,
    );
    defer asset.deinit(allocator);
    return try asset.toAirmassFactorLut(allocator);
}

pub fn loadMiePhaseTable(
    allocator: Allocator,
) !ReferenceData.MiePhaseTable {
    var asset = try reference_assets.loadCsvBundleAsset(
        allocator,
        .mie_phase_table,
        bundle_manifest_paths.luts,
        asset_ids.mie_phase_table,
    );
    defer asset.deinit(allocator);
    return try asset.toMiePhaseTable(allocator);
}

pub fn shouldLoadVisibleBandContinuum(scene: *const Scene) bool {
    // PARITY:
    //   The visible-band bundle uses the same 405-465 nm gate as the vendor reference path.
    return overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0);
}

pub fn shouldLoadVisibleBandLineList(scene: *const Scene) bool {
    if (!overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0)) {
        return false;
    }
    if (scene.absorbers.items.len == 0) return true;
    var uses_only_implicit_absorbers = true;
    for (scene.absorbers.items) |absorber| {
        switch (absorber.spectroscopy.mode) {
            .line_by_line => return true,
            .none => {},
            .cross_sections, .cia => uses_only_implicit_absorbers = false,
        }
    }
    return uses_only_implicit_absorbers;
}

pub fn shouldLoadBundledO2ALineList(scene: *const Scene) bool {
    // DECISION:
    //   Empty absorber lists are treated as a bundled-default scene, not as a fully specified
    //   explicit configuration.
    if (scene.absorbers.items.len == 0) return true;
    return sceneRequestsSpectroscopyMode(scene, .o2, .line_by_line);
}

pub fn shouldLoadBundledO2ACia(scene: *const Scene) bool {
    // DECISION:
    //   Empty absorber lists are treated as a bundled-default scene, not as a fully specified
    //   explicit configuration.
    if (scene.absorbers.items.len == 0) return true;
    return sceneRequestsSpectroscopyMode(scene, .o2, .line_by_line) or
        sceneRequestsSpectroscopyMode(scene, .o2_o2, .cia);
}

pub fn sceneRequestsSpectroscopyMode(
    scene: *const Scene,
    species: AbsorberSpecies,
    mode: AbsorberModel.SpectroscopyMode,
) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.mode != mode) continue;
        const absorber_species = resolvedAbsorberSpecies(absorber) orelse continue;
        if (absorber_species == species) return true;
    }
    return false;
}

pub fn hasExplicitSpectroscopyBindings(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.line_list.kind() == .asset or
            absorber.spectroscopy.strong_lines.kind() == .asset or
            absorber.spectroscopy.line_mixing.kind() == .asset)
        {
            return true;
        }
    }
    return false;
}

pub fn hasExplicitCiaBindings(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.cia_table.kind() == .asset) return true;
    }
    return false;
}

pub fn resolvedAbsorberSpecies(absorber: AbsorberModel.Absorber) ?AbsorberSpecies {
    return AbsorberModel.resolvedAbsorberSpecies(absorber);
}

pub fn resolvedSpectroscopyLineList(scene: *const Scene) ?*const ReferenceData.SpectroscopyLineList {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_line_list) |*line_list| return line_list;
    }
    return null;
}

pub fn cloneResolvedSpectroscopyLineList(
    allocator: Allocator,
    scene: *const Scene,
) !?ReferenceData.SpectroscopyLineList {
    for (scene.absorbers.items) |absorber| {
        const resolved = absorber.spectroscopy.resolved_line_list orelse continue;
        var owned = try resolved.clone(allocator);
        normalizeResolvedLineGasIndex(&owned, resolvedAbsorberSpecies(absorber));
        return owned;
    }
    return null;
}

pub fn resolvedCollisionInducedAbsorptionTable(scene: *const Scene) ?*const ReferenceData.CollisionInducedAbsorptionTable {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_cia_table) |*cia_table| return cia_table;
    }
    return null;
}

fn normalizeResolvedLineGasIndex(
    line_list: *ReferenceData.SpectroscopyLineList,
    maybe_species: ?AbsorberSpecies,
) void {
    const species = maybe_species orelse return;
    const gas_index = species.hitranIndex() orelse return;
    for (line_list.lines) |*line| {
        if (line.gas_index == 0) line.gas_index = gas_index;
    }
}
