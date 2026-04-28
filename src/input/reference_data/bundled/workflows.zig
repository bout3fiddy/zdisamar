const std = @import("std");
const Scene = @import("../../Scene.zig").Scene;
const AbsorberModel = @import("../../Absorber.zig");
const ReferenceData = @import("../../ReferenceData.zig");
const Instrument = @import("../../Instrument.zig").Instrument;
const LutControls = @import("../../../common/lut_controls.zig");
const OpticsState = @import("../../../forward_model/optical_properties/state_build/state.zig");
const OperationalCrossSectionLut = @import("../../Instrument.zig").OperationalCrossSectionLut;
const assets = @import("assets.zig");
const selection = @import("selection.zig");

const Allocator = std.mem.Allocator;

const PrimaryOperationalBandSupportLut = enum {
    o2,
    o2o2,
};

pub fn applyLutWorkflows(
    allocator: Allocator,
    source_scene: *const Scene,
    working_scene: *Scene,
    owned_absorbers: *?AbsorberModel.AbsorberSet,
    owned_operational_band_support: *?[]Instrument.OperationalBandSupport,
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
                const wavelengths_nm = try selection.sampleSceneWavelengthsOwned(allocator, source_scene);
                defer allocator.free(wavelengths_nm);
                const o2_absorber = try findUniqueAbsorberBySpeciesAndMode(
                    source_scene.absorbers.items,
                    .o2,
                    .line_by_line,
                ) orelse return error.InvalidRequest;
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
                try replacePrimaryOperationalBandSupportLut(
                    allocator,
                    source_scene,
                    working_scene,
                    owned_operational_band_support,
                    generated_o2_lut.*.?,
                    .o2,
                );
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
                const wavelengths_nm = try selection.sampleSceneWavelengthsOwned(allocator, source_scene);
                defer allocator.free(wavelengths_nm);

                generated_o2o2_lut.* = try OperationalCrossSectionLut.buildFromSource(
                    allocator,
                    wavelengths_nm,
                    .{ .cia_table = o2o2_table },
                    xsec_controls,
                );
                try replacePrimaryOperationalBandSupportLut(
                    allocator,
                    source_scene,
                    working_scene,
                    owned_operational_band_support,
                    generated_o2o2_lut.*.?,
                    .o2o2,
                );
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
        if (AbsorberModel.resolvedAbsorberSpecies(absorber) == null) {
            if (xsec_controls.mode != .direct) return error.InvalidRequest;
            continue;
        }
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
                const wavelengths_nm = try selection.sampleSceneWavelengthsOwned(allocator, source_scene);
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

fn ensureOwnedOperationalBandSupport(
    allocator: Allocator,
    source_scene: *const Scene,
    working_scene: *Scene,
    owned_operational_band_support: *?[]Instrument.OperationalBandSupport,
) ![]Instrument.OperationalBandSupport {
    if (owned_operational_band_support.* == null) {
        const source_support = source_scene.observation_model.operational_band_support;
        const cloned_support = try allocator.alloc(Instrument.OperationalBandSupport, source_support.len);
        errdefer allocator.free(cloned_support);

        var initialized: usize = 0;
        errdefer for (cloned_support[0..initialized]) |*support| support.deinitOwned(allocator);

        for (source_support, 0..) |support, index| {
            cloned_support[index] = try support.clone(allocator);
            initialized += 1;
        }

        owned_operational_band_support.* = cloned_support;
        working_scene.observation_model.operational_band_support = cloned_support;
        working_scene.observation_model.owns_operational_band_support = true;
    }
    return owned_operational_band_support.*.?;
}

fn replacePrimaryOperationalBandSupportLut(
    allocator: Allocator,
    source_scene: *const Scene,
    working_scene: *Scene,
    owned_operational_band_support: *?[]Instrument.OperationalBandSupport,
    generated_lut: OperationalCrossSectionLut,
    which: PrimaryOperationalBandSupportLut,
) !void {
    if (source_scene.observation_model.operational_band_support.len == 0) return;

    const supports = try ensureOwnedOperationalBandSupport(
        allocator,
        source_scene,
        working_scene,
        owned_operational_band_support,
    );
    switch (which) {
        .o2 => {
            supports[0].o2_operational_lut.deinitOwned(allocator);
            supports[0].o2_operational_lut = try generated_lut.clone(allocator);
        },
        .o2o2 => {
            supports[0].o2o2_operational_lut.deinitOwned(allocator);
            supports[0].o2o2_operational_lut = try generated_lut.clone(allocator);
        },
    }
}

fn findAbsorberIndexById(items: []const AbsorberModel.Absorber, id: []const u8) ?usize {
    for (items, 0..) |absorber, index| {
        if (std.mem.eql(u8, absorber.id, id)) return index;
    }
    return null;
}

fn findUniqueAbsorberBySpeciesAndMode(
    items: []const AbsorberModel.Absorber,
    species: AbsorberModel.AbsorberSpecies,
    mode: AbsorberModel.SpectroscopyMode,
) !?AbsorberModel.Absorber {
    var matched: ?AbsorberModel.Absorber = null;
    for (items) |absorber| {
        if (absorber.spectroscopy.mode != mode) continue;
        if ((AbsorberModel.resolvedAbsorberSpecies(absorber) orelse continue) != species) continue;
        if (matched != null) return error.InvalidRequest;
        matched = absorber;
    }
    return matched;
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
