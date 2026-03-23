const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const OpticsPreparation = @import("../../optics/preparation.zig");
const common = @import("../common.zig");
const labos = @import("../labos.zig");
const PluginProviders = @import("../../../plugins/providers/root.zig");
const Types = @import("types.zig");

const Allocator = std.mem.Allocator;
const PreparedOpticalState = OpticsPreparation.PreparedOpticalState;
const PreparedLayer = OpticsPreparation.PreparedLayer;
const PreparedSublayer = OpticsPreparation.PreparedSublayer;
const ProviderBindings = Types.ProviderBindings;
const phase_coefficient_count = @import("../../optics/prepare/phase_functions.zig").phase_coefficient_count;
const centimeters_per_kilometer = 1.0e5;

pub fn buildTestPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(PreparedLayer, &.{
            .{ .layer_index = 0, .sublayer_start_index = 0, .sublayer_count = 2, .altitude_km = 2.0, .pressure_hpa = 820.0, .temperature_k = 280.0, .number_density_cm3 = 2.0e19, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 1.0e-20, .line_mixing_cross_section_cm2_per_molecule = 2.0e-21, .cia_optical_depth = 0.03, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23, .gas_optical_depth = 0.12, .aerosol_optical_depth = 0.05, .cloud_optical_depth = 0.03, .layer_single_scatter_albedo = 0.94, .depolarization_factor = 0.03, .optical_depth = 0.2 },
            .{ .layer_index = 1, .sublayer_start_index = 2, .sublayer_count = 2, .altitude_km = 10.0, .pressure_hpa = 280.0, .temperature_k = 240.0, .number_density_cm3 = 6.0e18, .continuum_cross_section_cm2_per_molecule = 5.0e-19, .line_cross_section_cm2_per_molecule = 5.0e-21, .line_mixing_cross_section_cm2_per_molecule = 1.0e-21, .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24, .cia_optical_depth = 0.0, .gas_optical_depth = 0.07, .aerosol_optical_depth = 0.02, .cloud_optical_depth = 0.01, .layer_single_scatter_albedo = 0.96, .depolarization_factor = 0.02, .optical_depth = 0.1 },
        }),
        .sublayers = try allocator.dupe(PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.0,
                .pressure_hpa = 880.0,
                .temperature_k = 284.0,
                .number_density_cm3 = 2.1e19,
                .oxygen_number_density_cm3 = 4.4e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 9.0e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.8e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.015,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23,
                .gas_absorption_optical_depth = 0.06,
                .gas_scattering_optical_depth = 0.02,
                .gas_extinction_optical_depth = 0.08,
                .d_gas_optical_depth_d_temperature = -7.5e-5,
                .d_cia_optical_depth_d_temperature = -1.5e-5,
                .aerosol_optical_depth = 0.028,
                .cloud_optical_depth = 0.018,
                .aerosol_single_scatter_albedo = 0.94,
                .cloud_single_scatter_albedo = 0.96,
                .aerosol_phase_coefficients = .{ 1.0, 0.20, 0.04, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.10, 0.02, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.17, 0.035, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 3.0,
                .pressure_hpa = 760.0,
                .temperature_k = 276.0,
                .number_density_cm3 = 1.9e19,
                .oxygen_number_density_cm3 = 4.0e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 1.1e-20,
                .line_mixing_cross_section_cm2_per_molecule = 2.2e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.015,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -1.0e-23,
                .gas_absorption_optical_depth = 0.06,
                .gas_scattering_optical_depth = 0.02,
                .gas_extinction_optical_depth = 0.08,
                .d_gas_optical_depth_d_temperature = -7.5e-5,
                .d_cia_optical_depth_d_temperature = -1.5e-5,
                .aerosol_optical_depth = 0.022,
                .cloud_optical_depth = 0.012,
                .aerosol_single_scatter_albedo = 0.94,
                .cloud_single_scatter_albedo = 0.96,
                .aerosol_phase_coefficients = .{ 1.0, 0.18, 0.03, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.08, 0.02, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.15, 0.028, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 0,
                .altitude_km = 8.0,
                .pressure_hpa = 360.0,
                .temperature_k = 248.0,
                .number_density_cm3 = 7.0e18,
                .oxygen_number_density_cm3 = 1.47e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 5.2e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.0e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24,
                .gas_absorption_optical_depth = 0.035,
                .gas_scattering_optical_depth = 0.012,
                .gas_extinction_optical_depth = 0.047,
                .d_gas_optical_depth_d_temperature = -3.0e-5,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.011,
                .cloud_optical_depth = 0.006,
                .aerosol_single_scatter_albedo = 0.96,
                .cloud_single_scatter_albedo = 0.98,
                .aerosol_phase_coefficients = .{ 1.0, 0.14, 0.02, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.05, 0.01, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.11, 0.018, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 1,
                .altitude_km = 12.0,
                .pressure_hpa = 220.0,
                .temperature_k = 232.0,
                .number_density_cm3 = 5.0e18,
                .oxygen_number_density_cm3 = 1.05e18,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 5.0e-19,
                .line_cross_section_cm2_per_molecule = 4.8e-21,
                .line_mixing_cross_section_cm2_per_molecule = 1.0e-21,
                .cia_sigma_cm5_per_molecule2 = 1.0e-46,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = -5.0e-24,
                .gas_absorption_optical_depth = 0.035,
                .gas_scattering_optical_depth = 0.012,
                .gas_extinction_optical_depth = 0.047,
                .d_gas_optical_depth_d_temperature = -3.0e-5,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.009,
                .cloud_optical_depth = 0.004,
                .aerosol_single_scatter_albedo = 0.96,
                .cloud_single_scatter_albedo = 0.98,
                .aerosol_phase_coefficients = .{ 1.0, 0.12, 0.02, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.05, 0.01, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.10, 0.016, 0.0 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 405.0, .sigma_cm2_per_molecule = 6.0e-19 },
            .{ .wavelength_nm = 465.0, .sigma_cm2_per_molecule = 4.0e-19 },
        }),
        .collision_induced_absorption = .{
            .scale_factor_cm5_per_molecule2 = 1.0e-46,
            .points = try allocator.dupe(ReferenceData.CollisionInducedAbsorptionPoint, &.{
                .{ .wavelength_nm = 405.0, .a0 = 0.5, .a1 = 0.0, .a2 = 0.0 },
                .{ .wavelength_nm = 465.0, .a0 = 1.5, .a1 = 0.0, .a2 = 0.0 },
            }),
        },
        .spectroscopy_lines = .{
            .lines = try allocator.dupe(ReferenceData.SpectroscopyLine, &.{
                .{ .center_wavelength_nm = 434.6, .line_strength_cm2_per_molecule = 1.0e-20, .air_half_width_nm = 0.04, .temperature_exponent = 0.7, .lower_state_energy_cm1 = 120.0, .pressure_shift_nm = 0.002, .line_mixing_coefficient = 0.06 },
            }),
        },
        .mean_cross_section_cm2_per_molecule = 5.0e-19,
        .line_mean_cross_section_cm2_per_molecule = 7.5e-21,
        .line_mixing_mean_cross_section_cm2_per_molecule = 1.5e-21,
        .cia_mean_cross_section_cm5_per_molecule2 = 1.0e-46,
        .effective_air_mass_factor = 1.25,
        .effective_single_scatter_albedo = 0.92,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 550.0,
        .column_density_factor = 6.0e0,
        .cia_pair_path_factor_cm5 = 4.0e42,
        .aerosol_reference_wavelength_nm = 550.0,
        .aerosol_angstrom_exponent = 1.3,
        .cloud_reference_wavelength_nm = 550.0,
        .cloud_angstrom_exponent = 0.3,
        .gas_optical_depth = 0.19,
        .cia_optical_depth = 0.03,
        .aerosol_optical_depth = 0.07,
        .cloud_optical_depth = 0.04,
        .d_optical_depth_d_temperature = -1.5e-4,
        .depolarization_factor = 0.025,
        .total_optical_depth = 0.3,
    };
}

pub fn buildQuadratureSensitivePreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 2,
                .altitude_km = 2.0,
                .pressure_hpa = 820.0,
                .temperature_k = 280.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.22,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.22,
            },
            .{
                .layer_index = 1,
                .sublayer_start_index = 2,
                .sublayer_count = 2,
                .altitude_km = 8.0,
                .pressure_hpa = 380.0,
                .temperature_k = 245.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.13,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.13,
            },
        }),
        .sublayers = try allocator.dupe(PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.0,
                .pressure_hpa = 860.0,
                .temperature_k = 283.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.35, 0.12, 0.03 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 3.0,
                .pressure_hpa = 780.0,
                .temperature_k = 277.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.32, 0.10, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.32, 0.10, 0.02 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 2,
                .altitude_km = 7.0,
                .pressure_hpa = 420.0,
                .temperature_k = 250.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.065,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.24, 0.09, 0.02 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 3,
                .altitude_km = 9.0,
                .pressure_hpa = 340.0,
                .temperature_k = 240.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 5.0e4,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.065,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.21, 0.08, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.21, 0.08, 0.02 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 262.0,
        .effective_pressure_hpa = 560.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.35,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.35,
    };
}

pub fn buildNonuniformQuadraturePreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 4,
                .altitude_km = 5.0,
                .pressure_hpa = 650.0,
                .temperature_k = 268.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.50,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.50,
            },
        }),
        .sublayers = try allocator.dupe(PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 0.5,
                .pressure_hpa = 900.0,
                .temperature_k = 282.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 1.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.05,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.18, 0.04, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.18, 0.04, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 1,
                .altitude_km = 2.0,
                .pressure_hpa = 790.0,
                .temperature_k = 276.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 2.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.09,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.24, 0.05, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.24, 0.05, 0.0 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 2,
                .altitude_km = 4.5,
                .pressure_hpa = 610.0,
                .temperature_k = 266.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 3.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.14,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.31, 0.07, 0.01 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.31, 0.07, 0.01 },
            },
            .{
                .parent_layer_index = 0,
                .sublayer_index = 3,
                .altitude_km = 8.0,
                .pressure_hpa = 430.0,
                .temperature_k = 255.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 4.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.22,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.38, 0.09, 0.02 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.38, 0.09, 0.02 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 268.0,
        .effective_pressure_hpa = 650.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.50,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.50,
    };
}

