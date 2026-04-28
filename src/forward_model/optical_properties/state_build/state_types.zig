const std = @import("std");
const AbsorberModel = @import("../../../input/Absorber.zig");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const OperationalCrossSectionLut = @import("../../../input/Instrument.zig").OperationalCrossSectionLut;
const LutControls = @import("../../../common/lut_controls.zig");
const PhaseSupportKind = @import("../../../input/reference/airmass_phase.zig").PhaseSupportKind;
const PhaseFunctions = @import("../shared/phase_functions.zig");

const Allocator = std.mem.Allocator;

pub const phase_coefficient_count = PhaseFunctions.phase_coefficient_count;

// Active line absorber resolved from the scene's absorber set.
pub const ActiveLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    controls: AbsorberModel.LineGasControls,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
};

// Active cross-section absorber resolved from the scene's absorber set.
pub const ActiveCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    representation: AbsorberModel.AbsorptionRepresentation,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
    use_effective_cross_section: bool = false,
    polynomial_order: u32 = 0,
};

// Prepared line absorber with runtime controls and stored number densities.
pub const PreparedLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    line_list: ReferenceData.SpectroscopyLineList,
    number_densities_cm3: []f64,
    strong_line_states: ?[]ReferenceData.StrongLinePreparedState = null,
    strong_line_state_initialized: ?[]bool = null,
    strong_line_state_count: usize = 0,
    column_density_factor: f64 = 0.0,

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

// Prepared cross-section absorber with stored densities and typed representation metadata.
pub const PreparedCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    representation_kind: CrossSectionRepresentationKind,
    polynomial_order: u32 = 0,
    representation: PreparedCrossSectionRepresentation,
    number_densities_cm3: []f64,
    column_density_factor: f64 = 0.0,

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

// Prepared layer state on the radiative transfer grid.
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

pub const PreparedSupportRowKind = enum {
    physical,
    parity_boundary,
    parity_active,
};

// Prepared sublayer state on the fine radiative transfer grid.
pub const PreparedSublayer = struct {
    parent_layer_index: u32,
    sublayer_index: u32,
    global_sublayer_index: u32 = 0,
    altitude_km: f64,
    pressure_hpa: f64,
    temperature_k: f64,
    number_density_cm3: f64,
    oxygen_number_density_cm3: f64,
    cia_pair_density_cm6: f64 = 0.0,
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
    support_row_kind: PreparedSupportRowKind = .physical,

    pub fn ciaPairDensityCm6(self: PreparedSublayer) f64 {
        return if (self.cia_pair_density_cm6 > 0.0)
            self.cia_pair_density_cm6
        else
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3;
    }
};

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

pub const EvaluatedLayer = struct {
    breakdown: OpticalDepthBreakdown = .{},
    phase_coefficients: [phase_coefficient_count]f64 = PhaseFunctions.gasPhaseCoefficients(),
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
};

pub const SharedRtmLayerGeometry = struct {
    lower_altitude_km: f64 = 0.0,
    upper_altitude_km: f64 = 0.0,
    midpoint_altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    support_start_index: u32 = 0,
    support_count: u32 = 0,
};

pub const SharedRtmLevelGeometry = struct {
    altitude_km: f64 = 0.0,
    weight_km: f64 = 0.0,
    support_start_index: u32 = 0,
    support_count: u32 = 0,
    support_row_index: u32 = 0,
    particle_above_support_row_index: u32 = std.math.maxInt(u32),
    particle_below_support_row_index: u32 = std.math.maxInt(u32),
};

pub const SharedRtmGeometry = struct {
    layers: []SharedRtmLayerGeometry = &.{},
    levels: []SharedRtmLevelGeometry = &.{},

    pub fn isValidFor(self: SharedRtmGeometry, layer_count: usize) bool {
        return self.layers.len == layer_count and self.levels.len == layer_count + 1;
    }

    pub fn deinit(self: *SharedRtmGeometry, allocator: Allocator) void {
        if (self.layers.len != 0) allocator.free(self.layers);
        if (self.levels.len != 0) allocator.free(self.levels);
        self.* = .{};
    }
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

pub const PreparedStateFractions = struct {
    aerosol_phase_support: PhaseSupportKind = .none,
    cloud_phase_support: PhaseSupportKind = .none,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
    cloud_fraction_control: AtmosphereModel.FractionControl = .{},
};
