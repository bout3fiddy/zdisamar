const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const reference_assets = @import("../ingest/reference_assets.zig");

// assets.zig -------------------------------------------------------------------------------------------------|
// Names the retained O2 A reference-data assets and converts them into typed rows used by scene preparation.  |
// This is the asset-ID and clone helper layer below bundled/selection.zig: selection decides whether a scene  |
// should use a resolved scene asset, a bundled default, or a typed rejection; this file performs the concrete |
// load or clone once that decision has been made.                                                             |
//                                                                                                             |
// called by                                                                                                   |
//   selection.zig chooses continuum, spectroscopy, CIA, and LUT inputs for bundled/load.zig. load.zig owns    |
//   the hydrated Data object passed to optical preparation. workflows.zig may consume the same selected       |
//   line lists and CIA tables while generating operational LUTs. Tests cover bundle defaults, explicit        |
//   binding rejection, resolved-payload cloning, and asset-schema conversion.                                 |
//                                                                                                             |
// main paths                                                                                                  |
//   load* functions route manifest IDs through ingest/reference_assets.zig and convert LoadedAsset rows.      |
//   loadO2aSpectroscopyLineList attaches the O2 strong-line sidecar set and relaxation matrix.                |
//   cloneResolvedSpectroscopyLineList copies scene-provided rows and normalizes missing HITRAN gas indexes.   |
//   shouldLoadBundled* treats empty absorber lists as the bundled-default O2 A scene.                         |
//                                                                                                             |
// boundary                                                                                                    |
//   This file may load retained CSV assets through the reference-asset ingest layer, but it does not parse    |
//   user control files, choose fallback policy, run the RTM, or write diagnostics. Explicit unresolved        |
//   bindings are rejected by selection.zig instead of silently falling back to bundled defaults.              |
//                                                                                                             |
// row handoff                                                                                                 |
//   SpectroscopyLineList rows returned from here are owned by the caller. Bundled O2 A rows already carry     |
//   HITRAN gas_index values; cloned scene-provided rows may use gas_index=0, so clone normalization fills     |
//   the absorber species HITRAN index before optical preparation hashes and filters the list.                 |
//                                                                                                             |
// memory                                                                                                      |
//   bundle_manifest_paths and asset_ids are namespace-only constant groups, so they have no runtime state.    |
//   Loaded tables own their returned arrays; zeroContinuumTable allocates the small 3-point zero table.       |
//   normalizeResolvedLineGasIndex mutates only a cloned list and leaves scene-owned line lists borrowed.      |
// ------------------------------------------------------------------------------------------------------------|

pub const bundle_manifest_paths = struct {
    pub const climatology = "data/reference_data/climatologies/bundle_manifest.json";
    pub const cross_sections = "data/reference_data/cross_sections/bundle_manifest.json";
    pub const luts = "data/reference_data/luts/bundle_manifest.json";
};

pub const asset_ids = struct {
    pub const standard_climatology_profile = "us_standard_1976_profile";
    pub const o2a_line_list = "o2a_hitran_07_hit08_tropomi";
    pub const o2a_strong_line_set = "o2a_lisa_sdf";
    pub const o2a_relaxation_matrix = "o2a_lisa_rmf";
    pub const o2a_cia = "o2o2_bira_o2a";
    pub const airmass_factor_lut = "airmass_factor_nadir_demo";
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
    // loadO2aSpectroscopyLineList ----------------------------------------------------------------------------|
    // Load the bundled O2 A line list and attach DISAMAR-style strong-line sidecars.                          |
    //                                                                                                         |
    // ownership                                                                                               |
    //   The returned SpectroscopyLineList owns its line rows plus cloned strong-line and relaxation storage.  |
    //   Temporary sidecar containers are released after attachStrongLineSidecars clones them into the list.   |
    //                                                                                                         |
    // call path                                                                                               |
    //   selection.zig uses this only after policy has chosen the bundled O2 A line-list path.                 |
    // --------------------------------------------------------------------------------------------------------|

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
    // cloneResolvedSpectroscopyLineList ----------------------------------------------------------------------|
    // Clone the first resolved scene-provided spectroscopy line list for bundled preparation.                 |
    //                                                                                                         |
    // boundary                                                                                                |
    //   This is not the bundled-default path. It preserves an explicit resolved scene payload, then fills     |
    //   missing HITRAN gas indexes from the absorber species so later spectroscopy setup sees concrete rows.  |
    //                                                                                                         |
    // ownership                                                                                               |
    //   The clone is caller-owned. The source Scene and its resolved line list remain borrowed.               |
    // --------------------------------------------------------------------------------------------------------|

    for (scene.absorbers.items) |absorber| {
        const resolved = absorber.spectroscopy.resolved_line_list orelse continue;
        var owned = try resolved.clone(allocator);
        normalizeResolvedLineGasIndex(&owned, resolvedAbsorberSpecies(absorber));
        return owned;
    }
    return null;
}

pub fn resolvedCollisionInducedAbsorptionTable(
    scene: *const Scene,
) ?*const ReferenceData.CollisionInducedAbsorptionTable {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_cia_table) |*cia_table| return cia_table;
    }
    return null;
}

fn normalizeResolvedLineGasIndex(
    line_list: *ReferenceData.SpectroscopyLineList,
    maybe_species: ?AbsorberSpecies,
) void {
    // normalizeResolvedLineGasIndex --------------------------------------------------------------------------|
    // Fill missing HITRAN gas indexes on a cloned scene-provided line list.                                   |
    //                                                                                                         |
    // hot path                                                                                                |
    //   This is setup work after cloneResolvedSpectroscopyLineList, not per-wavelength spectroscopy.          |
    //                                                                                                         |
    // memory                                                                                                  |
    //   The loop reads and may write gas_index at [88..89] of each 104 B SpectroscopyLine row. It uses        |
    //   pointer capture, does not copy rows, and avoids a side index because this one-time normalization      |
    //   must keep the public line-list row intact for later spectroscopy evaluation and cache-key hashing.    |
    // --------------------------------------------------------------------------------------------------------|

    const species = maybe_species orelse return;
    const gas_index = species.hitranIndex() orelse return;
    for (line_list.lines) |*line| {
        if (line.gas_index == 0) line.gas_index = gas_index;
    }
}
