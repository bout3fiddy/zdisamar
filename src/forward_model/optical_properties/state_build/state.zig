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

// state.zig --------------------------------------------------------------------------------------------------|
// Compiler-measured row definitions for optical-property preparation, RTM setup, and diagnostics.             |
// prepared_state.zig owns the final PreparedOpticalState header; this file owns the repeated row payload      |
// shapes that are filled during setup and read many times during wavelength evaluation.                       |
//                                                                                                             |
// build route                                                                                                 |
//   Context owns mutable preparation arrays while Scene controls are reduced.                                 |
//   Absorbers build active absorber rows and density columns.                                                 |
//   layer_accumulation writes PreparedLayer and PreparedSublayer rows.                                        |
//   finalize moves those rows into PreparedOpticalState, which is defined in prepared_state.zig.              |
//   forward_layers, rtm_quadrature, shared_carrier, diagnostics, and retrieval read these rows for each       |
//   wavelength.                                                                                               |
//                                                                                                             |
// row groups                                                                                                  |
//   Active* rows     : scene absorber controls after input validation, before prepared density columns exist  |
//   Prepared* rows   : retained line/cross-section, layer, sublayer, and LUT rows after preparation           |
//   wavelength rows  : OpticalDepthBreakdown and EvaluatedLayer, short-lived results for one wavelength       |
//   SharedRtm* rows  : cached geometry used only by reduced shared-RTM interval routes                        |
//                                                                                                             |
// layout policy                                                                                               |
//   The boxes below show compiler-measured storage order, not source order. PreparedOpticalState owns only    |
//   slice headers and ownership flags for most of these rows; the row comments here document the payload      |
//   bytes that dominate repeated loops. Keep layout notes beside the row definitions so they change with the  |
//   field list, and keep owner/deinit notes in prepared_state.zig where the slices are released.              |
//                                                                                                             |
// hot rows                                                                                                    |
//   PreparedLayer and PreparedSublayer are intentionally row-shaped even when some loops read only support    |
//   indexes. Nearby RTM and carrier builders read thermodynamics, aerosol fields, optical depths, and support |
//   spans from the same arrays; splitting columns needs benchmark evidence because it adds ownership surface. |
// ------------------------------------------------------------------------------------------------------------|

// ActiveLineAbsorber -----------------------------------------------------------------------------------------|
// Active line absorber resolved from the scene's absorber set.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 160 B (0.156 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..135] controls                         : LineGasControls                                               |
// [136..151] volume_mixing_ratio_profile_ppmv : []const [2]f64                                                |
// [152..152] species                          : AbsorberSpecies                                               |
// [153..159] padding                          : 7 B                                                           |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 160 B; VMR profile storage is borrowed                                            |
pub const ActiveLineAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    controls: AbsorberModel.LineGasControls,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// ActiveCrossSectionAbsorber ---------------------------------------------------------------------------------|
// Active cross-section absorber resolved from the scene's absorber set.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] representation                   : AbsorptionRepresentation                                        |
// [16..31] volume_mixing_ratio_profile_ppmv : []const [2]f64                                                  |
// [32..32] species                          : AbsorberSpecies                                                 |
// [33..39] padding                          : 7 B                                                             |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// footprint: per instance = 40 B; VMR profile storage is borrowed                                             |
pub const ActiveCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
    representation: AbsorberModel.AbsorptionRepresentation,
    volume_mixing_ratio_profile_ppmv: []const [2]f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// PreparedLineAbsorber ---------------------------------------------------------------------------------------|
