const std = @import("std");
const Scene = @import("../../../input/Scene.zig").Scene;
const OpticsPreparation = @import("../../optical_properties/root.zig");
const CarrierEval = @import("../../optical_properties/state_build/carrier_eval.zig");
const common = @import("../../radiative_transfer/root.zig");
const Storage = @import("storage.zig");

pub const Profile = struct {
    mutex: std.Thread.Mutex = .{},
    cache_ns: i128 = 0,
    layers_ns: i128 = 0,
    rtm_ns: i128 = 0,
    source_ns: i128 = 0,
    pseudo_ns: i128 = 0,
    calls: usize = 0,

    pub fn add(
        self: *Profile,
        cache_ns: i128,
        layers_ns: i128,
        rtm_ns: i128,
        source_ns: i128,
        pseudo_ns: i128,
    ) void {
        self.mutex.lock();
        defer self.mutex.unlock();
        self.cache_ns += cache_ns;
        self.layers_ns += layers_ns;
        self.rtm_ns += rtm_ns;
        self.source_ns += source_ns;
        self.pseudo_ns += pseudo_ns;
        self.calls += 1;
    }

    pub fn print(self: *const Profile) void {
        std.debug.print(
            "[zds-profile] configured_input_calls={} cache={d:.3}ms layers={d:.3}ms rtm_quadrature={d:.3}ms source_interfaces={d:.3}ms pseudo_spherical={d:.3}ms\n",
            .{
                self.calls,
                @as(f64, @floatFromInt(self.cache_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.layers_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.rtm_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.source_ns)) / 1.0e6,
                @as(f64, @floatFromInt(self.pseudo_ns)) / 1.0e6,
            },
        );
    }
};

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
    profile: ?*Profile,
) common.ExecuteError!common.ForwardInput {
    const should_profile = profile != null;
    const cache_start = if (should_profile) std.time.nanoTimestamp() else 0;
    var wavelength_cache = CarrierEval.WavelengthCarrierCache.init(
        prepared,
        wavelength_nm,
        support_carrier_valid,
        support_carriers,
    );
    const layers_start = if (should_profile) std.time.nanoTimestamp() else 0;
    const optical_depths = OpticsPreparation.transport.fillForwardLayersAtWavelengthWithCarrierCache(
        prepared,
        scene,
        wavelength_nm,
        layer_inputs,
        &wavelength_cache,
    );
    var input = OpticsPreparation.transport.forwardInputFromOpticalDepths(
        prepared,
        scene,
        wavelength_nm,
        optical_depths,
        layer_inputs,
    );
    const rtm_start = if (should_profile) std.time.nanoTimestamp() else 0;
    const source_interface_slice = source_interfaces[0 .. input.layers.len + 1];
    input.source_interfaces = source_interface_slice;
    var has_rtm_quadrature = false;
    if (route.rtm_controls.integrate_source_function) {
        // DECISION:
        //   Only attach RTM quadrature when the route requests integrated
        //   source-function evaluation.
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
        } else if (prepared.interval_semantics != .none) {
            // INVARIANT:
            //   The explicit-interval integrated-source route must stay on
            //   the RTM-native carrier path instead of silently drifting back
            //   to the coarse source-interface fallback.
            return error.MissingExplicitRtmQuadrature;
        }
    }
    const source_start = if (should_profile) std.time.nanoTimestamp() else 0;
    if (!has_rtm_quadrature) {
        OpticsPreparation.transport.fillSourceInterfacesAtWavelengthWithLayersAndCarrierCache(
            prepared,
            wavelength_nm,
            input.layers,
            source_interface_slice,
            &wavelength_cache,
        );
    }
    const pseudo_start = if (should_profile) std.time.nanoTimestamp() else 0;
    if (route.rtm_controls.use_spherical_correction) {
        // DECISION:
        //   Pseudo-spherical samples are only attached for routes that request
        //   the geometric correction. Explicit shared-grid routes rebuild the
        //   dense wavelength-specific attenuation contract directly from the
        //   RTM subgrid instead of reusing midpoint-style layer surrogates.
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
    }
    if (profile) |profiler| {
        const end = std.time.nanoTimestamp();
        profiler.add(
            layers_start - cache_start,
            rtm_start - layers_start,
            source_start - rtm_start,
            pseudo_start - source_start,
            end - pseudo_start,
        );
    }
    input.rtm_controls = route.rtm_controls;
    return input;
}
