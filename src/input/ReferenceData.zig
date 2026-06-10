const std = @import("std");
const climatology = @import("reference/climatology.zig");
const cross_section_types = @import("reference/cross_sections.zig");
const cia = @import("reference/cia.zig");
const airmass_phase = @import("reference/airmass_phase.zig");
const rayleigh = @import("reference/rayleigh.zig");
const spectroscopy_types = @import("reference/spectroscopy/types.zig");
const spectroscopy_line_list = @import("reference/spectroscopy/line_list.zig");

const Allocator = std.mem.Allocator;

// ReferenceData.zig -----------------------------------------------------------------------------------------|
// Public typed-reference-data facade for loaders, input bindings, preparation, diagnostics, and tests.       |
//                                                                                                            |
// called by                                                                                                  |
//   input/reference_data loaders return the concrete owner rows re-exported here after manifest conversion.  |
//   input/Absorber.zig stores resolved line-list, cross-section, and CIA payloads on scene absorbers.        |
//   optical_properties/state_build consumes profile, LUT, cross-section, CIA, Rayleigh, and spectroscopy     |
//   rows while preparing per-wavelength optical state.                                                       |
//   output/o2_line_contributions.zig and tests import these names as the stable public row vocabulary.       |
//                                                                                                            |
// export map                                                                                                 |
//   climatology.zig      -> ClimatologyPoint/Profile and pressure-grid helpers                               |
//   cross_sections.zig   -> continuum/cross-section point tables                                             |
//   cia.zig              -> O2-O2 collision-induced absorption polynomial tables                             |
//   airmass_phase.zig    -> airmass-factor LUT rows                                                          |
//   rayleigh.zig         -> Rayleigh scalar helper namespace                                                 |
//   spectroscopy/types   -> line, sidecar, relaxation, runtime-control, and prepared-state structs           |
//   spectroscopy/line_list.zig -> SpectroscopyLineList owner and evaluation entrypoint                       |
//                                                                                                            |
// boundary and ownership                                                                                     |
//   This file is the public facade for the imported reference modules. Owner/deinit behavior and math        |
//   routines live there; callers use these re-exported names as the stable row vocabulary.                   |
//                                                                                                            |
// demo data                                                                                                  |
//   The buildDemo* helpers allocate deterministic fixture rows for examples and smoke tests. Scientific      |
//   reference assets are loaded from data/reference_data through input/reference_data loaders.               |
// -----------------------------------------------------------------------------------------------------------|

pub const ClimatologyPoint = climatology.ClimatologyPoint;
pub const ClimatologyProfile = climatology.ClimatologyProfile;
pub const CrossSectionPoint = cross_section_types.CrossSectionPoint;
pub const CrossSectionTable = cross_section_types.CrossSectionTable;
pub const CollisionInducedAbsorptionPoint = cia.CollisionInducedAbsorptionPoint;
pub const CollisionInducedAbsorptionTable = cia.CollisionInducedAbsorptionTable;
pub const Rayleigh = rayleigh;

pub const max_strong_line_sidecars = spectroscopy_types.max_strong_line_sidecars;
pub const StrongLineAnchorIndex = spectroscopy_types.StrongLineAnchorIndex;
pub const hitran_hc_over_kb_cm_k = spectroscopy_types.hitran_hc_over_kb_cm_k;
pub const hitran_o2_line_mixing_hc_over_kb_cm_k = spectroscopy_types.hitran_o2_line_mixing_hc_over_kb_cm_k;
pub const SpectroscopyLine = spectroscopy_types.SpectroscopyLine;
pub const SpectroscopyStrongLine = spectroscopy_types.SpectroscopyStrongLine;
pub const SpectroscopyStrongLineSet = spectroscopy_types.SpectroscopyStrongLineSet;
pub const RelaxationMatrix = spectroscopy_types.RelaxationMatrix;
pub const SpectroscopyEvaluation = spectroscopy_types.SpectroscopyEvaluation;
pub const SpectroscopyRuntimeControls = spectroscopy_types.SpectroscopyRuntimeControls;
pub const StrongLinePreparedState = spectroscopy_types.StrongLinePreparedState;
pub const WeakLinePreparedState = spectroscopy_types.WeakLinePreparedState;
pub const SpectroscopyLineList = spectroscopy_line_list.SpectroscopyLineList;

pub const AirmassFactorPoint = airmass_phase.AirmassFactorPoint;
pub const AirmassFactorLut = airmass_phase.AirmassFactorLut;