// Prepared line absorber retained after setup. The row keeps the line-list handle, one density column,        |
// optional prepared strong-line states, and the species tag that ties continuum ownership back to this row.   |
//                                                                                                             |
// row use                                                                                                     |
//   absorbers.zig builds and owns these rows until finalize moves them into PreparedOpticalState.             |
//   state_spectroscopy.zig and carrier_eval.zig read line_list, densities, and prepared strong-line states    |
//   during wavelength evaluation. spectroscopy.zig reads only species when choosing the continuum owner.      |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 280 B (0.273 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..207] line_list                     : SpectroscopyLineList                                             |
// [208..223] number_densities_cm3          : []f64                                                            |
// [224..239] strong_line_states            : ?[]StrongLinePreparedState                                       |
// [240..255] strong_line_state_initialized : ?[]bool                                                          |
// [256..263] strong_line_state_count       : usize                                                            |
// [264..271] column_density_factor         : f64                                                              |
// [272..272] species                       : AbsorberSpecies                                                  |
// [273..279] padding                       : 7 B                                                              |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 5 cache lines at 64 B per line                                                                  |
// footprint: per instance = 280 B; line list, densities, and optional line states own out-of-line storage     |
// hot reads: setup-only owner scan reads species at [272..272]; wavelength loops read the larger payload      |
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
            self.deinitStrongLineStates(allocator, states);
            allocator.free(states);
        }

        self.* = undefined;
    }

    fn deinitStrongLineStates(
        self: *PreparedLineAbsorber,
        allocator: Allocator,
        states: []ReferenceData.StrongLinePreparedState,
    ) void {
        if (self.strong_line_state_initialized) |initialized| {
            for (states, initialized) |*state, is_initialized| {
                if (!is_initialized) continue;
                state.deinit(allocator);
            }

            allocator.free(initialized);
        } else {
            for (states[0..self.strong_line_state_count]) |*state| state.deinit(allocator);
        }
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub const PreparedCrossSectionRepresentation = union(enum) {
    table: ReferenceData.CrossSectionTable,
    lut: OperationalCrossSectionLut,
};

// PreparedCrossSectionAbsorber -------------------------------------------------------------------------------|
// Prepared cross-section absorber with stored densities and typed representation metadata.                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 79] representation        : PreparedCrossSectionRepresentation                                       |
// [ 80.. 95] number_densities_cm3  : []f64                                                                    |
// [ 96..103] column_density_factor : f64                                                                      |
// [104..104] species               : AbsorberSpecies                                                          |
// [105..111] padding               : 7 B                                                                      |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 112 B; density and table/LUT storage can be out of line                           |
pub const PreparedCrossSectionAbsorber = struct {
    species: AbsorberModel.AbsorberSpecies,
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
// ------------------------------------------------------------------------------------------------------------|

// PreparedLayer ----------------------------------------------------------------------------------------------|
// Prepared layer state on the transport grid. One row keeps the physical layer values plus the indexes        |
// that connect the row back to its prepared support rows.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] aerosol_optical_depth                         : f64                                              |
// [  8.. 15] bottom_altitude_km                             : f64                                             |
// [ 16.. 23] aerosol_fraction                               : f64                                             |
// [ 24.. 31] altitude_km                                    : f64                                             |
// [ 32.. 39] bottom_pressure_hpa                            : f64                                             |
// [ 40.. 47] temperature_k                                  : f64                                             |
// [ 48.. 55] number_density_cm3                             : f64                                             |
// [ 56.. 63] continuum_cross_section_cm2_per_molecule       : f64                                             |
// [ 64.. 71] line_cross_section_cm2_per_molecule            : f64                                             |
// [ 72.. 79] line_mixing_cross_section_cm2_per_molecule     : f64                                             |
// [ 80.. 87] cia_optical_depth                              : f64                                             |
// [ 88.. 95] d_cross_section_d_temperature_cm2_per_molecule_per_k : f64                                       |
// [ 96..103] top_pressure_hpa                               : f64                                             |
// [104..111] gas_optical_depth                              : f64                                             |
// [112..119] pressure_hpa                                   : f64                                             |
// [120..127] aerosol_base_optical_depth                     : f64                                             |
// [128..135] aerosol_single_scatter_albedo                  : f64                                             |
// [136..143] aerosol_reference_wavelength_nm                : f64                                             |
// [144..151] aerosol_angstrom_exponent                      : f64                                             |
// [152..159] layer_single_scatter_albedo                    : f64                                             |
// [160..167] depolarization_factor                          : f64                                             |
// [168..175] optical_depth                                  : f64                                             |
// [176..183] top_altitude_km                                : f64                                             |
// [184..191] gas_scattering_optical_depth                   : f64                                             |
// [192..195] sublayer_start_index                           : u32                                             |
// [196..199] layer_index                                    : u32                                             |
// [200..203] interval_index_1based                          : u32                                             |
// [204..207] sublayer_count                                 : u32                                             |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 208 B (0.203 KiB); total = per instance * live instance count                     |
//                                                                                                             |
// support-index tail                                                                                          |
// [192..207] stores {sublayer_start_index, layer_index, interval_index_1based, sublayer_count}. Shape checks  |
// and reduced shared-RTM routing read this tail even when they do not need the physical f64 fields.           |
//                                                                                                             |
// hot path                                                                                                    |
// Index-only loops read the four u32 support fields at the end of this 208 B row. The row stays whole         |
// because forward-layer, RTM quadrature, and optical-depth paths consume the same layer array's physical      |
// fields nearby. Split columns would need a measured repeated-boundary win before they are worth the extra    |
// ownership and call-surface complexity.                                                                      |
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
    aerosol_single_scatter_albedo: f64 = 0.0,
    aerosol_reference_wavelength_nm: f64 = 550.0,
    aerosol_angstrom_exponent: f64 = 0.0,
    layer_single_scatter_albedo: f64,
    depolarization_factor: f64,
    optical_depth: f64,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    aerosol_fraction: f64 = 0.0,
};
// ----------------------------------------------------------------------------------------------------------- |

pub const PreparedSupportRowKind = enum {
    physical,
    parity_boundary,
    parity_active,
};

// PreparedSublayer ------------------------------------------------------------------------------------------ |
// Prepared support row on the fine optical-property grid. Layer reduction code can collapse many rows         |
// into one transport layer while still preserving DISAMAR support-row placement.                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 256 B (0.250 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..  7] d_cross_section_d_temperature_cm2_per_molecule_per_k : f64                                       |
// [  8.. 15] gas_absorption_optical_depth                  : f64                                              |
// [ 16.. 23] aerosol_fraction                              : f64                                              |
// [ 24.. 31] altitude_km                                   : f64                                              |
// [ 32.. 39] pressure_hpa                                  : f64                                              |
// [ 40.. 47] temperature_k                                 : f64                                              |
// [ 48.. 55] number_density_cm3                            : f64                                              |
// [ 56.. 63] oxygen_number_density_cm3                     : f64                                              |
// [ 64.. 71] cia_pair_density_cm6                          : f64                                              |
// [ 72.. 79] absorber_number_density_cm3                   : f64                                              |
// [ 80.. 87] gas_scattering_optical_depth                  : f64                                              |
// [ 88.. 95] continuum_cross_section_cm2_per_molecule      : f64                                              |
// [ 96..103] line_cross_section_cm2_per_molecule           : f64                                              |
// [104..111] line_mixing_cross_section_cm2_per_molecule    : f64                                              |
// [112..119] cia_sigma_cm5_per_molecule2                   : f64                                              |
// [120..127] cia_optical_depth                             : f64                                              |
// [128..135] bottom_pressure_hpa                           : f64                                              |
// [136..143] top_pressure_hpa                              : f64                                              |
// [144..151] path_length_cm                                : f64                                              |
// [152..159] gas_extinction_optical_depth                  : f64                                              |
// [160..167] d_gas_optical_depth_d_temperature             : f64                                              |
// [168..175] d_cia_optical_depth_d_temperature             : f64                                              |
// [176..183] aerosol_optical_depth                         : f64                                              |
// [184..191] aerosol_base_optical_depth                    : f64                                              |
// [192..199] aerosol_single_scatter_albedo                 : f64                                              |
// [200..207] aerosol_reference_wavelength_nm               : f64                                              |
// [208..215] aerosol_angstrom_exponent                     : f64                                              |
// [216..223] top_altitude_km                               : f64                                              |
// [224..231] bottom_altitude_km                            : f64                                              |
// [232..235] parent_layer_index                            : u32                                              |
// [236..239] sublayer_index                                : u32                                              |
// [240..243] interval_index_1based                         : u32                                              |
// [244..247] global_sublayer_index                         : u32                                              |
// [248..248] support_row_kind                              : PreparedSupportRowKind                           |
// [249..255] padding                                       : 7 B                                              |
//                                                                                                             |
// unused bits: 56 padding + 7 enum-storage slack = 63 bits                                                    |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 256 B (0.250 KiB); total = per instance * live instance count                     |
//                                                                                                             |
// hot path                                                                                                    |
// Shared-carrier and reduced RTM routes read thermodynamics, optical depths, aerosol fields, and density      |
// indexes from the same support row. The row is wide, but each pass usually needs several neighboring         |
// physical fields; splitting only one or two columns would add ownership and stitching costs.                 |
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
    aerosol_single_scatter_albedo: f64,
    aerosol_reference_wavelength_nm: f64 = 550.0,
    aerosol_angstrom_exponent: f64 = 0.0,
    top_altitude_km: f64 = 0.0,
    bottom_altitude_km: f64 = 0.0,
    top_pressure_hpa: f64 = 0.0,
    bottom_pressure_hpa: f64 = 0.0,
    interval_index_1based: u32 = 0,
    aerosol_fraction: f64 = 0.0,
    support_row_kind: PreparedSupportRowKind = .physical,

    pub fn ciaPairDensityCm6(self: PreparedSublayer) f64 {
        return if (self.cia_pair_density_cm6 > 0.0)
            self.cia_pair_density_cm6
        else
            self.oxygen_number_density_cm3 * self.oxygen_number_density_cm3;
    }
};
// ----------------------------------------------------------------------------------------------------------- |

