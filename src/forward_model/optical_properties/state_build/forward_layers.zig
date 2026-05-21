const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const transport_common = @import("../../radiative_transfer/root.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const PhaseFunctions = @import("../shared/phase_functions.zig");
const State = @import("state.zig");
const Evaluation = @import("evaluation.zig");
const shared_geometry = @import("shared_geometry.zig");
const shared_carrier = @import("shared_carrier.zig");
const carrier_eval = @import("carrier_eval.zig");
const SpectroscopyState = @import("state_spectroscopy.zig");
const jacobian = transport_common.Jacobian;

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
    return toForwardInputAtWavelengthWithLayersAndSpectroscopyCache(
        prepared,
        scene,
        wavelength_nm,
        layer_inputs,
        null,
    );
}

pub fn toForwardInputAtWavelengthWithLayersAndSpectroscopyCache(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: ?[]transport_common.LayerInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) transport_common.ForwardInput {
    const optical_depths = if (layer_inputs) |owned_layers|
        fillForwardLayersAtWavelengthWithSpectroscopyCache(
            prepared,
            scene,
            wavelength_nm,
            owned_layers,
            profile_cache,
            true,
        )
    else
        prepared.opticalDepthBreakdownAtWavelength(wavelength_nm);
    return forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        if (layer_inputs) |owned_layers| owned_layers else &.{},
    );
}

pub fn forwardInputFromOpticalDepths(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    optical_depths: OpticalDepthBreakdown,
    layers: []transport_common.LayerInput,
) transport_common.ForwardInput {
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
        .optical_depth = optical_depths.totalOpticalDepth(),
        .single_scatter_albedo = if (optical_depths.totalOpticalDepth() > 0.0)
            optical_depths.singleScatterAlbedo()
        else
            prepared.effective_single_scatter_albedo,
        .layers = layers,
    };
}

pub fn fillForwardLayersAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
) OpticalDepthBreakdown {
    var profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(self, wavelength_nm);
    return fillForwardLayersAtWavelengthWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        layer_inputs,
        &profile_cache,
        true,
    );
}

// hot path:
//   when: forward input construction fills transport layers without a wavelength carrier cache
//   work: reduces prepared layers or support rows into layer input optical-depth fields
//   data: prepared layers/sublayers, profile spectroscopy cache, layer input array
//   follow: shared_carrier.fillReducedLayerInputFromSupportRowsWithSpectroscopyCache
pub fn fillForwardLayersAtWavelengthWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    if (layer_inputs.len == 0) return self.opticalDepthBreakdownAtWavelength(wavelength_nm);

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                var totals: OpticalDepthBreakdown = .{};
                for (geometry.layers, layer_inputs) |layer_geometry, *layer_input| {
                    const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                    const support_count: usize = @intCast(layer_geometry.support_count);
                    const support = shared_geometry.sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );

                    // PARITY:
                    //   DISAMAR forms radiative transfer-layer optical thickness from
                    //   the already prepared RTM support rows and their
                    //   `RTMweightSub` values. Re-integrating a new Gauss
                    //   subgrid here changes line-shoulder absorption even
                    //   when the support grid itself matches.
                    const breakdown = shared_carrier.fillReducedLayerInputFromSupportRowsWithSpectroscopyCache(
                        self,
                        scene,
                        wavelength_nm,
                        support.sublayers,
                        support.strong_line_states,
                        layer_geometry,
                        profile_cache,
                        layer_input,
                        compute_jacobian,
                    );
                    if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
                    Evaluation.accumulateBreakdown(&totals, breakdown);
                }
                return totals;
            }

            var totals: OpticalDepthBreakdown = .{};
            for (self.layers, layer_inputs) |layer, *layer_input| {
                const start_index: usize = @intCast(layer.sublayer_start_index);
                const count: usize = @intCast(layer.sublayer_count);
                if (count == 0) continue;
                const support = shared_geometry.sharedSupportSlices(self, sublayers, start_index, count);
                const breakdown = shared_carrier.fillReducedLayerInputFromSupportRowsWithSpectroscopyCache(
                    self,
                    scene,
                    wavelength_nm,
                    support.sublayers,
                    support.strong_line_states,
                    .{
                        .lower_altitude_km = layer.bottom_altitude_km,
                        .upper_altitude_km = layer.top_altitude_km,
                        .midpoint_altitude_km = layer.altitude_km,
                        .thickness_km = @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0),
                        .support_start_index = layer.sublayer_start_index,
                        .support_count = layer.sublayer_count,
                    },
                    profile_cache,
                    layer_input,
                    compute_jacobian,
                );
                if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
                Evaluation.accumulateBreakdown(&totals, breakdown);
            }
            return totals;
        }

        if (layer_inputs.len == sublayers.len) {
            var totals: OpticalDepthBreakdown = .{};
            for (sublayers, 0..) |sublayer, sublayer_index| {
                const evaluated = self.evaluateLayerAtWavelengthWithSpectroscopyCache(
                    scene,
                    sublayer.altitude_km,
                    wavelength_nm,
                    sublayer_index,
                    sublayers[sublayer_index .. sublayer_index + 1],
                    if (self.strong_line_states) |states| states[sublayer_index .. sublayer_index + 1] else null,
                    profile_cache,
                );
                layer_inputs[sublayer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, &layer_inputs[sublayer_index]);
                Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
            }
            return totals;
        }

        var totals: OpticalDepthBreakdown = .{};
        for (self.layers, layer_inputs) |layer, *layer_input| {
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const evaluated = self.evaluateLayerAtWavelengthWithSpectroscopyCache(
                scene,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                if (self.strong_line_states) |states| states[start_index..end_index] else null,
                profile_cache,
            );
            layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
            if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
            Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
        }
        return totals;
    }

    const aerosol_single_scatter_albedo = self.resolvedAerosolSingleScatterAlbedo();

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
        const gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
        const gas_absorption_optical_depth = @max(
            layer.gas_optical_depth - gas_scattering_optical_depth,
            0.0,
        );
        const aerosol_scattering_optical_depth =
            aerosol_optical_depth * aerosol_single_scatter_albedo;
        const optical_depth =
            gas_absorption_optical_depth +
            gas_scattering_optical_depth +
            layer.cia_optical_depth +
            aerosol_optical_depth;
        const scattering_optical_depth =
            gas_scattering_optical_depth +
            aerosol_scattering_optical_depth;
        layer_input.* = .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = layer.cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_scattering_optical_depth,
            .optical_depth = optical_depth,
            .scattering_optical_depth = scattering_optical_depth,
            .single_scatter_albedo = if (optical_depth > 0.0)
                std.math.clamp(scattering_optical_depth / optical_depth, 0.0, 1.0)
            else
                0.0,
            .solar_mu = scene.geometry.solarCosineAtAltitude(layer.altitude_km),
            .view_mu = scene.geometry.viewingCosineAtAltitude(layer.altitude_km),
            .phase = PhaseFunctions.PhaseMixture.fromUnitPhase(&self.aerosol_phase_coefficients),
        };
        if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
        totals.gas_absorption_optical_depth += gas_absorption_optical_depth;
        totals.gas_scattering_optical_depth += gas_scattering_optical_depth;
        totals.cia_optical_depth += layer.cia_optical_depth;
        totals.aerosol_optical_depth += aerosol_optical_depth;
        totals.aerosol_scattering_optical_depth += aerosol_scattering_optical_depth;
    }
    return totals;
}

