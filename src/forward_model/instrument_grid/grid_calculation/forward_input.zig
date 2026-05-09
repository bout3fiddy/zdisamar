const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const Trace = @import("../../performance_trace.zig");
const common = @import("../../radiative_transfer/root.zig");

pub fn configuredForwardInput(
    scene: *const Scene,
    route: common.Route,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
    layer_inputs: []common.LayerInput,
    pseudo_spherical_layers: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_valid: []bool,
    support_carriers: []CarrierEval.SharedOpticalCarrier,
    profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
    trace: Trace.WorkerRef,
) common.ExecuteError!common.ForwardInput {
    const carrier_start = Trace.begin();
    var wavelength_cache = CarrierEval.WavelengthCarrierCache.init(
        prepared,
        wavelength_nm,
        support_carrier_valid,
        support_carriers,
        profile_spectroscopy_cache,
    );
    if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_carrier_init, Trace.elapsed(carrier_start));
    const layers_start = Trace.begin();
    const optical_depths = OpticsPreparation.transport.fillForwardLayersAtWavelengthWithCarrierCache(
        prepared,
        scene,
        wavelength_nm,
        layer_inputs,
        &wavelength_cache,
    );
    if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_layers, Trace.elapsed(layers_start));
    var input = OpticsPreparation.transport.forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        layer_inputs,
    );
    const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];
    var has_rtm_quadrature = false;
    if (route.rtm_controls.integrate_source_function) {
        // DECISION:
        //   Only attach RTM quadrature when the route requests integrated
        //   source-function evaluation.
        const rtm_quadrature_start = Trace.begin();
        has_rtm_quadrature = OpticsPreparation.transport.fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
            prepared,
            wavelength_nm,
            input.layers,
            rtm_quadrature_levels[0 .. input.layers.len + 1],
            &wavelength_cache,
        );
        if (has_rtm_quadrature) {
            input.rtm_quadrature = .{
                .levels = rtm_quadrature_levels[0 .. input.layers.len + 1],
            };
            if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_rtm_quadrature, Trace.elapsed(rtm_quadrature_start));
        } else if (prepared.interval_semantics != .none) {
            // INVARIANT:
            //   The explicit-interval integrated-source route must stay on
            //   the RTM-native carrier path instead of silently drifting back
            //   to the coarse source-interface fallback.
            if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_rtm_quadrature, Trace.elapsed(rtm_quadrature_start));
            return error.MissingExplicitRtmQuadrature;
        } else {
            if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_rtm_quadrature, Trace.elapsed(rtm_quadrature_start));
        }
    }
    if (!has_rtm_quadrature) {
        const source_interfaces_start = Trace.begin();
        OpticsPreparation.transport.fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
            prepared,
            wavelength_nm,
            input.layers,
            source_interface_slice,
            &wavelength_cache,
        );
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_source_interfaces, Trace.elapsed(source_interfaces_start));
        input.source_interfaces = source_interface_slice;
    }
    if (route.rtm_controls.use_spherical_correction) {
        // DECISION:
        //   Pseudo-spherical samples are only attached for routes that request
        //   the geometric correction. Explicit shared-grid routes rebuild the
        //   dense wavelength-specific attenuation contract directly from the
        //   RTM subgrid instead of reusing midpoint-style layer surrogates.
        const pseudo_spherical_start = Trace.begin();
        const has_pseudo_spherical_grid = OpticsPreparation.transport.fillPseudoSphericalGridAtWavelengthWithCarrierCache(
            prepared,
            scene,
            wavelength_nm,
            input.layers.len,
            pseudo_spherical_layers,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            &wavelength_cache,
        );
        if (has_pseudo_spherical_grid) {
            const pseudo_spherical_sample_count = pseudo_spherical_level_starts[input.layers.len];
            input.pseudo_spherical_grid = .{
                .samples = pseudo_spherical_samples[0..pseudo_spherical_sample_count],
                .level_sample_starts = pseudo_spherical_level_starts[0 .. input.layers.len + 1],
                .level_altitudes_km = pseudo_spherical_level_altitudes[0 .. input.layers.len + 1],
            };
        }
        if (Trace.enabled) if (Trace.asWorker(trace)) |sink| sink.addSection(.forward_input_pseudo_spherical, Trace.elapsed(pseudo_spherical_start));
    }
    input.rtm_controls = route.rtm_controls;
    return input;
}
