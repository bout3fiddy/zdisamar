//! Purpose:
//!   Load bundled reference optics data for a scene.
//!
//! Physics:
//!   Assemble the reference climatology, spectroscopy, CIA, LUT, and optional Mie data needed
//!   by optics preparation.
//!
//! Vendor:
//!   `bundled optics reference loader`
//!
//! Design:
//!   Keep the scene-selection rules in `bundled_optics_assets.zig` and let this module act as a
//!   loader facade over typed reference data. Explicit scene bindings win over bundled defaults,
//!   and unresolved explicit bindings fail early instead of silently falling back.
//!
//! Invariants:
//!   Bundle ids, manifest paths, and spectral-window thresholds stay centralized in the helper
//!   module.
//!
//! Validation:
//!   `tests/unit/bundled_optics_test.zig` and the O2A validation helpers.

const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const assets = @import("bundled_optics_assets.zig");

const Allocator = std.mem.Allocator;

/// Purpose:
///   Build the bundled optics state for a canonical scene.
///
/// Physics:
///   Load the climatology, spectroscopy, CIA, LUT, and optional Mie inputs that optics
///   preparation needs for the current scene.
///
/// Vendor:
///   `bundled optics reference loader::prepareForScene`
///
/// Inputs:
///   `scene` provides the canonical spectral range, absorber bindings, and observation controls.
///
/// Outputs:
///   A prepared optical state that owns the cloned reference data used by optics kernels.
///
/// Decisions:
///   Bundled data is loaded only when the scene does not already carry explicit bindings for the
///   same scientific role.
///
/// Validation:
///   Bundled optics unit tests and the O2A validation helpers.
pub fn prepareForScene(allocator: Allocator, scene: *const Scene) !OpticsPrepare.PreparedOpticalState {
    var profile = try assets.loadStandardClimatologyProfile(allocator);
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

    var lut = try assets.loadAirmassFactorLut(allocator);
    defer lut.deinit(allocator);

    var aerosol_mie: ?ReferenceData.MiePhaseTable = null;
    defer if (aerosol_mie) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (scene.atmosphere.has_aerosols or scene.aerosol.enabled) {
        aerosol_mie = try assets.loadMiePhaseTable(allocator);
    }

    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = if (collision_induced_absorption) |*table| table else null;
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = if (line_list) |*table| table else null;
    const aerosol_mie_ptr: ?*const ReferenceData.MiePhaseTable = if (aerosol_mie) |*table| table else null;

    return OpticsPrepare.prepare(allocator, scene, .{
        .profile = &profile,
        .cross_sections = &cross_sections,
        .collision_induced_absorption = cia_ptr,
        .spectroscopy_lines = line_list_ptr,
        .lut = &lut,
        .aerosol_mie = aerosol_mie_ptr,
    });
}

/// Purpose:
///   Resolve the continuum table required by the current scene.
///
/// Physics:
///   Load the visible-band continuum when the scene overlaps the bundled window; otherwise emit a
///   zero-valued table that preserves the expected spectral span.
///
/// Units:
///   The visible-band check uses nanometers.
fn loadContinuumForScene(allocator: Allocator, scene: *const Scene) !ReferenceData.CrossSectionTable {
    if (assets.shouldLoadVisibleBandContinuum(scene)) {
        return try assets.loadVisibleBandContinuumTable(allocator);
    }

    // UNITS:
    //   The fallback table preserves the scene's spectral grid in nanometers while keeping the
    //   continuum coefficient identically zero.
    return assets.zeroContinuumTable(allocator, scene.spectral_grid.start_nm, scene.spectral_grid.end_nm);
}

/// Purpose:
///   Resolve the spectroscopy line list required by the current scene.
///
/// Physics:
///   Load explicit line-list bindings first, then bundled O2A or visible-band defaults when the
///   scene requests them.
///
/// Units:
///   The O2A gate spans 760.8 nm to 771.5 nm.
fn loadSpectroscopyForScene(allocator: Allocator, scene: *const Scene) !?ReferenceData.SpectroscopyLineList {
    if (try assets.cloneResolvedSpectroscopyLineList(allocator, scene)) |line_list| {
        return line_list;
    }
    if (assets.hasExplicitSpectroscopyBindings(scene)) {
        // GOTCHA:
        //   Explicit asset bindings must resolve; otherwise a missing asset would silently mask a
        //   configuration problem if we fell back to bundled defaults here.
        return error.UnresolvedSpectroscopyBinding;
    }

    if (assets.shouldLoadBundledO2ALineList(scene) and
        assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return try assets.loadO2aSpectroscopyLineList(allocator);
    }

    if (assets.shouldLoadVisibleBandLineList(scene)) {
        return try assets.loadVisibleBandLineList(allocator);
    }

    return null;
}

/// Purpose:
///   Resolve the CIA table required by the current scene.
///
/// Physics:
///   Prefer explicit CIA bindings, suppress the bundled O2-O2 table when the operational LUT is
///   active, and otherwise load the bundled O2A CIA in the O2A window.
///
/// Units:
///   The O2A gate spans 760.8 nm to 771.5 nm.
fn loadCollisionInducedAbsorptionForScene(
    allocator: Allocator,
    scene: *const Scene,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    const requests_explicit_cia = assets.sceneRequestsSpectroscopyMode(scene, .o2_o2, .cia);
    const has_explicit_cia_bindings = assets.hasExplicitCiaBindings(scene);
    if (requests_explicit_cia) {
        if (assets.resolvedCollisionInducedAbsorptionTable(scene)) |table| {
            return try table.clone(allocator);
        }
    }
    if (has_explicit_cia_bindings) {
        // GOTCHA:
        //   Explicit CIA bindings must be materialized or the scene configuration is incomplete.
        return error.UnresolvedCollisionInducedAbsorptionBinding;
    }
    if (scene.observation_model.primaryOperationalBandSupport().o2o2_operational_lut.enabled()) {
        // DECISION:
        //   The operational LUT takes precedence over the bundled O2-O2 CIA sidecar to preserve
        //   the runtime control path expected by the scene configuration.
        return null;
    }

    if (!assets.shouldLoadBundledO2ACia(scene) or
        !assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return null;
    }

    return try assets.loadO2ACollisionInducedAbsorptionTable(allocator);
}
