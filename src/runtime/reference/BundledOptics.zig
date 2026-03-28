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
const AbsorberModel = @import("../../model/Absorber.zig");
const ReferenceData = @import("../../model/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../model/Instrument.zig").OperationalCrossSectionLut;
const LutControls = @import("../../core/lut_controls.zig");
const OpticsPrepare = @import("../../kernels/optics/preparation.zig");
const OpticsState = @import("../../kernels/optics/preparation/state.zig");
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
    var working_scene = scene.*;
    var owned_absorbers: ?AbsorberModel.AbsorberSet = null;
    defer if (owned_absorbers) |*absorbers| absorbers.deinitOwned(allocator);

    var generated_assets = std.ArrayList(OpticsState.GeneratedLutAsset).empty;
    defer {
        for (generated_assets.items) |*asset| asset.deinitOwned(allocator);
        generated_assets.deinit(allocator);
    }
    var execution_entries = std.ArrayList([]const u8).empty;
    defer {
        for (execution_entries.items) |entry| allocator.free(entry);
        execution_entries.deinit(allocator);
    }

    var generated_o2_lut: ?OperationalCrossSectionLut = null;
    defer if (generated_o2_lut) |*generated_lut| generated_lut.deinitOwned(allocator);
    var generated_o2o2_lut: ?OperationalCrossSectionLut = null;
    defer if (generated_o2o2_lut) |*generated_lut| generated_lut.deinitOwned(allocator);

    try applyLutWorkflows(
        allocator,
        scene,
        &working_scene,
        &owned_absorbers,
        line_list_ptr,
        cia_ptr,
        &generated_o2_lut,
        &generated_o2o2_lut,
        &generated_assets,
        &execution_entries,
    );

    var prepared = try OpticsPrepare.prepare(allocator, &working_scene, .{
        .profile = &profile,
        .cross_sections = &cross_sections,
        .collision_induced_absorption = cia_ptr,
        .spectroscopy_lines = line_list_ptr,
        .lut = &lut,
        .aerosol_mie = aerosol_mie_ptr,
    });
    errdefer prepared.deinit(allocator);
    prepared.generated_lut_assets = try generated_assets.toOwnedSlice(allocator);
    prepared.owns_generated_lut_assets = true;
    prepared.lut_execution_entries = try execution_entries.toOwnedSlice(allocator);
    prepared.owns_lut_execution_entries = true;
    return prepared;
}