pub fn buildSingleSubdivisionPreparedOpticalState(allocator: Allocator) !PreparedOpticalState {
    return .{
        .layers = try allocator.dupe(PreparedLayer, &.{
            .{
                .layer_index = 0,
                .sublayer_start_index = 0,
                .sublayer_count = 1,
                .altitude_km = 1.5,
                .pressure_hpa = 820.0,
                .temperature_k = 279.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.16,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.16,
            },
            .{
                .layer_index = 1,
                .sublayer_start_index = 1,
                .sublayer_count = 1,
                .altitude_km = 6.0,
                .pressure_hpa = 470.0,
                .temperature_k = 252.0,
                .number_density_cm3 = 0.0,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_optical_depth = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .layer_single_scatter_albedo = 1.0,
                .depolarization_factor = 0.0,
                .optical_depth = 0.11,
            },
        }),
        .sublayers = try allocator.dupe(PreparedSublayer, &.{
            .{
                .parent_layer_index = 0,
                .sublayer_index = 0,
                .altitude_km = 1.5,
                .pressure_hpa = 820.0,
                .temperature_k = 279.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 3.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.16,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.22, 0.05, 0.0 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.22, 0.05, 0.0 },
            },
            .{
                .parent_layer_index = 1,
                .sublayer_index = 1,
                .altitude_km = 6.0,
                .pressure_hpa = 470.0,
                .temperature_k = 252.0,
                .number_density_cm3 = 0.0,
                .oxygen_number_density_cm3 = 0.0,
                .path_length_cm = 6.0e5,
                .continuum_cross_section_cm2_per_molecule = 0.0,
                .line_cross_section_cm2_per_molecule = 0.0,
                .line_mixing_cross_section_cm2_per_molecule = 0.0,
                .cia_sigma_cm5_per_molecule2 = 0.0,
                .cia_optical_depth = 0.0,
                .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
                .gas_absorption_optical_depth = 0.0,
                .gas_scattering_optical_depth = 0.0,
                .gas_extinction_optical_depth = 0.0,
                .d_gas_optical_depth_d_temperature = 0.0,
                .d_cia_optical_depth_d_temperature = 0.0,
                .aerosol_optical_depth = 0.11,
                .cloud_optical_depth = 0.0,
                .aerosol_single_scatter_albedo = 1.0,
                .cloud_single_scatter_albedo = 0.0,
                .aerosol_phase_coefficients = .{ 1.0, 0.31, 0.08, 0.01 },
                .cloud_phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 },
                .combined_phase_coefficients = .{ 1.0, 0.31, 0.08, 0.01 },
            },
        }),
        .continuum_points = try allocator.dupe(ReferenceData.CrossSectionPoint, &.{
            .{ .wavelength_nm = 430.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 435.0, .sigma_cm2_per_molecule = 0.0 },
            .{ .wavelength_nm = 440.0, .sigma_cm2_per_molecule = 0.0 },
        }),
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 1.0,
        .effective_temperature_k = 266.0,
        .effective_pressure_hpa = 640.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = 435.0,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = 435.0,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.27,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.27,
    };
}

pub fn testProviders() ProviderBindings {
    const resolved = PluginProviders.PreparedProviders.resolve(.{}) catch unreachable;
    return .{
        .transport = resolved.transport,
        .surface = resolved.surface,
        .instrument = resolved.instrument,
        .noise = resolved.noise,
    };
}

