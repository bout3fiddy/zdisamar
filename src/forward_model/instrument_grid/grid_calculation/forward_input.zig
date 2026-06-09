const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const SpectroscopyState = @import("../../optical_properties/state_build/state_spectroscopy.zig");
const Trace = @import("../../instrumentation/trace.zig");
const common = @import("../../radiative_transfer/root.zig");

// forward_input.zig -----------------------------------------------------------------------------------------------------|
// Builds one LABOS ForwardInput at one high-resolution wavelength from prepared optical state.                           |
//                                                                                                                        |
// called by                                                                                                              |
//   spectral_forward.zig for each unique high-resolution forward miss before LABOS execution                             |
//                                                                                                                        |
// main path                                                                                                              |
//   prepared state + wavelength -> carrier cache -> layer optical depths -> base ForwardInput                            |
//   -> optional RTM quadrature or source-interface fallback -> optional pseudo-spherical support grid                    |
//                                                                                                                        |
// hot path                                                                                                               |
//   This runs inside the forward-prefetch worker loop. The caller supplies all mutable layer/source/quadrature           |
//   and pseudo-spherical buffers, plus a support carrier cache and optional profile spectroscopy cache, so the           |
//   function refreshes wavelength-specific data without allocating.                                                      |
//                                                                                                                        |
// boundary                                                                                                               |
//   No file I/O, text parsing, or product assembly happens here. Explicit-interval integrated-source routes              |
//   must use RTM-native quadrature; falling back to coarse source interfaces would change layer placement.               |
//                                                                                                                        |
// memory                                                                                                                 |
//   Returned ForwardInput borrows the slices written into worker scratch storage. Those slices stay valid only           |
//   until the next worker iteration refills the same scratch buffers.                                                    |
// -----------------------------------------------------------------------------------------------------------------------|

pub fn configuredForwardInput(
    scene: *const Scene,
    rtm_config: common.SolveConfig,
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
    // configuredForwardInput --------------------------------------------------------------------------------------------|
    // Fill the wavelength-specific transport input consumed by LABOS. The fixed scene/prepared state stays               |
    // outside this function; only arrays that depend on wavelength are refreshed here.                                   |
    //                                                                                                                    |
    // steps                                                                                                              |
    //   1. build carrier-backed spectroscopy caches for this wavelength                                                  |
    //   2. fill layer optical depths and base ForwardInput                                                               |
    //   3. attach integrated-source quadrature, or source interfaces when the RTM route needs that fallback              |
    //   4. attach pseudo-spherical support samples when spherical correction is enabled                                  |
    //                                                                                                                    |
    // boundary                                                                                                           |
    //   No file I/O or text parsing happens here. All buffers are provided by ProductStorage or worker                   |
    //   scratch storage.                                                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    const compute_jacobian = rtm_config.derivative_mode != .none;

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

        // instrumentation: trace zone: forward layers -------------------------------------------------------------------|
        // captures: wavelength-specific layer optical-depth fill                                                         |
        // why: measures carrier-backed layer preparation before LABOS transport.                                         |
        const zone = Trace.deepStaticZone(@src(), "forward_input.layers");
        defer zone.end();
        // end instrumentation: trace zone: forward layers ---------------------------------------------------------------|

        break :optical_depths OpticsPreparation.forward_layers.fillForwardLayersAtWavelengthWithCarrierCache(
            prepared,
            scene,
            wavelength_nm,
            layer_inputs,
            &wavelength_cache,
            compute_jacobian,
        );
    };

    var input = OpticsPreparation.forward_layers.forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        layer_inputs,
    );

    var has_rtm_quadrature = false;
    if (rtm_config.rtm_controls.integrate_source_function) {

        // The integrated-source route first tries the RTM-native quadrature table. When explicit interval
        // semantics are active, falling back to coarse source interfaces would silently change the layer
        // placement, so missing quadrature is rejected below.
        {

            // instrumentation: trace zone: RTM quadrature ---------------------------------------------------------------|
            // captures: RTM source-function quadrature preparation                                                       |
            // why: separates explicit quadrature setup from coarse source-interface fallback.                            |
            const zone = Trace.deepStaticZone(@src(), "forward_input.rtm_quadrature");
            defer zone.end();
            // end instrumentation: trace zone: RTM quadrature -----------------------------------------------------------|

            const fill_rtm_quadrature =
                OpticsPreparation.rtm_quadrature.fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache;
            has_rtm_quadrature = fill_rtm_quadrature(
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

            // Explicit-interval integrated-source cases must stay on the RTM-native carrier path. The coarse
            // source-interface fallback would use a different vertical contract.
            return error.MissingExplicitRtmQuadrature;
        }
    }

    if (rtm_config.rtm_controls.integrate_source_function and !has_rtm_quadrature) {
        const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];

        {

            // instrumentation: trace zone: source interfaces ------------------------------------------------------------|
            // captures: source-interface fill wall time                                                                  |
            // why: quantifies the fallback source-function boundary when RTM quadrature is unavailable.                  |
            const zone = Trace.deepStaticZone(@src(), "forward_input.source_interfaces");
            defer zone.end();
            // end instrumentation: trace zone: source interfaces --------------------------------------------------------|

            OpticsPreparation.source_interfaces.fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
                prepared,
                wavelength_nm,
                input.layers,
                source_interface_slice,
                &wavelength_cache,
            );
        }

        input.source_interfaces = source_interface_slice;
    }

    if (rtm_config.rtm_controls.use_spherical_correction) {

        // Pseudo-spherical samples are attached only for the geometric-correction route. Explicit shared-grid
        // cases rebuild the dense wavelength-specific attenuation contract from the RTM subgrid instead of
        // reusing midpoint-style layer surrogates.
        const has_pseudo_spherical_grid = has_grid: {

            // instrumentation: trace zone: pseudo-spherical grid --------------------------------------------------------|
            // captures: pseudo-spherical support-grid fill wall time                                                     |
            // why: keeps geometric-correction setup visible in forward-sample traces.                                    |
            const zone = Trace.deepStaticZone(@src(), "forward_input.pseudo_spherical");
            defer zone.end();
            // end instrumentation: trace zone: pseudo-spherical grid ----------------------------------------------------|

            break :has_grid OpticsPreparation.pseudo_spherical.fillPseudoSphericalGridAtWavelengthWithCarrierCache(
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

    input.rtm_controls = rtm_config.rtm_controls;
    return input;
}
