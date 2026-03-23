//! Purpose:
//!   Centralize bundled reference optics asset ids, manifest paths, and scene-selection helpers.
//!
//! Physics:
//!   Encodes which climatology, spectroscopy, CIA, LUT, and Mie reference assets are used for
//!   the bundled optics reference paths.
//!
//! Vendor:
//!   `bundled optics reference selection`
//!
//! Design:
//!   Keep scene selection logic pure here and let `BundledOptics.zig` focus on loading and
//!   assembling typed reference data. When a scene does not declare absorbers, bundled defaults
//!   are allowed to stand in for the missing configuration.
//!
//! Invariants:
//!   Bundle ids, manifest paths, and spectral window thresholds stay centralized in this module.
//!
//! Validation:
//!   `tests/unit/bundled_optics_test.zig` and the O2A validation helpers.

const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const AbsorberModel = @import("../../model/Absorber.zig");
const ReferenceData = @import("../../model/ReferenceData.zig");
const reference_assets = @import("../../adapters/ingest/reference_assets.zig");

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

/// Purpose:
///   Test whether two wavelength windows overlap.
///
/// Physics:
///   Compare spectral ranges in nanometers for bundled asset gating.
///
/// Units:
///   All arguments are in nanometers.
pub fn overlapsRange(start_nm: f64, end_nm: f64, range_start_nm: f64, range_end_nm: f64) bool {
    return end_nm >= range_start_nm and start_nm <= range_end_nm;
}

/// Purpose:
///   Build a zero-valued continuum table that preserves the scene grid.
///
/// Physics:
///   Keep the spectral sampling but remove continuum absorption when the bundled continuum does
///   not apply.
///
/// Units:
///   The wavelength span is in nanometers.
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

/// Purpose:
///   Load the bundled standard climatology profile.
///
/// Physics:
///   Provide the reference atmospheric background used by bundled optics preparation.
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

/// Purpose:
///   Load the bundled visible-band continuum table.
///
/// Physics:
///   Provide the reference continuum used when the scene overlaps the visible-band window.
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

/// Purpose:
///   Load the bundled visible-band line list.
///
/// Physics:
///   Provide the visible-band spectroscopy reference when the scene does not request O2A data.
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

/// Purpose:
///   Load the bundled O2A line list before strong-line sidecars are attached.
///
/// Physics:
///   Provide the base HITRAN-style O2A spectroscopy table.
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

/// Purpose:
///   Load the bundled O2A strong-line set.
///
/// Physics:
///   Supply the LISA sidecar data needed for the strong-line augmentation path.
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

/// Purpose:
///   Load the bundled O2A relaxation matrix.
///
/// Physics:
///   Supply the LISA sidecar matrix needed to drive strong-line relaxation behavior.
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

/// Purpose:
///   Load the bundled O2A spectroscopy line list with strong-line sidecars attached.
///
/// Physics:
///   Combine the base HITRAN-style line list with the matching strong-line and relaxation data
///   used by the O2A path.
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

/// Purpose:
///   Load the bundled O2A CIA table.
///
/// Physics:
///   Provide the O2-O2 collision-induced absorption data used in the O2A window.
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

/// Purpose:
///   Load the bundled airmass-factor lookup table.
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

/// Purpose:
///   Load the bundled Mie phase table.
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

/// Purpose:
///   Decide whether the visible-band continuum should be loaded for a scene.
///
/// Physics:
///   Gate the visible-band continuum on overlap with the 405-465 nm window.
///
/// Units:
///   The window boundaries are in nanometers.
pub fn shouldLoadVisibleBandContinuum(scene: *const Scene) bool {
    // PARITY:
    //   The visible-band bundle uses the same 405-465 nm gate as the vendor reference path.
    return overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0);
}

/// Purpose:
///   Decide whether the visible-band line list should be loaded for a scene.
///
/// Physics:
///   Gate the visible-band spectroscopy on overlap with the 405-465 nm window.
///
/// Units:
///   The window boundaries are in nanometers.
pub fn shouldLoadVisibleBandLineList(scene: *const Scene) bool {
    return overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 405.0, 465.0);
}