// OpticalDepthBreakdown --------------------------------------------------------------------------------------|
// Wavelength-local optical-depth components used to build transport rows.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] gas_absorption_optical_depth     : f64                                                             |
// [ 8..15] gas_scattering_optical_depth     : f64                                                             |
// [16..23] cia_optical_depth                : f64                                                             |
// [24..31] aerosol_optical_depth            : f64                                                             |
// [32..39] aerosol_scattering_optical_depth : f64                                                             |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B; stack or caller-owned row                                                   |
pub const OpticalDepthBreakdown = struct {
    gas_absorption_optical_depth: f64 = 0.0,
    gas_scattering_optical_depth: f64 = 0.0,
    cia_optical_depth: f64 = 0.0,
    aerosol_optical_depth: f64 = 0.0,
    aerosol_scattering_optical_depth: f64 = 0.0,

    pub fn totalScatteringOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_scattering_optical_depth +
            self.aerosol_scattering_optical_depth;
    }

    pub fn totalOpticalDepth(self: OpticalDepthBreakdown) f64 {
        return self.gas_absorption_optical_depth +
            self.gas_scattering_optical_depth +
            self.cia_optical_depth +
            self.aerosol_optical_depth;
    }

    pub fn singleScatterAlbedo(self: OpticalDepthBreakdown) f64 {
        const total_optical_depth = self.totalOpticalDepth();
        if (total_optical_depth <= 0.0) return 0.0;

        // math: omega0 = tau_sca / tau_ext, clamped to physical [0, 1].
        return std.math.clamp(
            self.totalScatteringOpticalDepth() / total_optical_depth,
            0.0,
            1.0,
        );
    }
};
// ------------------------------------------------------------------------------------------------------------|

