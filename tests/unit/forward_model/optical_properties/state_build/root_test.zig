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

test "prepared layer layout matches documented support-tail comments" {
    const State = internal.forward_model.optical_properties.state;

    try std.testing.expectEqual(@as(usize, 208), @sizeOf(State.PreparedLayer));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(State.PreparedLayer));
    try expectOffset(State.PreparedLayer, "aerosol_optical_depth", 0);
    try expectOffset(State.PreparedLayer, "altitude_km", 24);
    try expectOffset(State.PreparedLayer, "gas_optical_depth", 104);
    try expectOffset(State.PreparedLayer, "optical_depth", 168);
    try expectOffset(State.PreparedLayer, "top_altitude_km", 176);
    try expectOffset(State.PreparedLayer, "gas_scattering_optical_depth", 184);
    try expectOffset(State.PreparedLayer, "sublayer_start_index", 192);
    try expectOffset(State.PreparedLayer, "layer_index", 196);
    try expectOffset(State.PreparedLayer, "interval_index_1based", 200);
    try expectOffset(State.PreparedLayer, "sublayer_count", 204);
}

test "prepared optical state layout matches documented comments" {
    const PreparedOpticalState = internal.forward_model.optical_properties.PreparedOpticalState;

    try std.testing.expectEqual(@as(usize, 2136), @sizeOf(PreparedOpticalState));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(PreparedOpticalState));
    try expectOffset(PreparedOpticalState, "gas_optical_depth", 0);
    try expectOffset(PreparedOpticalState, "operational_o2o2_lut", 8);
    try expectOffset(PreparedOpticalState, "strong_line_states", 80);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_strong_line_states", 96);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_weak_line_states", 112);
    try expectOffset(PreparedOpticalState, "shared_rtm_geometry", 128);
    try expectOffset(PreparedOpticalState, "continuum_points", 160);
    try expectOffset(PreparedOpticalState, "lut_execution_entries", 176);
    try expectOffset(PreparedOpticalState, "collision_induced_absorption", 192);
    try expectOffset(PreparedOpticalState, "generated_lut_assets", 224);
    try expectOffset(PreparedOpticalState, "spectroscopy_lines", 240);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_altitudes_km", 456);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_pressures_hpa", 472);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_temperatures_k", 488);
    try expectOffset(PreparedOpticalState, "line_mixing_mean_cross_section_cm2_per_molecule", 504);
    try expectOffset(PreparedOpticalState, "column_density_factor", 512);
    try expectOffset(PreparedOpticalState, "aerosol_fraction_control", 520);
    try expectOffset(PreparedOpticalState, "spectroscopy_plan_key", 600);
    try expectOffset(PreparedOpticalState, "effective_air_mass_factor", 608);
    try expectOffset(PreparedOpticalState, "cross_section_absorbers", 616);
    try expectOffset(PreparedOpticalState, "line_absorbers", 632);
    try expectOffset(PreparedOpticalState, "aerosol_base_optical_depth", 648);
    try expectOffset(PreparedOpticalState, "operational_o2_lut", 656);
    try expectOffset(PreparedOpticalState, "aerosol_optical_depth", 728);
    try expectOffset(PreparedOpticalState, "total_optical_depth", 736);
    try expectOffset(PreparedOpticalState, "depolarization_factor", 744);
    try expectOffset(PreparedOpticalState, "mean_cross_section_cm2_per_molecule", 752);
    try expectOffset(PreparedOpticalState, "line_mean_cross_section_cm2_per_molecule", 760);
    try expectOffset(PreparedOpticalState, "sublayers", 768);
    try expectOffset(PreparedOpticalState, "layers", 784);
    try expectOffset(PreparedOpticalState, "spectroscopy_profile_cache_inputs_key", 800);
    try expectOffset(PreparedOpticalState, "effective_single_scatter_albedo", 808);
    try expectOffset(PreparedOpticalState, "aerosol_single_scatter_albedo", 816);
    try expectOffset(PreparedOpticalState, "aerosol_phase_coefficients", 824);
    try expectOffset(PreparedOpticalState, "effective_temperature_k", 2032);
    try expectOffset(PreparedOpticalState, "effective_pressure_hpa", 2040);
    try expectOffset(PreparedOpticalState, "air_column_density_factor", 2048);
    try expectOffset(PreparedOpticalState, "oxygen_column_density_factor", 2056);
    try expectOffset(PreparedOpticalState, "cia_mean_cross_section_cm5_per_molecule2", 2064);
    try expectOffset(PreparedOpticalState, "cia_pair_path_factor_cm5", 2072);
    try expectOffset(PreparedOpticalState, "aerosol_reference_wavelength_nm", 2080);
    try expectOffset(PreparedOpticalState, "aerosol_angstrom_exponent", 2088);
    try expectOffset(PreparedOpticalState, "cia_optical_depth", 2096);
    try expectOffset(PreparedOpticalState, "d_optical_depth_d_temperature", 2104);
    try expectOffset(PreparedOpticalState, "fit_interval_index_1based", 2112);
    try expectOffset(PreparedOpticalState, "owns_spectroscopy_profile_strong_line_states", 2116);
    try expectOffset(PreparedOpticalState, "has_aerosol_profile_properties", 2117);
    try expectOffset(PreparedOpticalState, "owns_spectroscopy_profile_arrays", 2118);
    try expectOffset(PreparedOpticalState, "owns_operational_o2o2_lut", 2119);
    try expectOffset(PreparedOpticalState, "owns_operational_o2_lut", 2120);
    try expectOffset(PreparedOpticalState, "interval_semantics", 2121);
    try expectOffset(PreparedOpticalState, "continuum_owner_species", 2122);
    try expectOffset(PreparedOpticalState, "aerosol_phase_support", 2124);
    try expectOffset(PreparedOpticalState, "owns_spectroscopy_profile_weak_line_states", 2125);
    try expectOffset(PreparedOpticalState, "owns_collision_induced_absorption", 2126);
    try expectOffset(PreparedOpticalState, "owns_generated_lut_assets", 2127);
    try expectOffset(PreparedOpticalState, "owns_continuum_points", 2128);
    try expectOffset(PreparedOpticalState, "owns_lut_execution_entries", 2129);
}

