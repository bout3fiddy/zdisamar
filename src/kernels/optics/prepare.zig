const std = @import("std");
const Scene = @import("../../model/Scene.zig").Scene;
const ReferenceData = @import("../../model/ReferenceData.zig");
const Preparation = @import("preparation.zig");

const Allocator = std.mem.Allocator;

pub const state = Preparation.state;
pub const builder = Preparation.builder;
pub const spectroscopy = Preparation.spectroscopy;
pub const evaluation = Preparation.evaluation;
pub const transport = Preparation.transport;

pub const PreparationInputs = Preparation.PreparationInputs;
pub const PreparedLayer = Preparation.PreparedLayer;
pub const PreparedSublayer = Preparation.PreparedSublayer;
pub const OpticalDepthBreakdown = Preparation.OpticalDepthBreakdown;
pub const PreparedOpticalState = Preparation.PreparedOpticalState;

pub fn prepare(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        null,
        lut,
        null,
        null,
    );
}

pub fn prepareWithInputs(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparedOpticalState {
    return Preparation.prepare(allocator, scene, inputs);
}

pub fn prepareWithSpectroscopy(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        null,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithSpectroscopyAndCollisionInducedAbsorption(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
) !PreparedOpticalState {
    return prepareWithParticleTables(
        allocator,
        scene,
        profile,
        cross_sections,
        collision_induced_absorption,
        spectroscopy_lines,
        lut,
        null,
        null,
    );
}

pub fn prepareWithParticleTables(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList,
    lut: *const ReferenceData.AirmassFactorLut,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable,
    cloud_mie: ?*const ReferenceData.MiePhaseTable,
) !PreparedOpticalState {
    return Preparation.prepare(allocator, scene, .{
        .profile = profile,
        .cross_sections = cross_sections,
        .lut = lut,
        .collision_induced_absorption = collision_induced_absorption,
        .spectroscopy_lines = spectroscopy_lines,
        .aerosol_mie = aerosol_mie,
        .cloud_mie = cloud_mie,
    });
}

test "legacy optics prepare shim preserves compatibility entrypoints" {
    try std.testing.expect(@hasDecl(@This(), "prepare"));
    try std.testing.expect(@hasDecl(@This(), "prepareWithInputs"));
    try std.testing.expect(@hasDecl(@This(), "prepareWithSpectroscopy"));
    try std.testing.expect(@hasDecl(@This(), "prepareWithSpectroscopyAndCollisionInducedAbsorption"));
    try std.testing.expect(@hasDecl(@This(), "prepareWithParticleTables"));
}
