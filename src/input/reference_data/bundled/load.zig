const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const Instrument = @import("../../Instrument.zig").Instrument;
const OperationalCrossSectionLut = @import("../../Instrument.zig").OperationalCrossSectionLut;
const OpticsPrepare = @import("../../../forward_model/optical_properties/root.zig");
const OpticsState = @import("../../../forward_model/optical_properties/state_build/state.zig");
const assets = @import("assets.zig");
const selection = @import("selection.zig");
const workflows = @import("workflows.zig");

const Allocator = std.mem.Allocator;

// load.zig ---------------------------------------------------------------------------------------------------|
// Bundled reference-data orchestration behind public zdisamar.prepare(). Public prepare needs matching        |
// owners: loaded reference rows must live as long as the PreparedOpticalState pointers that refer to them.    |
// This file builds the owner first, mutates only a working Scene copy when LUT workflows need generated       |
// assets, then prepares optical state from the owned rows.                                                    |
//                                                                                                             |
// called by                                                                                                   |
//   src/root.zig prepare() calls load, then buildOptics, and stores both Data and PreparedOpticalState in     |
//   PreparedInput. prepareForScene gives tests and internal callers a one-shot path when they do not need     |
//   to retain Data separately.                                                                                |
//                                                                                                             |
// route map                                                                                                   |
//   load            -> select/load climatology, continuum, CIA, spectroscopy, and airmass LUT assets          |
//                   -> apply LUT workflows to a shallow working Scene copy, cloning only mutated subtrees     |
//                   -> return Data owning loaded tables, working-case slices, and generated LUT metadata      |
//   buildOptics     -> OpticsPrepare.prepare(Data.working_case, Data tables)                                  |
//                   -> move generated_lut_assets and lut_execution_entries into PreparedOpticalState          |
//   prepareForScene -> one-shot load + buildOptics + Data cleanup                                             |
//                                                                                                             |
// why this file exists                                                                                        |
//   selection.zig decides which reference rows a Scene is allowed to use; assets.zig performs concrete asset  |
//   loads and clones; workflows.zig applies LUT controls that may generate operational tables. This file      |
//   keeps those setup concerns together and hands forward_model/optical_properties the normal Scene +         |
//   PreparationInputs shape.                                                                                  |
//                                                                                                             |
// boundary shape                                                                                              |
//   This module belongs to input/reference-data preparation. It may read retained asset bundles and adjust a  |
//   working input scene. RTM execution, report writing, and user-text parsing stay at their own boundaries.   |
//   Forward-model code receives prepared values and borrowed table pointers only through OpticsPrepare.       |
//                                                                                                             |
// setup cost                                                                                                  |
//   This is setup-time work before the wavelength loops. The performance-sensitive choice is to clone only    |
//   absorber/support subtrees that LUT workflows mutate, pass large reference tables by pointer into          |
//   preparation, and move generated metadata into PreparedOpticalState.                                       |
//                                                                                                             |
// memory                                                                                                      |
//   Data owns loaded asset tables, generated LUT descriptors, execution labels, and any working-scene slices  |
//   cloned by workflows.zig. The source Scene stays borrowed. buildOptics transfers generated LUT metadata    |
//   into PreparedOpticalState and clears Data's slices so Data.deinit does not release moved ownership.       |
// ------------------------------------------------------------------------------------------------------------|

