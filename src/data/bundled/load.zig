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
//!   Keep the scene-selection rules in `assets.zig` and let this module act as a
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
const AbsorberModel = @import("../../model/Absorber.zig");
const ReferenceData = @import("../../model/ReferenceData.zig");
const Instrument = @import("../../model/Instrument.zig").Instrument;
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const OpticsState = @import("../../kernels/optics/preparation/state.zig");
const assets = @import("assets.zig");
const selection = @import("selection.zig");
const workflows = @import("workflows.zig");

const Allocator = std.mem.Allocator;

pub const Data = struct {
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    lut: ReferenceData.AirmassFactorLut,
    aerosol_mie: ?ReferenceData.MiePhaseTable = null,
    working_case: Scene,
    owns_absorbers: bool = false,
    owns_operational_band_support: bool = false,
    generated_lut_assets: []OpticsState.GeneratedLutAsset = &.{},
    lut_execution_entries: []const []const u8 = &.{},

    pub fn deinit(self: *Data, allocator: Allocator) void {
        self.profile.deinit(allocator);
        self.cross_sections.deinit(allocator);
        if (self.collision_induced_absorption) |*owned_table| owned_table.deinit(allocator);
        if (self.spectroscopy_lines) |*owned_lines| owned_lines.deinit(allocator);
        self.lut.deinit(allocator);
        if (self.aerosol_mie) |*owned_table| owned_table.deinit(allocator);
        if (self.owns_absorbers) {
            self.working_case.absorbers.deinitOwned(allocator);
        }
        if (self.owns_operational_band_support) {
            for (self.working_case.observation_model.operational_band_support) |*support| support.deinitOwned(allocator);
            allocator.free(self.working_case.observation_model.operational_band_support);
        }
        for (self.generated_lut_assets) |*asset| asset.deinitOwned(allocator);
        if (self.generated_lut_assets.len != 0) allocator.free(self.generated_lut_assets);
        for (self.lut_execution_entries) |entry| allocator.free(entry);
        if (self.lut_execution_entries.len != 0) allocator.free(self.lut_execution_entries);
        self.* = undefined;
    }
};

pub fn load(allocator: Allocator, scene: *const Scene) !Data {
    var profile = try assets.loadStandardClimatologyProfile(allocator);
    errdefer profile.deinit(allocator);

    var cross_sections = try selection.loadContinuumForScene(allocator, scene);
    errdefer cross_sections.deinit(allocator);

    const collision_induced_absorption = try selection.loadCollisionInducedAbsorptionForScene(allocator, scene);
    errdefer if (collision_induced_absorption) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    const line_list = try selection.loadSpectroscopyForScene(allocator, scene);
    errdefer if (line_list) |owned_lines| {
        var owned = owned_lines;
        owned.deinit(allocator);
    };

    var lut = try assets.loadAirmassFactorLut(allocator);
    errdefer lut.deinit(allocator);

    var aerosol_mie: ?ReferenceData.MiePhaseTable = null;
    errdefer if (aerosol_mie) |owned_table| {
        var owned = owned_table;
        owned.deinit(allocator);
    };

    if (scene.atmosphere.has_aerosols or scene.aerosol.enabled) {
        aerosol_mie = try assets.loadMiePhaseTable(allocator);
    }

    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = if (collision_induced_absorption) |*table| table else null;
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = if (line_list) |*table| table else null;
    var working_case = scene.*;
    var owned_absorbers: ?AbsorberModel.AbsorberSet = null;
    errdefer if (owned_absorbers) |*absorbers| absorbers.deinitOwned(allocator);
    var owned_operational_band_support: ?[]Instrument.OperationalBandSupport = null;
    errdefer if (owned_operational_band_support) |supports| {
        for (supports) |*support| support.deinitOwned(allocator);
        allocator.free(supports);
    };

    var generated_assets = std.ArrayList(OpticsState.GeneratedLutAsset).empty;
    defer generated_assets.deinit(allocator);
    var execution_entries = std.ArrayList([]const u8).empty;
    defer execution_entries.deinit(allocator);

    var generated_o2_lut: ?OperationalCrossSectionLut = null;
    defer if (generated_o2_lut) |*generated_lut| generated_lut.deinitOwned(allocator);
    var generated_o2o2_lut: ?OperationalCrossSectionLut = null;
    defer if (generated_o2o2_lut) |*generated_lut| generated_lut.deinitOwned(allocator);

    try workflows.applyLutWorkflows(
        allocator,
        scene,
        &working_case,
        &owned_absorbers,
        &owned_operational_band_support,
        line_list_ptr,
        cia_ptr,
        &generated_o2_lut,
        &generated_o2o2_lut,
        &generated_assets,
        &execution_entries,
    );

    return .{
        .profile = profile,
        .cross_sections = cross_sections,
        .collision_induced_absorption = collision_induced_absorption,
        .spectroscopy_lines = line_list,
        .lut = lut,
        .aerosol_mie = aerosol_mie,
        .working_case = working_case,
        .owns_absorbers = owned_absorbers != null,
        .owns_operational_band_support = owned_operational_band_support != null,
        .generated_lut_assets = try generated_assets.toOwnedSlice(allocator),
        .lut_execution_entries = try execution_entries.toOwnedSlice(allocator),
    };
}

pub fn buildOptics(
    allocator: Allocator,
    scene: *const Scene,
    data: *Data,
) !OpticsPrepare.PreparedOpticalState {
    _ = scene;
    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = if (data.collision_induced_absorption) |*table| table else null;
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = if (data.spectroscopy_lines) |*table| table else null;
    const aerosol_mie_ptr: ?*const ReferenceData.MiePhaseTable = if (data.aerosol_mie) |*table| table else null;

    var prepared = try OpticsPrepare.prepare(allocator, &data.working_case, .{
        .profile = &data.profile,
        .cross_sections = &data.cross_sections,
        .collision_induced_absorption = cia_ptr,
        .spectroscopy_lines = line_list_ptr,
        .lut = &data.lut,
        .aerosol_mie = aerosol_mie_ptr,
    });
    errdefer prepared.deinit(allocator);

    prepared.generated_lut_assets = data.generated_lut_assets;
    prepared.owns_generated_lut_assets = true;
    prepared.lut_execution_entries = data.lut_execution_entries;
    prepared.owns_lut_execution_entries = true;

    data.generated_lut_assets = &.{};
    data.lut_execution_entries = &.{};
    return prepared;
}

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
    var loaded = try load(allocator, scene);
    defer loaded.deinit(allocator);
    return buildOptics(allocator, scene, &loaded);
}
