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

test "prepared means layout matches documented comments" {
    const Accumulation = internal.forward_model.optical_properties.internal.accumulation;

    try std.testing.expectEqual(@as(usize, 152), @sizeOf(Accumulation.PreparedMeans));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(Accumulation.PreparedMeans));
    try std.testing.expectEqual(
        @as(usize, 0),
        @offsetOf(Accumulation.PreparedMeans, "cross_section_mean_cm2_per_molecule"),
    );
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Accumulation.PreparedMeans, "line_means"));
    try std.testing.expectEqual(
        @as(usize, 24),
        @offsetOf(Accumulation.PreparedMeans, "cia_mean_cross_section_cm5_per_molecule2"),
    );
    try std.testing.expectEqual(
        @as(usize, 32),
        @offsetOf(Accumulation.PreparedMeans, "effective_air_mass_factor"),
    );
    try std.testing.expectEqual(
        @as(usize, 40),
        @offsetOf(Accumulation.PreparedMeans, "effective_single_scatter_albedo"),
    );
    try std.testing.expectEqual(
        @as(usize, 48),
        @offsetOf(Accumulation.PreparedMeans, "effective_temperature_k"),
    );
    try std.testing.expectEqual(
        @as(usize, 56),
        @offsetOf(Accumulation.PreparedMeans, "effective_pressure_hpa"),
    );
    try std.testing.expectEqual(
        @as(usize, 64),
        @offsetOf(Accumulation.PreparedMeans, "air_column_density_factor"),
    );
    try std.testing.expectEqual(
        @as(usize, 72),
        @offsetOf(Accumulation.PreparedMeans, "oxygen_column_density_factor"),
    );
    try std.testing.expectEqual(@as(usize, 80), @offsetOf(Accumulation.PreparedMeans, "column_density_factor"));
    try std.testing.expectEqual(@as(usize, 88), @offsetOf(Accumulation.PreparedMeans, "cia_pair_path_factor_cm5"));
    try std.testing.expectEqual(@as(usize, 96), @offsetOf(Accumulation.PreparedMeans, "gas_optical_depth"));
    try std.testing.expectEqual(@as(usize, 104), @offsetOf(Accumulation.PreparedMeans, "cia_optical_depth"));
    try std.testing.expectEqual(@as(usize, 112), @offsetOf(Accumulation.PreparedMeans, "aerosol_optical_depth"));
    try std.testing.expectEqual(
        @as(usize, 120),
        @offsetOf(Accumulation.PreparedMeans, "aerosol_base_optical_depth"),
    );
    try std.testing.expectEqual(
        @as(usize, 128),
        @offsetOf(Accumulation.PreparedMeans, "d_optical_depth_d_temperature"),
    );
    try std.testing.expectEqual(@as(usize, 136), @offsetOf(Accumulation.PreparedMeans, "total_optical_depth"));
    try std.testing.expectEqual(@as(usize, 144), @offsetOf(Accumulation.PreparedMeans, "depolarization_factor"));
}
