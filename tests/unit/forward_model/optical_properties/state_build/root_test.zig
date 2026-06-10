const std = @import("std");
const internal = @import("internal");

test {
    const preparation = internal.forward_model.optical_properties;

    _ = preparation.state;
    _ = preparation.PreparationInputs;
    _ = preparation.prepare;
    _ = preparation.spectroscopy;
    _ = preparation.evaluation;
    _ = preparation.forward_layers;
    _ = preparation.source_interfaces;
    _ = preparation.rtm_quadrature;
    _ = preparation.pseudo_spherical;
    _ = preparation.shared_geometry;
}

test "owned vertical grid layout matches documented comments" {
    const VerticalGrid = internal.forward_model.optical_properties.internal.vertical_grid;

    try std.testing.expectEqual(@as(usize, 224), @sizeOf(VerticalGrid.OwnedVerticalGrid));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(VerticalGrid.OwnedVerticalGrid));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_top_altitudes_km"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_bottom_altitudes_km"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_top_pressures_hpa"));
    try std.testing.expectEqual(
        @as(usize, 48),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_bottom_pressures_hpa"),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_interval_indices_1based"),
    );
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_sublayer_starts"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(VerticalGrid.OwnedVerticalGrid, "layer_sublayer_counts"));
    try std.testing.expectEqual(
        @as(usize, 112),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_top_altitudes_km"),
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_bottom_altitudes_km"),
    );
    try std.testing.expectEqual(
        @as(usize, 144),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_top_pressures_hpa"),
    );
    try std.testing.expectEqual(
        @as(usize, 160),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_bottom_pressures_hpa"),
    );
    try std.testing.expectEqual(
        @as(usize, 176),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_mid_altitudes_km"),
    );
    try std.testing.expectEqual(
        @as(usize, 192),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_support_weights_km"),
    );
    try std.testing.expectEqual(
        @as(usize, 208),
        @offsetOf(VerticalGrid.OwnedVerticalGrid, "sublayer_interval_indices_1based"),
    );
}
