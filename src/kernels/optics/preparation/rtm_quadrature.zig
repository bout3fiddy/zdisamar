const std = @import("std");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const shared_geometry = @import("shared_geometry.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const LevelCarrier = struct {
    ksca: f64,
    phase_coefficients: [PhaseFunctions.phase_coefficient_count]f64,
};

pub fn fillRtmQuadratureAtWavelengthWithLayers(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
) bool {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
        self,
        wavelength_nm,
        layer_inputs,
        rtm_levels,
        &profile_cache,
    );
}

pub fn fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
    self: *const PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []const transport_common.LayerInput,
    rtm_levels: []transport_common.RtmQuadratureLevel,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) bool {
    const sublayers = self.sublayers orelse return false;
    if (rtm_levels.len != layer_inputs.len + 1) return false;

    if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
            for (rtm_levels, geometry.levels) |*rtm_level, level_geometry| {
                const level_carrier: LevelCarrier = if (level_geometry.weight_km > 0.0) blk: {
                    const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                        profile_cache,
                    );
                    break :blk LevelCarrier{
                        .ksca = boundary_carrier.ksca_above,
                        .phase_coefficients = boundary_carrier.phase_coefficients_above,
                    };
                } else blk: {
                    const boundary_carrier = carrier_eval.sharedBoundaryCarrierAtLevelWithSpectroscopyCache(
                        self,
                        wavelength_nm,
                        sublayers,
                        if (self.strong_line_states) |states| states else null,
                        level_geometry,
                        profile_cache,
                    );
                    break :blk LevelCarrier{
                        .ksca = boundary_carrier.ksca_above,
                        .phase_coefficients = boundary_carrier.phase_coefficients_above,
                    };
                };
                rtm_level.* = .{
                    .altitude_km = level_geometry.altitude_km,
                    .weight = level_geometry.weight_km,
                    .ksca = level_carrier.ksca,
                    .phase_coefficients = level_carrier.phase_coefficients,
                };
            }

            // PARITY:
            //   DISAMAR's integrated-source reflectance uses RTMweight(level)
            //   multiplied by the scattering carrier sampled at that coarse
            //   RTM level. The source quadrature is not renormalized back to
            //   the sublayer-integrated layer scattering totals.
            var has_active_quadrature = false;
            for (rtm_levels) |rtm_level| {
                if (rtm_level.weightedScattering() > 0.0) {
                    has_active_quadrature = true;
                    break;
                }
            }
            return has_active_quadrature;
        }

        for (rtm_levels) |*rtm_level| {
            rtm_level.* = .{
                .altitude_km = 0.0,
                .weight = 0.0,
                .ksca = 0.0,
                .phase_coefficients = PhaseFunctions.zeroPhaseCoefficients(),
            };
        }

        return false;
    }

    if (layer_inputs.len != sublayers.len) return false;

    for (rtm_levels, 0..) |*rtm_level, level| {
        rtm_level.* = .{
            .altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, level),
            .weight = 0.0,
            .ksca = 0.0,
            .phase_coefficients = PhaseFunctions.zeroPhaseCoefficients(),
        };
    }

    var has_active_quadrature = false;
    for (self.layers) |layer| {
        const start: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count == 0) continue;
        const stop = start + count;
        if (stop >= rtm_levels.len) return false;

        const active_count = if (count > 0) count - 1 else 0;
        if (active_count == 0) continue;
        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        const lower_altitude_km = rtm_levels[start].altitude_km;
        const upper_altitude_km = rtm_levels[stop].altitude_km;
        const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);

        var total_span_km: f64 = 0.0;
        var total_scattering: f64 = 0.0;
        for (sublayers[start..stop], layer_inputs[start..stop]) |sublayer, layer_input| {
            total_span_km += @max(sublayer.path_length_cm / 1.0e5, 0.0);
            total_scattering += @max(layer_input.scattering_optical_depth, 0.0);
        }
        if (total_span_km <= 0.0) continue;

        var raw_scattering_sum: f64 = 0.0;
        for (0..active_count) |node_index| {
            const level = start + 1 + node_index;
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = lower_altitude_km + normalized_position * altitude_span_km;
            const carrier = carrier_eval.quadratureCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                sublayers[start..stop],
                if (self.strong_line_states) |states| states[start..stop] else null,
                node_altitude_km,
                profile_cache,
            );
            rtm_levels[level].altitude_km = node_altitude_km;
            rtm_levels[level].weight = 0.5 * rule.weights[node_index] * total_span_km;
            rtm_levels[level].ksca = carrier.ksca;
            rtm_levels[level].phase_coefficients = carrier.phase_coefficients;
            raw_scattering_sum += rtm_levels[level].weightedScattering();
        }

        if (total_scattering <= 0.0) {
            for (start + 1..stop) |level| {
                rtm_levels[level].ksca = 0.0;
            }
            continue;
        }

        if (raw_scattering_sum > 0.0) {
            const scale = total_scattering / raw_scattering_sum;
            for (start + 1..stop) |level| {
                rtm_levels[level].ksca *= scale;
            }
            has_active_quadrature = true;
        } else {
            for (start + 1..stop) |level| {
                rtm_levels[level].weight = 0.0;
                rtm_levels[level].ksca = 0.0;
            }
        }
    }

    return has_active_quadrature;
}

