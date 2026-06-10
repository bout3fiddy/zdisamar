const std = @import("std");
const AbsorberModel = @import("../../input/Absorber.zig");
const AerosolModel = @import("../../input/Aerosol.zig");
const AtmosphereModel = @import("../../input/Atmosphere.zig");
const InstrumentModel = @import("../../input/Instrument.zig");
const Instrument = InstrumentModel.Instrument;
const ObservationModel = @import("../../input/ObservationModel.zig");
const ReferenceDataModel = @import("../../input/ReferenceData.zig");
const Scene = @import("../../input/Scene.zig").Scene;
const SpectralGrid = @import("../../input/Spectrum.zig").SpectralGrid;
const transport_common = @import("../../forward_model/radiative_transfer/root.zig");

const Allocator = std.mem.Allocator;
const BuiltinLineShapeKind = InstrumentModel.BuiltinLineShapeKind;
pub const AbsorberSpecies = AbsorberModel.AbsorberSpecies;
pub const SolveConfig = transport_common.SolveConfig;
pub const RadiativeTransferPerformanceThresholds = transport_common.RadiativeTransferPerformanceThresholds;
pub const RadiativeTransferControls = transport_common.RadiativeTransferControls;

// types.zig ------------------------------------------------------------------------------------------------- |
// Parsed O2 A reference-case schema used before runtime preparation.                                          |
//                                                                                                             |
// call route                                                                                                  |
//   root.zig parses and validates these records from reference-case JSON. run.zig consumes them into loaded   |
//   reference assets, Scene, SolveConfig, and PreparedOpticalState. metrics.zig keeps validation wrappers     |
//   typed against the same row family.                                                                        |
//                                                                                                             |
// record groups                                                                                               |
//   Metadata and ExternalAsset identify fixed/reference files. GeometrySpec, AtmosphereSpec, AerosolSpec,     |
//   ObservationSpec, LineGasSpec, CiaSpec, and RadiativeTransferControls hold the model controls consumed     |
//   by run.zig. LoadedVendorO2AInputs is the post-load owner bundle reused by retrieval sessions.             |
//                                                                                                             |
// contract                                                                                                    |
//   These rows preserve vendor/reference inputs until run.zig can consume each control into                   |
//   Scene/PreparationInputs/SolveConfig or reject unsupported combinations.                                   |
//                                                                                                             |
// runtime shape                                                                                               |
//   These setup rows are consumed before wavelength-time work begins. Forward-model workers receive the       |
//   Scene, prepared optical rows, and solve controls produced from the reference-case records.                |
//                                                                                                             |
// memory                                                                                                      |
//   Small numeric/control rows stay inline. Asset ids, paths, intervals, profiles, measured wavelengths, and  |
//   spectra are slice headers over parser-owned storage until load/prepare functions duplicate or borrow them.|
//   LoadedVendorO2AInputs owns loaded profile, cross-section, line-list, CIA, LUT, reference, and solar rows. |
// ----------------------------------------------------------------------------------------------------------- |

// ReferenceSample ------------------------------------------------------------------------------------------- |
// Vendor reference spectrum row used for validation and metric comparisons.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm : f64                                                                                |
// [ 8..15] irradiance    : f64                                                                                |
// [16..23] reflectance   : f64                                                                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 24 B; total = per instance * reference sample count                               |
pub const ReferenceSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
    reflectance: f64,
};

// ExternalAsset --------------------------------------------------------------------------------------------- |
// Borrowed descriptor for a named reference-data asset.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] id     : []const u8                                                                                |
// [16..31] path   : []const u8                                                                                |
// [32..47] format : []const u8                                                                                |
//                                                                                                             |
// out-of-line                                                                                                 |
//   id, path, and format are borrowed string slice headers; string bytes are not included in this size.       |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B plus borrowed string storage                                                 |
pub const ExternalAsset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
};

