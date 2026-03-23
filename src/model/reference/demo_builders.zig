//! Purpose:
//!   Build small owned demo reference tables for tests and examples.
//!
//! Physics:
//!   Materializes representative climatology, cross-section, and airmass-factor data.
//!
//! Vendor:
//!   `demo reference builders`
//!
//! Design:
//!   The builders duplicate static arrays into owned slices so callers can free them with the table types.
//!
//! Invariants:
//!   The demo arrays are already monotonic and representative of the supported spectral windows.
//!
//! Validation:
//!   Exercised indirectly by the tests that use these demo tables.

const std = @import("std");
const climatology = @import("climatology.zig");
const cross_sections = @import("cross_sections.zig");
const airmass_phase = @import("airmass_phase.zig");
const Allocator = std.mem.Allocator;

const demo_profile_rows = [_]climatology.ClimatologyPoint{
    .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
    .{ .altitude_km = 5.0, .pressure_hpa = 540.48, .temperature_k = 255.65, .air_number_density_cm3 = 1.149e19 },
    .{ .altitude_km = 10.0, .pressure_hpa = 264.36, .temperature_k = 223.15, .air_number_density_cm3 = 5.413e18 },
    .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
    .{ .altitude_km = 40.0, .pressure_hpa = 2.87, .temperature_k = 251.05, .air_number_density_cm3 = 8.24e16 },
};

const demo_cross_section_points = [_]cross_sections.CrossSectionPoint{
    .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.21e-19 },
    .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 5.72e-19 },
    .{ .wavelength_nm = 450.0, .sigma_cm2_per_molecule = 5.13e-19 },
    .{ .wavelength_nm = 470.0, .sigma_cm2_per_molecule = 4.42e-19 },
    .{ .wavelength_nm = 490.0, .sigma_cm2_per_molecule = 3.98e-19 },
};

const demo_airmass_factor_points = [_]airmass_phase.AirmassFactorPoint{
    .{ .solar_zenith_deg = 20.0, .view_zenith_deg = 0.0, .relative_azimuth_deg = 0.0, .airmass_factor = 1.08 },
    .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
    .{ .solar_zenith_deg = 55.0, .view_zenith_deg = 20.0, .relative_azimuth_deg = 60.0, .airmass_factor = 1.58 },
    .{ .solar_zenith_deg = 70.0, .view_zenith_deg = 30.0, .relative_azimuth_deg = 90.0, .airmass_factor = 2.11 },
};

/// Purpose:
///   Build the demo climatology profile with owned storage.
pub fn buildDemoClimatology(allocator: Allocator) !climatology.ClimatologyProfile {
    return .{
        .rows = try allocator.dupe(climatology.ClimatologyPoint, demo_profile_rows[0..]),
    };
}

/// Purpose:
///   Build the demo cross-section table with owned storage.
pub fn buildDemoCrossSections(allocator: Allocator) !cross_sections.CrossSectionTable {
    return .{
        .points = try allocator.dupe(cross_sections.CrossSectionPoint, demo_cross_section_points[0..]),
    };
}

/// Purpose:
///   Build the demo airmass-factor table with owned storage.
pub fn buildDemoAirmassFactorLut(allocator: Allocator) !airmass_phase.AirmassFactorLut {
    return .{
        .points = try allocator.dupe(airmass_phase.AirmassFactorPoint, demo_airmass_factor_points[0..]),
    };
}
