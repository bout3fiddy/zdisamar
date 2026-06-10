const std = @import("std");
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

// ForwardSampleRequest --------------------------------------------------------------------------------------------------|
// Fixed inputs for one high-resolution forward sample. This is a borrowed view; it does not own scene,                   |
// prepared optical state, or any wavelength-specific scratch storage.                                                    |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 104 B (0.102 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [ 0.. 7] scene         : *const Scene                                                                                  |
// [ 8..87] rtm_config    : common.SolveConfig                                                                            |
// [88..95] prepared      : *const OpticsPreparation.PreparedOpticalState                                                 |
// [96..103] wavelength_nm: f64                                                                                           |
//                                                                                                                        |
// out-of-line storage: scene and prepared are borrowed from the caller.                                                  |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 104 B (0.102 KiB); total excludes borrowed scene/prepared storage                            |
pub const ForwardSampleRequest = struct {
    scene: *const Scene,
    rtm_config: common.SolveConfig,
    prepared: *const OpticsPreparation.PreparedOpticalState,
    wavelength_nm: f64,
};
// -----------------------------------------------------------------------------------------------------------------------|

// ForwardInputScratch ---------------------------------------------------------------------------------------------------|
// Caller-owned mutable buffers used while building one ForwardInput. The slices point at worker or product               |
// storage and are reused across many high-resolution samples.                                                            |
//                                                                                                                        |
// layout(64-bit)                                                                                                         |
// size: 112 B (0.109 KiB), align: 8 B                                                                                    |
//                                                                                                                        |
// memory                                                                                                                 |
// [  0.. 15] layer_inputs                     : []common.LayerInput                                                      |
// [ 16.. 31] source_interfaces                : []common.SourceInterfaceInput                                            |
// [ 32.. 47] rtm_quadrature_levels            : []common.RtmQuadratureLevel                                              |
// [ 48.. 63] pseudo_spherical_samples         : []common.PseudoSphericalSample                                           |
// [ 64.. 79] pseudo_spherical_level_starts    : []usize                                                                  |
// [ 80.. 95] pseudo_spherical_level_altitudes : []f64                                                                    |
// [ 96..103] support_carrier_cache            : *CarrierEval.SupportRowScalarCache                                       |
// [104..111] profile_spectroscopy_cache       : ?*const SpectroscopyState.ProfileNodeSpectroscopyCache                   |
//                                                                                                                        |
// out-of-line storage: all slices and cache pointers are borrowed scratch owned by the caller.                           |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                                 |
// footprint: per instance = 112 B (0.109 KiB); total excludes borrowed scratch buffers                                   |
pub const ForwardInputScratch = struct {
    layer_inputs: []common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
    rtm_quadrature_levels: []common.RtmQuadratureLevel,
    pseudo_spherical_samples: []common.PseudoSphericalSample,
    pseudo_spherical_level_starts: []usize,
    pseudo_spherical_level_altitudes: []f64,
    support_carrier_cache: *CarrierEval.SupportRowScalarCache,
    profile_spectroscopy_cache: ?*const SpectroscopyState.ProfileNodeSpectroscopyCache,
};
// -----------------------------------------------------------------------------------------------------------------------|

