const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const PhaseSupportKind = @import("../../../input/reference/airmass_phase.zig").PhaseSupportKind;
const transport_common = @import("../../radiative_transfer/root.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const Types = @import("state.zig");

const Allocator = std.mem.Allocator;

// prepared_state.zig -----------------------------------------------------------------------------------------|
// PreparedOpticalState lifecycle and read helpers.                                                            |
//                                                                                                             |
// built by                                                                                                    |
//   finalize.zig after context setup, absorber preparation, and layer accumulation finish.                    |
//                                                                                                             |
// used by                                                                                                     |
//   optical-depth evaluation, forward-layer construction, shared RTM geometry, and diagnostics.               |
//                                                                                                             |
// important state                                                                                             |
//   layers and sublayers hold the prepared vertical model.                                                    |
//   absorber rows hold spectroscopy/cross-section data and density columns.                                   |
//   ownership flags say whether referenced tables, profile arrays, LUT assets, and line states are borrowed   |
//   or owned by this final state.                                                                             |
//                                                                                                             |
// memory                                                                                                      |
//   PreparedOpticalState is a wide header over out-of-line rows. Deinit must follow the same ownership flags  |
//   that finalize.zig sets when moving buffers out of the preparation structs.                                |
// ------------------------------------------------------------------------------------------------------------|

// PreparedOpticalState ---------------------------------------------------------------------------------------|
// Final optical-property state returned to transport and diagnostics.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 2136 B (2.086 KiB), align: 8 B                                                                        |
//                                                                                                             |
// memory                                                                                                      |
// inline: aerosol_phase_coefficients : [151]f64 = 1208 B                                                      |
// inline: spectroscopy_lines        : ?SpectroscopyLineList = 216 B                                           |
// inline: scalar fields, flags, ownership markers, cache keys, and slice/table headers                        |
// out-of-line: continuum points, spectroscopy profile arrays, absorber arrays, line states, LUT assets,       |
//              generated LUT assets, and execution-entry strings                                              |
//                                                                                                             |
// unused bits: 56 padding + 63 bool-storage slack = 119 bits                                                  |
// cache span: 34 cache lines at 64 B per line                                                                 |
// footprint: per instance = 2136 B (2.086 KiB); total also includes referenced storage above                  |
pub const PreparedOpticalState = struct {
    layers: []Types.PreparedLayer,
    sublayers: ?[]Types.PreparedSublayer = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_profile_strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    spectroscopy_profile_weak_line_states: ?[]ReferenceData.WeakLinePreparedState = null,
    shared_rtm_geometry: Types.SharedRtmGeometry = .{},
    continuum_points: []const ReferenceData.CrossSectionPoint,
    owns_continuum_points: bool = true,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    owns_collision_induced_absorption: bool = true,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    spectroscopy_profile_altitudes_km: []f64 = &.{},
    spectroscopy_profile_pressures_hpa: []f64 = &.{},
    spectroscopy_profile_temperatures_k: []f64 = &.{},
    owns_spectroscopy_profile_arrays: bool = true,
    owns_spectroscopy_profile_strong_line_states: bool = true,
    owns_spectroscopy_profile_weak_line_states: bool = true,
    spectroscopy_plan_key: u64 = 0,
    spectroscopy_profile_cache_inputs_key: u64 = 0,
    cross_section_absorbers: []Types.PreparedCrossSectionAbsorber = &.{},
    line_absorbers: []Types.PreparedLineAbsorber = &.{},
    continuum_owner_species: ?AbsorberModel.AbsorberSpecies = null,
    operational_o2_lut: OperationalCrossSectionLut = .{},
    operational_o2o2_lut: OperationalCrossSectionLut = .{},
    owns_operational_o2_lut: bool = false,
    owns_operational_o2o2_lut: bool = false,
    mean_cross_section_cm2_per_molecule: f64,
    line_mean_cross_section_cm2_per_molecule: f64,
    line_mixing_mean_cross_section_cm2_per_molecule: f64,
    cia_mean_cross_section_cm5_per_molecule2: f64,
    effective_air_mass_factor: f64,
    effective_single_scatter_albedo: f64,
    aerosol_single_scatter_albedo: f64 = -1.0,
    aerosol_phase_coefficients: [Types.phase_coefficient_count]f64 = PhaseFunctions.zeroPhaseCoefficients(),
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64,
    cia_pair_path_factor_cm5: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    has_aerosol_profile_properties: bool = false,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64 = 0.0,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,
    interval_semantics: AtmosphereModel.IntervalSemantics = .none,
    fit_interval_index_1based: u32 = 0,
    aerosol_phase_support: PhaseSupportKind = .none,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    generated_lut_assets: []Types.GeneratedLutAsset = &.{},
    owns_generated_lut_assets: bool = false,
    lut_execution_entries: []const []const u8 = &.{},
    owns_lut_execution_entries: bool = false,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        // PreparedOpticalState.deinit ----------------------------------------------------------------------- |
        // Release owned prepared optical-property storage. Borrowed tables and profile arrays stay with       |
        // their owner when the corresponding owns_* flag is false.                                            |
        // --------------------------------------------------------------------------------------------------- |

        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);

        self.shared_rtm_geometry.deinit(allocator);

        if (self.owns_continuum_points) allocator.free(self.continuum_points);

        if (self.owns_collision_induced_absorption and self.collision_induced_absorption != null) {
            const cia = self.collision_induced_absorption.?;
            var owned_cia = cia;
            owned_cia.deinit(allocator);
        }

        if (self.cross_section_absorbers.len != 0) {
            for (self.cross_section_absorbers) |*cross_section_absorber| {
                cross_section_absorber.deinit(allocator);
            }
            allocator.free(self.cross_section_absorbers);
        }

        if (self.line_absorbers.len != 0) {
            for (self.line_absorbers) |*line_absorber| {
                line_absorber.deinit(allocator);
            }
            allocator.free(self.line_absorbers);
        } else {
            if (self.strong_line_states) |states| {
                for (states) |*state| state.deinit(allocator);
                allocator.free(states);
            }

            if (self.spectroscopy_profile_strong_line_states) |states| {
                if (self.owns_spectroscopy_profile_strong_line_states) {
                    for (states) |*state| state.deinit(allocator);
                    allocator.free(states);
                }
            }

            if (self.spectroscopy_profile_weak_line_states) |states| {
                if (self.owns_spectroscopy_profile_weak_line_states) {
                    for (states) |*state| state.deinit(allocator);
                    allocator.free(states);
                }
            }

            if (self.spectroscopy_lines) |line_list| {
                var owned = line_list;
                owned.deinit(allocator);
            }
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

        self.aerosol_fraction_control.deinitOwned(allocator);

        if (self.owns_operational_o2_lut) {
            var owned = self.operational_o2_lut;
            owned.deinitOwned(allocator);
        }

        if (self.owns_operational_o2o2_lut) {
            var owned = self.operational_o2o2_lut;
            owned.deinitOwned(allocator);
        }

        if (self.owns_generated_lut_assets) {
            for (self.generated_lut_assets) |*asset| asset.deinitOwned(allocator);
            if (self.generated_lut_assets.len != 0) allocator.free(self.generated_lut_assets);
        }

        if (self.owns_lut_execution_entries) {
            for (self.lut_execution_entries) |entry| allocator.free(entry);
            if (self.lut_execution_entries.len != 0) allocator.free(self.lut_execution_entries);
        }

        self.* = undefined;
    }

    pub fn transportLayerCount(self: *const PreparedOpticalState) usize {
        if (self.intervalSemanticsUseReducedSharedRtmLayers()) return self.layers.len;
        if (self.sublayers) |sublayers| return sublayers.len;
        return self.layers.len;
    }

    pub fn computeSpectroscopyPlanKey(self: *const PreparedOpticalState) u64 {
        var hash = std.hash.Wyhash.init(0x4f32_4132_7370_6c6e);
        updateInt(&hash, self.spectroscopy_lines != null);
        if (self.spectroscopy_lines) |line_list| {
            updateLineListPlanInputs(&hash, line_list);
        }
        updateInt(&hash, self.line_absorbers.len);
        for (self.line_absorbers) |line_absorber| {
            updateLineListPlanInputs(&hash, line_absorber.line_list);
        }
        return hash.final();
    }

    pub fn computeSpectroscopyProfileCacheInputsKey(self: *const PreparedOpticalState) u64 {
        var hash = std.hash.Wyhash.init(0x4f32_4132_7370_726f);
        updateFloatSlice(&hash, self.spectroscopy_profile_altitudes_km);
        updateFloatSlice(&hash, self.spectroscopy_profile_pressures_hpa);
        updateFloatSlice(&hash, self.spectroscopy_profile_temperatures_k);
        updateSpectroscopyCacheInputs(&hash, self);
        return hash.final();
    }

    pub fn intervalSemanticsUseReducedSharedRtmLayers(self: *const PreparedOpticalState) bool {
        // PreparedOpticalState.intervalSemanticsUseReducedSharedRtmLayers ----------------------------------- |
        // Detect the DISAMAR interval mode where several support rows collapse into fewer RTM layers.         |
        //                                                                                                     |
        // hot path                                                                                            |
        // This loop reads only sublayer_count from each wide PreparedLayer row. It stays here because this    |
        // is a rare cache-validity decision, not the repeated per-wavelength carrier evaluation loop.         |
        // --------------------------------------------------------------------------------------------------- |

        if (self.interval_semantics == .none) return false;
        const sublayers = self.sublayers orelse return false;

        var referenced_support_rows: usize = 0;
        const layers: []const Types.PreparedLayer = self.layers;
        for (layers) |*layer| referenced_support_rows += @as(usize, @intCast(layer.sublayer_count));

        return referenced_support_rows > sublayers.len;
    }

    pub fn ensureSharedRtmGeometryCache(
        self: *PreparedOpticalState,
        allocator: Allocator,
    ) !void {
        if (self.shared_rtm_geometry.isValidFor(self.transportLayerCount())) return;
        self.shared_rtm_geometry.deinit(allocator);
        self.shared_rtm_geometry = try @import("shared_geometry.zig").buildSharedRtmGeometry(allocator, self);
    }

    pub fn resolvedAerosolSingleScatterAlbedo(self: *const PreparedOpticalState) f64 {
        // PreparedOpticalState.resolvedAerosolSingleScatterAlbedo ------------------------------------------- |
        // Return the effective aerosol SSA in physical [0, 1] bounds.                                         |
        //                                                                                                     |
        // math                                                                                                |
        // explicit aerosol SSA wins when present; otherwise the mixed effective SSA is used.                  |
        // --------------------------------------------------------------------------------------------------- |

        return std.math.clamp(
            if (self.aerosol_single_scatter_albedo >= 0.0)
                self.aerosol_single_scatter_albedo
            else
                self.effective_single_scatter_albedo,
            0.0,
            1.0,
        );
    }

    pub fn totalCrossSectionAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return @import("state_spectroscopy.zig").totalCrossSectionAtWavelength(self, wavelength_nm);
    }

    pub fn effectiveSpectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        return @import("state_spectroscopy.zig").effectiveSpectroscopyEvaluationAtWavelength(self, wavelength_nm);
    }

    pub fn collisionInducedSigmaAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return @import("state_spectroscopy.zig").collisionInducedSigmaAtWavelength(self, wavelength_nm);
    }

    pub fn gasOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        const optical_depths = self.opticalDepthBreakdownAtWavelength(wavelength_nm);
        return optical_depths.gas_absorption_optical_depth + optical_depths.gas_scattering_optical_depth;
    }

    pub fn totalOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).totalOpticalDepth();
    }

    pub fn preparedScalarForSublayer(values: []const f64, sublayer: Types.PreparedSublayer) f64 {
        return @import("state_scalar.zig").preparedScalarForSublayer(values, sublayer);
    }

    pub fn interpolatePreparedScalarAtAltitude(
        sublayers: []const Types.PreparedSublayer,
        values: []const f64,
        altitude_km: f64,
    ) f64 {
        return @import("state_scalar.zig").interpolatePreparedScalarAtAltitude(sublayers, values, altitude_km);
    }

    pub fn lineSpectroscopyCarrierDensity(
        self: *const PreparedOpticalState,
        absorber_density_cm3: f64,
        oxygen_density_cm3: f64,
        cross_section_density_cm3: f64,
    ) f64 {
        return @import("state_scalar.zig").lineSpectroscopyCarrierDensity(
            self,
            absorber_density_cm3,
            oxygen_density_cm3,
            cross_section_density_cm3,
        );
    }

    pub fn continuumCarrierDensityAtAltitude(
        self: *const PreparedOpticalState,
        sublayers: []const Types.PreparedSublayer,
        altitude_km: f64,
        absorber_density_cm3: f64,
        oxygen_density_cm3: f64,
    ) f64 {
        return @import("state_scalar.zig").continuumCarrierDensityAtAltitude(
            self,
            sublayers,
            altitude_km,
            absorber_density_cm3,
            oxygen_density_cm3,
        );
    }

    pub fn particleOpticalDepthAtWavelength(
        effective_reference_optical_depth: f64,
        base_reference_optical_depth: f64,
        reference_wavelength_nm: f64,
        angstrom_exponent: f64,
        control: AtmosphereModel.FractionControl,
        wavelength_nm: f64,
    ) f64 {
        return @import("state_scalar.zig").particleOpticalDepthAtWavelength(
            effective_reference_optical_depth,
            base_reference_optical_depth,
            reference_wavelength_nm,
            angstrom_exponent,
            control,
            wavelength_nm,
        );
    }

    pub fn opticalDepthBreakdownAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) Types.OpticalDepthBreakdown {
        return @import("state_optical_depth.zig").opticalDepthBreakdownAtWavelength(self, wavelength_nm);
    }

    pub fn evaluateLayerAtWavelength(
        self: *const PreparedOpticalState,
        scene: ?*const Scene,
        altitude_km: f64,
        wavelength_nm: f64,
        sublayer_start_index: usize,
        sublayers: []const Types.PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    ) Types.EvaluatedLayer {
        return @import("state_optical_depth.zig").evaluateLayerAtWavelength(
            self,
            scene,
            altitude_km,
            wavelength_nm,
            sublayer_start_index,
            sublayers,
            strong_line_states,
        );
    }

    pub fn evaluateLayerAtWavelengthWithSpectroscopyCache(
        self: *const PreparedOpticalState,
        scene: ?*const Scene,
        altitude_km: f64,
        wavelength_nm: f64,
        sublayer_start_index: usize,
        sublayers: []const Types.PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
        profile_cache: ?*const @import("state_spectroscopy.zig").ProfileNodeSpectroscopyCache,
    ) Types.EvaluatedLayer {
        return @import("state_optical_depth.zig").evaluateLayerAtWavelengthWithSpectroscopyCache(
            self,
            scene,
            altitude_km,
            wavelength_nm,
            sublayer_start_index,
            sublayers,
            strong_line_states,
            profile_cache,
        );
    }

    pub fn spectroscopySigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    ) f64 {
        return @import("state_spectroscopy.zig").spectroscopySigmaAtWavelength(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            prepared_state,
        );
    }

    pub fn spectroscopyEvaluationAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        altitude_km: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    ) ReferenceData.SpectroscopyEvaluation {
        return @import("state_spectroscopy.zig").spectroscopyEvaluationAtAltitude(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            altitude_km,
            prepared_state,
        );
    }

    pub fn spectroscopyEvaluationAtAltitudeWithCache(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        altitude_km: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
        profile_cache: ?*const @import("state_spectroscopy.zig").ProfileNodeSpectroscopyCache,
    ) ReferenceData.SpectroscopyEvaluation {
        return @import("state_spectroscopy.zig").spectroscopyEvaluationAtAltitudeWithCache(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            altitude_km,
            prepared_state,
            profile_cache,
        );
    }

    pub fn spectroscopySigmaAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        altitude_km: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    ) f64 {
        return @import("state_spectroscopy.zig").spectroscopyEvaluationAtAltitude(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            altitude_km,
            prepared_state,
        ).total_sigma_cm2_per_molecule;
    }

    pub fn spectroscopySigmaAtAltitudeWithCache(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        altitude_km: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
        profile_cache: ?*const @import("state_spectroscopy.zig").ProfileNodeSpectroscopyCache,
    ) f64 {
        return @import("state_spectroscopy.zig").spectroscopySigmaAtAltitudeWithCache(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            altitude_km,
            prepared_state,
            profile_cache,
        );
    }

    pub fn preparedStrongLineStateAtAltitude(
        sublayers: []const Types.PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
        altitude_km: f64,
    ) ?*const ReferenceData.StrongLinePreparedState {
        return @import("state_spectroscopy.zig").preparedStrongLineStateAtAltitude(
            sublayers,
            strong_line_states,
            altitude_km,
        );
    }

    pub fn weightedSpectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        return @import("state_spectroscopy.zig").weightedSpectroscopyEvaluationAtWavelength(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
    }

    pub fn weightedSpectroscopyEvaluationAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        sublayers: []const Types.PreparedSublayer,
        altitude_km: f64,
        oxygen_density_cm3: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        return @import("state_spectroscopy.zig").weightedSpectroscopyEvaluationAtAltitude(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
            sublayers,
            altitude_km,
            oxygen_density_cm3,
        );
    }

    pub fn ciaSigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return @import("state_spectroscopy.zig").ciaSigmaAtWavelength(
            self,
            wavelength_nm,
            temperature_k,
            pressure_hpa,
        );
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn updateSpectroscopyCacheInputs(
    hash: *std.hash.Wyhash,
    prepared: *const PreparedOpticalState,
) void {
    updateInt(hash, prepared.spectroscopy_lines != null);
    if (prepared.spectroscopy_lines) |line_list| updateFullLineListInputs(hash, line_list);
    updateInt(hash, prepared.operational_o2_lut.enabled());
    updateStrongLinePreparedStates(hash, prepared.spectroscopy_profile_strong_line_states);
    updateWeakLinePreparedStates(hash, prepared.spectroscopy_profile_weak_line_states);
}