fn applyLutWorkflows(
    allocator: Allocator,
    source_scene: *const Scene,
    working_scene: *Scene,
    owned_absorbers: *?AbsorberModel.AbsorberSet,
    line_list: ?*const ReferenceData.SpectroscopyLineList,
    cia_table: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    generated_o2_lut: *?OperationalCrossSectionLut,
    generated_o2o2_lut: *?OperationalCrossSectionLut,
    generated_assets: *std.ArrayList(OpticsState.GeneratedLutAsset),
    execution_entries: *std.ArrayList([]const u8),
) !void {
    try applyReflectanceLutWorkflow(
        allocator,
        source_scene,
        generated_assets,
        execution_entries,
    );

    const xsec_controls = source_scene.lut_controls.xsec;
    const compatibility = source_scene.lutCompatibilityKey();
    var xsec_applied = false;

    if (assets.sceneRequestsSpectroscopyMode(source_scene, .o2, .line_by_line)) {
        switch (xsec_controls.mode) {
            .direct => {
                if (source_scene.observation_model.primaryOperationalBandSupport().o2_operational_lut.enabled()) {
                    try appendExecutionLabel(allocator, execution_entries, "o2:xsec_lut:consume");
                } else {
                    try appendExecutionLabel(allocator, execution_entries, "o2:xsec:direct");
                }
                xsec_applied = true;
            },
            .consume => {
                if (!source_scene.observation_model.primaryOperationalBandSupport().o2_operational_lut.enabled()) {
                    return error.InvalidRequest;
                }
                try appendExecutionLabel(allocator, execution_entries, "o2:xsec_lut:consume");
                xsec_applied = true;
            },
            .generate => {
                const o2_lines = line_list orelse return error.InvalidRequest;
                const wavelengths_nm = try sampleSceneWavelengthsOwned(allocator, source_scene);
                defer allocator.free(wavelengths_nm);
                const o2_absorber = findAbsorberBySpecies(source_scene.absorbers.items, .o2) orelse return error.InvalidRequest;
                const o2_hitran_index = (AbsorberModel.resolvedAbsorberSpecies(o2_absorber) orelse return error.InvalidRequest).hitranIndex() orelse return error.InvalidRequest;
                var controlled_o2_lines = try o2_lines.clone(allocator);
                defer controlled_o2_lines.deinit(allocator);
                try controlled_o2_lines.applyRuntimeControls(
                    allocator,
                    o2_hitran_index,
                    o2_absorber.spectroscopy.line_gas_controls.activeIsotopes(),
                    o2_absorber.spectroscopy.line_gas_controls.activeThresholdLine(),
                    o2_absorber.spectroscopy.line_gas_controls.activeCutoffCm1(),
                    o2_absorber.spectroscopy.line_gas_controls.activeLineMixingFactor(),
                );

                generated_o2_lut.* = try OperationalCrossSectionLut.buildFromSource(
                    allocator,
                    wavelengths_nm,
                    .{ .line_list = &controlled_o2_lines },
                    xsec_controls,
                );
                working_scene.observation_model.o2_operational_lut = generated_o2_lut.*.?;
                try appendExecutionLabel(allocator, execution_entries, "o2:xsec_lut:generated");
                try appendGeneratedAsset(
                    allocator,
                    generated_assets,
                    source_scene,
                    .xsec,
                    xsec_controls.mode,
                    "o2",
                    "o2:xsec_lut:generated",
                    compatibility,
                    @intCast(wavelengths_nm.len),
                    source_scene.atmosphere.preparedLayerCount(),
                    xsec_controls.coefficientCount(),
                );
                xsec_applied = true;
            },
        }
    }

    if (assets.sceneRequestsSpectroscopyMode(source_scene, .o2_o2, .cia)) {
        switch (xsec_controls.mode) {
            .direct => {
                if (source_scene.observation_model.primaryOperationalBandSupport().o2o2_operational_lut.enabled()) {
                    try appendExecutionLabel(allocator, execution_entries, "o2o2:xsec_lut:consume");
                } else {
                    try appendExecutionLabel(allocator, execution_entries, "o2o2:xsec:direct");
                }
                xsec_applied = true;
            },
            .consume => {
                if (!source_scene.observation_model.primaryOperationalBandSupport().o2o2_operational_lut.enabled()) {
                    return error.InvalidRequest;
                }
                try appendExecutionLabel(allocator, execution_entries, "o2o2:xsec_lut:consume");
                xsec_applied = true;
            },
            .generate => {
                const o2o2_table = cia_table orelse return error.InvalidRequest;
                const wavelengths_nm = try sampleSceneWavelengthsOwned(allocator, source_scene);
                defer allocator.free(wavelengths_nm);

                generated_o2o2_lut.* = try OperationalCrossSectionLut.buildFromSource(
                    allocator,
                    wavelengths_nm,
                    .{ .cia_table = o2o2_table },
                    xsec_controls,
                );
                working_scene.observation_model.o2o2_operational_lut = generated_o2o2_lut.*.?;
                try appendExecutionLabel(allocator, execution_entries, "o2o2:xsec_lut:generated");
                try appendGeneratedAsset(
                    allocator,
                    generated_assets,
                    source_scene,
                    .xsec,
                    xsec_controls.mode,
                    "o2o2",
                    "o2o2:xsec_lut:generated",
                    compatibility,
                    @intCast(wavelengths_nm.len),
                    source_scene.atmosphere.preparedLayerCount(),
                    xsec_controls.coefficientCount(),
                );
                xsec_applied = true;
            },
        }
    }

    for (source_scene.absorbers.items) |absorber| {
        if (absorber.spectroscopy.mode != .cross_sections) continue;
        _ = AbsorberModel.resolvedAbsorberSpecies(absorber) orelse continue;
        switch (xsec_controls.mode) {
            .direct => {
                if (absorber.spectroscopy.resolved_cross_section_lut != null) {
                    try appendExecutionLabelOwned(
                        allocator,
                        execution_entries,
                        "{s}:xsec_lut:consume",
                        .{absorber.id},
                    );
                } else {
                    try appendExecutionLabelOwned(
                        allocator,
                        execution_entries,
                        "{s}:xsec:direct",
                        .{absorber.id},
                    );
                }
                xsec_applied = true;
            },
            .consume => {
                if (absorber.spectroscopy.resolved_cross_section_lut == null) {
                    return error.InvalidRequest;
                }
                try appendExecutionLabelOwned(
                    allocator,
                    execution_entries,
                    "{s}:xsec_lut:consume",
                    .{absorber.id},
                );
                xsec_applied = true;
            },
            .generate => {
                const table = absorber.spectroscopy.resolved_cross_section_table orelse return error.InvalidRequest;
                const wavelengths_nm = try sampleSceneWavelengthsOwned(allocator, source_scene);
                defer allocator.free(wavelengths_nm);

                const owned = try ensureOwnedAbsorbers(allocator, source_scene, working_scene, owned_absorbers);
                const target_absorber = @constCast(&owned.items[findAbsorberIndexById(owned.items, absorber.id) orelse return error.InvalidRequest]);
                target_absorber.spectroscopy.cross_section_table.deinitOwned(allocator);
                if (target_absorber.spectroscopy.resolved_cross_section_table) |*owned_table| {
                    var cleanup = owned_table.*;
                    cleanup.deinit(allocator);
                }
                target_absorber.spectroscopy.resolved_cross_section_table = null;
                target_absorber.spectroscopy.operational_lut.deinitOwned(allocator);
                target_absorber.spectroscopy.operational_lut = .{
                    .asset = .{ .name = try allocator.dupe(u8, "generated.xsec_lut") },
                };
                target_absorber.spectroscopy.resolved_cross_section_lut = try OperationalCrossSectionLut.buildFromSource(
                    allocator,
                    wavelengths_nm,
                    .{ .cross_section_table = &table },
                    xsec_controls,
                );
                try appendExecutionLabelOwned(
                    allocator,
                    execution_entries,
                    "{s}:xsec_lut:generated",
                    .{absorber.id},
                );
                const generated_label = try std.fmt.allocPrint(
                    allocator,
                    "{s}:xsec_lut:generated",
                    .{absorber.id},
                );
                defer allocator.free(generated_label);
                try appendGeneratedAsset(
                    allocator,
                    generated_assets,
                    source_scene,
                    .xsec,
                    xsec_controls.mode,
                    absorber.id,
                    generated_label,
                    compatibility,
                    @intCast(wavelengths_nm.len),
                    source_scene.atmosphere.preparedLayerCount(),
                    xsec_controls.coefficientCount(),
                );
                xsec_applied = true;
            },
        }
    }

    if (xsec_controls.mode != .direct and !xsec_applied) {
        return error.InvalidRequest;
    }
}

