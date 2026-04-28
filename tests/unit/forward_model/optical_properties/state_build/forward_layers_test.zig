const std = @import("std");
const internal = @import("internal");

const preparation = internal.kernels.optics.preparation;
const Scene = internal.Scene;
const transport_common = internal.kernels.transport.common;
const ParticleProfiles = internal.kernels.optics.prepare.particle_profiles;
const PhaseFunctions = internal.kernels.optics.prepare.phase_functions;
const State = preparation.state;
const Evaluation = preparation.evaluation;
const shared_geometry = preparation.shared_geometry;
const shared_carrier = preparation.shared_carrier;
const SpectroscopyState = preparation.state_spectroscopy;
const forward_layers = preparation.forward_layers;

const PreparedOpticalState = preparation.PreparedOpticalState;
const OpticalDepthBreakdown = preparation.OpticalDepthBreakdown;
const fillForwardLayersAtWavelength = forward_layers.fillForwardLayersAtWavelength;

test "shared forward layers reduce prepared support rows" {
    const allocator = std.testing.allocator;
    const wavelength_nm = 760.0;
    const zero_phase = PhaseFunctions.zeroPhaseCoefficients();
    const aerosol_phase = PhaseFunctions.hgPhaseCoefficients(0.65);

    var layers = [_]State.PreparedLayer{
        .{
            .layer_index = 0,
            .sublayer_start_index = 0,
            .sublayer_count = 3,
            .altitude_km = 0.5,
            .pressure_hpa = 900.0,
            .temperature_k = 280.0,
            .number_density_cm3 = 1.0e19,
            .continuum_cross_section_cm2_per_molecule = 0.0,
            .line_cross_section_cm2_per_molecule = 0.0,
            .line_mixing_cross_section_cm2_per_molecule = 0.0,
            .cia_optical_depth = 0.0,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
            .gas_optical_depth = 0.0,
            .aerosol_optical_depth = 0.0,
            .cloud_optical_depth = 0.0,
            .layer_single_scatter_albedo = 0.0,
            .depolarization_factor = 0.0,
            .optical_depth = 0.0,
            .top_altitude_km = 1.0,
            .bottom_altitude_km = 0.0,
            .top_pressure_hpa = 800.0,
            .bottom_pressure_hpa = 1000.0,
            .interval_index_1based = 1,
        },
        .{
            .layer_index = 1,
            .sublayer_start_index = 2,
            .sublayer_count = 3,
            .altitude_km = 1.5,
            .pressure_hpa = 700.0,
            .temperature_k = 260.0,
            .number_density_cm3 = 2.0e19,
            .continuum_cross_section_cm2_per_molecule = 0.0,
            .line_cross_section_cm2_per_molecule = 0.0,
            .line_mixing_cross_section_cm2_per_molecule = 0.0,
            .cia_optical_depth = 0.0,
            .d_cross_section_d_temperature_cm2_per_molecule_per_k = 0.0,
            .gas_optical_depth = 0.0,
            .aerosol_optical_depth = 0.0,
            .cloud_optical_depth = 0.0,
            .layer_single_scatter_albedo = 0.0,
            .depolarization_factor = 0.0,
            .optical_depth = 0.0,
            .top_altitude_km = 2.0,
            .bottom_altitude_km = 1.0,
            .top_pressure_hpa = 600.0,
            .bottom_pressure_hpa = 800.0,
            .interval_index_1based = 2,
        },
    };

    var sublayers = [_]State.PreparedSublayer{
        .{
            .parent_layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 0,
            .altitude_km = 0.0,
            .pressure_hpa = 1000.0,
            .temperature_k = 290.0,
            .number_density_cm3 = 1.1e19,
            .oxygen_number_density_cm3 = 0.0,
            .path_length_cm = 0.0,
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
            .aerosol_optical_depth = 0.0,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = zero_phase,
            .support_row_kind = .parity_boundary,
        },
        .{
            .parent_layer_index = 0,
            .sublayer_index = 1,
            .global_sublayer_index = 1,
            .altitude_km = 0.2,
            .pressure_hpa = 930.0,
            .temperature_k = 285.0,
            .number_density_cm3 = 2.0e19,
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
            .aerosol_optical_depth = 0.9,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = aerosol_phase,
            .support_row_kind = .parity_active,
        },
        .{
            .parent_layer_index = 0,
            .sublayer_index = 2,
            .global_sublayer_index = 2,
            .altitude_km = 1.0,
            .pressure_hpa = 800.0,
            .temperature_k = 270.0,
            .number_density_cm3 = 1.3e19,
            .oxygen_number_density_cm3 = 0.0,
            .path_length_cm = 0.0,
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
            .aerosol_optical_depth = 0.0,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = zero_phase,
            .support_row_kind = .parity_boundary,
        },
        .{
            .parent_layer_index = 1,
            .sublayer_index = 1,
            .global_sublayer_index = 3,
            .altitude_km = 1.8,
            .pressure_hpa = 680.0,
            .temperature_k = 255.0,
            .number_density_cm3 = 2.8e19,
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
            .aerosol_optical_depth = 0.4,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = aerosol_phase,
            .support_row_kind = .parity_active,
        },
        .{
            .parent_layer_index = 1,
            .sublayer_index = 2,
            .global_sublayer_index = 4,
            .altitude_km = 2.0,
            .pressure_hpa = 600.0,
            .temperature_k = 245.0,
            .number_density_cm3 = 1.5e19,
            .oxygen_number_density_cm3 = 0.0,
            .path_length_cm = 0.0,
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
            .aerosol_optical_depth = 0.0,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = zero_phase,
            .support_row_kind = .parity_boundary,
        },
    };

    var prepared = State.PreparedOpticalState{
        .layers = layers[0..],
        .sublayers = sublayers[0..],
        .continuum_points = &.{},
        .mean_cross_section_cm2_per_molecule = 0.0,
        .line_mean_cross_section_cm2_per_molecule = 0.0,
        .line_mixing_mean_cross_section_cm2_per_molecule = 0.0,
        .cia_mean_cross_section_cm5_per_molecule2 = 0.0,
        .effective_air_mass_factor = 1.0,
        .effective_single_scatter_albedo = 0.0,
        .effective_temperature_k = 270.0,
        .effective_pressure_hpa = 800.0,
        .column_density_factor = 0.0,
        .cia_pair_path_factor_cm5 = 0.0,
        .aerosol_reference_wavelength_nm = wavelength_nm,
        .aerosol_angstrom_exponent = 0.0,
        .cloud_reference_wavelength_nm = wavelength_nm,
        .cloud_angstrom_exponent = 0.0,
        .gas_optical_depth = 0.0,
        .cia_optical_depth = 0.0,
        .aerosol_optical_depth = 0.0,
        .cloud_optical_depth = 0.0,
        .d_optical_depth_d_temperature = 0.0,
        .depolarization_factor = 0.0,
        .total_optical_depth = 0.0,
        .interval_semantics = .explicit_pressure_bounds,
    };
    prepared.shared_rtm_geometry = try shared_geometry.buildSharedRtmGeometry(allocator, &prepared);
    defer prepared.shared_rtm_geometry.deinit(allocator);

    const scene = Scene{
        .atmosphere = .{
            .sublayer_divisions = 3,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 40.0,
            .viewing_zenith_deg = 20.0,
        },
        .spectral_grid = .{
            .start_nm = wavelength_nm,
            .end_nm = wavelength_nm,
            .sample_count = 1,
        },
        .aerosol = .{
            .asymmetry_factor = 0.65,
        },
    };

    var scratch: shared_geometry.GaussRuleScratch = .{};
    const geometry = prepared.shared_rtm_geometry;
    const support0 = shared_geometry.sharedSupportSlices(
        &prepared,
        sublayers[0..],
        @intCast(geometry.layers[0].support_start_index),
        @intCast(geometry.layers[0].support_count),
    );
    const subgrid0 = shared_carrier.evaluateSharedLayerOnSubgrid(
        &prepared,
        &scene,
        wavelength_nm,
        support0.sublayers,
        support0.strong_line_states,
        geometry.layers[0],
        &scratch,
    );
    const expected0 = shared_carrier.evaluateReducedLayerFromSupportRows(
        &prepared,
        &scene,
        wavelength_nm,
        support0.sublayers,
        support0.strong_line_states,
        geometry.layers[0],
    );
    try std.testing.expect(@abs(subgrid0.breakdown.totalOpticalDepth() - expected0.breakdown.totalOpticalDepth()) > 1.0e-3);

    const support1 = shared_geometry.sharedSupportSlices(
        &prepared,
        sublayers[0..],
        @intCast(geometry.layers[1].support_start_index),
        @intCast(geometry.layers[1].support_count),
    );
    const expected1 = shared_carrier.evaluateReducedLayerFromSupportRows(
        &prepared,
        &scene,
        wavelength_nm,
        support1.sublayers,
        support1.strong_line_states,
        geometry.layers[1],
    );

    var layer_inputs = [_]transport_common.LayerInput{ .{}, .{} };
    _ = fillForwardLayersAtWavelength(&prepared, &scene, wavelength_nm, layer_inputs[0..]);

    const expected_input0 = Evaluation.layerInputFromEvaluated(expected0);
    const expected_input1 = Evaluation.layerInputFromEvaluated(expected1);
    try std.testing.expectApproxEqAbs(expected_input0.optical_depth, layer_inputs[0].optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_input0.gas_scattering_optical_depth, layer_inputs[0].gas_scattering_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_input0.aerosol_optical_depth, layer_inputs[0].aerosol_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_input1.optical_depth, layer_inputs[1].optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_input1.gas_scattering_optical_depth, layer_inputs[1].gas_scattering_optical_depth, 1.0e-12);
    try std.testing.expectApproxEqAbs(expected_input1.aerosol_optical_depth, layer_inputs[1].aerosol_optical_depth, 1.0e-12);
}