fn updateStrongLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    updateInt(hash, states != null);
    if (states) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |state| {
            updateInt(hash, state.line_count);
            updateFloat(hash, state.sig_moy_cm1);
            updateFloatSlice(hash, state.population_t);
            updateFloatSlice(hash, state.dipole_t);
            updateFloatSlice(hash, state.mod_sig_cm1);
            updateFloatSlice(hash, state.half_width_cm1_at_t);
            updateFloatSlice(hash, state.line_mixing_coefficients);
        }
    }
}

fn updateWeakLinePreparedStates(hash: *std.hash.Wyhash, states: anytype) void {
    updateInt(hash, states != null);
    if (states) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |state| {
            updateInt(hash, state.line_count);
            updateFloat(hash, state.safe_temperature);
            updateFloat(hash, state.safe_pressure);
            updateInt(hash, state.lines.len);
            for (state.lines) |line| {
                updateFloat(hash, line.shifted_center_wavenumber_cm1);
                updateFloat(hash, line.cte);
                updateFloat(hash, line.line_shape_y);
                updateFloat(hash, line.prefactor_base);
            }
        }
    }
}

fn updateLineListPlanInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    updateOptionalFloat(hash, line_list.runtime_controls.threshold_line_scale);
    updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        updateFloat(hash, line.center_wavelength_nm);
        updateFloat(hash, line.line_strength_cm2_per_molecule);
    }
}

