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
//!   loader facade over typed reference data.
//!
//! Invariants:
//!   Bundle ids and manifest paths stay centralized in the helper module.
//!
//! Validation:
//!   `tests/unit/bundled_optics_test.zig` and the O2A validation helpers.

const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const assets = @import("bundled_optics_assets.zig");

const Allocator = std.mem.Allocator;

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

fn loadContinuumForScene(allocator: Allocator, scene: *const Scene) !ReferenceData.CrossSectionTable {
    if (assets.shouldLoadVisibleBandContinuum(scene)) {
        return try assets.loadVisibleBandContinuumTable(allocator);
    }

    return assets.zeroContinuumTable(allocator, scene.spectral_grid.start_nm, scene.spectral_grid.end_nm);
}

fn loadSpectroscopyForScene(allocator: Allocator, scene: *const Scene) !?ReferenceData.SpectroscopyLineList {
    if (try assets.cloneResolvedSpectroscopyLineList(allocator, scene)) |line_list| {
        return line_list;
    }
    if (assets.hasExplicitSpectroscopyBindings(scene)) {
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

fn loadCollisionInducedAbsorptionForScene(
    allocator: Allocator,
    scene: *const Scene,
) !?ReferenceData.CollisionInducedAbsorptionTable {
    if (assets.resolvedCollisionInducedAbsorptionTable(scene)) |table| {
        return try table.clone(allocator);
    }
    if (assets.hasExplicitCiaBindings(scene)) {
        return error.UnresolvedCollisionInducedAbsorptionBinding;
    }
    if (scene.observation_model.o2o2_operational_lut.enabled()) {
        return null;
    }

    if (!assets.shouldLoadBundledO2ACia(scene) or
        !assets.overlapsRange(scene.spectral_grid.start_nm, scene.spectral_grid.end_nm, 760.8, 771.5))
    {
        return null;
    }

    return try assets.loadO2ACollisionInducedAbsorptionTable(allocator);
}
