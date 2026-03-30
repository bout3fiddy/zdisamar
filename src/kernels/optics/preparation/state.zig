//! Purpose:
//!   Define the prepared optical-state carriers produced by optics
//!   preparation.
//!
//! Physics:
//!   Stores layer, sublayer, spectroscopy, and optical-depth breakdown data
//!   that feed transport execution and measurement-space evaluation.
//!
//! Vendor:
//!   `optics preparation state`
//!
//! Design:
//!   Keeps the prepared state typed and reusable so transport execution does
//!   not rebuild scientific intermediates on every sample.
//!
//! Invariants:
//!   Prepared layers, sublayers, and sidecar arrays must stay aligned with the
//!   scene grid and any optional strong-line state.
//!
//! Validation:
//!   Optics-preparation transport tests and measurement-space tests.

const std = @import("std");
const AbsorberModel = @import("../../../model/Absorber.zig");
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../model/Instrument.zig").OperationalCrossSectionLut;
const LutControls = @import("../../../core/lut_controls.zig");
const PhaseSupportKind = @import("../../../model/reference/airmass_phase.zig").PhaseSupportKind;
const Rayleigh = @import("../../../model/reference/rayleigh.zig");
const transport_common = @import("../../transport/common.zig");
const OperationalO2 = @import("operational_o2.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");

const Allocator = std.mem.Allocator;
const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;
const oxygen_volume_mixing_ratio = 0.2095;
const centimeters_per_kilometer = 1.0e5;

/// Active line absorber resolved from the scene's absorber set.
pub const ActiveLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    controls: AbsorberModel.LineGasControls,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
};

/// Active cross-section absorber resolved from the scene's absorber set.
pub const ActiveCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    representation: AbsorberModel.AbsorptionRepresentation,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
    use_effective_cross_section: bool = false,
    polynomial_order: u32 = 0,
};

/// Prepared line absorber with runtime controls and stored number densities.
pub const PreparedLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    line_list: ReferenceData.SpectroscopyLineList,
    number_densities_cm3: []f64,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    strong_line_state_initialized: ?[]bool = null,
    strong_line_state_count: usize = 0,
    column_density_factor: f64 = 0.0,

    /// Purpose:
    ///   Release the owned line-list and sidecar buffers.
    pub fn deinit(self: *PreparedLineAbsorber, allocator: Allocator) void {
        self.line_list.deinit(allocator);
        allocator.free(self.number_densities_cm3);
        if (self.strong_line_states) |states| {
            if (self.strong_line_state_initialized) |initialized| {
                for (states, initialized) |*state, is_initialized| {
                    if (!is_initialized) continue;
                    state.deinit(allocator);
                }
                allocator.free(initialized);
            } else {
                for (states[0..self.strong_line_state_count]) |*state| state.deinit(allocator);
            }
            allocator.free(states);
        }
        self.* = undefined;
    }
};

pub const CrossSectionRepresentationKind = enum {
    table,
    lut,
    effective_table,
    effective_lut,
};

pub const PreparedCrossSectionRepresentation = union(enum) {
    table: ReferenceData.CrossSectionTable,
    lut: OperationalCrossSectionLut,
};

/// Prepared cross-section absorber with stored densities and typed representation metadata.
pub const PreparedCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    representation_kind: CrossSectionRepresentationKind,
    polynomial_order: u32 = 0,
    representation: PreparedCrossSectionRepresentation,
    number_densities_cm3: []f64,
    column_density_factor: f64 = 0.0,

    /// Purpose:
    ///   Release the owned cross-section representation and density storage.
    pub fn deinit(self: *PreparedCrossSectionAbsorber, allocator: Allocator) void {
        switch (self.representation) {
            .table => |*table| {
                var owned = table.*;
                owned.deinit(allocator);
            },
            .lut => |*lut| {
                var owned = lut.*;
                owned.deinitOwned(allocator);
            },
        }
        allocator.free(self.number_densities_cm3);
        self.* = undefined;
    }

    /// Purpose:
    ///   Evaluate the prepared cross section at a wavelength.
    pub fn sigmaAt(
        self: *const PreparedCrossSectionAbsorber,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return switch (self.representation) {
            .table => |table| table.interpolateSigma(wavelength_nm),
            .lut => |lut| lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa),
        };
    }

    /// Purpose:
    ///   Evaluate the prepared temperature derivative at a wavelength.
    pub fn dSigmaDTemperatureAt(
        self: *const PreparedCrossSectionAbsorber,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return switch (self.representation) {
            .table => 0.0,
            .lut => |lut| lut.dSigmaDTemperatureAt(wavelength_nm, temperature_k, pressure_hpa),
        };
    }

    /// Purpose:
    ///   Compute a representative band mean for the prepared representation.
    pub fn meanSigmaInRange(
        self: *const PreparedCrossSectionAbsorber,
        start_nm: f64,
        end_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        return switch (self.representation) {
            .table => |table| table.meanSigmaInRange(start_nm, end_nm),
            .lut => |lut| {
                const midpoint_nm = (start_nm + end_nm) * 0.5;
                return lut.sigmaAt(midpoint_nm, temperature_k, pressure_hpa);
            },
        };
    }
};

