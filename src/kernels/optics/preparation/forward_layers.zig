const std = @import("std");
const Scene = @import("../../../model/Scene.zig").Scene;
const transport_common = @import("../../transport/common.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");
const PhaseFunctions = @import("../prepare/phase_functions.zig");
const State = @import("state.zig");
const Evaluation = @import("evaluation.zig");
const shared_geometry = @import("shared_geometry.zig");
const shared_carrier = @import("shared_carrier.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const OpticalDepthBreakdown = State.OpticalDepthBreakdown;

const centimeters_per_kilometer = 1.0e5;

fn transportAzimuthDifferenceRad(relative_azimuth_deg: f64) f64 {
    const transport_dphi_deg = @mod(180.0 - relative_azimuth_deg, 360.0);
    return std.math.degreesToRadians(transport_dphi_deg);
}

pub fn toForwardInput(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
) transport_common.ForwardInput {
    return toForwardInputWithLayers(prepared, scene, null);
}

pub fn toForwardInputWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    return toForwardInputAtWavelengthWithLayers(
        prepared,
        scene,
        (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        layer_inputs,
    );
}

pub fn toForwardInputAtWavelength(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
) transport_common.ForwardInput {
    return toForwardInputAtWavelengthWithLayers(prepared, scene, wavelength_nm, null);
}

pub fn toForwardInputAtWavelengthWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    const optical_depths = if (layer_inputs) |owned_layers|
        fillForwardLayersAtWavelength(prepared, scene, wavelength_nm, owned_layers)
    else
        prepared.opticalDepthBreakdownAtWavelength(wavelength_nm);
    const mu0 = scene.geometry.solarCosineAtAltitude(0.0);
    const muv = scene.geometry.viewingCosineAtAltitude(0.0);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const spectral_weight = if (scene.spectral_grid.sample_count <= 1)
        @max(span_nm, 1.0e-6)
    else
        span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));
    return .{
        .wavelength_nm = wavelength_nm,
        .spectral_weight = @max(spectral_weight, 1.0e-6),
        .air_mass_factor = prepared.effective_air_mass_factor,
        .mu0 = mu0,
        .muv = muv,
        .relative_azimuth_rad = transportAzimuthDifferenceRad(scene.geometry.relative_azimuth_deg),
        .surface_albedo = std.math.clamp(scene.surface.albedo, 0.0, 1.0),
        .gas_absorption_optical_depth = optical_depths.gas_absorption_optical_depth,
        .gas_scattering_optical_depth = optical_depths.gas_scattering_optical_depth,
        .cia_optical_depth = optical_depths.cia_optical_depth,
        .aerosol_optical_depth = optical_depths.aerosol_optical_depth,
        .aerosol_scattering_optical_depth = optical_depths.aerosol_scattering_optical_depth,
        .cloud_optical_depth = optical_depths.cloud_optical_depth,
        .cloud_scattering_optical_depth = optical_depths.cloud_scattering_optical_depth,
        .optical_depth = optical_depths.totalOpticalDepth(),
        .single_scatter_albedo = if (optical_depths.totalOpticalDepth() > 0.0)
            optical_depths.singleScatterAlbedo()
        else
            prepared.effective_single_scatter_albedo,
        .layers = if (layer_inputs) |owned_layers| owned_layers else &.{},
    };
}

