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

// forward_layers.zig ----------------------------------------------------------------------------------------|
// Turns PreparedOpticalState into the LayerInput rows and scalar ForwardInput that LABOS consumes.           |
//                                                                                                            |
// called by                                                                                                  |
//   forward_input.configuredForwardInput for every high-resolution wavelength miss.                          |
//   diagnostics and scalar report helpers when they need layer-resolved or total optical depths.             |
//                                                                                                            |
// main paths                                                                                                 |
//   scalar route : evaluate OpticalDepthBreakdown and build a layer-free ForwardInput.                       |
//   shared route : reduce cached shared RTM support rows into one LayerInput per transport layer.            |
//   direct route : evaluate prepared layers or sublayers when shared geometry is not active.                 |
//   cache route  : reuse ProfileNodeSpectroscopyCache or WavelengthCarrierCache across the wavelength work.  |
//                                                                                                            |
// row handoff                                                                                                |
//   LayerInput is the transport row: optical-depth pieces, Jacobian vectors, mu values, and phase mix.       |
//   PreparedLayer supplies support spans and fallback physical fields; PreparedSublayer holds support rows.  |
//   The same LayerInput slice is passed on to RTM quadrature, pseudo-spherical grids, and LABOS execution.   |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs per high-resolution wavelength. Caller-owned layer_inputs are refreshed without allocation.         |
//   Index-only PreparedLayer loops use pointer capture and read support spans at [192..207] without copying  |
//   the 208 B row. The span stays beside physical fields because direct paths also read altitude and aerosol |
//   fields from the same row.                                                                                |
//                                                                                                            |
// math                                                                                                       |
//   tau_ext = tau_gas_abs + tau_rayleigh + tau_cia + tau_aerosol(lambda).                                    |
//   omega0 = scattering optical depth / tau_ext, clamped into physical bounds.                               |
// -----------------------------------------------------------------------------------------------------------|

fn transportAzimuthDifferenceRad(relative_azimuth_deg: f64) f64 {
    const transport_dphi_deg = @mod(180.0 - relative_azimuth_deg, 360.0);

    // LABOS transport azimuth uses radians of (180 deg - relative_azimuth) mod 360.
    return std.math.degreesToRadians(transport_dphi_deg);
}

pub fn toForwardInputWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    // toForwardInputWithLayers ----------------------------------------------------------------------------- |
    // Build a ForwardInput at the scene midpoint wavelength. This is the simple route for diagnostics and    |
    // scalar callers; high-resolution workers call the wavelength-specific route below.                      |
    // -------------------------------------------------------------------------------------------------------|

    return toForwardInputAtWavelengthWithLayers(
        prepared,
        scene,
        (scene.spectral_grid.start_nm + scene.spectral_grid.end_nm) * 0.5,
        layer_inputs,
    );
}

pub fn toForwardInputAtWavelengthWithLayers(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: ?[]transport_common.LayerInput,
) transport_common.ForwardInput {
    // toForwardInputAtWavelengthWithLayers ----------------------------------------------------------------- |
    // Build a ForwardInput for one wavelength when no caller-owned profile spectroscopy cache is available.  |
    // -------------------------------------------------------------------------------------------------------|

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
    // toForwardInputAtWavelengthWithLayersAndSpectroscopyCache --------------------------------------------- |
    // Choose between the scalar optical-depth route and the caller-owned LayerInput route.                   |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Wavelength workers pass layer_inputs so this fills transport rows once, then reuses the same slice   |
    //   for RTM quadrature, pseudo-spherical correction, and LABOS execution.                                |
    // -------------------------------------------------------------------------------------------------------|

    const optical_depths = choose_optical_depths: {
        if (layer_inputs) |owned_layers| {
            break :choose_optical_depths fillForwardLayersAtWavelengthWithSpectroscopyCache(
                prepared,
                scene,
                wavelength_nm,
                owned_layers,
                profile_cache,
                true,
            );
        }

        break :choose_optical_depths prepared.opticalDepthBreakdownAtWavelength(wavelength_nm);
    };

    const resolved_layers = if (layer_inputs) |owned_layers| owned_layers else &.{};
    return forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        resolved_layers,
    );
}

