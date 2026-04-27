const std = @import("std");
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const State = @import("state.zig");
const VerticalGrid = @import("vertical_grid.zig");

const Allocator = std.mem.Allocator;

pub const PreparationInputs = struct {
    profile: *const ReferenceData.ClimatologyProfile,
    spectroscopy_profile: ?*const ReferenceData.ClimatologyProfile = null,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList = null,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable = null,
    cloud_mie: ?*const ReferenceData.MiePhaseTable = null,
};

pub const PreparationContext = struct {
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    aerosol_mie: ?*const ReferenceData.MiePhaseTable = null,
    cloud_mie: ?*const ReferenceData.MiePhaseTable = null,
    vertical_grid: VerticalGrid.OwnedVerticalGrid = undefined,
    layers: []State.PreparedLayer = &.{},
    sublayers: []State.PreparedSublayer = &.{},
    continuum_points: []ReferenceData.CrossSectionPoint = &.{},
    spectroscopy_profile_altitudes_km: []f64 = &.{},
    spectroscopy_profile_pressures_hpa: []f64 = &.{},
    spectroscopy_profile_temperatures_k: []f64 = &.{},
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    cloud_fraction_control: AtmosphereModel.FractionControl = .{},
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    midpoint_nm: f64 = 0.0,

    pub fn deinit(self: *PreparationContext, allocator: Allocator) void {
        self.vertical_grid.deinit(allocator);
        if (self.layers.len != 0) allocator.free(self.layers);
        if (self.sublayers.len != 0) allocator.free(self.sublayers);
        if (self.continuum_points.len != 0) allocator.free(self.continuum_points);
        if (self.spectroscopy_profile_altitudes_km.len != 0) allocator.free(self.spectroscopy_profile_altitudes_km);
        if (self.spectroscopy_profile_pressures_hpa.len != 0) allocator.free(self.spectroscopy_profile_pressures_hpa);
        if (self.spectroscopy_profile_temperatures_k.len != 0) allocator.free(self.spectroscopy_profile_temperatures_k);
        if (self.collision_induced_absorption) |cia| {
            var owned = cia;
            owned.deinit(allocator);
        }
        if (self.spectroscopy_lines) |line_list| {
            var owned = line_list;
            owned.deinit(allocator);
        }
        self.aerosol_fraction_control.deinitOwned(allocator);
        self.cloud_fraction_control.deinitOwned(allocator);
        if (self.operational_o2_lut.enabled()) {
            var owned = self.operational_o2_lut;
            owned.deinitOwned(allocator);
        }
        if (self.operational_o2o2_lut.enabled()) {
            var owned = self.operational_o2o2_lut;
            owned.deinitOwned(allocator);
        }
        self.* = undefined;
    }
};

pub fn init(
    allocator: Allocator,
    scene: *const Scene,
    inputs: PreparationInputs,
) !PreparationContext {
    try scene.validate();

    var vertical_grid = try VerticalGrid.build(allocator, scene, inputs.profile);
    errdefer vertical_grid.deinit(allocator);

    const layer_count: u32 = @intCast(vertical_grid.layer_top_altitudes_km.len);
    const total_sublayer_count = vertical_grid.sublayer_mid_altitudes_km.len;
    const layers = try allocator.alloc(State.PreparedLayer, layer_count);
    errdefer if (layers.len != 0) allocator.free(layers);
    const sublayers = try allocator.alloc(State.PreparedSublayer, total_sublayer_count);
    errdefer if (sublayers.len != 0) allocator.free(sublayers);
    const continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, inputs.cross_sections.points);
    errdefer if (continuum_points.len != 0) allocator.free(continuum_points);
    const spectroscopy_profile = inputs.spectroscopy_profile orelse inputs.profile;
    const profile_node_count = spectroscopy_profile.rows.len;
    const spectroscopy_profile_altitudes_km: []f64 = if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (spectroscopy_profile_altitudes_km.len != 0) allocator.free(spectroscopy_profile_altitudes_km);
    const spectroscopy_profile_pressures_hpa: []f64 = if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (spectroscopy_profile_pressures_hpa.len != 0) allocator.free(spectroscopy_profile_pressures_hpa);
    const spectroscopy_profile_temperatures_k: []f64 = if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (spectroscopy_profile_temperatures_k.len != 0) allocator.free(spectroscopy_profile_temperatures_k);
    for (spectroscopy_profile.rows, 0..) |row, index| {
        spectroscopy_profile_altitudes_km[index] = row.altitude_km;
        spectroscopy_profile_pressures_hpa[index] = row.pressure_hpa;
        spectroscopy_profile_temperatures_k[index] = row.temperature_k;
    }

    const collision_induced_absorption = if (inputs.collision_induced_absorption) |cia|
        try cia.clone(allocator)
    else
        null;
    errdefer if (collision_induced_absorption) |cia| {
        var owned = cia;
        owned.deinit(allocator);
    };

    const spectroscopy_lines = if (inputs.spectroscopy_lines) |line_list|
        try line_list.clone(allocator)
    else
        null;
    errdefer if (spectroscopy_lines) |line_list| {
        var owned = line_list;
        owned.deinit(allocator);
    };

    var aerosol_fraction_control = try scene.aerosol.fraction.clone(allocator);
    errdefer aerosol_fraction_control.deinitOwned(allocator);
    var cloud_fraction_control = try scene.cloud.fraction.clone(allocator);
    errdefer cloud_fraction_control.deinitOwned(allocator);

    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const operational_o2_lut = if (operational_band_support.o2_operational_lut.enabled())
        try operational_band_support.o2_operational_lut.clone(allocator)
    else
        OperationalCrossSectionLut{};
    errdefer if (operational_o2_lut.enabled()) {
        var owned = operational_o2_lut;
        owned.deinitOwned(allocator);
    };
    const operational_o2o2_lut = if (operational_band_support.o2o2_operational_lut.enabled())
        try operational_band_support.o2o2_operational_lut.clone(allocator)
    else
        OperationalCrossSectionLut{};
    errdefer if (operational_o2o2_lut.enabled()) {
        var owned = operational_o2o2_lut;
        owned.deinitOwned(allocator);
    };

    return .{
        .scene = scene,
        .profile = inputs.profile,
        .cross_sections = inputs.cross_sections,
        .lut = inputs.lut,
        .collision_induced_absorption = collision_induced_absorption,
        .spectroscopy_lines = spectroscopy_lines,
        .aerosol_mie = inputs.aerosol_mie,
        .cloud_mie = inputs.cloud_mie,
        .vertical_grid = vertical_grid,
        .layers = layers,
        .sublayers = sublayers,
        .continuum_points = continuum_points,
        .spectroscopy_profile_altitudes_km = spectroscopy_profile_altitudes_km,
        .spectroscopy_profile_pressures_hpa = spectroscopy_profile_pressures_hpa,
        .spectroscopy_profile_temperatures_k = spectroscopy_profile_temperatures_k,
        .aerosol_fraction_control = aerosol_fraction_control,
        .cloud_fraction_control = cloud_fraction_control,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
    };
}