const demo_profile_rows = [_]ClimatologyPoint{
    .{ .altitude_km = 0.0, .pressure_hpa = 1013.25, .temperature_k = 288.15, .air_number_density_cm3 = 2.547e19 },
    .{ .altitude_km = 5.0, .pressure_hpa = 540.48, .temperature_k = 255.65, .air_number_density_cm3 = 1.149e19 },
    .{ .altitude_km = 10.0, .pressure_hpa = 264.36, .temperature_k = 223.15, .air_number_density_cm3 = 5.413e18 },
    .{ .altitude_km = 20.0, .pressure_hpa = 54.75, .temperature_k = 216.65, .air_number_density_cm3 = 1.095e18 },
    .{ .altitude_km = 40.0, .pressure_hpa = 2.87, .temperature_k = 251.05, .air_number_density_cm3 = 8.24e16 },
};

const demo_cross_section_points = [_]CrossSectionPoint{
    .{ .wavelength_nm = 758.0, .sigma_cm2_per_molecule = 1.2e-24 },
    .{ .wavelength_nm = 761.0, .sigma_cm2_per_molecule = 2.8e-24 },
    .{ .wavelength_nm = 764.0, .sigma_cm2_per_molecule = 3.6e-24 },
    .{ .wavelength_nm = 768.0, .sigma_cm2_per_molecule = 2.1e-24 },
    .{ .wavelength_nm = 771.0, .sigma_cm2_per_molecule = 1.5e-24 },
};

const demo_airmass_factor_points = [_]AirmassFactorPoint{
    .{ .solar_zenith_deg = 20.0, .view_zenith_deg = 0.0, .relative_azimuth_deg = 0.0, .airmass_factor = 1.08 },
    .{ .solar_zenith_deg = 40.0, .view_zenith_deg = 10.0, .relative_azimuth_deg = 30.0, .airmass_factor = 1.241 },
    .{ .solar_zenith_deg = 55.0, .view_zenith_deg = 20.0, .relative_azimuth_deg = 60.0, .airmass_factor = 1.58 },
    .{ .solar_zenith_deg = 70.0, .view_zenith_deg = 30.0, .relative_azimuth_deg = 90.0, .airmass_factor = 2.11 },
};

const demo_spectroscopy_lines = [_]SpectroscopyLine{
    .{
        .center_wavelength_nm = 429.8,
        .line_strength_cm2_per_molecule = 8.2e-21,
        .air_half_width_nm = 0.035,
        .temperature_exponent = 0.72,
        .lower_state_energy_cm1 = 112.0,
        .pressure_shift_nm = 0.002,
        .line_mixing_coefficient = 0.04,
    },
    .{
        .center_wavelength_nm = 434.6,
        .line_strength_cm2_per_molecule = 1.15e-20,
        .air_half_width_nm = 0.041,
        .temperature_exponent = 0.69,
        .lower_state_energy_cm1 = 140.0,
        .pressure_shift_nm = 0.003,
        .line_mixing_coefficient = 0.07,
    },
    .{
        .center_wavelength_nm = 441.2,
        .line_strength_cm2_per_molecule = 9.7e-21,
        .air_half_width_nm = 0.038,
        .temperature_exponent = 0.74,
        .lower_state_energy_cm1 = 165.0,
        .pressure_shift_nm = 0.002,
        .line_mixing_coefficient = 0.05,
    },
    .{
        .center_wavelength_nm = 448.1,
        .line_strength_cm2_per_molecule = 7.6e-21,
        .air_half_width_nm = 0.034,
        .temperature_exponent = 0.77,
        .lower_state_energy_cm1 = 188.0,
        .pressure_shift_nm = 0.001,
        .line_mixing_coefficient = 0.03,
    },
    .{
        .center_wavelength_nm = 456.0,
        .line_strength_cm2_per_molecule = 5.4e-21,
        .air_half_width_nm = 0.030,
        .temperature_exponent = 0.81,
        .lower_state_energy_cm1 = 205.0,
        .pressure_shift_nm = 0.001,
        .line_mixing_coefficient = 0.02,
    },
};

pub fn buildDemoClimatology(allocator: Allocator) !ClimatologyProfile {
    return .{
        .rows = try allocator.dupe(ClimatologyPoint, demo_profile_rows[0..]),
    };
}

pub fn buildDemoCrossSections(allocator: Allocator) !CrossSectionTable {
    return .{
        .points = try allocator.dupe(CrossSectionPoint, demo_cross_section_points[0..]),
    };
}

pub fn buildDemoAirmassFactorLut(allocator: Allocator) !AirmassFactorLut {
    return .{
        .points = try allocator.dupe(AirmassFactorPoint, demo_airmass_factor_points[0..]),
    };
}

pub fn buildDemoSpectroscopyLines(allocator: Allocator) !SpectroscopyLineList {
    return .{
        .lines = try allocator.dupe(SpectroscopyLine, demo_spectroscopy_lines[0..]),
        .lines_sorted_ascending = true,
    };
}