pub fn forwardInputFromOpticalDepths(
    prepared: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    optical_depths: OpticalDepthBreakdown,
    layers: []transport_common.LayerInput,
) transport_common.ForwardInput {
    // forwardInputFromOpticalDepths ------------------------------------------------------------------------ |
    // Copy scalar optical-depth totals, geometry, surface, spectral weight, and optional layer slice into    |
    // the RTM public input row. This is the last optical-preparation step before radiative_transfer/root.zig.|
    // -------------------------------------------------------------------------------------------------------|

    const mu0 = scene.geometry.solarCosineAtAltitude(0.0);
    const muv = scene.geometry.viewingCosineAtAltitude(0.0);
    const span_nm = scene.spectral_grid.end_nm - scene.spectral_grid.start_nm;
    const spectral_weight = if (scene.spectral_grid.sample_count <= 1)
        @max(span_nm, 1.0e-6)
    else
        span_nm / @as(f64, @floatFromInt(scene.spectral_grid.sample_count - 1));

    // Scalar forward input carries tau_ext, omega0, mu0/muv, and spectral quadrature weight dlambda.
    const single_scatter_albedo = if (optical_depths.totalOpticalDepth() > 0.0)
        optical_depths.singleScatterAlbedo()
    else
        prepared.effective_single_scatter_albedo;

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
        .single_scatter_albedo = single_scatter_albedo,
        .layers = layers,
    };
}

