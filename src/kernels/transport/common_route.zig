const common = @import("common_types.zig");
const phase_functions = @import("../optics/prepare/phase_functions.zig");

pub fn prepareRoute(request: common.DispatchRequest) common.PrepareError!common.Route {
    if (request.derivative_mode == .analytical_plugin) {
        return common.Error.UnsupportedDerivativeMode;
    }
    try request.rtm_controls.validate(request.execution_mode);
    const family = selectFamily(request);
    if (family == .adding and request.execution_mode != .scalar) {
        return common.Error.UnsupportedExecutionMode;
    }
    return .{
        .family = family,
        .regime = request.regime,
        .execution_mode = request.execution_mode,
        .derivative_mode = request.derivative_mode,
        .rtm_controls = request.rtm_controls,
    };
}

fn selectFamily(request: common.DispatchRequest) common.TransportFamily {
    if (request.rtm_controls.use_adding) return .adding;
    if (request.regime != .nadir) return .labos;
    return .labos;
}

pub fn sourceInterfaceFromLayers(layers: []const common.LayerInput, ilevel: usize) common.SourceInterfaceInput {
    if (layers.len == 0) return .{};
    const above_index = @min(ilevel, layers.len - 1);
    const below_index = if (ilevel > 0) ilevel - 1 else above_index;
    const source_weight = if (ilevel < layers.len)
        @max(layers[ilevel].scattering_optical_depth, 0.0)
    else
        0.5 * @max(layers[above_index].scattering_optical_depth, 0.0);

    return .{
        .source_weight = source_weight,
        .particle_ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .particle_ksca_below = if (ilevel > 0)
            @max(layers[below_index].scattering_optical_depth, 0.0)
        else
            0.0,
        .ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .ksca_below = if (ilevel > 0)
            @max(layers[below_index].scattering_optical_depth, 0.0)
        else
            0.0,
        .phase_coefficients_above = layers[above_index].phase_coefficients,
        .phase_coefficients_below = if (ilevel > 0)
            layers[below_index].phase_coefficients
        else
            phase_functions.zeroPhaseCoefficients(),
    };
}

pub fn fillSourceInterfacesFromLayers(
    layers: []const common.LayerInput,
    source_interfaces: []common.SourceInterfaceInput,
) void {
    if (layers.len == 0 or source_interfaces.len != layers.len + 1) return;
    for (source_interfaces, 0..) |*source_interface, ilevel| {
        source_interface.* = sourceInterfaceFromLayers(layers, ilevel);
    }
}