// EvaluatedLayer ---------------------------------------------------------------------------------------------|
// Optical-depth and phase result for one layer or shared support interval.                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..39] breakdown : OpticalDepthBreakdown                                                                  |
// [40..63] phase     : PhaseMixture                                                                           |
// [64..71] solar_mu  : f64                                                                                    |
// [72..79] view_mu   : f64                                                                                    |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B; phase can reference shared phase storage                                    |
pub const EvaluatedLayer = struct {
    breakdown: OpticalDepthBreakdown = .{},
    phase: PhaseFunctions.PhaseMixture = .{},
    solar_mu: f64 = 1.0,
    view_mu: f64 = 1.0,
};
// ------------------------------------------------------------------------------------------------------------|

// SharedRtmLayerGeometry -------------------------------------------------------------------------------------|
// Cached altitude and support-span geometry for one shared RTM layer.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] lower_altitude_km  : f64                                                                           |
// [ 8..15] upper_altitude_km  : f64                                                                           |
// [16..23] midpoint_altitude_km : f64                                                                         |
// [24..31] thickness_km       : f64                                                                           |
// [32..35] support_start_index: u32                                                                           |
// [36..39] support_count      : u32                                                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 40 B; stored in SharedRtmGeometry.layers                                          |
pub const SharedRtmLayerGeometry = struct {
    lower_altitude_km: f64 = 0.0,
    upper_altitude_km: f64 = 0.0,
    midpoint_altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    support_start_index: u32 = 0,
    support_count: u32 = 0,
};
// ------------------------------------------------------------------------------------------------------------|

