const std = @import("std");
const common = @import("common.zig");
const derivatives = @import("derivatives.zig");
const doubling = @import("doubling.zig");

const ReflectanceComponents = struct {
    toa_reflectance_factor: f64,
    surface_term: f64,
    scattering_term: f64,
};

pub fn execute(route: common.Route, input: common.ForwardInput) common.ExecuteError!common.ForwardResult {
    if (route.family != .adding) unreachable;

    // Adding solver lane intentionally does not accept plugin analytical derivatives.
    if (route.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }

    const total_scattering_optical_depth = input.gas_scattering_optical_depth +
        input.aerosol_scattering_optical_depth +
        input.cloud_scattering_optical_depth;
    const surface_path_factor = (1.0 / input.mu0) + (1.0 / input.muv);
    const scattering_path_factor = 0.5 * surface_path_factor;

    const components = if (input.layers.len == 0)
        aggregateReflectance(input, total_scattering_optical_depth, surface_path_factor, scattering_path_factor)
    else
        try layerResolvedReflectance(input);

    return .{
        .family = route.family,
        .regime = route.regime,
        .execution_mode = route.execution_mode,
        .derivative_mode = route.derivative_mode,
        .toa_reflectance_factor = components.toa_reflectance_factor,
        .jacobian_column = switch (route.derivative_mode) {
            .none => null,
            .semi_analytical => derivatives.proxyOpticalDepthSensitivity(
                components.surface_term,
                components.scattering_term,
                surface_path_factor,
                scattering_path_factor,
            ),
            .analytical_plugin => null,
            .numerical => derivatives.proxyOpticalDepthSensitivity(
                components.surface_term,
                components.scattering_term,
                surface_path_factor,
                scattering_path_factor,
            ),
        },
    };
}

fn aggregateReflectance(
    input: common.ForwardInput,
    total_scattering_optical_depth: f64,
    surface_path_factor: f64,
    scattering_path_factor: f64,
) ReflectanceComponents {
    const atmosphere_reflectance = std.math.clamp(
        (input.mu0 / @max(input.mu0 + input.muv, 1.0e-6)) *
            total_scattering_optical_depth *
            input.single_scatter_albedo *
            std.math.exp(-0.5 * input.optical_depth * scattering_path_factor),
        0.0,
        1.0,
    );
    const atmosphere_transmittance = std.math.exp(-0.5 * input.optical_depth);
    _ = surface_path_factor;
    const surface_term = input.surface_albedo *
        atmosphere_transmittance *
        atmosphere_transmittance /
        @max(1.0 - input.surface_albedo * atmosphere_reflectance, 1.0e-6);
    return .{
        .toa_reflectance_factor = std.math.clamp(surface_term + atmosphere_reflectance, 0.0, 1.5),
        .surface_term = surface_term,
        .scattering_term = atmosphere_reflectance,
    };
}

fn layerResolvedReflectance(
    input: common.ForwardInput,
) common.ExecuteError!ReflectanceComponents {
    var index = input.layers.len - 1;
    var atmosphere = try doubling.propagateLayer(input.layers[index], 2);
    while (index > 0) {
        index -= 1;
        atmosphere = try doubling.addUpperOverLower(
            try doubling.propagateLayer(input.layers[index], 2),
            atmosphere,
        );
    }

    const direct_surface_term = input.surface_albedo *
        atmosphere.direct_down_transmittance *
        atmosphere.transmittance;
    const surface_illumination = atmosphere.direct_down_transmittance + atmosphere.downward_source;
    const diffuse_surface_term = input.surface_albedo *
        surface_illumination *
        atmosphere.transmittance /
        @max(1.0 - input.surface_albedo * atmosphere.reflectance, 1.0e-6);
    const coupled_surface_term = @max(diffuse_surface_term, direct_surface_term);
    const atmospheric_term = atmosphere.reflectance + atmosphere.source_reflectance;
    return .{
        .toa_reflectance_factor = std.math.clamp(atmospheric_term + coupled_surface_term, 0.0, 1.5),
        .surface_term = coupled_surface_term,
        .scattering_term = atmospheric_term,
    };
}

test "adding execution returns deterministic scalar output" {
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{ .use_adding = true },
    });
    const result = try execute(route, .{
        .spectral_weight = 1.2,
        .air_mass_factor = 0.8,
    });

    try std.testing.expectEqual(common.TransportFamily.adding, result.family);
    try std.testing.expect(result.toa_reflectance_factor > 0.0);
    try std.testing.expectEqual(@as(?f64, null), result.jacobian_column);
}