fn updateFullLineListInputs(hash: *std.hash.Wyhash, line_list: anytype) void {
    updateFloat(hash, line_list.strong_line_tolerance_nm);
    updateInt(hash, line_list.lines_sorted_ascending);
    updateInt(hash, line_list.preserve_anchor_weak_lines);
    updateInt(hash, line_list.vendor_strong_line_partition);
    updateOptionalIntSlice(hash, line_list.strong_line_match_by_line);
    updateFullRuntimeControls(hash, line_list.runtime_controls);

    updateInt(hash, line_list.lines.len);
    for (line_list.lines) |line| {
        updateInt(hash, line.gas_index);
        updateInt(hash, line.isotope_number);
        updateFloat(hash, line.abundance_fraction);
        updateInt(hash, line.vendor_filter_metadata_from_source);
        updateFloat(hash, line.center_wavelength_nm);
        updateFloat(hash, line.center_wavenumber_cm1);
        updateFloat(hash, line.line_strength_cm2_per_molecule);
        updateFloat(hash, line.air_half_width_nm);
        updateFloat(hash, line.air_half_width_cm1);
        updateFloat(hash, line.temperature_exponent);
        updateFloat(hash, line.lower_state_energy_cm1);
        updateFloat(hash, line.pressure_shift_nm);
        updateFloat(hash, line.pressure_shift_cm1);
        updateFloat(hash, line.line_mixing_coefficient);
        updateOptionalInt(hash, line.branch_ic1);
        updateOptionalInt(hash, line.branch_ic2);
        updateOptionalInt(hash, line.rotational_nf);
    }

    updateInt(hash, line_list.strong_lines != null);
    if (line_list.strong_lines) |strong_lines| {
        updateInt(hash, strong_lines.len);
        for (strong_lines) |line| {
            updateFloat(hash, line.center_wavenumber_cm1);
            updateFloat(hash, line.center_wavelength_nm);
            updateFloat(hash, line.population_t0);
            updateFloat(hash, line.dipole_ratio);
            updateFloat(hash, line.dipole_t0);
            updateFloat(hash, line.lower_state_energy_cm1);
            updateFloat(hash, line.air_half_width_cm1);
            updateFloat(hash, line.air_half_width_nm);
            updateFloat(hash, line.temperature_exponent);
            updateFloat(hash, line.pressure_shift_cm1);
            updateFloat(hash, line.pressure_shift_nm);
            updateInt(hash, line.rotational_index_m1);
        }
    }

    updateInt(hash, line_list.relaxation_matrix != null);
    if (line_list.relaxation_matrix) |matrix| {
        updateInt(hash, matrix.line_count);
        updateFloatSlice(hash, matrix.wt0);
        updateFloatSlice(hash, matrix.bw);
    }
}

