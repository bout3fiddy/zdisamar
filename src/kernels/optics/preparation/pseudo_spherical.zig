const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const transport_common = @import("../../transport/common.zig");
const State = @import("state.zig");
const shared_geometry = @import("shared_geometry.zig");
const shared_carrier = @import("shared_carrier.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");

const PreparedOpticalState = State.PreparedOpticalState;

const PseudoSphericalInterval = struct {
    support_sublayers: []const State.PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
    lower_altitude_km: f64,
    upper_altitude_km: f64,
};

pub fn fillSharedPseudoSphericalGridFromLayerInputs(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: []const transport_common.LayerInput,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    const geometry = shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len) orelse return false;
    const subgrid_divisions = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
    const sample_count = layer_inputs.len * subgrid_divisions;
    if (attenuation_samples.len < sample_count or
        level_sample_starts.len != layer_inputs.len + 1 or
        level_altitudes_km.len != layer_inputs.len + 1)
    {
        return false;
    }

    for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
        altitude_km.* = level_geometry.altitude_km;
    }

    var sample_index: usize = 0;
    for (geometry.layers, layer_inputs, 0..) |layer_geometry, layer_input, layer_index| {
        level_sample_starts[layer_index] = sample_index;
        if (subgrid_divisions <= 1) {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.midpoint_altitude_km,
                .thickness_km = layer_geometry.thickness_km,
                .optical_depth = layer_input.optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = layer_input.optical_depth };
            }
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        if (sample_index < attenuation_layers.len) attenuation_layers[sample_index] = .{};
        sample_index += 1;

        attenuation_samples[sample_index] = .{
            .altitude_km = layer_geometry.midpoint_altitude_km,
            .thickness_km = layer_geometry.thickness_km,
            .optical_depth = layer_input.optical_depth,
        };
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{ .optical_depth = layer_input.optical_depth };
        }
        sample_index += 1;

        for (2..subgrid_divisions) |_| {
            attenuation_samples[sample_index] = .{
                .altitude_km = layer_geometry.upper_altitude_km,
                .thickness_km = 0.0,
                .optical_depth = 0.0,
            };
            if (sample_index < attenuation_layers.len) attenuation_layers[sample_index] = .{};
            sample_index += 1;
        }
    }

    level_sample_starts[layer_inputs.len] = sample_index;
    return true;
}

pub fn fillPseudoSphericalGridAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) bool {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        solver_layer_count,
        attenuation_layers,
        attenuation_samples,
        level_sample_starts,
        level_altitudes_km,
        &profile_cache,
    );
}

pub fn fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    solver_layer_count: usize,
    attenuation_layers: []transport_common.LayerInput,
    attenuation_samples: []transport_common.PseudoSphericalSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) bool {
    const sublayers = self.sublayers orelse return false;
    const subgrid_divisions = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
    const sample_count = solver_layer_count * subgrid_divisions;
    if (attenuation_samples.len < sample_count or
        level_sample_starts.len != solver_layer_count + 1 or
        level_altitudes_km.len != solver_layer_count + 1)
    {
        return false;
    }

    if (solver_layer_count != sublayers.len and solver_layer_count != self.layers.len) {
        return false;
    }
    if (shared_geometry.usesSharedRtmGrid(self, solver_layer_count)) {
        if (shared_geometry.cachedSharedRtmGeometry(self, solver_layer_count)) |geometry| {
            for (level_altitudes_km, geometry.levels) |*altitude_km, level_geometry| {
                altitude_km.* = level_geometry.altitude_km;
            }

            var sample_index: usize = 0;
            for (geometry.layers, 0..) |layer_geometry, layer_index| {
                level_sample_starts[layer_index] = sample_index;
                const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                const support_count: usize = @intCast(layer_geometry.support_count);
                const support = shared_geometry.sharedSupportSlices(
                    self,
                    sublayers,
                    support_start_index,
                    support_count,
                );
                sample_index = shared_carrier.fillSharedPseudoSphericalSamplesFromSupportRows(
                    self,
                    wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    attenuation_layers,
                    attenuation_samples,
                    sample_index,
                    profile_cache,
                );
            }

            level_sample_starts[solver_layer_count] = sample_index;
            return true;
        }
        return false;
    }

    var sample_index: usize = 0;
    if (solver_layer_count == sublayers.len) {
        level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count + 1) |ilevel| {
            level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, ilevel);
        }
    } else {
        level_altitudes_km[0] = shared_geometry.levelAltitudeFromSublayers(sublayers, 0);
        for (1..solver_layer_count) |ilevel| {
            const start_index: usize = @intCast(self.layers[ilevel].sublayer_start_index);
            level_altitudes_km[ilevel] = shared_geometry.levelAltitudeFromSublayers(sublayers, start_index);
        }
        level_altitudes_km[solver_layer_count] = shared_geometry.levelAltitudeFromSublayers(sublayers, sublayers.len);
    }

    for (0..solver_layer_count) |solver_level| {
        const interval = if (solver_layer_count == sublayers.len)
            PseudoSphericalInterval{
                .support_sublayers = sublayers[solver_level .. solver_level + 1],
                .strong_line_states = if (self.strong_line_states) |states|
                    states[solver_level .. solver_level + 1]
                else
                    null,
                .lower_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level),
                .upper_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, solver_level + 1),
            }
        else blk: {
            const layer = self.layers[solver_level];
            const start: usize = @intCast(layer.sublayer_start_index);
            const count: usize = @intCast(layer.sublayer_count);
            if (count == 0) return false;
            const stop = start + count;
            break :blk PseudoSphericalInterval{
                .support_sublayers = sublayers[start..stop],
                .strong_line_states = if (self.strong_line_states) |states|
                    states[start..stop]
                else
                    null,
                .lower_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, start),
                .upper_altitude_km = shared_geometry.levelAltitudeFromSublayers(sublayers, stop),
            };
        };
        const altitude_span_km = @max(interval.upper_altitude_km - interval.lower_altitude_km, 0.0);
        const active_count = subgrid_divisions - 1;

        level_sample_starts[solver_level] = sample_index;
        if (active_count == 0) {
            const sample_altitude_km = if (altitude_span_km > 0.0)
                interval.lower_altitude_km + 0.5 * altitude_span_km
            else
                interval.lower_altitude_km;
            const optical_depth = carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                sample_altitude_km,
                profile_cache,
            ).totalOpticalDepthPerKm() * altitude_span_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = sample_altitude_km,
                .thickness_km = altitude_span_km,
                .optical_depth = optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
            }
            sample_index += 1;
            continue;
        }

        attenuation_samples[sample_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .thickness_km = 0.0,
            .optical_depth = 0.0,
        };
        if (sample_index < attenuation_layers.len) {
            attenuation_layers[sample_index] = .{};
        }
        sample_index += 1;

        if (altitude_span_km <= 0.0) {
            for (0..active_count) |_| {
                attenuation_samples[sample_index] = .{
                    .altitude_km = interval.lower_altitude_km,
                    .thickness_km = 0.0,
                    .optical_depth = 0.0,
                };
                if (sample_index < attenuation_layers.len) {
                    attenuation_layers[sample_index] = .{};
                }
                sample_index += 1;
            }
            continue;
        }

        const rule = gauss_legendre.rule(@intCast(active_count)) catch return false;
        for (0..active_count) |node_index| {
            const normalized_position = 0.5 * (rule.nodes[node_index] + 1.0);
            const node_altitude_km = interval.lower_altitude_km + normalized_position * altitude_span_km;
            const weight_km = 0.5 * rule.weights[node_index] * altitude_span_km;
            const optical_depth = carrier_eval.sharedOpticalCarrierAtAltitudeWithSpectroscopyCache(
                self,
                wavelength_nm,
                interval.support_sublayers,
                interval.strong_line_states,
                node_altitude_km,
                profile_cache,
            ).totalOpticalDepthPerKm() * weight_km;
            attenuation_samples[sample_index] = .{
                .altitude_km = node_altitude_km,
                .thickness_km = weight_km,
                .optical_depth = optical_depth,
            };
            if (sample_index < attenuation_layers.len) {
                attenuation_layers[sample_index] = .{ .optical_depth = optical_depth };
            }
            sample_index += 1;
        }
    }

    level_sample_starts[solver_layer_count] = sample_index;
    return true;
}