// PlanSpec -------------------------------------------------------------------------------------------------- |
// Runtime plan controls selected from the reference case.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 1 B (0.001 KiB), align: 1 B                                                                           |
//                                                                                                             |
// memory                                                                                                      |
// [0..0] derivative_mode : DerivativeMode                                                                     |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 1 B                                                                               |
pub const PlanSpec = struct {
    derivative_mode: transport_common.DerivativeMode = .none,

    pub fn validate(self: PlanSpec) !void {
        _ = self.derivativeMode();
    }

    pub fn derivativeMode(self: PlanSpec) transport_common.DerivativeMode {
        return self.derivative_mode;
    }
};

// Metadata -------------------------------------------------------------------------------------------------- |
// Borrowed identifiers that describe one resolved vendor case.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] id          : []const u8                                                                           |
// [16..31] storage     : []const u8                                                                           |
// [32..47] description : []const u8                                                                           |
//                                                                                                             |
// out-of-line                                                                                                 |
//   id, storage, and description are borrowed string slice headers.                                           |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 48 B plus borrowed string storage                                                 |
pub const Metadata = struct {
    id: []const u8,
    storage: []const u8,
    description: []const u8,
};

// GeometrySpec ---------------------------------------------------------------------------------------------- |
// Viewing and solar geometry for one O2 A case.                                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_zenith_deg    : f64                                                                          |
// [ 8..15] viewing_zenith_deg  : f64                                                                          |
// [16..23] relative_azimuth_deg: f64                                                                          |
// [24..24] model               : Geometry.Model                                                               |
// [25..31] trailing padding    : 7 B                                                                          |
//                                                                                                             |
// unused bits: 56 padding + 0 bool-storage slack = 56 bits                                                    |
// footprint: per instance = 32 B                                                                              |
pub const GeometrySpec = struct {
    model: @TypeOf(@as(Scene, .{}).geometry.model),
    solar_zenith_deg: f64,
    viewing_zenith_deg: f64,
    relative_azimuth_deg: f64,
};

// AerosolSpec ----------------------------------------------------------------------------------------------- |
// Aerosol optical controls plus optional profile placement data.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] optical_depth          : f64                                                                       |
// [ 8..15] single_scatter_albedo  : f64                                                                       |
// [16..23] asymmetry_factor       : f64                                                                       |
// [24..31] angstrom_exponent      : f64                                                                       |
// [32..39] reference_wavelength_nm: f64                                                                       |
// [40..79] placement              : IntervalPlacement                                                         |
// [80..95] profile                : []const ProfileLayer                                                      |
//                                                                                                             |
// out-of-line                                                                                                 |
//   profile is a borrowed slice header; profile-layer storage is not included in this size.                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 96 B plus borrowed profile storage                                                |
pub const AerosolSpec = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    placement: AtmosphereModel.IntervalPlacement,
    profile: []const AerosolModel.ProfileLayer = &.{},
};

// ObservationSpec ------------------------------------------------------------------------------------------- |
// Instrument sampling and reference-grid controls for the validation observation.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] instrument_name             : []const u8                                                           |
// [16..23] instrument_line_fwhm_nm     : f64                                                                  |
// [24..31] high_resolution_step_nm     : f64                                                                  |
// [32..39] high_resolution_half_span_nm: f64                                                                  |
// [40..55] solar_reference_asset_id    : []const u8                                                           |
// [56..71] measured_wavelengths_nm     : []const f64                                                          |
// [72..77] adaptive_reference_grid     : AdaptiveReferenceGrid                                                |
// [78..77] regime                      : zero-size ObservationRegime                                          |
// [78..78] sampling                    : SamplingMode                                                         |
// [79..79] builtin_line_shape          : BuiltinLineShapeKind                                                 |
//                                                                                                             |
// out-of-line                                                                                                 |
//   instrument_name, solar_reference_asset_id, and measured_wavelengths_nm are borrowed slice headers.        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 2 cache lines at 64 B per line                                                                  |
// footprint: per instance = 80 B plus borrowed string/grid storage                                            |
pub const ObservationSpec = struct {
    instrument_name: []const u8,
    regime: ObservationModel.ObservationRegime = .nadir,
    sampling: Instrument.SamplingMode,
    instrument_line_fwhm_nm: f64,
    builtin_line_shape: BuiltinLineShapeKind,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_reference_grid: InstrumentModel.AdaptiveReferenceGrid,
    solar_reference_asset_id: []const u8,
    measured_wavelengths_nm: []const f64 = &.{},
};

