const std = @import("std");
const AerosolModel = @import("../../../input/Aerosol.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const VerticalGrid = @import("vertical_grid.zig");

const Allocator = std.mem.Allocator;

// layout(64-bit):
//   size: 80 B, align: 8 B
//   field storage: 74 B across 11 fields; largest: profile=8 B, spectroscopy_profile=8 B, cross_sections=8 B; padding: 6 B (48 bits)
//   unused bits: 48 padding + 14 bool-storage slack = 62 bits
//   out-of-line: profile, spectroscopy_profile, cross_sections, lut, collision_induced_absorption, +4 more carry references/descriptors; referenced storage is not included in size
//   cache span: 2 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 80 B (0.078 KiB); total also includes referenced storage above
pub const PreparationInputs = struct {
    profile: *const ReferenceData.ClimatologyProfile,
    spectroscopy_profile: ?*const ReferenceData.ClimatologyProfile = null,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?*const ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?*const ReferenceData.SpectroscopyLineList = null,
    borrowed_profile_preparation: ?*const BorrowedProfilePreparation = null,
    aerosol_profile_layers: []const AerosolModel.ProfileLayer = &.{},
    borrow_continuum_points: bool = false,
    borrow_collision_induced_absorption: bool = false,
};

// Retrieval sessions can borrow profile spectroscopy support across state
// evaluations. Pressure-placement states change the vertical grid and layer
// optical depths, but these profile rows and prepared line states are keyed
// only by the static spectroscopy profile and filtered line list.
// layout(64-bit):
//   size: 96 B, align: 8 B
//   field storage: 96 B across 7 fields; padding: 0 B
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: profile arrays and prepared line-state arrays remain session-owned; keys summarize the same borrowed support
//   cache span: 2 cache line(s) at 64 B per line
//   count: at most one borrowed profile-preparation view per retrieval-owned optical refresh
//   footprint: per instance = 96 B (0.094 KiB); referenced arrays live in the retrieval session
pub const BorrowedProfilePreparation = struct {
    altitudes_km: []f64 = &.{},
    pressures_hpa: []f64 = &.{},
    temperatures_k: []f64 = &.{},
    weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_plan_key: u64 = 0,
    spectroscopy_profile_cache_inputs_key: u64 = 0,

    fn validate(self: BorrowedProfilePreparation, expected_node_count: usize) !void {
        if (self.altitudes_km.len != expected_node_count or
            self.pressures_hpa.len != expected_node_count or
            self.temperatures_k.len != expected_node_count)
        {
            return error.InvalidRequest;
        }
        if (self.weak_line_states) |states| {
            if (states.len != expected_node_count) return error.InvalidRequest;
        }
        if (self.strong_line_states) |states| {
            if (states.len != expected_node_count) return error.InvalidRequest;
        }
        if ((self.weak_line_states == null) != (self.strong_line_states == null)) {
            return error.InvalidRequest;
        }
    }
};

// layout(64-bit):
//   size: 2096 B, align: 8 B
//   field storage: 2091 B across 25 fields; largest: aerosol_phase_coefficients=1208 B, vertical_grid=256 B; padding: 5 B (40 bits)
//   unused bits: 40 padding + 21 bool-storage slack = 61 bits
//   inline arrays: aerosol_phase_coefficients:[151]f64=1208 B
//   out-of-line: scene, profile, cross_sections, lut, collision_induced_absorption, +9 more carry references/descriptors; referenced storage is not included in size
//   cache span: 33 cache line(s) at 64 B per line
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 2096 B (2.047 KiB); total also includes referenced storage above
pub const PreparationContext = struct {
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    cross_sections: *const ReferenceData.CrossSectionTable,
    lut: *const ReferenceData.AirmassFactorLut,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    owns_collision_induced_absorption: bool = true,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    vertical_grid: VerticalGrid.OwnedVerticalGrid = undefined,
    layers: []State.PreparedLayer = &.{},
    sublayers: []State.PreparedSublayer = &.{},
    continuum_points: []const ReferenceData.CrossSectionPoint = &.{},
    owns_continuum_points: bool = true,
    spectroscopy_profile_altitudes_km: []f64 = &.{},
    spectroscopy_profile_pressures_hpa: []f64 = &.{},
    spectroscopy_profile_temperatures_k: []f64 = &.{},
    owns_spectroscopy_profile_arrays: bool = true,
    borrowed_profile_weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    borrowed_profile_strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    borrowed_spectroscopy_plan_key: u64 = 0,
    borrowed_spectroscopy_profile_cache_inputs_key: u64 = 0,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    aerosol_profile_layers: []const AerosolModel.ProfileLayer = &.{},
    aerosol_phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    midpoint_nm: f64 = 0.0,

    pub fn deinit(self: *PreparationContext, allocator: Allocator) void {
        self.vertical_grid.deinit(allocator);
        if (self.layers.len != 0) allocator.free(self.layers);
        if (self.sublayers.len != 0) allocator.free(self.sublayers);
        if (self.owns_continuum_points and self.continuum_points.len != 0) allocator.free(self.continuum_points);
        if (self.owns_spectroscopy_profile_arrays) {
            if (self.spectroscopy_profile_altitudes_km.len != 0) allocator.free(self.spectroscopy_profile_altitudes_km);
            if (self.spectroscopy_profile_pressures_hpa.len != 0) allocator.free(self.spectroscopy_profile_pressures_hpa);
            if (self.spectroscopy_profile_temperatures_k.len != 0) allocator.free(self.spectroscopy_profile_temperatures_k);
        }
        if (self.owns_collision_induced_absorption and self.collision_induced_absorption != null) {
            const cia = self.collision_induced_absorption.?;
            var owned = cia;
            owned.deinit(allocator);
        }
        if (self.spectroscopy_lines) |line_list| {
            var owned = line_list;
            owned.deinit(allocator);
        }
        self.aerosol_fraction_control.deinitOwned(allocator);
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
    const owns_continuum_points = !inputs.borrow_continuum_points;
    const continuum_points: []const ReferenceData.CrossSectionPoint = if (inputs.borrow_continuum_points)
        inputs.cross_sections.points
    else
        try allocator.dupe(ReferenceData.CrossSectionPoint, inputs.cross_sections.points);
    errdefer if (owns_continuum_points and continuum_points.len != 0) allocator.free(continuum_points);
    const spectroscopy_profile = inputs.spectroscopy_profile orelse inputs.profile;
    const profile_node_count = spectroscopy_profile.rows.len;
    const borrowed_profile_preparation = inputs.borrowed_profile_preparation;
    if (borrowed_profile_preparation) |borrowed| try borrowed.validate(profile_node_count);
    const owns_spectroscopy_profile_arrays = borrowed_profile_preparation == null;
    const spectroscopy_profile_altitudes_km: []f64 = if (borrowed_profile_preparation) |borrowed|
        borrowed.altitudes_km
    else if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (owns_spectroscopy_profile_arrays and spectroscopy_profile_altitudes_km.len != 0) allocator.free(spectroscopy_profile_altitudes_km);
    const spectroscopy_profile_pressures_hpa: []f64 = if (borrowed_profile_preparation) |borrowed|
        borrowed.pressures_hpa
    else if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (owns_spectroscopy_profile_arrays and spectroscopy_profile_pressures_hpa.len != 0) allocator.free(spectroscopy_profile_pressures_hpa);
    const spectroscopy_profile_temperatures_k: []f64 = if (borrowed_profile_preparation) |borrowed|
        borrowed.temperatures_k
    else if (profile_node_count != 0)
        try allocator.alloc(f64, profile_node_count)
    else
        &.{};
    errdefer if (owns_spectroscopy_profile_arrays and spectroscopy_profile_temperatures_k.len != 0) allocator.free(spectroscopy_profile_temperatures_k);
    if (owns_spectroscopy_profile_arrays) {
        for (spectroscopy_profile.rows, 0..) |row, index| {
            spectroscopy_profile_altitudes_km[index] = row.altitude_km;
            spectroscopy_profile_pressures_hpa[index] = row.pressure_hpa;
            spectroscopy_profile_temperatures_k[index] = row.temperature_k;
        }
    }

    const owns_collision_induced_absorption = !inputs.borrow_collision_induced_absorption;
    const collision_induced_absorption = if (inputs.collision_induced_absorption) |cia|
        if (inputs.borrow_collision_induced_absorption)
            cia.*
        else
            try cia.clone(allocator)
    else
        null;
    errdefer if (owns_collision_induced_absorption and collision_induced_absorption != null) {
        const cia = collision_induced_absorption.?;
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
    const aerosol_profile: AerosolModel.Profile = .{ .layers = inputs.aerosol_profile_layers };
    try aerosol_profile.validate();
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
        .owns_collision_induced_absorption = owns_collision_induced_absorption,
        .spectroscopy_lines = spectroscopy_lines,
        .vertical_grid = vertical_grid,
        .layers = layers,
        .sublayers = sublayers,
        .continuum_points = continuum_points,
        .owns_continuum_points = owns_continuum_points,
        .spectroscopy_profile_altitudes_km = spectroscopy_profile_altitudes_km,
        .spectroscopy_profile_pressures_hpa = spectroscopy_profile_pressures_hpa,
        .spectroscopy_profile_temperatures_k = spectroscopy_profile_temperatures_k,
        .owns_spectroscopy_profile_arrays = owns_spectroscopy_profile_arrays,
        .borrowed_profile_weak_line_states = if (borrowed_profile_preparation) |borrowed| borrowed.weak_line_states else null,
        .borrowed_profile_strong_line_states = if (borrowed_profile_preparation) |borrowed| borrowed.strong_line_states else null,
        .borrowed_spectroscopy_plan_key = if (borrowed_profile_preparation) |borrowed| borrowed.spectroscopy_plan_key else 0,
        .borrowed_spectroscopy_profile_cache_inputs_key = if (borrowed_profile_preparation) |borrowed| borrowed.spectroscopy_profile_cache_inputs_key else 0,
        .aerosol_fraction_control = aerosol_fraction_control,
        .aerosol_profile_layers = inputs.aerosol_profile_layers,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
    };
}