// SharedRtmLevelGeometry -------------------------------------------------------------------------------------|
// Cached level altitude, quadrature weight, and support-row references for shared RTM source terms.           |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 40 B (0.039 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km                      : f64                                                             |
// [ 8..15] weight_km                        : f64                                                             |
// [16..19] support_start_index              : u32                                                             |
// [20..23] support_count                    : u32                                                             |
// [24..27] support_row_index                : u32                                                             |
// [28..31] particle_above_support_row_index : u32                                                             |
// [32..35] particle_below_support_row_index : u32                                                             |
// [36..39] padding                          : 4 B                                                             |
//                                                                                                             |
// unused bits: 32 padding + 0 bool-storage slack = 32 bits                                                    |
// footprint: per instance = 40 B; stored in SharedRtmGeometry.levels                                          |
pub const SharedRtmLevelGeometry = struct {
    altitude_km: f64 = 0.0,
    weight_km: f64 = 0.0,
    support_start_index: u32 = 0,
    support_count: u32 = 0,
    support_row_index: u32 = 0,
    particle_above_support_row_index: u32 = std.math.maxInt(u32),
    particle_below_support_row_index: u32 = std.math.maxInt(u32),
};
// ------------------------------------------------------------------------------------------------------------|

// SharedRtmGeometry ------------------------------------------------------------------------------------------|
// Owned cached geometry arrays for the shared RTM grid.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] layers : []SharedRtmLayerGeometry                                                                  |
// [16..31] levels : []SharedRtmLevelGeometry                                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B; layer and level arrays are out of line                                      |
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
// ------------------------------------------------------------------------------------------------------------|

pub const GeneratedLutAssetKind = enum {
    reflectance,
    correction,
    xsec,
};

// GeneratedLutAsset ------------------------------------------------------------------------------------------|
// Metadata and optional owned strings for generated LUT assets retained on PreparedOpticalState.              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 216 B (0.211 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] dataset_id       : []const u8                                                                    |
// [ 16.. 31] lut_id           : []const u8                                                                    |
// [ 32.. 47] provenance_label : []const u8                                                                    |
// [ 48.. 48] kind             : GeneratedLutAssetKind                                                         |
// [ 49.. 49] mode             : LutControls.Mode                                                              |
// [ 52.. 63] spectral/layer/coefficient counts: 3 x u32                                                       |
// [ 64..215] compatibility, owns_strings, and padding                                                         |
//                                                                                                             |
// unused bits: 8 padding + 7 bool-storage slack = 15 bits                                                     |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 216 B; optional strings are out of line                                           |
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
// ------------------------------------------------------------------------------------------------------------|

// PreparedStateFractions -------------------------------------------------------------------------------------|
// Fraction-control state copied into PreparedOpticalState for aerosol optical-depth evaluation.               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 88 B (0.086 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..79] aerosol_fraction_control : AtmosphereModel.FractionControl                                         |
// [80..80] aerosol_phase_support    : PhaseSupportKind                                                        |
// [81..87] padding                  : 7 B                                                                     |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 88 B; stack or caller-owned row                                                   |
pub const PreparedStateFractions = struct {
    aerosol_phase_support: PhaseSupportKind = .none,
    aerosol_fraction_control: AtmosphereModel.FractionControl = .{},
};
// ------------------------------------------------------------------------------------------------------------|

pub const PreparedOpticalState = @import("prepared_state.zig").PreparedOpticalState;