pub fn fillSyntheticIntegratedSourceField(
    geo: *const labos.Geometry,
    ud: []labos.UDField,
) void {
    const solar_col: usize = 1;
    const view_idx = geo.viewIdx();
    const solar_idx = geo.n_gauss + 1;

    for (ud, 0..) |*field, ilevel| {
        field.* = .{
            .E = labos.Vec.zero(geo.nmutot),
            .U = labos.Vec2.zero(geo.nmutot),
            .D = labos.Vec2.zero(geo.nmutot),
        };

        const level_scale = @as(f64, @floatFromInt(ilevel + 1));
        field.E.set(view_idx, 0.40 + 0.08 * level_scale);
        field.E.set(solar_idx, 0.22 + 0.05 * level_scale);
        for (0..geo.n_gauss) |imu| {
            const mu_scale = @as(f64, @floatFromInt(imu + 1));
            field.D.col[solar_col].set(imu, 0.12 + 0.02 * level_scale + 0.01 * mu_scale);
            field.U.col[solar_col].set(imu, 0.08 + 0.015 * level_scale + 0.008 * mu_scale);
        }
    }

    // Zero the direct surface addend so changes come only from RTM quadrature nodes.
    ud[0].U.col[solar_col].set(view_idx, 0.0);
}

pub fn inputWithQuadrature(
    base_input: common.ForwardInput,
    levels: []const common.RtmQuadratureLevel,
) common.ForwardInput {
    var input = base_input;
    input.rtm_quadrature = .{ .levels = levels };
    return input;
}

fn blendLegacyPhaseCoefficients(
    left: [phase_coefficient_count]f64,
    left_weight: f64,
    right: [phase_coefficient_count]f64,
    right_weight: f64,
) [phase_coefficient_count]f64 {
    var blended = [_]f64{0.0} ** phase_coefficient_count;
    blended[0] = 1.0;
    const total_weight = @max(left_weight, 0.0) + @max(right_weight, 0.0);
    if (total_weight <= 0.0) return blended;
    for (0..phase_coefficient_count) |index| {
        blended[index] = (left[index] * @max(left_weight, 0.0) +
            right[index] * @max(right_weight, 0.0)) / total_weight;
    }
    return blended;
}

pub fn fillLegacyMidpointQuadratureLevels(
    prepared: *const PreparedOpticalState,
    layer_inputs: []const common.LayerInput,
    levels: []common.RtmQuadratureLevel,
) void {
    const sublayers = prepared.sublayers orelse unreachable;
    for (levels) |*level| {
        level.weight = 0.0;
        level.ksca = 0.0;
        level.phase_coefficients = .{ 1.0, 0.0, 0.0, 0.0 };
    }

    for (prepared.layers) |layer| {
        const start: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count <= 1) continue;
        const stop = start + count;

        var parent_scattering: f64 = 0.0;
        for (layer_inputs[start..stop]) |layer_input| {
            parent_scattering += @max(layer_input.scattering_optical_depth, 0.0);
        }

        var raw_scattering_sum: f64 = 0.0;
        for (start + 1..stop) |ilevel| {
            const left_sublayer = sublayers[ilevel - 1];
            const right_sublayer = sublayers[ilevel];
            const left_input = layer_inputs[ilevel - 1];
            const right_input = layer_inputs[ilevel];
            const left_span = @max(left_sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            const right_span = @max(right_sublayer.path_length_cm / centimeters_per_kilometer, 0.0);
            const node_span = 0.5 * (left_span + right_span);
            const left_scattering = @max(left_input.scattering_optical_depth, 0.0);
            const right_scattering = @max(right_input.scattering_optical_depth, 0.0);
            const node_ksca = if ((left_span + right_span) > 0.0)
                (left_scattering + right_scattering) / (left_span + right_span)
            else
                0.0;

            levels[ilevel].weight = node_span;
            levels[ilevel].ksca = node_ksca;
            levels[ilevel].phase_coefficients = blendLegacyPhaseCoefficients(
                left_input.phase_coefficients,
                left_scattering,
                right_input.phase_coefficients,
                right_scattering,
            );
            raw_scattering_sum += levels[ilevel].weightedScattering();
        }

        if (raw_scattering_sum > 0.0 and parent_scattering > 0.0) {
            const scale = parent_scattering / raw_scattering_sum;
            for (start + 1..stop) |ilevel| {
                levels[ilevel].weight *= scale;
            }
        } else {
            for (start + 1..stop) |ilevel| {
                levels[ilevel].weight = 0.0;
                levels[ilevel].ksca = 0.0;
            }
        }
    }
}
