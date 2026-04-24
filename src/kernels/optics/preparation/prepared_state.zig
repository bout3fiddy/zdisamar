//! Purpose:
//!   Define the owned prepared optical state and route its behavior to focused
//!   optics-preparation helper modules.

const std = @import("std");
const AbsorberModel = @import("../../../model/Absorber.zig");
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;
const PhaseSupportKind = @import("../../../model/reference/airmass_phase.zig").PhaseSupportKind;
const transport_common = @import("../../transport/common.zig");
const particle_compat = @import("../../../compat/optics/particle_support.zig");
const Types = @import("state_types.zig");

const Allocator = std.mem.Allocator;

pub const PreparedOpticalState = struct {
    layers: []Types.PreparedLayer,
    sublayers: ?[]Types.PreparedSublayer = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    shared_rtm_geometry: Types.SharedRtmGeometry = .{},
    continuum_points: []ReferenceData.CrossSectionPoint,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    spectroscopy_profile_altitudes_km: []f64 = &.{},
    spectroscopy_profile_pressures_hpa: []f64 = &.{},
    spectroscopy_profile_temperatures_k: []f64 = &.{},
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
    cloud_single_scatter_albedo: f64 = -1.0,
    effective_temperature_k: f64,
    effective_pressure_hpa: f64,
    air_column_density_factor: f64 = 0.0,
    oxygen_column_density_factor: f64 = 0.0,
    column_density_factor: f64,
    cia_pair_path_factor_cm5: f64,
    aerosol_reference_wavelength_nm: f64,
    aerosol_angstrom_exponent: f64,
    cloud_reference_wavelength_nm: f64,
    cloud_angstrom_exponent: f64,
    gas_optical_depth: f64,
    cia_optical_depth: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64,
    cloud_base_optical_depth: f64 = 0.0,
    d_optical_depth_d_temperature: f64,
    depolarization_factor: f64,
    total_optical_depth: f64,
    interval_semantics: AtmosphereModel.IntervalSemantics = .none,
    fit_interval_index_1based: u32 = 0,
    subcolumn_semantics_enabled: bool = false,
    aerosol_phase_support: PhaseSupportKind = .none,
    cloud_phase_support: PhaseSupportKind = .none,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    cloud_fraction_control: AtmosphereModel.FractionControl = .{},
    generated_lut_assets: []Types.GeneratedLutAsset = &.{},
    owns_generated_lut_assets: bool = false,
    lut_execution_entries: []const []const u8 = &.{},
    owns_lut_execution_entries: bool = false,

    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);
        self.shared_rtm_geometry.deinit(allocator);
        allocator.free(self.continuum_points);
        if (self.collision_induced_absorption) |cia| {
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
            if (self.spectroscopy_lines) |line_list| {
                var owned = line_list;
                owned.deinit(allocator);
            }
        }
        if (self.spectroscopy_profile_altitudes_km.len != 0) allocator.free(self.spectroscopy_profile_altitudes_km);
        if (self.spectroscopy_profile_pressures_hpa.len != 0) allocator.free(self.spectroscopy_profile_pressures_hpa);
        if (self.spectroscopy_profile_temperatures_k.len != 0) allocator.free(self.spectroscopy_profile_temperatures_k);
        self.aerosol_fraction_control.deinitOwned(allocator);
        self.cloud_fraction_control.deinitOwned(allocator);
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

    pub fn intervalSemanticsUseReducedSharedRtmLayers(self: *const PreparedOpticalState) bool {
        if (self.interval_semantics == .none) return false;
        const sublayers = self.sublayers orelse return false;
        var referenced_support_rows: usize = 0;
        for (self.layers) |layer| referenced_support_rows += @as(usize, @intCast(layer.sublayer_count));
        return referenced_support_rows > sublayers.len;
    }

    pub fn ensureSharedRtmGeometryCache(
        self: *PreparedOpticalState,
        allocator: Allocator,
    ) !void {
        if (self.shared_rtm_geometry.isValidFor(self.transportLayerCount())) return;
        self.shared_rtm_geometry.deinit(allocator);
        self.shared_rtm_geometry = try @import("transport.zig").buildSharedRtmGeometry(allocator, self);
    }

    pub fn resolvedParticleSingleScatterAlbedos(self: *const PreparedOpticalState) struct {
        aerosol: f64,
        cloud: f64,
    } {
        const resolved = particle_compat.resolvedParticleSingleScatterAlbedos(
            self.aerosol_single_scatter_albedo,
            self.cloud_single_scatter_albedo,
            self.effective_single_scatter_albedo,
        );
        return .{
            .aerosol = resolved.aerosol,
            .cloud = resolved.cloud,
        };
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

    pub fn collisionInducedOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).cia_optical_depth;
    }

    pub fn gasOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        const optical_depths = self.opticalDepthBreakdownAtWavelength(wavelength_nm);
        return optical_depths.gas_absorption_optical_depth + optical_depths.gas_scattering_optical_depth;
    }

    pub fn aerosolOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).aerosol_optical_depth;
    }

    pub fn cloudOpticalDepthAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        return self.opticalDepthBreakdownAtWavelength(wavelength_nm).cloud_optical_depth;
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
