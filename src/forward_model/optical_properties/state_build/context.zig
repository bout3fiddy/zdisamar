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

// context.zig ------------------------------------------------------------------------------------------------|
// Builds the preparation context that owns vertical-grid, profile, aerosol, continuum, CIA, and LUT inputs.   |
//                                                                                                             |
// called by                                                                                                   |
//   root.prepare before absorber preparation and layer accumulation.                                          |
//                                                                                                             |
// main path                                                                                                   |
//   Scene and PreparationInputs                                                                               |
//     -> vertical grid                                                                                        |
//     -> spectroscopy profile arrays                                                                          |
//     -> continuum and CIA tables                                                                             |
//     -> aerosol profile and phase support                                                                    |
//     -> operational cross-section LUTs                                                                       |
//                                                                                                             |
// borrowed profile route                                                                                      |
//   Retrieval sessions can reuse spectroscopy profile arrays and prepared line states when the static         |
//   spectroscopy profile and line-list keys match the current request.                                        |
//                                                                                                             |
// ownership                                                                                                   |
//   Context owns arrays unless the matching borrow flag says the storage belongs to the caller. Finalize      |
//   moves owned buffers into PreparedOpticalState and clears the source references.                           |
// ------------------------------------------------------------------------------------------------------------|

// PreparationInputs ------------------------------------------------------------------------------------------|
// Borrowed input references and ownership flags for one optical-state preparation.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..55] profile/reference pointers: 7 x pointer-sized optional/reference fields                            |
// [56..71] aerosol_profile_layers: []const ProfileLayer                                                       |
// [72..73] borrow flags: 2 x bool                                                                             |
// [74..79] padding                                                                                            |
// ------------------------------------------------------------------------------------------------------------|
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

// BorrowedProfilePreparation ---------------------------------------------------------------------------------|
// Retrieval sessions can borrow profile spectroscopy support across state evaluations.                        |
// Pressure-placement states change vertical-grid and layer optical-depth data, but these rows are keyed       |
// only by the static spectroscopy profile and filtered line list.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..47] profile arrays: altitudes, pressures, temperatures                                                 |
// [48..79] prepared line states: weak and strong optional slices                                              |
// [80..95] spectroscopy cache keys: 2 x u64                                                                   |
// ------------------------------------------------------------------------------------------------------------|
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

const SpectroscopyProfileArrays = struct {
    altitudes_km: []f64 = &.{},
    pressures_hpa: []f64 = &.{},
    temperatures_k: []f64 = &.{},
    owns_arrays: bool = true,
    borrowed_weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    borrowed_strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_plan_key: u64 = 0,
    spectroscopy_profile_cache_inputs_key: u64 = 0,

    fn deinitOwned(self: *SpectroscopyProfileArrays, allocator: Allocator) void {
        if (!self.owns_arrays) return;

        if (self.altitudes_km.len != 0) allocator.free(self.altitudes_km);
        if (self.pressures_hpa.len != 0) allocator.free(self.pressures_hpa);
        if (self.temperatures_k.len != 0) allocator.free(self.temperatures_k);

        self.* = undefined;
    }
};

fn prepareSpectroscopyProfileArrays(
    allocator: Allocator,
    spectroscopy_profile: *const ReferenceData.ClimatologyProfile,
    borrowed_profile_preparation: ?*const BorrowedProfilePreparation,
) !SpectroscopyProfileArrays {
    const profile_node_count = spectroscopy_profile.rows.len;
    if (borrowed_profile_preparation) |borrowed| {
        try borrowed.validate(profile_node_count);
        return .{
            .altitudes_km = borrowed.altitudes_km,
            .pressures_hpa = borrowed.pressures_hpa,
            .temperatures_k = borrowed.temperatures_k,
            .owns_arrays = false,
            .borrowed_weak_line_states = borrowed.weak_line_states,
            .borrowed_strong_line_states = borrowed.strong_line_states,
            .spectroscopy_plan_key = borrowed.spectroscopy_plan_key,
            .spectroscopy_profile_cache_inputs_key = borrowed.spectroscopy_profile_cache_inputs_key,
        };
    }

    var altitudes_km: []f64 = &.{};
    errdefer if (altitudes_km.len != 0) allocator.free(altitudes_km);

    var pressures_hpa: []f64 = &.{};
    errdefer if (pressures_hpa.len != 0) allocator.free(pressures_hpa);

    var temperatures_k: []f64 = &.{};
    errdefer if (temperatures_k.len != 0) allocator.free(temperatures_k);

    if (profile_node_count != 0) {
        altitudes_km = try allocator.alloc(f64, profile_node_count);
        pressures_hpa = try allocator.alloc(f64, profile_node_count);
        temperatures_k = try allocator.alloc(f64, profile_node_count);
    }

    for (spectroscopy_profile.rows, 0..) |row, index| {
        altitudes_km[index] = row.altitude_km;
        pressures_hpa[index] = row.pressure_hpa;
        temperatures_k[index] = row.temperature_k;
    }

    return .{
        .altitudes_km = altitudes_km,
        .pressures_hpa = pressures_hpa,
        .temperatures_k = temperatures_k,
        .owns_arrays = true,
    };
}