pub fn fillForwardLayersAtWavelength(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
) OpticalDepthBreakdown {
    // fillForwardLayersAtWavelength ------------------------------------------------------------------------ |
    // Convenience route for callers that need transport rows but do not already hold a profile cache.        |
    // The cache is per wavelength and is shared by every layer evaluation in the delegated route.            |
    // -------------------------------------------------------------------------------------------------------|

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

pub fn fillForwardLayersAtWavelengthWithSpectroscopyCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
    profile_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    // fillForwardLayersAtWavelengthWithSpectroscopyCache ----------------------------------------------------|
    // Fill transport LayerInput rows when only the profile spectroscopy cache is available.                  |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Called while building forward inputs for each high-resolution wavelength sample.                     |
    //   Shared geometry reduces support rows; direct branches evaluate PreparedLayer or PreparedSublayer.    |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   Writes the exact LayerInput slice later passed to RTM quadrature, source interfaces, and LABOS.      |
    //   PreparedLayer provides support spans, representative altitude, and fallback aerosol profile fields.  |
    //   PreparedSublayer rows carry the fine thermodynamic/support data used for spectroscopy and CIA.       |
    //                                                                                                        |
    // memory                                                                                                 |
    //   The support-span loops read sublayer_start_index at [192..195], sublayer_count at [204..207], and    |
    //   sometimes altitude_km at [24..31] from 208 B PreparedLayer rows, all by pointer. Keeping span        |
    //   indexes beside physical layer fields avoids synchronizing a second layer-shape array. A column split |
    //   needs retained benchmark proof at the forward-input boundary before it is safer.                     |
    //                                                                                                        |
    // math                                                                                                   |
    //   tau_ext = tau_gas_abs + tau_rayleigh + tau_cia + tau_aerosol(lambda)                                 |
    //   omega0  = tau_sca / tau_ext                                                                          |
    // -------------------------------------------------------------------------------------------------------|

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

                    // DISAMAR forms radiative-transfer layer optical thickness from the already prepared RTM
                    // support rows and their RTMweightSub values. Re-integrating a new Gauss subgrid here
                    // changes line-shoulder absorption even when the support grid itself matches.
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
            for (self.layers, layer_inputs) |*layer, *layer_input| {

                // This fallback reads the support tail plus altitude fields from PreparedLayer:
                // sublayer_start_index [192..195], sublayer_count [204..207], altitude_km [24..31],
                // bottom_altitude_km [8..15], and top_altitude_km [176..183]. These fields stay with the
                // physical row so shared geometry, forward layers, and diagnostics slice the same support
                // rows. A side span table needs workload proof before it becomes simpler.
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
                const strong_line_state = if (self.strong_line_states) |states|
                    states[sublayer_index .. sublayer_index + 1]
                else
                    null;

                const evaluated = self.evaluateLayerAtWavelengthWithSpectroscopyCache(
                    scene,
                    sublayer.altitude_km,
                    wavelength_nm,
                    sublayer_index,
                    sublayers[sublayer_index .. sublayer_index + 1],
                    strong_line_state,
                    profile_cache,
                );
                layer_inputs[sublayer_index] = Evaluation.layerInputFromEvaluated(evaluated);
                if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, &layer_inputs[sublayer_index]);
                Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
            }
            return totals;
        }

        var totals: OpticalDepthBreakdown = .{};
        for (self.layers, layer_inputs) |*layer, *layer_input| {

            // Non-shared layer mode consumes more of PreparedLayer than just the support span:
            // sublayer_start_index [192..195], sublayer_count [204..207], altitude_km [24..31], CIA totals,
            // aerosol profile fields, gas/scattering totals, and phase support all come from this row.
            // Pointer capture keeps the 208 B row from being copied while preserving locality.
            const start_index: usize = @intCast(layer.sublayer_start_index);
            const end_index = start_index + @as(usize, @intCast(layer.sublayer_count));
            const strong_line_state = if (self.strong_line_states) |states|
                states[start_index..end_index]
            else
                null;

            const evaluated = self.evaluateLayerAtWavelengthWithSpectroscopyCache(
                scene,
                layer.altitude_km,
                wavelength_nm,
                start_index,
                sublayers[start_index..end_index],
                strong_line_state,
                profile_cache,
            );
            layer_input.* = Evaluation.layerInputFromEvaluated(evaluated);
            if (compute_jacobian) attachAerosolOpticalDepthJacobian(scene, layer_input);
            Evaluation.accumulateBreakdown(&totals, evaluated.breakdown);
        }
        return totals;
    }

    const aerosol_single_scatter_albedo = self.resolvedAerosolSingleScatterAlbedo();
    const AerosolProfile = struct {
        reference_wavelength_nm: f64,
        angstrom_exponent: f64,
        single_scatter_albedo: f64,
    };

    var totals: OpticalDepthBreakdown = .{};
    for (self.layers, layer_inputs) |*layer, *layer_input| {
        const aerosol_profile: AerosolProfile = choose_aerosol_profile: {
            if (self.has_aerosol_profile_properties) {
                break :choose_aerosol_profile .{
                    .reference_wavelength_nm = layer.aerosol_reference_wavelength_nm,
                    .angstrom_exponent = layer.aerosol_angstrom_exponent,
                    .single_scatter_albedo = layer.aerosol_single_scatter_albedo,
                };
            }

            break :choose_aerosol_profile .{
                .reference_wavelength_nm = self.aerosol_reference_wavelength_nm,
                .angstrom_exponent = self.aerosol_angstrom_exponent,
                .single_scatter_albedo = aerosol_single_scatter_albedo,
            };
        };

        const aerosol_optical_depth = PreparedOpticalState.particleOpticalDepthAtWavelength(
            layer.aerosol_optical_depth,
            layer.aerosol_base_optical_depth,
            aerosol_profile.reference_wavelength_nm,
            aerosol_profile.angstrom_exponent,
            self.aerosol_fraction_control,
            wavelength_nm,
        );
        const gas_scattering_optical_depth = layer.gas_scattering_optical_depth;
        const gas_absorption_optical_depth = @max(
            layer.gas_optical_depth - gas_scattering_optical_depth,
            0.0,
        );
        const aerosol_scattering_optical_depth =
            aerosol_optical_depth * aerosol_profile.single_scatter_albedo;

        // tau_ext = tau_gas_abs + tau_gas_sca + tau_cia + tau_aerosol.
        const optical_depth =
            gas_absorption_optical_depth +
            gas_scattering_optical_depth +
            layer.cia_optical_depth +
            aerosol_optical_depth;

        // tau_sca = tau_gas_sca + tau_aerosol * omega0_aerosol.
        const scattering_optical_depth =
            gas_scattering_optical_depth +
            aerosol_scattering_optical_depth;
        const single_scatter_albedo = if (optical_depth > 0.0)
            std.math.clamp(scattering_optical_depth / optical_depth, 0.0, 1.0)
        else
            0.0;

        layer_input.* = .{
            .gas_absorption_optical_depth = gas_absorption_optical_depth,
            .gas_scattering_optical_depth = gas_scattering_optical_depth,
            .cia_optical_depth = layer.cia_optical_depth,
            .aerosol_optical_depth = aerosol_optical_depth,
            .aerosol_scattering_optical_depth = aerosol_scattering_optical_depth,
            .optical_depth = optical_depth,
            .scattering_optical_depth = scattering_optical_depth,
            .single_scatter_albedo = single_scatter_albedo,
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

pub fn fillForwardLayersAtWavelengthWithCarrierCache(
    self: *const PreparedOpticalState,
    scene: *const Scene,
    wavelength_nm: f64,
    layer_inputs: []transport_common.LayerInput,
    wavelength_cache: *carrier_eval.WavelengthCarrierCache,
    compute_jacobian: bool,
) OpticalDepthBreakdown {
    // fillForwardLayersAtWavelengthWithCarrierCache ---------------------------------------------------------|
    // Fill transport LayerInput rows for a cached wavelength solve.                                          |
    //                                                                                                        |
    // call path                                                                                              |
    //   forward_input.configuredForwardInput calls this after WavelengthCarrierCache has prepared support    |
    //   row scalars for the same high-resolution wavelength miss.                                            |
    //                                                                                                        |
    // row handoff                                                                                            |
    //   layer_inputs is caller-owned ForwardInput storage. The shared route writes one 176 B LayerInput per  |
    //   transport layer; RTM quadrature, pseudo-spherical grids, source interfaces, and LABOS read the same  |
    //   slice later in the wavelength solve.                                                                 |
    //                                                                                                        |
    // hot path                                                                                               |
    //   Runs once per high-resolution wavelength. The cache route reduces shared support rows into transport |
    //   rows without repeating sigma * density * path work already stored in WavelengthCarrierCache.         |
    //                                                                                                        |
    // memory                                                                                                 |
    //   Shared geometry supplies support spans; support sublayers and cached carriers remain borrowed from   |
    //   PreparedOpticalState and WavelengthCarrierCache. This function only rewrites caller-owned LayerInput |
    //   rows and falls back to the profile-cache route when shared RTM geometry is not active.               |
    //                                                                                                        |
    // math                                                                                                   |
    //   tau_ext and phase terms are integrated over the support rows, then stored as the layer-level         |
    //   transport row consumed by LABOS.                                                                     |
    //                                                                                                        |
    // calls                                                                                                  |
    //   shared_carrier.fillReducedLayerInputFromSupportRowsWithCarrierCache                                  |
    //   fillForwardLayersAtWavelengthWithSpectroscopyCache fallback                                          |
    // -------------------------------------------------------------------------------------------------------|

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
    // attachAerosolOpticalDepthJacobian -------------------------------------------------------------------- |
    // Fill aerosol optical-depth Jacobian slots on an already-built LayerInput row. The derivative is stored |
    // beside the scalar layer values because LABOS and RTM quadrature read the row as one transport unit.    |
    // -------------------------------------------------------------------------------------------------------|

    const aerosol_tau = scene.aerosol.optical_depth;
    if (aerosol_tau <= 0.0) return;
    const optical_derivative = layer_input.aerosol_optical_depth / aerosol_tau;
    const scattering_derivative = layer_input.aerosol_scattering_optical_depth / aerosol_tau;
    jacobian.set(&layer_input.optical_depth_jacobian, .aerosol_optical_depth, optical_derivative);
    jacobian.set(
        &layer_input.scattering_optical_depth_jacobian,
        .aerosol_optical_depth,
        scattering_derivative,
    );

    const optical_depth = layer_input.optical_depth;
    if (optical_depth > 0.0) {
        const derivative =
            (scattering_derivative * optical_depth -
                layer_input.scattering_optical_depth * optical_derivative) /
            (optical_depth * optical_depth);
        jacobian.set(
            &layer_input.single_scatter_albedo_jacobian,
            .aerosol_optical_depth,
            derivative,
        );
    }
}
