const std = @import("std");

// o2_case.zig ----------------------------------------------------------------------------------------------- |
// Typed reference-case controls consumed by WP2 setup tables.                                                 |
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
//   rtm                  : layer/source/quadrature shape checked against WP1 evidence                         |
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
//   String bytes are borrowed from static defaults or parser-owned input.                                     |
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
// Pressure-bounded reference interval used to shape setup support layers.                                     |
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

// AerosolControls --------------------------------------------------------------------------------------------|
// Aerosol optical-depth and explicit interval placement controls.                                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.063 KiB), align: 8 B                                                                          |
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
pub const AerosolControls = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    interval_index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// ObservationControls ----------------------------------------------------------------------------------------|
// Instrument and high-resolution sampling controls for setup.                                                 |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 112 B (0.109 KiB), align: 8 B                                                                         |
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
pub const ObservationControls = struct {
    instrument_name: []const u8,
    instrument_line_fwhm_nm: f64,
    high_resolution_step_nm: f64,
    high_resolution_half_span_nm: f64,
    adaptive_points_per_fwhm: usize,
    strong_line_min_divisions: usize,
    strong_line_max_divisions: usize,
    solar_reference: Asset,
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
//   isotopes_sim borrows the static isotope list in defaults.                                                 |
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
// Retained transport-shape controls checked by WP2 but consumed by later packages.                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0.. 7] stream_count      : usize                                                                           |
// [8..15] fourier_term_limit: usize                                                                           |
pub const RtmControls = struct {
    stream_count: usize,
    fourier_term_limit: usize,
};
// ------------------------------------------------------------------------------------------------------------|

// O2Case -----------------------------------------------------------------------------------------------------|
// Borrowed reference-case setup row.                                                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 600 B (0.586 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] id           : []const u8                                                                        |
// [ 16.. 39] spectral_grid: SpectralGrid                                                                      |
// [ 40..135] atmosphere   : AtmosphereControls                                                                |
// [136..167] geometry     : GeometryControls                                                                  |
// [168..231] aerosol      : AerosolControls                                                                   |
// [232..343] observation  : ObservationControls                                                               |
// [344..527] line_gas     : LineGasControls                                                                   |
// [528..583] cia          : CiaControls                                                                       |
// [584..599] rtm          : RtmControls                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   id, asset strings, isotope slices, and interval slices are borrowed; table builders own loaded rows.      |
pub const O2Case = struct {
    id: []const u8,
    spectral_grid: SpectralGrid,
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
    // Build a borrowed asset descriptor for static reference-case defaults.                                   |
    // --------------------------------------------------------------------------------------------------------|
    return .{ .id = id, .path = path, .format = format };
}