fn updateFullRuntimeControls(hash: *std.hash.Wyhash, controls: anytype) void {
    updateOptionalInt(hash, controls.gas_index);
    updateInt(hash, controls.active_isotopes.len);
    hash.update(controls.active_isotopes);
    updateOptionalFloat(hash, controls.threshold_line_scale);
    updateOptionalFloat(hash, controls.cutoff_cm1);
    updateFloatSlice(hash, controls.cutoff_grid_wavelengths_nm);
    updateFloatSlice(hash, controls.cutoff_grid_wavenumbers_cm1);
    updateFloat(hash, controls.line_mixing_factor);
}

fn updateOptionalInt(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateInt(hash, resolved);
}

fn updateOptionalIntSlice(hash: *std.hash.Wyhash, value: anytype) void {
    updateInt(hash, value != null);
    if (value) |resolved| {
        updateInt(hash, resolved.len);
        for (resolved) |item| updateOptionalInt(hash, item);
    }
}

fn updateOptionalFloat(hash: *std.hash.Wyhash, value: ?f64) void {
    updateInt(hash, value != null);
    if (value) |resolved| updateFloat(hash, resolved);
}

fn updateFloatSlice(hash: *std.hash.Wyhash, values: []const f64) void {
    updateInt(hash, values.len);
    hash.update(std.mem.sliceAsBytes(values));
}

fn updateFloat(hash: *std.hash.Wyhash, value: f64) void {
    var bits = @as(u64, @bitCast(value));
    hash.update(std.mem.asBytes(&bits));
}

fn updateInt(hash: *std.hash.Wyhash, value: anytype) void {
    var bits = value;
    hash.update(std.mem.asBytes(&bits));
}