// Data -------------------------------------------------------------------------------------------------------|
// Owner for bundled reference assets, generated LUT metadata, and the working scene prepared from them.       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1008 B (0.984 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] profile                         : ReferenceData.ClimatologyProfile                             |
// [  16..  31] cross_sections                  : ReferenceData.CrossSectionTable                              |
// [  32..  63] collision_induced_absorption    : ?ReferenceData.CollisionInducedAbsorptionTable               |
// [  64.. 279] spectroscopy_lines              : ?ReferenceData.SpectroscopyLineList                          |
// [ 280.. 295] lut                             : ReferenceData.AirmassFactorLut                               |
// [ 296.. 967] working_case                    : Scene                                                        |
// [ 968.. 983] generated_lut_assets            : []OpticsState.GeneratedLutAsset                              |
// [ 984.. 999] lut_execution_entries           : []const []const u8                                           |
// [1000..1000] owns_absorbers                  : bool                                                         |
// [1001..1001] owns_operational_band_support   : bool                                                         |
// [1002..1007] trailing padding                : 6 B                                                          |
//                                                                                                             |
// referenced storage                                                                                          |
//   Asset tables, generated LUT assets, execution strings, and working-case slices are held out-of-line.      |
//   working_case is the only large inline member; its cloned subtrees stay behind pointers and slices.        |
//   The two owns_* flags decide whether deinit releases prepared scene buffers or treats them as borrowed.    |
//                                                                                                             |
// unused bits: 48 padding + 14 bool-storage slack = 62 bits                                                   |
// cache span: 16 cache lines at 64 B per line                                                                 |
// footprint: per instance = 1008 B (0.984 KiB); total also includes referenced storage above                  |
pub const Data = struct {
    profile: ReferenceData.ClimatologyProfile,
    cross_sections: ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    lut: ReferenceData.AirmassFactorLut,
    working_case: Scene,
    owns_absorbers: bool = false,
    owns_operational_band_support: bool = false,
    generated_lut_assets: []OpticsState.GeneratedLutAsset = &.{},
    lut_execution_entries: []const []const u8 = &.{},

    pub fn deinit(self: *Data, allocator: Allocator) void {
        // Data.deinit ----------------------------------------------------------------------------------------|
        // Release every owned table, scene subtree, generated asset row, and execution label retained by      |
        // load. buildOptics clears generated_lut_assets and lut_execution_entries after moving them into      |
        // PreparedOpticalState, so this cleanup only releases metadata still owned by Data.                   |
        //                                                                                                     |
        // ownership                                                                                           |
        //   owns_absorbers and owns_operational_band_support are paired with the working_case fields because  |
        //   load starts from a shallow Scene copy and workflows only clone the subtrees they mutate.          |
        // ----------------------------------------------------------------------------------------------------|

        self.profile.deinit(allocator);
        self.cross_sections.deinit(allocator);

        if (self.collision_induced_absorption) |*owned_table| {
            owned_table.deinit(allocator);
        }
        if (self.spectroscopy_lines) |*owned_lines| {
            owned_lines.deinit(allocator);
        }

        self.lut.deinit(allocator);

        if (self.owns_absorbers) {
            self.working_case.absorbers.deinitOwned(allocator);
        }
        if (self.owns_operational_band_support) {
            for (@constCast(self.working_case.observation_model.operational_band_support)) |*support| {
                support.deinitOwned(allocator);
            }
            allocator.free(self.working_case.observation_model.operational_band_support);
        }

        for (self.generated_lut_assets) |*asset| {
            asset.deinitOwned(allocator);
        }
        if (self.generated_lut_assets.len != 0) allocator.free(self.generated_lut_assets);

        for (self.lut_execution_entries) |entry| {
            allocator.free(entry);
        }
        if (self.lut_execution_entries.len != 0) allocator.free(self.lut_execution_entries);

        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn load(allocator: Allocator, scene: *const Scene) !Data {
    // load ---------------------------------------------------------------------------------------------------|
    // Build the owned reference-data bundle and working Scene used by public prepare().                       |
    //                                                                                                         |
    // route                                                                                                   |
    //   1. load/select owned reference tables from bundled assets or resolved scene payloads                  |
    //   2. make a shallow working_case copy of the source Scene                                               |
    //   3. let workflows.zig clone and mutate only the absorber/support subtrees needed for LUT generation    |
    //   4. return Data with ownership flags naming which working_case slices must be freed                    |
    //                                                                                                         |
    // memory                                                                                                  |
    //   Temporary generated LUT handles are owned locally until workflows clone them into working_case or     |
    //   generated asset metadata. ArrayLists are converted to owned slices in the returned Data.              |
    // --------------------------------------------------------------------------------------------------------|

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

    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = resolve_cia_ptr: {
        if (collision_induced_absorption) |*table| break :resolve_cia_ptr table;
        break :resolve_cia_ptr null;
    };
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = resolve_line_list_ptr: {
        if (line_list) |*table| break :resolve_line_list_ptr table;
        break :resolve_line_list_ptr null;
    };

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
        .working_case = working_case,
        .owns_absorbers = owned_absorbers != null,
        .owns_operational_band_support = owned_operational_band_support != null,
        .generated_lut_assets = try generated_assets.toOwnedSlice(allocator),
        .lut_execution_entries = try execution_entries.toOwnedSlice(allocator),
    };
}

pub fn buildOptics(
    allocator: Allocator,
    data: *Data,
) !OpticsPrepare.PreparedOpticalState {
    // buildOptics --------------------------------------------------------------------------------------------|
    // Prepare optical state from Data's working Scene and move generated LUT metadata into the final state.   |
    //                                                                                                         |
    // call path                                                                                               |
    //   src/root.zig calls this after load and keeps both Data and PreparedOpticalState in PreparedInput.     |
    //   prepareForScene uses the same route for one-shot internal callers.                                    |
    //   Data carries both the working Scene and the loaded tables, so optical state is prepared from the      |
    //   working_case that owns any LUT workflow mutations.                                                    |
    //                                                                                                         |
    // ownership                                                                                               |
    //   OpticsPrepare.prepare clones or borrows reference tables according to PreparationInputs. The          |
    //   generated LUT descriptor slices are moved from Data into PreparedOpticalState after preparation, then |
    //   Data is cleared so Data.deinit cannot free moved metadata.                                            |
    // --------------------------------------------------------------------------------------------------------|

    const cia_ptr: ?*const ReferenceData.CollisionInducedAbsorptionTable = resolve_cia_ptr: {
        if (data.collision_induced_absorption) |*table| break :resolve_cia_ptr table;
        break :resolve_cia_ptr null;
    };
    const line_list_ptr: ?*const ReferenceData.SpectroscopyLineList = resolve_line_list_ptr: {
        if (data.spectroscopy_lines) |*table| break :resolve_line_list_ptr table;
        break :resolve_line_list_ptr null;
    };

    var prepared = try OpticsPrepare.prepare(allocator, &data.working_case, .{
        .profile = &data.profile,
        .cross_sections = &data.cross_sections,
        .collision_induced_absorption = cia_ptr,
        .spectroscopy_lines = line_list_ptr,
        .lut = &data.lut,
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

pub fn prepareForScene(allocator: Allocator, scene: *const Scene) !OpticsPrepare.PreparedOpticalState {
    // prepareForScene ----------------------------------------------------------------------------------------|
    // One-shot helper for callers that need PreparedOpticalState with scoped Data owner cleanup.              |
    // --------------------------------------------------------------------------------------------------------|

    var loaded = try load(allocator, scene);
    defer loaded.deinit(allocator);
    return buildOptics(allocator, &loaded);
}