// LineGasSpec ----------------------------------------------------------------------------------------------- |
// O2 line-list asset references and runtime spectroscopy controls.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 208 B (0.203 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] line_list_asset   : ExternalAsset                                                                |
// [ 48.. 95] line_mixing_asset : ExternalAsset                                                                |
// [ 96..143] strong_lines_asset: ExternalAsset                                                                |
// [144..159] line_mixing_factor: ?f64                                                                         |
// [160..175] isotopes_sim      : []const u8                                                                   |
// [176..191] threshold_line_sim: ?f64                                                                         |
// [192..207] cutoff_sim_cm1    : ?f64                                                                         |
//                                                                                                             |
// out-of-line                                                                                                 |
//   Asset rows and isotopes_sim carry borrowed slice headers; referenced strings/bytes are not inline.        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 4 cache lines at 64 B per line                                                                  |
// footprint: per instance = 208 B plus borrowed asset string and isotope storage                              |
pub const LineGasSpec = struct {
    line_list_asset: ExternalAsset,
    line_mixing_asset: ExternalAsset,
    strong_lines_asset: ExternalAsset,
    line_mixing_factor: ?f64,
    isotopes_sim: []const u8,
    threshold_line_sim: ?f64,
    cutoff_sim_cm1: ?f64,
};

// CiaSpec --------------------------------------------------------------------------------------------------- |
// O2-O2 CIA enable flag plus optional asset descriptor.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..55] cia_asset       : ?ExternalAsset                                                                   |
// [56..56] enabled         : bool                                                                             |
// [57..63] trailing padding: 7 B                                                                              |
//                                                                                                             |
// out-of-line                                                                                                 |
//   cia_asset stores ExternalAsset slice headers when present; referenced string bytes are out-of-line.       |
//                                                                                                             |
// unused bits: 56 padding + 7 bool-storage slack = 63 bits                                                    |
// cache span: 1 cache line at 64 B per line                                                                   |
// footprint: per instance = 64 B plus borrowed asset string storage                                           |
pub const CiaSpec = struct {
    enabled: bool,
    cia_asset: ?ExternalAsset,
};

// InputsSpec ------------------------------------------------------------------------------------------------ |
// Required reference-data asset descriptors for a resolved O2 A case.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 192 B (0.188 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] atmosphere_profile  : ExternalAsset                                                              |
// [ 48.. 95] vendor_reference_csv: ExternalAsset                                                              |
// [ 96..143] raw_solar_reference : ExternalAsset                                                              |
// [144..191] airmass_factor_lut  : ExternalAsset                                                              |
//                                                                                                             |
// out-of-line                                                                                                 |
//   Each ExternalAsset stores borrowed string slice headers.                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 3 cache lines at 64 B per line                                                                  |
// footprint: per instance = 192 B plus borrowed asset string storage                                          |
pub const InputsSpec = struct {
    atmosphere_profile: ExternalAsset,
    vendor_reference_csv: ExternalAsset,
    raw_solar_reference: ExternalAsset,
    airmass_factor_lut: ExternalAsset,
};

// SolarSpectrumSample --------------------------------------------------------------------------------------- |
// High-resolution solar irradiance row loaded from a reference asset.                                         |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] wavelength_nm : f64                                                                                 |
// [8..15] irradiance    : f64                                                                                 |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 16 B; total = per instance * solar sample count                                   |
pub const SolarSpectrumSample = struct {
    wavelength_nm: f64,
    irradiance: f64,
};

