const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const OpticsSpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const common = @import("../../radiative_transfer/root.zig");
const Workspace = @import("workspace.zig");

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
) common.ExecuteError!common.ForwardInput {
    var profile_cache = OpticsSpectroscopyState.ProfileNodeSpectroscopyCache.init(prepared, wavelength_nm);
    var input = OpticsPreparation.transport.toForwardInputAtWavelengthWithLayersAndSpectroscopyCache(
        prepared,
        scene,
        wavelength_nm,
        layer_inputs,
        &profile_cache,
    );
    const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];
    input.source_interfaces = source_interface_slice;
    if (route.rtm_controls.integrate_source_function) {
        // DECISION:
        //   Only attach RTM quadrature when the route requests integrated
        //   source-function evaluation.
        const has_rtm_quadrature = OpticsPreparation.transport.fillRtmQuadratureAtWavelengthWithLayersAndSpectroscopyCache(
            prepared,
            wavelength_nm,
            input.layers,
            rtm_quadrature_levels[0 .. input.layers.len + 1],
            &profile_cache,
        );
        if (has_rtm_quadrature) {
            input.rtm_quadrature = .{
                .levels = rtm_quadrature_levels[0 .. input.layers.len + 1],
            };
        } else if (prepared.interval_semantics != .none) {
            // INVARIANT:
            //   The explicit-interval integrated-source route must stay on
            //   the RTM-native carrier path instead of silently drifting back
            //   to the coarse source-interface fallback.
            return error.MissingExplicitRtmQuadrature;
        }
    }
    OpticsPreparation.transport.fillSourceInterfacesAtWavelengthWithLayersAndSpectroscopyCache(
        prepared,
        wavelength_nm,
        input.layers,
        source_interface_slice,
        &profile_cache,
    );
    if (route.rtm_controls.use_spherical_correction) {
        // DECISION:
        //   Pseudo-spherical samples are only attached for routes that request
        //   the geometric correction. Explicit shared-grid routes rebuild the
        //   dense wavelength-specific attenuation contract directly from the
        //   RTM subgrid instead of reusing midpoint-style layer surrogates.
        const has_pseudo_spherical_grid = OpticsPreparation.transport.fillPseudoSphericalGridAtWavelengthWithSpectroscopyCache(
            prepared,
            scene,
            wavelength_nm,
            input.layers.len,
            pseudo_spherical_layers,
            pseudo_spherical_samples,
            pseudo_spherical_level_starts,
            pseudo_spherical_level_altitudes,
            &profile_cache,
        );
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