test "shared RTM geometry layouts match documented comments" {
    const State = internal.forward_model.optical_properties.state;
    const SharedCarrier = internal.forward_model.optical_properties.shared_carrier;
    const SharedGeometry = internal.forward_model.optical_properties.shared_geometry;

    try std.testing.expectEqual(@as(usize, 40), @sizeOf(State.SharedRtmLayerGeometry));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(State.SharedRtmLayerGeometry));
    try expectOffset(State.SharedRtmLayerGeometry, "lower_altitude_km", 0);
    try expectOffset(State.SharedRtmLayerGeometry, "upper_altitude_km", 8);
    try expectOffset(State.SharedRtmLayerGeometry, "midpoint_altitude_km", 16);
    try expectOffset(State.SharedRtmLayerGeometry, "thickness_km", 24);
    try expectOffset(State.SharedRtmLayerGeometry, "support_start_index", 32);
    try expectOffset(State.SharedRtmLayerGeometry, "support_count", 36);

    try std.testing.expectEqual(@as(usize, 40), @sizeOf(State.SharedRtmLevelGeometry));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(State.SharedRtmLevelGeometry));
    try expectOffset(State.SharedRtmLevelGeometry, "altitude_km", 0);
    try expectOffset(State.SharedRtmLevelGeometry, "weight_km", 8);
    try expectOffset(State.SharedRtmLevelGeometry, "support_start_index", 16);
    try expectOffset(State.SharedRtmLevelGeometry, "support_count", 20);
    try expectOffset(State.SharedRtmLevelGeometry, "support_row_index", 24);
    try expectOffset(State.SharedRtmLevelGeometry, "particle_above_support_row_index", 28);
    try expectOffset(State.SharedRtmLevelGeometry, "particle_below_support_row_index", 32);

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(State.SharedRtmGeometry));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(State.SharedRtmGeometry));
    try expectOffset(State.SharedRtmGeometry, "layers", 0);
    try expectOffset(State.SharedRtmGeometry, "levels", 16);

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SharedCarrier.SharedRtmSubgrid));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(SharedCarrier.SharedRtmSubgrid));
    try expectOffset(SharedCarrier.SharedRtmSubgrid, "altitudes_km", 0);
    try expectOffset(SharedCarrier.SharedRtmSubgrid, "weights_km", 16);

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SharedGeometry.ResolvedGaussRule));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(SharedGeometry.ResolvedGaussRule));
    try expectOffset(SharedGeometry.ResolvedGaussRule, "nodes", 0);
    try expectOffset(SharedGeometry.ResolvedGaussRule, "weights", 16);

    try std.testing.expectEqual(@as(usize, 2048), @sizeOf(SharedGeometry.GaussRuleScratch));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(SharedGeometry.GaussRuleScratch));
    try expectOffset(SharedGeometry.GaussRuleScratch, "nodes", 0);
    try expectOffset(SharedGeometry.GaussRuleScratch, "weights", 1024);

    try std.testing.expectEqual(@as(usize, 48), @sizeOf(SharedGeometry.SharedRtmInterval));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(SharedGeometry.SharedRtmInterval));
    try expectOffset(SharedGeometry.SharedRtmInterval, "lower_altitude_km", 0);
    try expectOffset(SharedGeometry.SharedRtmInterval, "upper_altitude_km", 8);
    try expectOffset(SharedGeometry.SharedRtmInterval, "support_sublayers", 16);
    try expectOffset(SharedGeometry.SharedRtmInterval, "strong_line_states", 32);

    try std.testing.expectEqual(@as(usize, 32), @sizeOf(SharedGeometry.SharedSupportSlices));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(SharedGeometry.SharedSupportSlices));
    try expectOffset(SharedGeometry.SharedSupportSlices, "sublayers", 0);
    try expectOffset(SharedGeometry.SharedSupportSlices, "strong_line_states", 16);
}

fn expectOffset(comptime Struct: type, comptime field_name: []const u8, expected: usize) !void {
    try std.testing.expectEqual(expected, @offsetOf(Struct, field_name));
}