test "shared RTM quadrature preserves direct coarse-level source weights" {
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
            .layer_single_scatter_albedo = 0.0,
            .depolarization_factor = 0.0,
            .optical_depth = 0.0,
            .top_altitude_km = 2.0,
            .bottom_altitude_km = 1.0,
            .top_pressure_hpa = 600.0,
            .bottom_pressure_hpa = 800.0,
            .interval_index_1based = 1,
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
    const level_geometry = prepared.shared_rtm_geometry.levels[1];
    const expected_boundary = carrier_eval.sharedBoundaryCarrierAtLevel(
        &prepared,
        wavelength_nm,
        sublayers[0..],
        null,
        level_geometry,
    );

    const layer_inputs = [_]transport_common.LayerInput{
        .{ .scattering_optical_depth = 0.25 },
        .{ .scattering_optical_depth = 0.75 },
    };
    var rtm_levels = [_]transport_common.RtmQuadratureLevel{ .{}, .{}, .{} };

    try std.testing.expect(fillRtmQuadratureAtWavelengthWithLayers(
        &prepared,
        wavelength_nm,
        layer_inputs[0..],
        rtm_levels[0..],
    ));

    const weighted_sum = rtm_levels[1].weightedScattering();
    try std.testing.expectApproxEqAbs(level_geometry.weight_km * expected_boundary.ksca_above, weighted_sum, 1.0e-12);
}

test "shared RTM quadrature weighted levels use above-sided phase carriers" {
    const allocator = std.testing.allocator;
    const wavelength_nm = 760.0;
    const zero_phase = PhaseFunctions.zeroPhaseCoefficients();
    const aerosol_phase_below = PhaseFunctions.hgPhaseCoefficients(0.2);
    const aerosol_phase_above = PhaseFunctions.hgPhaseCoefficients(0.8);

    var layers = [_]State.PreparedLayer{
        .{
            .layer_index = 0,
            .sublayer_start_index = 0,
            .sublayer_count = 3,
            .altitude_km = 0.5,
            .pressure_hpa = 900.0,
            .temperature_k = 280.0,
            .number_density_cm3 = 1.0e19,
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
            .layer_single_scatter_albedo = 0.0,
            .depolarization_factor = 0.0,
            .optical_depth = 0.0,
            .top_altitude_km = 2.0,
            .bottom_altitude_km = 1.0,
            .top_pressure_hpa = 600.0,
            .bottom_pressure_hpa = 800.0,
            .interval_index_1based = 1,
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
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase_below,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = zero_phase,
            .support_row_kind = .parity_boundary,
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
            .aerosol_phase_coefficients = aerosol_phase_below,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = aerosol_phase_below,
            .support_row_kind = .parity_active,
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
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase_below,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = zero_phase,
            .support_row_kind = .parity_boundary,
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
            .aerosol_phase_coefficients = aerosol_phase_above,
            .cloud_phase_coefficients = zero_phase,
            .combined_phase_coefficients = aerosol_phase_above,
            .support_row_kind = .parity_active,
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
            .cloud_single_scatter_albedo = 0.0,
            .aerosol_phase_coefficients = aerosol_phase_above,
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

    const level_geometry = prepared.shared_rtm_geometry.levels[1];
    try std.testing.expect(level_geometry.weight_km > 0.0);
    const expected_boundary = carrier_eval.sharedBoundaryCarrierAtLevel(
        &prepared,
        wavelength_nm,
        sublayers[0..],
        null,
        level_geometry,
    );

    const layer_inputs = [_]transport_common.LayerInput{
        .{ .scattering_optical_depth = 0.25 },
        .{ .scattering_optical_depth = 0.75 },
    };
    var rtm_levels = [_]transport_common.RtmQuadratureLevel{ .{}, .{}, .{} };

    try std.testing.expect(fillRtmQuadratureAtWavelengthWithLayers(
        &prepared,
        wavelength_nm,
        layer_inputs[0..],
        rtm_levels[0..],
    ));

    try std.testing.expectApproxEqAbs(expected_boundary.phase_coefficients_above[1], rtm_levels[1].phase_coefficients[1], 1.0e-12);
    try std.testing.expect(@abs(expected_boundary.phase_coefficients_below[1] - rtm_levels[1].phase_coefficients[1]) > 1.0e-6);
}
