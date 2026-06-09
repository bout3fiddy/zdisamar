const std = @import("std");
const ClimatologyProfile = @import("../../../input/reference/climatology.zig").ClimatologyProfile;

// internal.zig -----------------------------------------------------------------------------------------------|
// Test-access exports for preparation submodules and lifted private helpers.                                  |
//                                                                                                             |
// called by                                                                                                   |
//   internal.forward_model.optical_properties.internal in unit and validation tests.                          |
//                                                                                                             |
// contents                                                                                                    |
//   Re-exports state-build modules that are private to the product path but useful for focused tests.         |
//   Keeps scalar helper constants next to the interpolation code that uses them.                              |
//                                                                                                             |
// boundary                                                                                                    |
//   No runtime preparation route depends on this module; it is an inspection and test surface only.           |
// ------------------------------------------------------------------------------------------------------------|

pub const carrier_eval = @import("carrier_eval.zig");
pub const forward_layers = @import("forward_layers.zig");
pub const layer_accumulation = @import("layer_accumulation.zig");
pub const pseudo_spherical = @import("pseudo_spherical.zig");
pub const rtm_quadrature = @import("rtm_quadrature.zig");
pub const source_interfaces = @import("source_interfaces.zig");
pub const shared_geometry = @import("shared_geometry.zig");
pub const shared_carrier = @import("shared_carrier.zig");
pub const state_spectroscopy = @import("state_spectroscopy.zig");

pub const boltzmann_hpa_cm3_per_k = 1.380658e-19;

// ParitySupportThermodynamics --------------------------------------------------------------------------------|
// Interpolated thermodynamic state used by DISAMAR-parity support rows.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] pressure_hpa  : f64                                                                                |
// [ 8..15] temperature_k : f64                                                                                |
// [16..23] density_cm3   : f64                                                                                |
// ------------------------------------------------------------------------------------------------------------|
pub const ParitySupportThermodynamics = struct {
    pressure_hpa: f64,
    temperature_k: f64,
    density_cm3: f64,
};

pub fn pressureFromParitySupportBounds(
    bottom_altitude_km: f64,
    top_altitude_km: f64,
    bottom_pressure_hpa: f64,
    top_pressure_hpa: f64,
    altitude_km: f64,
) f64 {
    const safe_bottom_pressure_hpa = @max(bottom_pressure_hpa, 1.0e-9);
    const safe_top_pressure_hpa = @max(top_pressure_hpa, 1.0e-9);
    const altitude_span_km = top_altitude_km - bottom_altitude_km;
    if (altitude_span_km <= 0.0 or
        std.math.approxEqAbs(f64, safe_bottom_pressure_hpa, safe_top_pressure_hpa, 1.0e-12))
    {
        return if (bottom_pressure_hpa > 0.0) bottom_pressure_hpa else top_pressure_hpa;
    }

    const unclamped_weight = (altitude_km - bottom_altitude_km) / altitude_span_km;
    const weight = std.math.clamp(unclamped_weight, 0.0, 1.0);
    const bottom_log_pressure = @log(safe_bottom_pressure_hpa);
    const top_log_pressure = @log(safe_top_pressure_hpa);

    // math: pressure(z) = exp(log(p_bottom) + w * (log(p_top) - log(p_bottom))).
    return @exp(bottom_log_pressure + weight * (top_log_pressure - bottom_log_pressure));
}

pub fn paritySupportThermodynamicsFromProfile(
    profile: *const ClimatologyProfile,
    altitude_km: f64,
) ParitySupportThermodynamics {
    const pressure_hpa = profile.interpolatePressureLogSpline(altitude_km);
    const temperature_k = profile.interpolateTemperatureSpline(altitude_km);

    return .{
        .pressure_hpa = pressure_hpa,
        .temperature_k = temperature_k,

        // math: number density [cm^-3] = pressure_hpa / temperature_k / k_B(hPa*cm^3/K).
        .density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k,
    };
}