/// Purpose:
///   Decide whether the bundled O2A line list should be used.
///
/// Physics:
///   Allow bundled defaults when no absorbers are declared, or when the scene explicitly requests
///   O2 line-by-line spectroscopy.
pub fn shouldLoadBundledO2ALineList(scene: *const Scene) bool {
    // DECISION:
    //   Empty absorber lists are treated as a bundled-default scene, not as a fully specified
    //   explicit configuration.
    if (scene.absorbers.items.len == 0) return true;
    return sceneRequestsSpectroscopyMode(scene, .o2, .line_by_line);
}

/// Purpose:
///   Decide whether the bundled O2A CIA table should be used.
///
/// Physics:
///   Allow bundled defaults when no absorbers are declared, or when the scene explicitly requests
///   O2 line-by-line or O2-O2 CIA spectroscopy.
pub fn shouldLoadBundledO2ACia(scene: *const Scene) bool {
    // DECISION:
    //   Empty absorber lists are treated as a bundled-default scene, not as a fully specified
    //   explicit configuration.
    if (scene.absorbers.items.len == 0) return true;
    return sceneRequestsSpectroscopyMode(scene, .o2, .line_by_line) or
        sceneRequestsSpectroscopyMode(scene, .o2_o2, .cia);
}

/// Purpose:
///   Check whether a scene requests a specific spectroscopy mode for one absorber species.
///
/// Physics:
///   Match the absorber list against the requested species and spectroscopy mode.
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

/// Purpose:
///   Detect whether the scene already carries explicit spectroscopy bindings.
///
/// Physics:
///   Treat asset-backed line lists, strong-line sidecars, and line-mixing tables as explicit
///   configuration that must resolve before bundled defaults are considered.
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

/// Purpose:
///   Detect whether the scene already carries an explicit CIA binding.
pub fn hasExplicitCiaBindings(scene: *const Scene) bool {
    for (scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.cia_table.kind() == .asset) return true;
    }
    return false;
}

/// Purpose:
///   Resolve an absorber's canonical species label.
///
/// Physics:
///   Normalize legacy spellings so the bundled asset selectors and vendor-style requests agree on
///   the absorber identity.
pub fn resolvedAbsorberSpecies(absorber: AbsorberModel.Absorber) ?AbsorberSpecies {
    if (absorber.resolved_species) |species| return species;
    if (std.meta.stringToEnum(AbsorberSpecies, absorber.species)) |species| return species;
    // GOTCHA:
    //   Legacy configs still spell O2-O2 as `o2o2` or `o2-o2`; both must normalize to the same
    //   canonical species so selector logic stays stable.
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2o2")) return .o2_o2;
    if (std.ascii.eqlIgnoreCase(absorber.species, "o2-o2")) return .o2_o2;
    return null;
}

/// Purpose:
///   Return the first resolved spectroscopy line-list binding in the scene, if any.
pub fn resolvedSpectroscopyLineList(scene: *const Scene) ?*const ReferenceData.SpectroscopyLineList {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_line_list) |*line_list| return line_list;
    }
    return null;
}

/// Purpose:
///   Clone the first resolved spectroscopy line list in the scene, if present.
///
/// Physics:
///   Materialize owned line-list storage so optics preparation can mutate per-request copies.
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

/// Purpose:
///   Return the first resolved CIA binding in the scene, if any.
pub fn resolvedCollisionInducedAbsorptionTable(scene: *const Scene) ?*const ReferenceData.CollisionInducedAbsorptionTable {
    for (scene.absorbers.items) |*absorber| {
        if (absorber.spectroscopy.resolved_cia_table) |*cia_table| return cia_table;
    }
    return null;
}

/// Purpose:
///   Normalize line-list gas indices for resolved spectroscopy bindings.
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