fn applyReflectanceLutWorkflow(
    allocator: Allocator,
    scene: *const Scene,
    generated_assets: *std.ArrayList(OpticsState.GeneratedLutAsset),
    execution_entries: *std.ArrayList([]const u8),
) !void {
    const compatibility = scene.lutCompatibilityKey();
    const controls = scene.lut_controls.reflectance;

    if (controls.reflectance_mode == .consume or controls.correction_mode == .consume) {
        return error.InvalidRequest;
    }

    if (controls.reflectance_mode != .direct) {
        try appendExecutionLabelOwned(
            allocator,
            execution_entries,
            "reflectance_lut:{s}",
            .{controls.reflectance_mode.label()},
        );
        if (controls.reflectance_mode == .generate) {
            try appendGeneratedAsset(
                allocator,
                generated_assets,
                scene,
                .reflectance,
                controls.reflectance_mode,
                "reflectance",
                "reflectance_lut:generated",
                compatibility,
                scene.spectral_grid.sample_count,
                scene.atmosphere.preparedLayerCount(),
                0,
            );
        }
    }

    if (controls.correction_mode != .direct) {
        try appendExecutionLabelOwned(
            allocator,
            execution_entries,
            "correction_lut:{s}",
            .{controls.correction_mode.label()},
        );
        if (controls.correction_mode == .generate) {
            try appendGeneratedAsset(
                allocator,
                generated_assets,
                scene,
                .correction,
                controls.correction_mode,
                "correction",
                "correction_lut:generated",
                compatibility,
                scene.spectral_grid.sample_count,
                scene.atmosphere.preparedLayerCount(),
                0,
            );
        }
    }
}

fn ensureOwnedAbsorbers(
    allocator: Allocator,
    source_scene: *const Scene,
    working_scene: *Scene,
    owned_absorbers: *?AbsorberModel.AbsorberSet,
) !*AbsorberModel.AbsorberSet {
    if (owned_absorbers.* == null) {
        owned_absorbers.* = try source_scene.absorbers.clone(allocator);
        working_scene.absorbers = owned_absorbers.*.?;
    }
    return &(owned_absorbers.*.?);
}

fn findAbsorberIndexById(items: []const AbsorberModel.Absorber, id: []const u8) ?usize {
    for (items, 0..) |absorber, index| {
        if (std.mem.eql(u8, absorber.id, id)) return index;
    }
    return null;
}

