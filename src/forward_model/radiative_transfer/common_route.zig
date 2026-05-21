const common = @import("common_types.zig");

pub fn prepareRoute(request: common.DispatchRequest) common.PrepareError!common.Route {
    if (request.regime != .nadir) return common.Error.UnsupportedObservationRegime;
    if (request.derivative_mode == .numerical) return common.Error.UnsupportedDerivativeMode;
    try request.rtm_controls.validate();
    return .{
        .family = .labos,
        .regime = request.regime,
        .execution_mode = request.execution_mode,
        .derivative_mode = request.derivative_mode,
        .rtm_controls = request.rtm_controls,
    };
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
        .ksca_above = @max(layers[above_index].scattering_optical_depth, 0.0),
        .phase_above = layers[above_index].phase,
        .phase_max_index_above = layers[above_index].phase.maxIndex(),
        .phase_max_index_below = if (ilevel > 0)
            layers[below_index].phase.maxIndex()
        else
            0,
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