// PreparationContext -----------------------------------------------------------------------------------------|
// Owned preparation state passed through absorber, layer, accumulation, and final assembly stages.            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2112 B (2.062 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// [   0..  15] spectroscopy_profile_altitudes_km: []f64                                                       |
// [  16..1223] aerosol_phase_coefficients: [151]f64                                                           |
// [1224..1495] reference pointers, CIA table, spectroscopy lines, midpoint                                    |
// [1496..1719] vertical_grid: OwnedVerticalGrid                                                               |
// [1720..1839] layer, sublayer, continuum slices, and operational O2-O2 LUT                                   |
// [1840..2071] profile/scene pointers, cache keys, operational O2 LUT, borrowed states, aerosol fraction      |
// [2072..2103] aerosol profile slice and spectroscopy pressure slice                                          |
// [2104..2111] ownership flags and padding                                                                    |
//                                                                                                             |
// cache span: 33 cache lines at 64 B per line                                                                 |
// ------------------------------------------------------------------------------------------------------------|
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
        if (self.owns_continuum_points and self.continuum_points.len != 0) {
            allocator.free(self.continuum_points);
        }

        if (self.owns_spectroscopy_profile_arrays) {
            if (self.spectroscopy_profile_altitudes_km.len != 0) {
                allocator.free(self.spectroscopy_profile_altitudes_km);
            }
            if (self.spectroscopy_profile_pressures_hpa.len != 0) {
                allocator.free(self.spectroscopy_profile_pressures_hpa);
            }
            if (self.spectroscopy_profile_temperatures_k.len != 0) {
                allocator.free(self.spectroscopy_profile_temperatures_k);
            }
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
    var spectroscopy_profile_arrays = try prepareSpectroscopyProfileArrays(
        allocator,
        spectroscopy_profile,
        inputs.borrowed_profile_preparation,
    );
    errdefer spectroscopy_profile_arrays.deinitOwned(allocator);

    const owns_collision_induced_absorption = !inputs.borrow_collision_induced_absorption;
    const collision_induced_absorption = choose_cia: {
        if (inputs.collision_induced_absorption) |cia| {
            if (inputs.borrow_collision_induced_absorption) break :choose_cia cia.*;
            break :choose_cia try cia.clone(allocator);
        }

        break :choose_cia null;
    };
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

    const aerosol_profile: AerosolModel.Profile = .{ .layers = inputs.aerosol_profile_layers };
    try aerosol_profile.validate();
    if (aerosol_profile.enabled() and scene.aerosol.fraction.enabled) return error.InvalidRequest;

    var aerosol_fraction_control = choose_aerosol_fraction_control: {
        if (aerosol_profile.enabled()) {
            break :choose_aerosol_fraction_control AtmosphereModel.FractionControl{};
        }

        break :choose_aerosol_fraction_control try scene.aerosol.fraction.clone(allocator);
    };
    errdefer aerosol_fraction_control.deinitOwned(allocator);

    const operational_band_support = scene.observation_model.primaryOperationalBandSupport();
    const operational_o2_lut = choose_operational_o2_lut: {
        if (operational_band_support.o2_operational_lut.enabled()) {
            break :choose_operational_o2_lut try operational_band_support.o2_operational_lut.clone(allocator);
        }

        break :choose_operational_o2_lut OperationalCrossSectionLut{};
    };
    errdefer if (operational_o2_lut.enabled()) {
        var owned = operational_o2_lut;
        owned.deinitOwned(allocator);
    };

    const operational_o2o2_lut = choose_operational_o2o2_lut: {
        if (operational_band_support.o2o2_operational_lut.enabled()) {
            break :choose_operational_o2o2_lut try operational_band_support.o2o2_operational_lut.clone(allocator);
        }

        break :choose_operational_o2o2_lut OperationalCrossSectionLut{};
    };
    errdefer if (operational_o2o2_lut.enabled()) {
        var owned = operational_o2o2_lut;
        owned.deinitOwned(allocator);
    };
    const profile_cache_inputs_key = spectroscopy_profile_arrays.spectroscopy_profile_cache_inputs_key;

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
        .spectroscopy_profile_altitudes_km = spectroscopy_profile_arrays.altitudes_km,
        .spectroscopy_profile_pressures_hpa = spectroscopy_profile_arrays.pressures_hpa,
        .spectroscopy_profile_temperatures_k = spectroscopy_profile_arrays.temperatures_k,
        .owns_spectroscopy_profile_arrays = spectroscopy_profile_arrays.owns_arrays,
        .borrowed_profile_weak_line_states = spectroscopy_profile_arrays.borrowed_weak_line_states,
        .borrowed_profile_strong_line_states = spectroscopy_profile_arrays.borrowed_strong_line_states,
        .borrowed_spectroscopy_plan_key = spectroscopy_profile_arrays.spectroscopy_plan_key,
        .borrowed_spectroscopy_profile_cache_inputs_key = profile_cache_inputs_key,
        .aerosol_fraction_control = aerosol_fraction_control,
        .aerosol_profile_layers = inputs.aerosol_profile_layers,
        .operational_o2_lut = operational_o2_lut,
        .operational_o2o2_lut = operational_o2o2_lut,
        .midpoint_nm = (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
    };
}