// ResolvedVendorO2ACase ------------------------------------------------------------------------------------- |
// Complete parsed O2 A case before asset loading and forward-model preparation.                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 880 B (0.859 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] metadata                   : Metadata                                                            |
// [ 48..239] inputs                     : InputsSpec                                                          |
// [240..255] scene_id                   : []const u8                                                          |
// [256..279] spectral_grid              : SpectralGrid                                                        |
// [280..287] surface_pressure_hpa       : f64                                                                 |
// [288..303] intervals                  : []const VerticalInterval                                            |
// [304..311] surface_albedo             : f64                                                                 |
// [312..343] geometry                   : GeometrySpec                                                        |
// [344..439] aerosol                    : AerosolSpec                                                         |
// [440..519] observation                : ObservationSpec                                                     |
// [520..727] o2                         : LineGasSpec                                                         |
// [728..791] o2o2                       : CiaSpec                                                             |
// [792..863] rtm_controls               : RadiativeTransferControls                                           |
// [864..867] layer_count                : u32                                                                 |
// [868..871] fit_interval_index_1based  : u32                                                                 |
// [872..872] plan                       : PlanSpec                                                            |
// [873..873] sublayer_divisions         : u8                                                                  |
// [874..879] trailing padding           : 6 B                                                                 |
//                                                                                                             |
// out-of-line                                                                                                 |
//   scene_id and intervals are borrowed slice headers. Nested asset/profile/spectrum fields also reference    |
//   storage outside this owner/view header.                                                                   |
//                                                                                                             |
// unused bits: 48 padding + 0 bool-storage slack = 48 bits                                                    |
// cache span: 14 cache lines at 64 B per line                                                                 |
// footprint: per instance = 880 B plus referenced case storage                                                |
pub const ResolvedVendorO2ACase = struct {
    metadata: Metadata,
    plan: PlanSpec,
    inputs: InputsSpec,
    scene_id: []const u8,
    spectral_grid: SpectralGrid,
    layer_count: u32,
    sublayer_divisions: u8,
    surface_pressure_hpa: f64,
    fit_interval_index_1based: u32,
    intervals: []const AtmosphereModel.VerticalInterval,
    surface_albedo: f64,
    geometry: GeometrySpec,
    aerosol: AerosolSpec,
    observation: ObservationSpec,
    o2: LineGasSpec,
    o2o2: CiaSpec,
    rtm_controls: RadiativeTransferControls,
};

// LoadedVendorO2AInputs ------------------------------------------------------------------------------------- |
// Loaded reference assets needed to build the scene and optical state.                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 336 B (0.328 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] profile              : ClimatologyProfile                                                        |
// [ 16.. 31] spectroscopy_profile : ClimatologyProfile                                                        |
// [ 32.. 47] cross_sections       : CrossSectionTable                                                         |
// [ 48..255] line_list            : SpectroscopyLineList                                                      |
// [256..287] cia_table            : ?CollisionInducedAbsorptionTable                                          |
// [288..303] lut                  : AirmassFactorLut                                                          |
// [304..319] reference            : []ReferenceSample                                                         |
// [320..335] raw_solar_spectrum   : []SolarSpectrumSample                                                     |
//                                                                                                             |
// out-of-line                                                                                                 |
//   All table/profile/list fields are headers over loaded storage. deinit releases the owned referenced data. |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// cache span: 6 cache lines at 64 B per line                                                                  |
// footprint: per instance = 336 B plus loaded reference-data storage                                          |
pub const LoadedVendorO2AInputs = struct {
    profile: ReferenceDataModel.ClimatologyProfile,
    spectroscopy_profile: ReferenceDataModel.ClimatologyProfile,
    cross_sections: ReferenceDataModel.CrossSectionTable,
    line_list: ReferenceDataModel.SpectroscopyLineList,
    cia_table: ?ReferenceDataModel.CollisionInducedAbsorptionTable,
    lut: ReferenceDataModel.AirmassFactorLut,
    reference: []ReferenceSample,
    raw_solar_spectrum: []SolarSpectrumSample,

    pub fn deinit(self: *LoadedVendorO2AInputs, allocator: Allocator) void {
        self.profile.deinit(allocator);
        self.spectroscopy_profile.deinit(allocator);
        self.cross_sections.deinit(allocator);
        self.line_list.deinit(allocator);
        if (self.cia_table) |*table| table.deinit(allocator);
        self.lut.deinit(allocator);
        if (self.reference.len != 0) allocator.free(self.reference);
        if (self.raw_solar_spectrum.len != 0) allocator.free(self.raw_solar_spectrum);
        self.* = undefined;
    }
};