pub fn configuredForwardInput(
    request: ForwardSampleRequest,
    scratch: ForwardInputScratch,
) common.ExecuteError!common.ForwardInput {
    // configuredForwardInput --------------------------------------------------------------------------------------------|
    // Fill the wavelength-specific transport input consumed by LABOS. The fixed scene/prepared state stays               |
    // in request; scratch names the mutable arrays refreshed for this wavelength.                                        |
    //                                                                                                                    |
    // steps                                                                                                              |
    //   1. build carrier-backed spectroscopy caches for this wavelength                                                  |
    //   2. fill layer optical depths and base ForwardInput                                                               |
    //   3. attach integrated-source quadrature, or source interfaces when the RTM route needs that fallback              |
    //   4. attach pseudo-spherical support samples when spherical correction is enabled                                  |
    //                                                                                                                    |
    // runtime                                                                                                            |
    //   No file I/O or text parsing happens here. All buffers are provided by ProductStorage or worker                   |
    //   scratch storage.                                                                                                 |
    // -------------------------------------------------------------------------------------------------------------------|

    const compute_jacobian = request.rtm_config.derivative_mode != .none;

    var local_profile_cache: SpectroscopyState.ProfileNodeSpectroscopyCache = undefined;
    const resolved_profile_cache = choose_profile_cache: {
        if (scratch.profile_spectroscopy_cache) |cache| break :choose_profile_cache cache;
        local_profile_cache = SpectroscopyState.ProfileNodeSpectroscopyCache.init(
            request.prepared,
            request.wavelength_nm,
        );
        break :choose_profile_cache &local_profile_cache;
    };

    var wavelength_cache = CarrierEval.WavelengthCarrierCache.init(
        request.prepared,
        request.wavelength_nm,
        scratch.support_carrier_cache,
        resolved_profile_cache,
    );

    const optical_depths = optical_depths: {

        // instrumentation: trace zone: forward layers -------------------------------------------------------------------|
        // captures: wavelength-specific layer optical-depth fill                                                         |
        // why: measures carrier-backed layer preparation before LABOS transport.                                         |
        const zone = Trace.deepStaticZone(@src(), "forward_input.layers");
        defer zone.end();
        // end instrumentation: trace zone: forward layers ---------------------------------------------------------------|

        const forward_layer_request = OpticsPreparation.forward_layers.ForwardLayerCarrierRequest{
            .prepared = request.prepared,
            .scene = request.scene,
            .layer_inputs = scratch.layer_inputs,
            .wavelength_cache = &wavelength_cache,
            .wavelength_nm = request.wavelength_nm,
            .compute_jacobian = compute_jacobian,
        };
        break :optical_depths OpticsPreparation.forward_layers.fillForwardLayersAtWavelengthWithCarrierCache(
            &forward_layer_request,
        );
    };

    const input_scalars = OpticsPreparation.forward_layers.ForwardInputScalars{
        .wavelength_nm = request.wavelength_nm,
        .spectral_weight = OpticsPreparation.forward_layers.forwardInputSpectralWeight(
            request.scene.spectral_grid,
        ),
        .air_mass_factor = request.prepared.effective_air_mass_factor,
        .mu0 = request.scene.geometry.solarCosineAtAltitude(0.0),
        .muv = request.scene.geometry.viewingCosineAtAltitude(0.0),
        .relative_azimuth_rad = OpticsPreparation.forward_layers.transportAzimuthDifferenceRad(
            request.scene.geometry.relative_azimuth_deg,
        ),
        .surface_albedo = std.math.clamp(request.scene.surface.albedo, 0.0, 1.0),
        .fallback_single_scatter_albedo = request.prepared.effective_single_scatter_albedo,
    };
    const input_request = OpticsPreparation.forward_layers.ForwardInputOpticalDepthRequest{
        .scalars = input_scalars,
        .optical_depths = optical_depths,
        .layers = scratch.layer_inputs,
    };
    var input = OpticsPreparation.forward_layers.forwardInputFromOpticalDepths(
        &input_request,
    );

    var has_rtm_quadrature = false;
    if (request.rtm_config.rtm_controls.integrate_source_function) {

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

            const rtm_quadrature_request = OpticsPreparation.rtm_quadrature.RtmQuadratureCarrierRequest{
                .prepared = request.prepared,
                .layer_inputs = input.layers,
                .rtm_levels = scratch.rtm_quadrature_levels[0 .. input.layers.len + 1],
                .wavelength_cache = &wavelength_cache,
                .wavelength_nm = request.wavelength_nm,
                .compute_jacobian = compute_jacobian,
            };
            has_rtm_quadrature =
                OpticsPreparation.rtm_quadrature.fillRtmQuadratureAtWavelengthWithLayersAndCarrierCache(
                    &rtm_quadrature_request,
                );
        }

        if (has_rtm_quadrature) {
            input.rtm_quadrature = .{
                .levels = scratch.rtm_quadrature_levels[0 .. input.layers.len + 1],
                .aerosol_phase_coefficients = &request.prepared.aerosol_phase_coefficients,
            };
        } else if (request.prepared.interval_semantics != .none) {

            // Explicit-interval integrated-source cases must stay on the RTM-native carrier path. The coarse
            // source-interface fallback would use a different vertical contract.
            return error.MissingExplicitRtmQuadrature;
        }
    }

    if (request.rtm_config.rtm_controls.integrate_source_function and !has_rtm_quadrature) {
        const source_interface_slice = scratch.source_interfaces[0 .. input.layers.len + 1];

        {

            // instrumentation: trace zone: source interfaces ------------------------------------------------------------|
            // captures: source-interface fill wall time                                                                  |
            // why: quantifies the fallback source-function boundary when RTM quadrature is unavailable.                  |
            const zone = Trace.deepStaticZone(@src(), "forward_input.source_interfaces");
            defer zone.end();
            // end instrumentation: trace zone: source interfaces --------------------------------------------------------|

            OpticsPreparation.source_interfaces.fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
                request.prepared,
                request.wavelength_nm,
                input.layers,
                source_interface_slice,
                &wavelength_cache,
            );
        }

        input.source_interfaces = source_interface_slice;
    }

    if (request.rtm_config.rtm_controls.use_spherical_correction) {

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

            const pseudo_spherical_request = OpticsPreparation.pseudo_spherical.PseudoSphericalCarrierRequest{
                .prepared = request.prepared,
                .scene = request.scene,
                .attenuation_samples = scratch.pseudo_spherical_samples,
                .level_sample_starts = scratch.pseudo_spherical_level_starts,
                .level_altitudes_km = scratch.pseudo_spherical_level_altitudes,
                .wavelength_cache = &wavelength_cache,
                .wavelength_nm = request.wavelength_nm,
                .solver_layer_count = input.layers.len,
            };
            break :has_grid OpticsPreparation.pseudo_spherical.fillPseudoSphericalGridAtWavelengthWithCarrierCache(
                &pseudo_spherical_request,
            );
        };

        if (has_pseudo_spherical_grid) {
            const pseudo_spherical_sample_count = scratch.pseudo_spherical_level_starts[input.layers.len];
            input.pseudo_spherical_grid = .{
                .samples = scratch.pseudo_spherical_samples[0..pseudo_spherical_sample_count],
                .level_sample_starts = scratch.pseudo_spherical_level_starts[0 .. input.layers.len + 1],
                .level_altitudes_km = scratch.pseudo_spherical_level_altitudes[0 .. input.layers.len + 1],
            };
        }
    }

    input.rtm_controls = request.rtm_config.rtm_controls;
    return input;
}
