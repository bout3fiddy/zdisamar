const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const Trace = @import("../../performance_trace.zig");
const common = @import("../../radiative_transfer/root.zig");

// hot path:
//   when: once per high-resolution wavelength before LABOS transport
//   work: fills optical depth layers, source interfaces, RTM quadrature, and pseudo-spherical samples
//   data: wavelength carrier cache, layer input arrays, quadrature/source-interface buffers
//   follow: carrier-backed transport fills and the ForwardInput consumed by LABOS
pub fn configuredForwardInput(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_cache: *CarrierEval.SupportRowScalarCache,
    profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
) common.ExecuteError!common.ForwardInput {
    const compute_jacobian = route.derivative_mode != .none;
    var local_profile_cache: SpectroscopyState.ProfileNodeSpectroscopyCache = undefined;
    const resolved_profile_cache = if (profile_spectroscopy_cache) |cache|
        cache
    else cache: {
        local_profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(prepared, wavelength_nm);
        break :cache &local_profile_cache;
    };
    var wavelength_cache = CarrierEval.WavelengthCarrierCache.init(
        prepared,
        wavelength_nm,
        support_carrier_cache,
        resolved_profile_cache,
    );
    const optical_depths = optical_depths: {
        const zone = Trace.deepStaticZone(@src(), "forward_input.layers");
        defer zone.end();
        break :optical_depths OpticsPreparation.transport.fillForwardLayersAtWavelengthWithCarrierCache(
            prepared,
            scene,
            wavelength_nm,
            layer_inputs,
            &wavelength_cache,
            compute_jacobian,
        );
    };
    var input = OpticsPreparation.transport.forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        layer_inputs,
    );
    var has_rtm_quadrature = false;
    if (route.rtm_controls.integrate_source_function) {
        // DECISION:
        //   Only attach RTM quadrature when the route requests integrated
        //   source-function evaluation.
        {
            const zone = Trace.deepStaticZone(@src(), "forward_input.rtm_quadrature");
            defer zone.end();
            has_rtm_quadrature = OpticsPreparation.transport.fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
                prepared,
                wavelength_nm,
                input.layers,
                rtm_quadrature_levels[0 .. input.layers.len + 1],
                &wavelength_cache,
                compute_jacobian,
            );
        }
        if (has_rtm_quadrature) {
            input.rtm_quadrature = .{
                .levels = rtm_quadrature_levels[0 .. input.layers.len + 1],
                .aerosol_phase_coefficients = &prepared.aerosol_phase_coefficients,
            };
        } else if (prepared.interval_semantics != .none) {
            // INVARIANT:
            //   The explicit-interval integrated-source route must stay on
            //   the RTM-native carrier path instead of silently drifting back
            //   to the coarse source-interface fallback.
            return error.MissingExplicitRtmQuadrature;
        }
    }
    if (route.rtm_controls.integrate_source_function and !has_rtm_quadrature) {
        const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];
        {
            const zone = Trace.deepStaticZone(@src(), "forward_input.source_interfaces");
            defer zone.end();
            OpticsPreparation.transport.fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
                prepared,
                wavelength_nm,
                input.layers,
                source_interface_slice,
                &wavelength_cache,
            );
        }
        input.source_interfaces = source_interface_slice;
    }
    if (route.rtm_controls.use_spherical_correction) {
        // DECISION:
        //   Pseudo-spherical samples are only attached for routes that request
        //   the geometric correction. Explicit shared-grid routes rebuild the
        //   dense wavelength-specific attenuation contract directly from the
        //   RTM subgrid instead of reusing midpoint-style layer surrogates.
        const has_pseudo_spherical_grid = has_grid: {
            const zone = Trace.deepStaticZone(@src(), "forward_input.pseudo_spherical");
            defer zone.end();
            break :has_grid OpticsPreparation.transport.fillPseudoSphericalGridAtWavelengthWithCarrierCache(
                prepared,
                scene,
                wavelength_nm,
                input.layers.len,
                pseudo_spherical_samples,
                pseudo_spherical_level_starts,
                pseudo_spherical_level_altitudes,
                &wavelength_cache,
            );
        };
        if (has_pseudo_spherical_grid) {
            const pseudo_spherical_sample_count = pseudo_spherical_level_starts[input.layers.len];
            input.pseudo_spherical_grid = .{
                .samples = pseudo_spherical_samples[0..pseudo_spherical_sample_count],
                .level_sample_starts = pseudo_spherical_level_starts[0 .. input.layers.len + 1],
                .level_altitudes_km = pseudo_spherical_level_altitudes[0 .. input.layers.len + 1],
            };
        }
    }
    input.rtm_controls = route.rtm_controls;
    return input;
}