/// Prepared layer state on the transport grid.
pub const PreparedLayer = struct {
    layer_index: u32,
    sublayer_start_index: u32 = 0,
    sublayer_count: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_optical_depth: f64,
    gas_scattering_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64,
    cloud_base_optical_depth: f64 = 0.0,
    layer_single_scatter_albedo: f64,
    depolarization_factor: f64,
    optical_depth: f64,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    subcolumn_label: AtmosphereModel.PartitionLabel = .unspecified,
    aerosol_fraction: f64 = 0.0,
    cloud_fraction: f64 = 0.0,
};

/// Prepared sublayer state on the fine transport grid.
pub const PreparedSublayer = struct {
    parent_layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    absorber_number_density_cm3: f64 = 0.0,
    path_length_cm: f64,
    continuum_cross_section_cm2_per_molecule: f64,
    line_cross_section_cm2_per_molecule: f64,
    line_mixing_cross_section_cm2_per_molecule: f64,
    cia_sigma_cm5_per_molecule2: f64,
    cia_optical_depth: f64,
    d_cross_section_d_temperature_cm2_per_molecule_per_k: f64,
    gas_absorption_optical_depth: f64,
    gas_scattering_optical_depth: f64,
    gas_extinction_optical_depth: f64,
    d_gas_optical_depth_d_temperature: f64,
    d_cia_optical_depth_d_temperature: f64,
    aerosol_optical_depth: f64,
    aerosol_base_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64,
    cloud_base_optical_depth: f64 = 0.0,
    aerosol_single_scatter_albedo: f64,
    cloud_single_scatter_albedo: f64,
    aerosol_phase_coefficients: [phase_coefficient_count]f64,
    cloud_phase_coefficients: [phase_coefficient_count]f64,
    combined_phase_coefficients: [phase_coefficient_count]f64,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    subcolumn_label: AtmosphereModel.PartitionLabel = .unspecified,
    aerosol_fraction: f64 = 0.0,
    cloud_fraction: f64 = 0.0,
};

/// Accumulated optical-depth contributions for one transport layer.
pub const OpticalDepthBreakdown = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,
    cloud_optical_depth: f64 = 0.0,
    cloud_scattering_optical_depth: f64 = 0.0,

    pub fn totalScatteringOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_scattering_optical_depth +
            self.aerosol_scattering_optical_depth +
            self.cloud_scattering_optical_depth;
    }

    pub fn totalOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_absorption_optical_depth +
            self.gas_scattering_optical_depth +
            self.cia_optical_depth +
            self.aerosol_optical_depth +
            self.cloud_optical_depth;
    }

    pub fn singleScatterAlbedo(self: OpticalDepthBreakdown) f64 {
        const total_optical_depth = self.totalOpticalDepth();
        if (total_optical_depth <= 0.0) return 0.0;
        return std.math.clamp(
            self.totalScatteringOpticalDepth() / total_optical_depth,
            0.0,
            1.0,
        );
    }
};

/// Evaluated layer state used to derive transport layer inputs.
pub const EvaluatedLayer = struct {
    breakdown: OpticalDepthBreakdown = .{},
    phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.gasPhaseCoefficients(),
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
};

pub const GeneratedLutAssetKind = enum {
    reflectance,
    correction,
    xsec,
};

pub const GeneratedLutAsset = struct {
    dataset_id: []const u8 = "",
    lut_id: []const u8 = "",
    provenance_label: []const u8 = "",
    kind: GeneratedLutAssetKind,
    mode: LutControls.Mode = .direct,
    spectral_bin_count: u32 = 0,
    layer_count: u32 = 0,
    coefficient_count: u32 = 0,
    compatibility: LutControls.CompatibilityKey = .{},
    owns_strings: bool = false,

    pub fn deinitOwned(self: *GeneratedLutAsset, allocator: Allocator) void {
        if (self.owns_strings) {
            if (self.dataset_id.len != 0) allocator.free(self.dataset_id);
            if (self.lut_id.len != 0) allocator.free(self.lut_id);
            if (self.provenance_label.len != 0) allocator.free(self.provenance_label);
        }
        self.* = undefined;
    }
};

