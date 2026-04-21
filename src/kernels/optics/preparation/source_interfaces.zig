const std = @import("std");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const Rayleigh = @import("../../../model/reference/rayleigh.zig");

const PreparedOpticalState = State.PreparedOpticalState;

pub fn fillSourceInterfacesAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    source_interfaces: []transport_common.SourceInterfaceInput,
) void {
    if (layer_inputs.len == 0 or source_interfaces.len != layer_inputs.len + 1) return;

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                for (source_interfaces, geometry.levels) |*source_interface, level_geometry| {
                    const support_row_index: usize = @intCast(level_geometry.support_row_index);
                    if (level_geometry.weight_km > 0.0) {
                        const strong_line_state = if (self.strong_line_states) |states|
                            if (support_row_index < states.len) &states[support_row_index] else null
                        else
                            null;
                        const carrier = carrier_eval.sharedOpticalCarrierAtSupportRow(
                            self,
                            wavelength_nm,
                            sublayers[support_row_index],
                            support_row_index,
                            strong_line_state,
                        );
                        source_interface.* = .{
                            .source_weight = 0.0,
                            .rtm_weight = level_geometry.weight_km,
                            .gas_ksca = carrier.gas_scattering_optical_depth_per_km,
                            .particle_ksca_above = carrier.aerosol_scattering_optical_depth_per_km + carrier.cloud_scattering_optical_depth_per_km,
                            .particle_ksca_below = carrier.aerosol_scattering_optical_depth_per_km + carrier.cloud_scattering_optical_depth_per_km,
                            .ksca_above = carrier.totalScatteringOpticalDepthPerKm(),
                            .ksca_below = carrier.totalScatteringOpticalDepthPerKm(),
                            .gas_phase_coefficients = @import("../prepare/phase_functions.zig").gasPhaseCoefficients(),
                            .phase_coefficients_above = carrier.phase_coefficients,
                            .phase_coefficients_below = carrier.phase_coefficients,
                        };
                    } else {
                        const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevel(
                            self,
                            wavelength_nm,
                            sublayers,
                            if (self.strong_line_states) |states| states else null,
                            level_geometry,
                        );
                        source_interface.* = .{
                            .source_weight = 0.0,
                            .rtm_weight = level_geometry.weight_km,
                            .gas_ksca = boundary_carrier.gas_scattering_optical_depth_per_km,
                            .particle_ksca_above = boundary_carrier.particle_scattering_optical_depth_above_per_km,
                            .particle_ksca_below = boundary_carrier.particle_scattering_optical_depth_below_per_km,
                            .ksca_above = boundary_carrier.ksca_above,
                            .ksca_below = boundary_carrier.ksca_below,
                            .gas_phase_coefficients = boundary_carrier.gas_phase_coefficients,
                            .phase_coefficients_above = boundary_carrier.phase_coefficients_above,
                            .phase_coefficients_below = boundary_carrier.phase_coefficients_below,
                        };
                    }
                }
                return;
            }
            for (source_interfaces) |*source_interface| source_interface.* = .{};
            return;
        }
    }

    transport_common.fillSourceInterfacesFromLayers(layer_inputs, source_interfaces);

    if (self.sublayers) |sublayers| {
        if (layer_inputs.len == sublayers.len) {
            for (1..layer_inputs.len) |ilevel| {
                const sublayer = sublayers[ilevel];
                const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
                const rtm_weight = @max(sublayer.path_length_cm / 1.0e5, 0.0);
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .rtm_weight = rtm_weight,
                    .ksca_above = if (rtm_weight > 0.0)
                        scattering_optical_depth / rtm_weight
                    else
                        0.0,
                    .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                };
            }
            return;
        }

        if (layer_inputs.len == 1) {
            return;
        }

        if (self.layers.len != layer_inputs.len) return;
        for (1..layer_inputs.len) |ilevel| {
            const layer = self.layers[ilevel];
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const sublayer_count: usize = @intCast(layer.sublayer_count);
            if (sublayer_count == 0) {
                source_interfaces[ilevel] = .{
                    .source_weight = 0.0,
                    .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
                };
                continue;
            }
            const stop_index = start_index + sublayer_count;
            var rtm_weight: f64 = 0.0;
            for (sublayers[start_index..stop_index]) |sublayer| {
                rtm_weight += @max(sublayer.path_length_cm / 1.0e5, 0.0);
            }
            const scattering_optical_depth = @max(layer_inputs[ilevel].scattering_optical_depth, 0.0);
            source_interfaces[ilevel] = .{
                .source_weight = 0.0,
                .rtm_weight = rtm_weight,
                .ksca_above = if (rtm_weight > 0.0)
                    scattering_optical_depth / rtm_weight
                else
                    0.0,
                .phase_coefficients_above = layer_inputs[ilevel].phase_coefficients,
            };
        }
        return;
    }
}

