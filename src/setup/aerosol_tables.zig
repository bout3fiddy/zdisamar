const std = @import("std");

const hashing = @import("../common/hashing.zig");
const scene_input = @import("../input/scene.zig");

// AerosolLayerTable ------------------------------------------------------------------------------------------|
// Aerosol optical-depth setup inputs copied into table form.                                                  |
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
//   profile borrows parser-owned JSON rows retained by the prepared scene/context owner.                      |
pub const AerosolLayerTable = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    asymmetry_factor: f64,
    angstrom_exponent: f64,
    reference_wavelength_nm: f64,
    interval_index_1based: usize,
    top_pressure_hpa: f64,
    bottom_pressure_hpa: f64,
    profile: []const scene_input.AerosolProfileLayer = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

pub fn hashAll(hasher: *std.hash.Wyhash, aerosol: AerosolLayerTable) void {
    // hashAll ----------------------------------------------------------------------------------------------- |
    // Hash scalar and explicit-profile aerosol controls uses fill per-wavelength layer optics.                |
    // --------------------------------------------------------------------------------------------------------|
    for ([_]f64{
        aerosol.optical_depth,
        aerosol.single_scatter_albedo,
        aerosol.asymmetry_factor,
        aerosol.angstrom_exponent,
        aerosol.reference_wavelength_nm,
        aerosol.top_pressure_hpa,
        aerosol.bottom_pressure_hpa,
    }) |value| hashing.updateValue(hasher, value);
    hashing.updateValue(hasher, aerosol.interval_index_1based);
    for (aerosol.profile) |layer| {
        for ([_]f64{
            layer.top_pressure_hpa,
            layer.bottom_pressure_hpa,
            layer.optical_depth,
            layer.single_scatter_albedo,
            layer.asymmetry_factor,
            layer.angstrom_exponent,
            layer.reference_wavelength_nm,
        }) |value| hashing.updateValue(hasher, value);
    }
}
// ------------------------------------------------------------------------------------------------------------|

pub fn build(scene: scene_input.Scene) AerosolLayerTable {
    // build --------------------------------------------------------------------------------------------------|
    // Copy scalar aerosol controls and the optional explicit profile view into setup table form.              |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .optical_depth = scene.aerosol.optical_depth,
        .single_scatter_albedo = scene.aerosol.single_scatter_albedo,
        .asymmetry_factor = scene.aerosol.asymmetry_factor,
        .angstrom_exponent = scene.aerosol.angstrom_exponent,
        .reference_wavelength_nm = scene.aerosol.reference_wavelength_nm,
        .interval_index_1based = scene.aerosol.interval_index_1based,
        .top_pressure_hpa = scene.aerosol.top_pressure_hpa,
        .bottom_pressure_hpa = scene.aerosol.bottom_pressure_hpa,
        .profile = scene.aerosol.profile,
    };
}