// hot path:
//   when: forward input construction fills transport layers for a cached wavelength solve
//   work: reduces shared support rows through WavelengthCarrierCache and writes layer inputs
//   data: shared RTM geometry, support sublayers, carrier cache, layer input array
//   follow: shared_carrier.fillReducedLayerInputFromSupportRowsWithCarrierCache
pub fn fillForwardLayersAtWavelengthWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    if (layer_inputs.len == 0) return self.opticalDepthBreakdownAtWavelength(wavelength_nm);

    if (self.sublayers) |sublayers| {
        if (shared_geometry.usesSharedRtmGrid(self, layer_inputs.len)) {
            if (shared_geometry.cachedSharedRtmGeometry(self, layer_inputs.len)) |geometry| {
                var totals: OpticalDepthBreakdown = .{};
                for (geometry.layers, layer_inputs) |layer_geometry, *layer_input| {
                    const support_start_index: usize = @intCast(layer_geometry.support_start_index);
                    const support_count: usize = @intCast(layer_geometry.support_count);
                    const support = shared_geometry.sharedSupportSlices(
                        self,
                        sublayers,
                        support_start_index,
                        support_count,
                    );
                    const breakdown = shared_carrier.fillReducedLayerInputFromSupportRowsWithCarrierCache(
                        self,
                        scene,
                        wavelength_nm,
                        support.sublayers,
                        support.strong_line_states,
                        layer_geometry,
                        wavelength_cache,
                        layer_input,
                        compute_jacobian,
                    );
                    if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
                    Evaluation.accumulateBreakdown(&totals, breakdown);
                }
                return totals;
            }
        }
    }

    return fillForwardLayersAtWavelengthWithSpectroscopyCache(
        self,
        scene,
        wavelength_nm,
        layer_inputs,
        wavelength_cache.profile_cache,
        compute_jacobian,
    );
}

fn attachAerosolOpticalDepthJacobian(
    scene: *const Scene,
    layer_input: *transport_common.LayerInput,
) void {
    const aerosol_tau = scene.aerosol.optical_depth;
    if (aerosol_tau <= 0.0) return;
    const optical_derivative = layer_input.aerosol_optical_depth / aerosol_tau;
    const scattering_derivative = layer_input.aerosol_scattering_optical_depth / aerosol_tau;
    jacobian.set(&layer_input.optical_depth_jacobian, .aerosol_optical_depth, optical_derivative);
    jacobian.set(&layer_input.scattering_optical_depth_jacobian, .aerosol_optical_depth, scattering_derivative);
    const optical_depth = layer_input.optical_depth;
    if (optical_depth > 0.0) {
        const derivative =
            (scattering_derivative * optical_depth -
                layer_input.scattering_optical_depth * optical_derivative) /
            (optical_depth * optical_depth);
        jacobian.set(&layer_input.single_scatter_albedo_jacobian, .aerosol_optical_depth, derivative);
    }
}
