const std = @import("std");
const transport_controls = @import("../rtm/controls.zig");

// scene.zig ----------------------------------------------------------------------------------------------    |
// Typed O2 A product-scene controls consumed by setup tables and forward runs.                                |
//                                                                                                             |
// runtime boundary                                                                                            |
//   These rows are setup inputs only. Asset paths and text formats are resolved by src/assets; setup tables   |
//   receive typed rows and never parse text themselves.                                                       |
//                                                                                                             |
// consumed controls                                                                                           |
//   spectral_grid        : exact output wavelength count and route span                                       |
//   atmosphere           : pressure/temperature profile and vertical interval controls                        |
//   geometry             : pseudo-spherical angles retained for later transport packages                      |
//   aerosol              : optical-depth inputs and explicit interval placement                               |
//   observation          : line-shape and support-grid spacing                                                |
//   line_gas / cia       : O2 line-list and O2-O2 continuum asset controls                                    |
//   rtm                  : stream count, Fourier limit, and LABOS performance thresholds                      |
// ----------------------------------------------------------------------------------------------------------- |

// Asset ------------------------------------------------------------------------------------------------------|
// Borrowed reference-data asset descriptor.                                                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] id     : []const u8                                                                                |
// [16..31] path   : []const u8                                                                                |
// [32..47] format : []const u8                                                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   String bytes are borrowed from parser-owned input or caller-owned scene storage.                          |
pub const Asset = struct {
    id: []const u8,
    path: []const u8,
    format: []const u8,
};
// ------------------------------------------------------------------------------------------------------------|