/// Prepared optical state consumed by transport and measurement evaluation.
pub const PreparedOpticalState = struct {
    layers: []PreparedLayer,
    sublayers: ?[]PreparedSublayer = null,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    continuum_points: []ReferenceData.CrossSectionPoint,
    collision_induced_absorption: ?ReferenceData.CollisionInducedAbsorptionTable = null,
    spectroscopy_lines: ?ReferenceData.SpectroscopyLineList = null,
    cross_section_absorbers: []PreparedCrossSectionAbsorber = &.{},
    line_absorbers: []PreparedLineAbsorber = &.{},
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
    generated_lut_assets: []GeneratedLutAsset = &.{},
    owns_generated_lut_assets: bool = false,
    lut_execution_entries: []const []const u8 = &.{},
    owns_lut_execution_entries: bool = false,

    /// Purpose:
    ///   Release the prepared optical state and all owned substructures.
    pub fn deinit(self: *PreparedOpticalState, allocator: Allocator) void {
        allocator.free(self.layers);
        if (self.sublayers) |sublayers| allocator.free(sublayers);
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

    /// Purpose:
    ///   Report the resolved transport layer count for this prepared state.
    pub fn transportLayerCount(self: *const PreparedOpticalState) usize {
        if (self.sublayers) |sublayers| return sublayers.len;
        return self.layers.len;
    }

    /// Purpose:
    ///   Convert the prepared state into a forward-input carrier.
    pub fn toForwardInput(self: *const PreparedOpticalState, scene: *const Scene) transport_common.ForwardInput {
        return @import("transport.zig").toForwardInput(self, scene);
    }

    /// Purpose:
    ///   Convert the prepared state into a forward-input carrier with explicit
    ///   layer inputs.
    pub fn toForwardInputWithLayers(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        layer_inputs: ?[]transport_common.LayerInput,
    ) transport_common.ForwardInput {
        return @import("transport.zig").toForwardInputWithLayers(self, scene, layer_inputs);
    }

    /// Purpose:
    ///   Convert the prepared state into a wavelength-specific forward input.
    pub fn toForwardInputAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
    ) transport_common.ForwardInput {
        return @import("transport.zig").toForwardInputAtWavelength(self, scene, wavelength_nm);
    }

    /// Purpose:
    ///   Convert the prepared state into a wavelength-specific forward input
    ///   with explicit layer inputs.
    pub fn toForwardInputAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        layer_inputs: ?[]transport_common.LayerInput,
    ) transport_common.ForwardInput {
        return @import("transport.zig").toForwardInputAtWavelengthWithLayers(
            self,
            scene,
            wavelength_nm,
            layer_inputs,
        );
    }

    /// Purpose:
    ///   Materialize transport layer inputs at one wavelength.
    pub fn fillForwardLayersAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        layer_inputs: []transport_common.LayerInput,
    ) OpticalDepthBreakdown {
        return @import("transport.zig").fillForwardLayersAtWavelength(
            self,
            scene,
            wavelength_nm,
            layer_inputs,
        );
    }

    /// Purpose:
    ///   Resolve per-particle single-scatter albedos with compatibility
    ///   fallbacks for hand-built prepared states.
    pub fn resolvedParticleSingleScatterAlbedos(self: *const PreparedOpticalState) struct {
        aerosol: f64,
        cloud: f64,
    } {
        return .{
            .aerosol = std.math.clamp(
                if (self.aerosol_single_scatter_albedo >= 0.0)
                    self.aerosol_single_scatter_albedo
                else
                    self.effective_single_scatter_albedo,
                0.0,
                1.0,
            ),
            .cloud = std.math.clamp(
                if (self.cloud_single_scatter_albedo >= 0.0)
                    self.cloud_single_scatter_albedo
                else
                    self.effective_single_scatter_albedo,
                0.0,
                1.0,
            ),
        };
    }

    /// Purpose:
    ///   Materialize source-interface carriers at one wavelength.
    pub fn fillSourceInterfacesAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        layer_inputs: []const transport_common.LayerInput,
        source_interfaces: []transport_common.SourceInterfaceInput,
    ) void {
        @import("transport.zig").fillSourceInterfacesAtWavelengthWithLayers(
            self,
            wavelength_nm,
            layer_inputs,
            source_interfaces,
        );
    }

    /// Purpose:
    ///   Materialize RTM quadrature carriers at one wavelength.
    pub fn fillRtmQuadratureAtWavelengthWithLayers(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        layer_inputs: []const transport_common.LayerInput,
        rtm_levels: []transport_common.RtmQuadratureLevel,
    ) bool {
        return @import("transport.zig").fillRtmQuadratureAtWavelengthWithLayers(
            self,
            wavelength_nm,
            layer_inputs,
            rtm_levels,
        );
    }

    /// Purpose:
    ///   Materialize the pseudo-spherical grid at one wavelength.
    pub fn fillPseudoSphericalGridAtWavelength(
        self: *const PreparedOpticalState,
        scene: *const Scene,
        wavelength_nm: f64,
        solver_layer_count: usize,
        attenuation_layers: []transport_common.LayerInput,
        attenuation_samples: []transport_common.PseudoSphericalSample,
        level_sample_starts: []usize,
        level_altitudes_km: []f64,
    ) bool {
        return @import("transport.zig").fillPseudoSphericalGridAtWavelength(
            self,
            scene,
            wavelength_nm,
            solver_layer_count,
            attenuation_layers,
            attenuation_samples,
            level_sample_starts,
            level_altitudes_km,
        );
    }

    pub fn totalCrossSectionAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        const continuum = if (self.cross_section_absorbers.len == 0)
            (ReferenceData.CrossSectionTable{
                .points = self.continuum_points,
            }).interpolateSigma(wavelength_nm)
        else
            self.weightedCrossSectionSigmaAtWavelength(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            );
        const line_sigma = if (self.line_absorbers.len != 0)
            self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else if (self.operational_o2_lut.enabled())
            self.operational_o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            )
        else if (self.spectroscopy_lines) |line_list|
            line_list.evaluateAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ).total_sigma_cm2_per_molecule
        else
            0.0;
        return continuum + line_sigma;
    }

    pub fn effectiveSpectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        return self.weightedSpectroscopyEvaluationAtWavelength(
            wavelength_nm,
            self.effective_temperature_k,
            self.effective_pressure_hpa,
        );
    }

    pub fn collisionInducedSigmaAtWavelength(self: *const PreparedOpticalState, wavelength_nm: f64) f64 {
        if (self.operational_o2o2_lut.enabled()) {
            return self.operational_o2o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            );
        }
        if (self.collision_induced_absorption) |cia_table| {
            return cia_table.sigmaAt(wavelength_nm, self.effective_temperature_k);
        }
        return 0.0;
    }

    fn weightedCrossSectionSigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        if (self.cross_section_absorbers.len == 0) return 0.0;

        var total_weight: f64 = 0.0;
        var weighted_sigma: f64 = 0.0;
        for (self.cross_section_absorbers) |cross_section_absorber| {
            const weight = if (cross_section_absorber.column_density_factor > 0.0)
                cross_section_absorber.column_density_factor
            else
                1.0;
            total_weight += weight;
            weighted_sigma += cross_section_absorber.sigmaAt(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            ) * weight;
        }
        if (total_weight <= 0.0) return 0.0;
        return weighted_sigma / total_weight;
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

    pub fn preparedScalarForSublayer(values: []const f64, sublayer: PreparedSublayer) f64 {
        const index: usize = @intCast(sublayer.global_sublayer_index);
        if (index >= values.len) return 0.0;
        return values[index];
    }

    fn interpolatePreparedScalarBetweenSublayers(
        left: PreparedSublayer,
        right: PreparedSublayer,
        values: []const f64,
        altitude_km: f64,
    ) f64 {
        const left_value = preparedScalarForSublayer(values, left);
        const right_value = preparedScalarForSublayer(values, right);
        const span = right.altitude_km - left.altitude_km;
        if (span <= 0.0) return right_value;
        const fraction = std.math.clamp((altitude_km - left.altitude_km) / span, 0.0, 1.0);
        return left_value + (right_value - left_value) * fraction;
    }

    pub fn interpolatePreparedScalarAtAltitude(
        sublayers: []const PreparedSublayer,
        values: []const f64,
        altitude_km: f64,
    ) f64 {
        if (sublayers.len == 0) return 0.0;
        if (sublayers.len == 1) return preparedScalarForSublayer(values, sublayers[0]);

        const first = sublayers[0];
        const last = sublayers[sublayers.len - 1];
        if (altitude_km <= first.altitude_km) {
            return interpolatePreparedScalarBetweenSublayers(first, sublayers[1], values, altitude_km);
        }
        if (altitude_km >= last.altitude_km) {
            return interpolatePreparedScalarBetweenSublayers(sublayers[sublayers.len - 2], last, values, altitude_km);
        }
        for (sublayers[0 .. sublayers.len - 1], sublayers[1..]) |left, right| {
            if (altitude_km > right.altitude_km) continue;
            return interpolatePreparedScalarBetweenSublayers(left, right, values, altitude_km);
        }
        return preparedScalarForSublayer(values, last);
    }

    fn lineAbsorberDensityForSpeciesAtSublayer(
        self: *const PreparedOpticalState,
        species: AbsorberModel.AbsorberSpecies,
        global_sublayer_index: usize,
    ) f64 {
        for (self.line_absorbers) |line_absorber| {
            if (line_absorber.species != species) continue;
            if (global_sublayer_index >= line_absorber.number_densities_cm3.len) return 0.0;
            return line_absorber.number_densities_cm3[global_sublayer_index];
        }
        return 0.0;
    }

    fn lineAbsorberDensityForSpeciesAtAltitude(
        self: *const PreparedOpticalState,
        species: AbsorberModel.AbsorberSpecies,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
    ) f64 {
        for (self.line_absorbers) |line_absorber| {
            if (line_absorber.species != species) continue;
            return interpolatePreparedScalarAtAltitude(
                sublayers,
                line_absorber.number_densities_cm3,
                altitude_km,
            );
        }
        return 0.0;
    }

    fn continuumCarrierDensityAtSublayer(
        self: *const PreparedOpticalState,
        sublayer: PreparedSublayer,
        global_sublayer_index: usize,
    ) f64 {
        if (self.line_absorbers.len == 0) return sublayer.absorber_number_density_cm3;

        const owner_species = self.continuum_owner_species orelse return sublayer.absorber_number_density_cm3;
        // DECISION:
        //   When preparation can identify a continuum owner, scope the continuum to that
        //   gas only. If ownership is unknown, preserve the prior summed-density behavior
        //   rather than dropping continuum absorption entirely for mixed non-O2 families.
        if (self.operational_o2_lut.enabled() and owner_species == .o2) {
            return sublayer.oxygen_number_density_cm3;
        }
        return self.lineAbsorberDensityForSpeciesAtSublayer(owner_species, global_sublayer_index);
    }

    fn crossSectionCarrierDensityAtSublayer(
        self: *const PreparedOpticalState,
        global_sublayer_index: usize,
    ) f64 {
        var density_cm3: f64 = 0.0;
        for (self.cross_section_absorbers) |cross_section_absorber| {
            if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;
            density_cm3 += cross_section_absorber.number_densities_cm3[global_sublayer_index];
        }
        return density_cm3;
    }

    pub fn lineSpectroscopyCarrierDensity(
        self: *const PreparedOpticalState,
        absorber_density_cm3: f64,
        oxygen_density_cm3: f64,
        cross_section_density_cm3: f64,
    ) f64 {
        if (self.operational_o2_lut.enabled()) return oxygen_density_cm3;
        if (cross_section_density_cm3 <= 0.0) return absorber_density_cm3;

        // DECISION:
        //   Prepared sublayers store total gas density so midpoint preparation can
        //   retain mixed line/cross-section bookkeeping. Every single-line
        //   re-evaluation path must subtract the explicit cross-section carriers
        //   back out before applying a line-by-line sigma.
        return @max(@as(f64, 0.0), absorber_density_cm3 - cross_section_density_cm3);
    }

    fn lineSpectroscopyCarrierDensityAtSublayer(
        self: *const PreparedOpticalState,
        sublayer: PreparedSublayer,
        global_sublayer_index: usize,
    ) f64 {
        return self.lineSpectroscopyCarrierDensity(
            sublayer.absorber_number_density_cm3,
            sublayer.oxygen_number_density_cm3,
            if (self.cross_section_absorbers.len == 0)
                0.0
            else
                self.crossSectionCarrierDensityAtSublayer(global_sublayer_index),
        );
    }

    pub fn continuumCarrierDensityAtAltitude(
        self: *const PreparedOpticalState,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
        absorber_density_cm3: f64,
        oxygen_density_cm3: f64,
    ) f64 {
        if (self.line_absorbers.len == 0) return absorber_density_cm3;

        const owner_species = self.continuum_owner_species orelse return absorber_density_cm3;
        if (self.operational_o2_lut.enabled() and owner_species == .o2) {
            return oxygen_density_cm3;
        }
        return self.lineAbsorberDensityForSpeciesAtAltitude(owner_species, sublayers, altitude_km);
    }

    fn fractionAtWavelength(control: AtmosphereModel.FractionControl, wavelength_nm: f64) f64 {
        if (!control.enabled) return 1.0;
        return control.valueAtWavelength(wavelength_nm);
    }

    pub fn particleOpticalDepthAtWavelength(
        effective_reference_optical_depth: f64,
        base_reference_optical_depth: f64,
        reference_wavelength_nm: f64,
        angstrom_exponent: f64,
        control: AtmosphereModel.FractionControl,
        wavelength_nm: f64,
    ) f64 {
        if (base_reference_optical_depth > 0.0) {
            return ParticleProfiles.scaleOpticalDepth(
                base_reference_optical_depth,
                reference_wavelength_nm,
                angstrom_exponent,
                wavelength_nm,
            ) * fractionAtWavelength(control, wavelength_nm);
        }

        const effective_optical_depth = ParticleProfiles.scaleOpticalDepth(
            effective_reference_optical_depth,
            reference_wavelength_nm,
            angstrom_exponent,
            wavelength_nm,
        );
        if (!control.enabled) return effective_optical_depth;

        const reference_fraction = control.valueAtWavelength(reference_wavelength_nm);
        if (reference_fraction <= 0.0) return 0.0;
        return effective_optical_depth * fractionAtWavelength(control, wavelength_nm) / reference_fraction;
    }

    pub fn opticalDepthBreakdownAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
    ) OpticalDepthBreakdown {
        if (self.sublayers) |sublayers| {
            var totals: OpticalDepthBreakdown = .{};
            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
                const evaluated = self.evaluateLayerAtWavelength(
                    null,
                    layer.altitude_km,
                    wavelength_nm,
                    start_index,
                    sublayers[start_index..end_index],
                    if (self.strong_line_states) |states| states[start_index..end_index] else null,
                );
                totals.gas_absorption_optical_depth += evaluated.breakdown.gas_absorption_optical_depth;
                totals.gas_scattering_optical_depth += evaluated.breakdown.gas_scattering_optical_depth;
                totals.cia_optical_depth += evaluated.breakdown.cia_optical_depth;
                totals.aerosol_optical_depth += evaluated.breakdown.aerosol_optical_depth;
                totals.aerosol_scattering_optical_depth += evaluated.breakdown.aerosol_scattering_optical_depth;
                totals.cloud_optical_depth += evaluated.breakdown.cloud_optical_depth;
                totals.cloud_scattering_optical_depth += evaluated.breakdown.cloud_scattering_optical_depth;
            }
            return totals;
        }

        const gas_absorption_optical_depth =
            self.totalCrossSectionAtWavelength(wavelength_nm) * self.column_density_factor;
        const gas_scattering_optical_depth = Rayleigh.crossSectionCm2(wavelength_nm) *
            self.air_column_density_factor;
        const cia_optical_depth = if (self.operational_o2o2_lut.enabled())
            self.operational_o2o2_lut.sigmaAt(
                wavelength_nm,
                self.effective_temperature_k,
                self.effective_pressure_hpa,
            ) * self.cia_pair_path_factor_cm5
        else if (self.collision_induced_absorption) |cia_table|
            cia_table.sigmaAt(wavelength_nm, self.effective_temperature_k) * self.cia_pair_path_factor_cm5
        else
            0.0;
        const aerosol_optical_depth = particleOpticalDepthAtWavelength(
            self.aerosol_optical_depth,
            self.aerosol_base_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const cloud_optical_depth = particleOpticalDepthAtWavelength(
            self.cloud_optical_depth,
            self.cloud_base_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            self.cloud_fraction_control,
            wavelength_nm,
        );
        const particle_single_scatter_albedos = self.resolvedParticleSingleScatterAlbedos();
        return .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_optical_depth * particle_single_scatter_albedos.aerosol,
            .cloud_optical_depth = cloud_optical_depth,
            .cloud_scattering_optical_depth = cloud_optical_depth * particle_single_scatter_albedos.cloud,
        };
    }

    pub fn evaluateLayerAtWavelength(
        self: *const PreparedOpticalState,
        scene: ?*const Scene,
        altitude_km: f64,
        wavelength_nm: f64,
        sublayer_start_index: usize,
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
    ) EvaluatedLayer {
        var breakdown: OpticalDepthBreakdown = .{};
        var phase_numerator = [_]f64{0.0} ** phase_coefficient_count;
        const gas_phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
        const continuum_table: ReferenceData.CrossSectionTable = .{ .points = self.continuum_points };

        for (sublayers, 0..) |sublayer, sublayer_index| {
            const global_sublayer_index = sublayer_start_index + sublayer_index;
            const continuum_sigma = if (self.cross_section_absorbers.len == 0)
                continuum_table.interpolateSigma(wavelength_nm)
            else
                0.0;
            const gas_absorption_optical_depth = blk: {
                const continuum_density_cm3 = if (self.cross_section_absorbers.len == 0)
                    self.continuumCarrierDensityAtSublayer(
                        sublayer,
                        global_sublayer_index,
                    )
                else
                    0.0;
                const continuum_optical_depth =
                    continuum_sigma *
                    continuum_density_cm3 *
                    sublayer.path_length_cm;
                var cross_section_optical_depth: f64 = 0.0;
                for (self.cross_section_absorbers) |cross_section_absorber| {
                    if (global_sublayer_index >= cross_section_absorber.number_densities_cm3.len) continue;
                    const absorber_density_cm3 = cross_section_absorber.number_densities_cm3[global_sublayer_index];
                    if (absorber_density_cm3 <= 0.0) continue;
                    cross_section_optical_depth += cross_section_absorber.sigmaAt(
                        wavelength_nm,
                        sublayer.temperature_k,
                        sublayer.pressure_hpa,
                    ) * absorber_density_cm3 * sublayer.path_length_cm;
                }
                if (self.line_absorbers.len != 0) {
                    var line_optical_depth: f64 = 0.0;
                    for (self.line_absorbers) |line_absorber| {
                        if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
                        const absorber_density_cm3 = line_absorber.number_densities_cm3[global_sublayer_index];
                        if (absorber_density_cm3 <= 0.0) continue;
                        const sigma = line_absorber.line_list.sigmaAtPrepared(
                            wavelength_nm,
                            sublayer.temperature_k,
                            sublayer.pressure_hpa,
                            if (line_absorber.strong_line_states) |states|
                                &states[global_sublayer_index]
                            else
                                null,
                        );
                        line_optical_depth += sigma * absorber_density_cm3 * sublayer.path_length_cm;
                    }
                    if (self.operational_o2_lut.enabled() and sublayer.oxygen_number_density_cm3 > 0.0) {
                        line_optical_depth +=
                            self.operational_o2_lut.sigmaAt(
                                wavelength_nm,
                                sublayer.temperature_k,
                                sublayer.pressure_hpa,
                            ) *
                            sublayer.oxygen_number_density_cm3 *
                            sublayer.path_length_cm;
                    }
                    break :blk continuum_optical_depth + cross_section_optical_depth + line_optical_depth;
                }

                const spectroscopy_sigma = self.spectroscopySigmaAtWavelength(
                    wavelength_nm,
                    sublayer.temperature_k,
                    sublayer.pressure_hpa,
                    if (strong_line_states) |states| &states[sublayer_index] else null,
                );
                const spectroscopy_carrier_density_cm3 = self.lineSpectroscopyCarrierDensityAtSublayer(
                    sublayer,
                    global_sublayer_index,
                );
                const gas_column_density_cm2 = spectroscopy_carrier_density_cm3 * sublayer.path_length_cm;
                break :blk continuum_optical_depth + cross_section_optical_depth + spectroscopy_sigma * gas_column_density_cm2;
            };
            const gas_scattering_optical_depth =
                Rayleigh.crossSectionCm2(wavelength_nm) *
                sublayer.number_density_cm3 *
                sublayer.path_length_cm;
            const cia_sigma_cm5_per_molecule2 = self.ciaSigmaAtWavelength(
                wavelength_nm,
                sublayer.temperature_k,
                sublayer.pressure_hpa,
            );
            const cia_optical_depth =
                cia_sigma_cm5_per_molecule2 *
                sublayer.oxygen_number_density_cm3 *
                sublayer.oxygen_number_density_cm3 *
                sublayer.path_length_cm;
            const aerosol_optical_depth = particleOpticalDepthAtWavelength(
                sublayer.aerosol_optical_depth,
                sublayer.aerosol_base_optical_depth,
                self.aerosol_reference_wavelength_nm,
                self.aerosol_angstrom_exponent,
                self.aerosol_fraction_control,
                wavelength_nm,
            );
            const cloud_optical_depth = particleOpticalDepthAtWavelength(
                sublayer.cloud_optical_depth,
                sublayer.cloud_base_optical_depth,
                self.cloud_reference_wavelength_nm,
                self.cloud_angstrom_exponent,
                self.cloud_fraction_control,
                wavelength_nm,
            );
            const aerosol_scattering_optical_depth = aerosol_optical_depth * sublayer.aerosol_single_scatter_albedo;
            const cloud_scattering_optical_depth = cloud_optical_depth * sublayer.cloud_single_scatter_albedo;

            breakdown.gas_absorption_optical_depth += gas_absorption_optical_depth;
            breakdown.gas_scattering_optical_depth += gas_scattering_optical_depth;
            breakdown.cia_optical_depth += cia_optical_depth;
            breakdown.aerosol_optical_depth += aerosol_optical_depth;
            breakdown.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
            breakdown.cloud_optical_depth += cloud_optical_depth;
            breakdown.cloud_scattering_optical_depth += cloud_scattering_optical_depth;

            for (0..phase_coefficient_count) |index| {
                phase_numerator[index] +=
                    gas_scattering_optical_depth * gas_phase_coefficients[index] +
                    aerosol_scattering_optical_depth * sublayer.aerosol_phase_coefficients[index] +
                    cloud_scattering_optical_depth * sublayer.cloud_phase_coefficients[index];
            }
        }

        const total_scattering = breakdown.totalScatteringOpticalDepth();
        var phase_coefficients = PhaseFunctions.gasPhaseCoefficients();
        if (total_scattering > 0.0) {
            for (0..phase_coefficient_count) |index| {
                phase_coefficients[index] = phase_numerator[index] / total_scattering;
            }
            phase_coefficients[0] = 1.0;
        }

        return .{
            .breakdown = breakdown,
            .phase_coefficients = phase_coefficients,
            .solar_mu = if (scene) |owned_scene| owned_scene.geometry.solarCosineAtAltitude(altitude_km) else 1.0,
            .view_mu = if (scene) |owned_scene| owned_scene.geometry.viewingCosineAtAltitude(altitude_km) else 1.0,
        };
    }

    fn spectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        if (self.line_absorbers.len != 0) {
            return self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
        }
        if (self.operational_o2_lut.enabled()) {
            return OperationalO2.operationalO2EvaluationAtWavelength(
                self.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
        }
        if (self.spectroscopy_lines) |line_list| {
            return line_list.evaluateAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        return .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };
    }

    pub fn spectroscopySigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        prepared_state: ?*const ReferenceData.StrongLinePreparedState,
    ) f64 {
        if (self.line_absorbers.len != 0) {
            return self.weightedSpectroscopyEvaluationAtWavelength(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            ).total_sigma_cm2_per_molecule;
        }
        if (self.operational_o2_lut.enabled()) {
            return self.operational_o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.spectroscopy_lines) |line_list| {
            return line_list.sigmaAtPrepared(wavelength_nm, temperature_k, pressure_hpa, prepared_state);
        }
        return 0.0;
    }

    /// Purpose:
    ///   Select the nearest prepared strong-line sidecar for an altitude sample.
    ///
    /// Physics:
    ///   Strong-line sidecars are prepared per sublayer and then reused by
    ///   interpolation-heavy transport paths that need a stable prepared state
    ///   representative for a specific altitude.
    ///
    /// Vendor:
    ///   `prepared strong-line state selection`
    ///
    /// Inputs:
    ///   `sublayers` and `strong_line_states` must describe the same prepared
    ///   vertical grid when sidecars are present.
    ///
    /// Outputs:
    ///   Returns the closest prepared strong-line state for `altitude_km`, or
    ///   `null` when no aligned sidecars exist.
    ///
    /// Assumptions:
    ///   `strong_line_states` must be aligned with `sublayers` when present.
    ///
    /// Validation:
    ///   Exercised by the optics-preparation transport tests that sample strong-
    ///   line prepared states at quadrature and pseudo-spherical altitudes.
    pub fn preparedStrongLineStateAtAltitude(
        sublayers: []const PreparedSublayer,
        strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
        altitude_km: f64,
    ) ?*const ReferenceData.StrongLinePreparedState {
        const states = strong_line_states orelse return null;
        if (states.len == 0 or states.len != sublayers.len) return null;
        if (states.len == 1) return &states[0];

        if (altitude_km <= sublayers[0].altitude_km) return &states[0];
        if (altitude_km >= sublayers[sublayers.len - 1].altitude_km) return &states[states.len - 1];

        for (sublayers[0 .. sublayers.len - 1], sublayers[1..], 0..) |left, right, index| {
            if (altitude_km > right.altitude_km) continue;
            const left_distance = @abs(altitude_km - left.altitude_km);
            const right_distance = @abs(right.altitude_km - altitude_km);
            return if (left_distance <= right_distance) &states[index] else &states[index + 1];
        }

        return &states[states.len - 1];
    }

    fn weightedSpectroscopyEvaluationAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        var total_weight: f64 = 0.0;
        var weighted: ReferenceData.SpectroscopyEvaluation = .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };

        if (self.operational_o2_lut.enabled() and self.oxygen_column_density_factor > 0.0) {
            const o2_evaluation = OperationalO2.operationalO2EvaluationAtWavelength(
                self.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
            total_weight += self.oxygen_column_density_factor;
            weighted.weak_line_sigma_cm2_per_molecule +=
                o2_evaluation.weak_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.strong_line_sigma_cm2_per_molecule +=
                o2_evaluation.strong_line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.line_sigma_cm2_per_molecule +=
                o2_evaluation.line_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.line_mixing_sigma_cm2_per_molecule +=
                o2_evaluation.line_mixing_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.total_sigma_cm2_per_molecule +=
                o2_evaluation.total_sigma_cm2_per_molecule * self.oxygen_column_density_factor;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * self.oxygen_column_density_factor;
        }

        for (self.line_absorbers) |line_absorber| {
            if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = if (line_absorber.column_density_factor > 0.0)
                line_absorber.column_density_factor
            else
                1.0;
            const evaluation = line_absorber.line_list.evaluateAt(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
            total_weight += weight;
            weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
            weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
            weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
            weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
            weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
        }

        if (total_weight <= 0.0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
        weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
        weighted.total_sigma_cm2_per_molecule /= total_weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
        return weighted;
    }

    pub fn weightedSpectroscopyEvaluationAtAltitude(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
        sublayers: []const PreparedSublayer,
        altitude_km: f64,
        oxygen_density_cm3: f64,
    ) ReferenceData.SpectroscopyEvaluation {
        var total_weight: f64 = 0.0;
        var weighted: ReferenceData.SpectroscopyEvaluation = .{
            .weak_line_sigma_cm2_per_molecule = 0.0,
            .strong_line_sigma_cm2_per_molecule = 0.0,
            .line_sigma_cm2_per_molecule = 0.0,
            .line_mixing_sigma_cm2_per_molecule = 0.0,
            .total_sigma_cm2_per_molecule = 0.0,
            .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
        };

        if (self.operational_o2_lut.enabled() and oxygen_density_cm3 > 0.0) {
            const o2_evaluation = OperationalO2.operationalO2EvaluationAtWavelength(
                self.operational_o2_lut,
                wavelength_nm,
                temperature_k,
                pressure_hpa,
            );
            total_weight += oxygen_density_cm3;
            weighted.weak_line_sigma_cm2_per_molecule += o2_evaluation.weak_line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.strong_line_sigma_cm2_per_molecule += o2_evaluation.strong_line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.line_sigma_cm2_per_molecule += o2_evaluation.line_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.line_mixing_sigma_cm2_per_molecule += o2_evaluation.line_mixing_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.total_sigma_cm2_per_molecule += o2_evaluation.total_sigma_cm2_per_molecule * oxygen_density_cm3;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                o2_evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * oxygen_density_cm3;
        }

        for (self.line_absorbers) |line_absorber| {
            if (self.operational_o2_lut.enabled() and line_absorber.species == .o2) continue;
            const weight = interpolatePreparedScalarAtAltitude(
                sublayers,
                line_absorber.number_densities_cm3,
                altitude_km,
            );
            if (weight <= 0.0) continue;

            const evaluation = line_absorber.line_list.evaluateAtPrepared(
                wavelength_nm,
                temperature_k,
                pressure_hpa,
                preparedStrongLineStateAtAltitude(
                    sublayers,
                    line_absorber.strong_line_states,
                    altitude_km,
                ),
            );
            total_weight += weight;
            weighted.weak_line_sigma_cm2_per_molecule += evaluation.weak_line_sigma_cm2_per_molecule * weight;
            weighted.strong_line_sigma_cm2_per_molecule += evaluation.strong_line_sigma_cm2_per_molecule * weight;
            weighted.line_sigma_cm2_per_molecule += evaluation.line_sigma_cm2_per_molecule * weight;
            weighted.line_mixing_sigma_cm2_per_molecule += evaluation.line_mixing_sigma_cm2_per_molecule * weight;
            weighted.total_sigma_cm2_per_molecule += evaluation.total_sigma_cm2_per_molecule * weight;
            weighted.d_sigma_d_temperature_cm2_per_molecule_per_k +=
                evaluation.d_sigma_d_temperature_cm2_per_molecule_per_k * weight;
        }

        if (total_weight <= 0.0) {
            return .{
                .weak_line_sigma_cm2_per_molecule = 0.0,
                .strong_line_sigma_cm2_per_molecule = 0.0,
                .line_sigma_cm2_per_molecule = 0.0,
                .line_mixing_sigma_cm2_per_molecule = 0.0,
                .total_sigma_cm2_per_molecule = 0.0,
                .d_sigma_d_temperature_cm2_per_molecule_per_k = 0.0,
            };
        }

        weighted.weak_line_sigma_cm2_per_molecule /= total_weight;
        weighted.strong_line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_sigma_cm2_per_molecule /= total_weight;
        weighted.line_mixing_sigma_cm2_per_molecule /= total_weight;
        weighted.total_sigma_cm2_per_molecule /= total_weight;
        weighted.d_sigma_d_temperature_cm2_per_molecule_per_k /= total_weight;
        return weighted;
    }

    pub fn ciaSigmaAtWavelength(
        self: *const PreparedOpticalState,
        wavelength_nm: f64,
        temperature_k: f64,
        pressure_hpa: f64,
    ) f64 {
        if (self.operational_o2o2_lut.enabled()) {
            return self.operational_o2o2_lut.sigmaAt(wavelength_nm, temperature_k, pressure_hpa);
        }
        if (self.collision_induced_absorption) |cia_table| {
            return cia_table.sigmaAt(wavelength_nm, temperature_k);
        }
        return 0.0;
    }
};

test "PreparedOpticalState preserves legacy transport-facing methods" {
    try std.testing.expect(@hasDecl(PreparedOpticalState, "toForwardInput"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "toForwardInputWithLayers"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "toForwardInputAtWavelength"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "toForwardInputAtWavelengthWithLayers"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "fillForwardLayersAtWavelength"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "fillSourceInterfacesAtWavelengthWithLayers"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "fillRtmQuadratureAtWavelengthWithLayers"));
    try std.testing.expect(@hasDecl(PreparedOpticalState, "fillPseudoSphericalGridAtWavelength"));
}