pub fn fillForwardLayersAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
) OpticalDepthBreakdown {
    if (layer_inputs.len == 0) return self.opticalDepthBreakdownAtWavelength(wavelength_nm);

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                var totals: OpticalDepthBreakdown = .{};
                var subgrid_rule_scratch: shared_geometry.GaussRuleScratch = .{};
                for (geometry.layers, layer_inputs) |layer_geometry, *layer_input| {
                    const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                    const support_count: usize = @intCast(layer_geometry.support_count);
                    const support = shared_geometry.sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );

                    const evaluated = shared_carrier.evaluateSharedLayerOnSubgrid(
                        self,
                        scene,
                        wavelength_nm,
                        support.sublayers,
                        support.strong_line_states,
                        layer_geometry,
                        &subgrid_rule_scratch,
                    );
                    layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
                    Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
                }
                return totals;
            }

            var totals: OpticalDepthBreakdown = .{};
            var interval_rule_scratch: shared_geometry.GaussRuleScratch = .{};

            for (self.layers) |layer| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) continue;

                const interval = shared_geometry.sharedRtmInterval(self, sublayers, layer);
                const level_node_count = count - 1;
                const level_rule = if (level_node_count > 0)
                    shared_geometry.resolveGaussRule(level_node_count, &interval_rule_scratch)
                else
                    null;

                for (0..count) |local_layer_index| {
                    const lower_altitude_km = if (local_layer_index == 0)
                        interval.lower_altitude_km
                    else
                        shared_geometry.intervalAltitudeAtNode(
                            interval.lower_altitude_km,
                            interval.upper_altitude_km,
                            level_rule.?.nodes[local_layer_index - 1],
                        );
                    const upper_altitude_km = if (local_layer_index + 1 == count)
                        interval.upper_altitude_km
                    else
                        shared_geometry.intervalAltitudeAtNode(
                            interval.lower_altitude_km,
                            interval.upper_altitude_km,
                            level_rule.?.nodes[local_layer_index],
                        );
                    const midpoint_altitude_km = 0.5 * (lower_altitude_km + upper_altitude_km);
                    const evaluated = shared_carrier.evaluateSharedLayerOnSubgrid(
                        self,
                        scene,
                        wavelength_nm,
                        interval.support_sublayers,
                        interval.strong_line_states,
                        .{
                            .lower_altitude_km = lower_altitude_km,
                            .upper_altitude_km = upper_altitude_km,
                            .midpoint_altitude_km = midpoint_altitude_km,
                            .thickness_km = @max(upper_altitude_km - lower_altitude_km, 0.0),
                            .support_start_index = @intCast(start_index),
                            .support_count = @intCast(count),
                        },
                        &interval_rule_scratch,
                    );
                    layer_inputs[start_index + local_layer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                    Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
                }
            }
            return totals;
        }

        if (layer_inputs.len == sublayers.len) {
            var totals: OpticalDepthBreakdown = .{};
            for (sublayers, 0..) |sublayer, sublayer_index| {
                const evaluated = self.evaluateLayerAtWavelength(
                    scene,
                    sublayer.altitude_km,
                    wavelength_nm,
                    sublayer_index,
                    sublayers[sublayer_index .. sublayer_index + 1],
                    if (self.strong_line_states) |states| states[sublayer_index .. sublayer_index + 1] else null,
                );
                layer_inputs[sublayer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
            }
            return totals;
        }

        var totals: OpticalDepthBreakdown = .{};
        for (self.layers, layer_inputs) |layer, *layer_input| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const evaluated = self.evaluateLayerAtWavelength(
                scene,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                if (self.strong_line_states) |states| states[start_index..end_index] else null,
            );
            layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
            Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
        }
        return totals;
    }

    const particle_single_scatter_albedos = self.resolvedParticleSingleScatterAlbedos();

    var totals: OpticalDepthBreakdown = .{};
    for (self.layers, layer_inputs) |layer, *layer_input| {
        const aerosol_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
            layer.aerosol_optical_depth,
            layer.aerosol_base_optical_depth,
            self.aerosol_reference_wavelength_nm,
            self.aerosol_angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const cloud_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
            layer.cloud_optical_depth,
            layer.cloud_base_optical_depth,
            self.cloud_reference_wavelength_nm,
            self.cloud_angstrom_exponent,
            self.cloud_fraction_control,
            wavelength_nm,
        );
        const gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
        const gas_absorption_optical_depth = @max(
            layer.gas_optical_depth - gas_scattering_optical_depth,
            0.0,
        );
        const aerosol_scattering_optical_depth =
            aerosol_optical_depth * particle_single_scatter_albedos.aerosol;
        const cloud_scattering_optical_depth =
            cloud_optical_depth * particle_single_scatter_albedos.cloud;
        const optical_depth =
            gas_absorption_optical_depth +
            gas_scattering_optical_depth +
            layer.cia_optical_depth +
            aerosol_optical_depth +
            cloud_optical_depth;
        const scattering_optical_depth =
            gas_scattering_optical_depth +
            aerosol_scattering_optical_depth +
            cloud_scattering_optical_depth;
        layer_input.* = .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = layer.cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_scattering_optical_depth,
            .cloud_optical_depth = cloud_optical_depth,
            .cloud_scattering_optical_depth = cloud_scattering_optical_depth,
            .optical_depth = optical_depth,
            .scattering_optical_depth = scattering_optical_depth,
            .single_scatter_albedo = if (optical_depth > 0.0)
                std.math.clamp(scattering_optical_depth / optical_depth, 0.0, 1.0)
            else
                0.0,
            .solar_mu = scene.geometry.solarCosineAtAltitude(layer.altitude_km),
            .view_mu = scene.geometry.viewingCosineAtAltitude(layer.altitude_km),
            .phase_coefficients = PhaseFunctions.hgPhaseCoefficients(scene.aerosol.asymmetry_factor),
        };
        totals.gas_absorption_optical_depth += gas_absorption_optical_depth;
        totals.gas_scattering_optical_depth += gas_scattering_optical_depth;
        totals.cia_optical_depth += layer.cia_optical_depth;
        totals.aerosol_optical_depth += aerosol_optical_depth;
        totals.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
        totals.cloud_optical_depth += cloud_optical_depth;
        totals.cloud_scattering_optical_depth += cloud_scattering_optical_depth;
    }
    return totals;
}