// SpectralGrid -----------------------------------------------------------------------------------------------|
// Exact public output wavelength route.                                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] start_nm     : f64                                                                                 |
// [ 8..15] end_nm       : f64                                                                                 |
// [16..23] sample_count : usize                                                                               |
pub const SpectralGrid = struct {
    start_nm: f64,
    end_nm: f64,
    sample_count: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// VerticalInterval -------------------------------------------------------------------------------------------|
// Pressure-bounded reference interval uses shape setup support layers.                                        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] index_1based       : usize                                                                         |
// [ 8..15] top_pressure_hpa   : f64                                                                           |
// [16..23] bottom_pressure_hpa: f64                                                                           |
// [24..31] altitude_divisions : usize                                                                         |
pub const VerticalInterval = struct {
    index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    altitude_divisions: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// AtmosphereControls -----------------------------------------------------------------------------------------|
// Borrowed atmosphere setup controls consumed before table building.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 96 B (0.094 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..47] profile                  : Asset                                                                   |
// [48..55] surface_pressure_hpa     : f64                                                                     |
// [56..63] layer_count              : usize                                                                   |
// [64..71] sublayer_divisions       : usize                                                                   |
// [72..79] fit_interval_index_1based: usize                                                                   |
// [80..95] intervals                : []const VerticalInterval                                                |
//                                                                                                             |
// referenced storage                                                                                          |
//   intervals borrows the default static interval array or parser-owned rows.                                 |
pub const AtmosphereControls = struct {
    profile: Asset,
    surface_pressure_hpa: f64,
    layer_count: usize,
    sublayer_divisions: usize,
    fit_interval_index_1based: usize,
    intervals: []const VerticalInterval,
};
// ------------------------------------------------------------------------------------------------------------|

// GeometryControls -------------------------------------------------------------------------------------------|
// Viewing and solar geometry retained for later transport setup.                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] solar_zenith_deg    : f64                                                                          |
// [ 8..15] viewing_zenith_deg  : f64                                                                          |
// [16..23] relative_azimuth_deg: f64                                                                          |
// [24..24] pseudo_spherical    : bool                                                                         |
// [25..31] trailing padding    : 7 B                                                                          |
pub const GeometryControls = struct {
    solar_zenith_deg: f64,
    viewing_zenith_deg: f64,
    relative_azimuth_deg: f64,
    pseudo_spherical: bool,
};
// ------------------------------------------------------------------------------------------------------------|

// AerosolProfileLayer ----------------------------------------------------------------------------------------|
// One explicit aerosol profile layer supplied by the public Python input.                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] top_pressure_hpa       : f64                                                                       |
// [ 8..15] bottom_pressure_hpa    : f64                                                                       |
// [16..23] optical_depth          : f64                                                                       |
// [24..31] single_scatter_albedo  : f64                                                                       |
// [32..39] asymmetry_factor       : f64                                                                       |
// [40..47] angstrom_exponent      : f64                                                                       |
// [48..55] reference_wavelength_nm: f64                                                                       |
pub const AerosolProfileLayer = struct {
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    optical_depth: f64,
    single_scatter_albedo: f64 = 0.93,
    asymmetry_factor: f64 = 0.65,
    angstrom_exponent: f64 = 1.3,
    reference_wavelength_nm: f64 = 550.0,
};
// ------------------------------------------------------------------------------------------------------------|

// AerosolControls --------------------------------------------------------------------------------------------|
// Aerosol optical-depth and explicit interval placement controls.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] optical_depth          : f64                                                                       |
// [ 8..15] single_scatter_albedo  : f64                                                                       |
// [16..23] asymmetry_factor       : f64                                                                       |
// [24..31] angstrom_exponent      : f64                                                                       |
// [32..39] reference_wavelength_nm: f64                                                                       |
// [40..47] interval_index_1based  : usize                                                                     |
// [48..55] top_pressure_hpa       : f64                                                                       |
// [56..63] bottom_pressure_hpa    : f64                                                                       |
// [64..79] profile                : []const AerosolProfileLayer                                               |
//                                                                                                             |
// referenced storage                                                                                          |
//   profile borrows parser-owned JSON rows. A one-layer public profile is folded back into scalar placement.  |
pub const AerosolControls = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    interval_index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    profile: []const AerosolProfileLayer = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// ObservationControls ----------------------------------------------------------------------------------------|
// Instrument and high-resolution sampling controls for setup.                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 128 B (0.125 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] instrument_name             : []const u8                                                         |
// [ 16.. 23] instrument_line_fwhm_nm     : f64                                                                |
// [ 24.. 31] high_resolution_step_nm     : f64                                                                |
// [ 32.. 39] high_resolution_half_span_nm: f64                                                                |
// [ 40.. 47] adaptive_points_per_fwhm    : usize                                                              |
// [ 48.. 55] strong_line_min_divisions   : usize                                                              |
// [ 56.. 63] strong_line_max_divisions   : usize                                                              |
// [ 64..111] solar_reference             : Asset                                                              |
// [112..127] measured_wavelengths_nm     : []const f64                                                        |
//                                                                                                             |
// referenced storage                                                                                          |
//   measured_wavelengths_nm borrows parser-owned JSON rows for sparse fastmode product grids.                 |
pub const ObservationControls = struct {
    instrument_name: []const u8,
    instrument_line_fwhm_nm: f64,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_points_per_fwhm: usize,
    strong_line_min_divisions: usize,
    strong_line_max_divisions: usize,
    solar_reference: Asset,
    measured_wavelengths_nm: []const f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

// LineGasControls --------------------------------------------------------------------------------------------|
// O2 line-list assets and runtime line-filter controls.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 184 B (0.180 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 47] line_list          : Asset                                                                       |
// [ 48.. 95] line_mixing        : Asset                                                                       |
// [ 96..143] strong_lines       : Asset                                                                       |
// [144..151] line_mixing_factor : f64                                                                         |
// [152..167] isotopes_sim       : []const u8                                                                  |
// [168..175] threshold_line_sim : f64                                                                         |
// [176..183] cutoff_sim_cm1     : f64                                                                         |
//                                                                                                             |
// referenced storage                                                                                          |
//   isotopes_sim borrows from parser-owned input or caller-owned scene storage.                               |
pub const LineGasControls = struct {
    line_list: Asset,
    line_mixing: Asset,
    strong_lines: Asset,
    line_mixing_factor: f64,
    isotopes_sim: []const u8,
    threshold_line_sim: f64,
    cutoff_sim_cm1: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// CiaControls ------------------------------------------------------------------------------------------------|
// O2-O2 CIA enable flag and coefficient-table asset.                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 56 B (0.055 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..47] table   : Asset                                                                                    |
// [48..48] enabled : bool                                                                                     |
// [49..55] trailing padding : 7 B                                                                             |
pub const CiaControls = struct {
    enabled: bool,
    table: Asset,
};
// ------------------------------------------------------------------------------------------------------------|

// RtmControls ------------------------------------------------------------------------------------------------|
// Retained transport controls consumed by forward runs.                                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 80 B (0.078 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] stream_count          : usize                                                                      |
// [ 8..15] fourier_term_limit    : usize                                                                      |
// [16..79] performance_thresholds: PerformanceThresholds                                                      |
pub const RtmControls = struct {
    stream_count: usize,
    fourier_term_limit: usize,
    performance_thresholds: transport_controls.PerformanceThresholds,
};
// ------------------------------------------------------------------------------------------------------------|

// Scene ------------------------------------------------------------------------------------------------------|
// Borrowed O2 A setup row.                                                                                    |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 704 B (0.688 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] id           : []const u8                                                                        |
// [ 16.. 39] spectral_grid: SpectralGrid                                                                      |
// [ 40.. 47] surface_albedo: f64                                                                              |
// [ 48..143] atmosphere   : AtmosphereControls                                                                |
// [144..175] geometry     : GeometryControls                                                                  |
// [176..255] aerosol      : AerosolControls                                                                   |
// [256..383] observation  : ObservationControls                                                               |
// [384..567] line_gas     : LineGasControls                                                                   |
// [568..623] cia          : CiaControls                                                                       |
// [624..703] rtm          : RtmControls                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   id, asset strings, isotope/interval/wavelength slices are borrowed; table builders own loaded rows.       |
pub const Scene = struct {
    id: []const u8,
    spectral_grid: SpectralGrid,
    surface_albedo: f64,
    atmosphere: AtmosphereControls,
    geometry: GeometryControls,
    aerosol: AerosolControls,
    observation: ObservationControls,
    line_gas: LineGasControls,
    cia: CiaControls,
    rtm: RtmControls,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn asset(id: []const u8, path: []const u8, format: []const u8) Asset {
    // asset --------------------------------------------------------------------------------------------------|
    // Build a borrowed asset descriptor for static default-scene assets.                                      |
    // --------------------------------------------------------------------------------------------------------|
    return .{ .id = id, .path = path, .format = format };
}