fn findAbsorberBySpecies(
    items: []const AbsorberModel.Absorber,
    species: AbsorberModel.AbsorberSpecies,
) ?AbsorberModel.Absorber {
    for (items) |absorber| {
        if ((AbsorberModel.resolvedAbsorberSpecies(absorber) orelse continue) == species) return absorber;
    }
    return null;
}

fn sampleSceneWavelengthsOwned(allocator: Allocator, scene: *const Scene) ![]f64 {
    const support = scene.observation_model.primaryOperationalBandSupport();
    const nominal_bounds = scene.lutNominalWavelengthBounds();
    const support_half_span_nm = scene.observation_model.lutSamplingHalfSpanNm();
    if (support.high_resolution_step_nm > 0.0 and support_half_span_nm > 0.0) {
        return uniformWavelengthGridOwned(
            allocator,
            nominal_bounds.start_nm - support_half_span_nm,
            nominal_bounds.end_nm + support_half_span_nm,
            support.high_resolution_step_nm,
        );
    }

    const sample_count: usize = scene.spectral_grid.sample_count;
    if (sample_count == 0) return error.InvalidRequest;

    const wavelengths_nm = try allocator.alloc(f64, sample_count);
    if (sample_count == 1) {
        wavelengths_nm[0] = scene.spectral_grid.start_nm;
        return wavelengths_nm;
    }

    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const step_nm = span_nm / @as(f64, @floatFromInt(sample_count - 1));
    for (wavelengths_nm, 0..) |*wavelength_nm, index| {
        wavelength_nm.* = scene.spectral_grid.start_nm + step_nm * @as(f64, @floatFromInt(index));
    }
    return wavelengths_nm;
}

fn uniformWavelengthGridOwned(
    allocator: Allocator,
    start_nm: f64,
    end_nm: f64,
    step_nm: f64,
) ![]f64 {
    if (!(step_nm > 0.0) or !std.math.isFinite(start_nm) or !std.math.isFinite(end_nm) or end_nm < start_nm) {
        return error.InvalidRequest;
    }

    const span_nm = end_nm - start_nm;
    const sample_count = @as(usize, @intFromFloat(@floor((span_nm / step_nm) + 0.5))) + 1;
    const wavelengths_nm = try allocator.alloc(f64, sample_count);
    for (wavelengths_nm, 0..) |*wavelength_nm, index| {
        wavelength_nm.* = @min(start_nm + step_nm * @as(f64, @floatFromInt(index)), end_nm);
    }
    return wavelengths_nm;
}

fn appendExecutionLabel(
    allocator: Allocator,
    execution_entries: *std.ArrayList([]const u8),
    label: []const u8,
) !void {
    const owned_label = try allocator.dupe(u8, label);
    errdefer allocator.free(owned_label);
    try execution_entries.append(allocator, owned_label);
}

fn appendExecutionLabelOwned(
    allocator: Allocator,
    execution_entries: *std.ArrayList([]const u8),
    comptime fmt: []const u8,
    args: anytype,
) !void {
    const owned_label = try std.fmt.allocPrint(allocator, fmt, args);
    errdefer allocator.free(owned_label);
    try execution_entries.append(allocator, owned_label);
}

fn appendGeneratedAsset(
    allocator: Allocator,
    generated_assets: *std.ArrayList(OpticsState.GeneratedLutAsset),
    scene: *const Scene,
    kind: OpticsState.GeneratedLutAssetKind,
    mode: LutControls.Mode,
    target: []const u8,
    provenance_label: []const u8,
    compatibility: LutControls.CompatibilityKey,
    spectral_bin_count: u32,
    layer_count: u32,
    coefficient_count: u32,
) !void {
    const dataset_id = try std.fmt.allocPrint(
        allocator,
        "generated.{s}.{s}",
        .{ @tagName(kind), target },
    );
    errdefer allocator.free(dataset_id);

    const lut_id = try allocator.dupe(u8, scene.id);
    errdefer allocator.free(lut_id);

    const owned_provenance_label = try allocator.dupe(u8, provenance_label);
    errdefer allocator.free(owned_provenance_label);

    try generated_assets.append(allocator, .{
        .dataset_id = dataset_id,
        .lut_id = lut_id,
        .provenance_label = owned_provenance_label,
        .kind = kind,
        .mode = mode,
        .spectral_bin_count = spectral_bin_count,
        .layer_count = layer_count,
        .coefficient_count = coefficient_count,
        .compatibility = compatibility,
        .owns_strings = true,
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