test "shared RTM boundaries keep boundary gas and explicit rows above and below" {
    const allocator = std.testing.allocator;
    const wavelength_nm = 760.0;
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
    const zero_phase = PhaseFunctions.zeroPhaseCoefficients();
    const aerosol_phase = PhaseFunctions.hgPhaseCoefficients(0.65);
    const cloud_phase = PhaseFunctions.hgPhaseCoefficients(0.25);
    var sublayers = [_]State.PreparedSublayer{
        .{
            .parent_layer_index = 0,
            .sublayer_index = 0,
            .global_sublayer_index = 0,
            .altitude_km = 0.0,
            .pressure_hpa = 1000.0,
            .temperature_k = 290.0,
            .number_density_cm3 = 1.0e19,
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
            .cloud_single_scatter_albedo = 0.5,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = cloud_phase,
            .combined_phase_coefficients = zero_phase,
        },
        .{
            .parent_layer_index = 0,
            .sublayer_index = 1,
            .global_sublayer_index = 1,
            .altitude_km = 0.5,
            .pressure_hpa = 900.0,
            .temperature_k = 280.0,
            .number_density_cm3 = 1.5e19,
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
            .cloud_phase_coefficients = cloud_phase,
            .combined_phase_coefficients = aerosol_phase,
        },
        .{
            .parent_layer_index = 0,
            .sublayer_index = 2,
            .global_sublayer_index = 2,
            .altitude_km = 1.0,
            .pressure_hpa = 800.0,
            .temperature_k = 270.0,
            .number_density_cm3 = 2.0e19,
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
            .cloud_single_scatter_albedo = 0.5,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = cloud_phase,
            .combined_phase_coefficients = zero_phase,
        },
        .{
            .parent_layer_index = 1,
            .sublayer_index = 1,
            .global_sublayer_index = 3,
            .altitude_km = 1.5,
            .pressure_hpa = 700.0,
            .temperature_k = 260.0,
            .number_density_cm3 = 2.5e19,
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
            .aerosol_optical_depth = 0.8,
            .cloud_optical_depth = 0.0,
            .aerosol_single_scatter_albedo = 0.5,
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = cloud_phase,
            .combined_phase_coefficients = aerosol_phase,
        },
        .{
            .parent_layer_index = 1,
            .sublayer_index = 2,
            .global_sublayer_index = 4,
            .altitude_km = 2.0,
            .pressure_hpa = 600.0,
            .temperature_k = 250.0,
            .number_density_cm3 = 3.0e19,
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
            .cloud_single_scatter_albedo = 0.5,
            .aerosol_phase_coefficients = aerosol_phase,
            .cloud_phase_coefficients = cloud_phase,
            .combined_phase_coefficients = zero_phase,
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

    const layer_inputs = [_]transport_common.LayerInput{ .{}, .{} };
    var source_interfaces: [3]transport_common.SourceInterfaceInput = undefined;
    fillSourceInterfacesAtWavelengthWithLayers(&prepared, wavelength_nm, &layer_inputs, &source_interfaces);

    const gas_bottom = Rayleigh.crossSectionCm2(wavelength_nm) * sublayers[0].number_density_cm3 * 1.0e5;
    const gas_middle = Rayleigh.crossSectionCm2(wavelength_nm) * sublayers[2].number_density_cm3 * 1.0e5;
    const gas_top = Rayleigh.crossSectionCm2(wavelength_nm) * sublayers[4].number_density_cm3 * 1.0e5;

    try std.testing.expectApproxEqAbs(gas_bottom, source_interfaces[0].gas_ksca, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.2, source_interfaces[0].particle_ksca_above, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.0, source_interfaces[0].particle_ksca_below, 1.0e-12);
    try std.testing.expectApproxEqAbs(gas_middle, source_interfaces[1].gas_ksca, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.2, source_interfaces[1].particle_ksca_below, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.4, source_interfaces[1].particle_ksca_above, 1.0e-12);
    try std.testing.expectApproxEqAbs(gas_top, source_interfaces[2].gas_ksca, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.4, source_interfaces[2].particle_ksca_below, 1.0e-12);
    try std.testing.expectApproxEqAbs(0.0, source_interfaces[2].particle_ksca_above, 1.0e-12);

    try std.testing.expectApproxEqAbs(gas_middle + 0.4, source_interfaces[1].ksca_above, 1.0e-12);
    try std.testing.expectApproxEqAbs(gas_middle + 0.2, source_interfaces[1].ksca_below, 1.0e-12);
    try std.testing.expect(@abs(source_interfaces[1].gas_ksca -
        (Rayleigh.crossSectionCm2(wavelength_nm) * sublayers[3].number_density_cm3 * 1.0e5)) > 1.0e-6);
}
