const o2_case = @import("../input/o2_case.zig");

// AerosolLayerTable ------------------------------------------------------------------------------------------|
// Aerosol optical-depth setup inputs copied into table form.                                                  |
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
pub const AerosolLayerTable = struct {
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

pub fn build(case: o2_case.O2Case) AerosolLayerTable {
    // build --------------------------------------------------------------------------------------------------|
    // Copy aerosol optical controls into the named setup table.                                               |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .optical_depth = case.aerosol.optical_depth,
        .single_scatter_albedo = case.aerosol.single_scatter_albedo,
        .asymmetry_factor = case.aerosol.asymmetry_factor,
        .angstrom_exponent = case.aerosol.angstrom_exponent,
        .reference_wavelength_nm = case.aerosol.reference_wavelength_nm,
        .interval_index_1based = case.aerosol.interval_index_1based,
        .top_pressure_hpa = case.aerosol.top_pressure_hpa,
        .bottom_pressure_hpa = case.aerosol.bottom_pressure_hpa,
    };
}