test "shared pseudo-spherical grid uses altitude-resolved subgrid samples" {
    const allocator = std.testing.allocator;
    const wavelength_nm = 760.0;
    const zero_phase = @import("../prepare/phase_functions.zig").zeroPhaseCoefficients();
    const aerosol_phase = @import("../prepare/phase_functions.zig").hgPhaseCoefficients(0.65);

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
    };

    var attenuation_layers = [_]transport_common.LayerInput{.{}} ** 6;
    var attenuation_samples = [_]transport_common.PseudoSphericalSample{.{}} ** 6;
    var level_sample_starts = [_]usize{0} ** 3;
    var level_altitudes_km = [_]f64{0.0} ** 3;

    try std.testing.expect(fillPseudoSphericalGridAtWavelength(
        &prepared,
        &scene,
        wavelength_nm,
        layers.len,
        attenuation_layers[0..],
        attenuation_samples[0..],
        level_sample_starts[0..],
        level_altitudes_km[0..],
    ));

    try std.testing.expectEqual(@as(usize, 6), level_sample_starts[2]);

    var expected_layers = [_]transport_common.LayerInput{.{}} ** 6;
    var expected_samples = [_]transport_common.PseudoSphericalSample{.{}} ** 6;
    var expected_starts = [_]usize{0} ** 3;
    const expected_altitudes = blk: {
        var altitudes = [_]f64{0.0} ** 3;
        for (altitudes[0..], prepared.shared_rtm_geometry.levels) |*altitude_km, level_geometry| {
            altitude_km.* = level_geometry.altitude_km;
        }
        break :blk altitudes;
    };

    var scratch: shared_geometry.GaussRuleScratch = .{};
    var sample_index: usize = 0;
    for (prepared.shared_rtm_geometry.layers, 0..) |layer_geometry, layer_index| {
        expected_starts[layer_index] = sample_index;
        const support = shared_geometry.sharedSupportSlices(
            &prepared,
            sublayers[0..],
            @intCast(layer_geometry.support_start_index),
            @intCast(layer_geometry.support_count),
        );
        sample_index = shared_carrier.fillSharedPseudoSphericalSamplesOnSubgrid(
            &prepared,
            &scene,
            wavelength_nm,
            support.sublayers,
            support.strong_line_states,
            layer_geometry,
            expected_layers[0..],
            expected_samples[0..],
            sample_index,
            &scratch,
        );
    }
    expected_starts[layers.len] = sample_index;

    try std.testing.expectEqualSlices(usize, expected_starts[0..], level_sample_starts[0..]);
    for (expected_altitudes, level_altitudes_km) |expected, actual| {
        try std.testing.expectApproxEqAbs(expected, actual, 1.0e-12);
    }
    for (0..sample_index) |index| {
        try std.testing.expectApproxEqAbs(expected_samples[index].altitude_km, attenuation_samples[index].altitude_km, 1.0e-12);
        try std.testing.expectApproxEqAbs(expected_samples[index].thickness_km, attenuation_samples[index].thickness_km, 1.0e-12);
        try std.testing.expectApproxEqAbs(expected_samples[index].optical_depth, attenuation_samples[index].optical_depth, 1.0e-12);
    }
}
