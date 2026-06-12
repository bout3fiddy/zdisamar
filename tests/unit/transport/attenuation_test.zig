const std = @import("std");

const internal = @import("internal");

const attenuation = internal.transport.attenuation;
const curved_sun_path = internal.optics.curved_sun_path;
const gauss_angles = internal.transport.gauss_angles;
const layer_depths = internal.optics.layer_depths;

const earth_radius_km: f64 = 6371.0;
const spherical_denominator_floor: f64 = 1.0e-12;

test "runtime attenuation uses adjacent table and top-to-level products" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const layers = testLayers();
    var layer_transmittance: [32]f64 = undefined;
    var top_to_level: [40]f64 = undefined;

    const runtime = try attenuation.fillRuntimeInBuffers(
        &layer_transmittance,
        &top_to_level,
        &layers,
        .{},
        &geometry,
        false,
    );

    try std.testing.expectEqual(@as(usize, geometry.stream_count), runtime.stream_count);
    try std.testing.expectEqual(@as(usize, layers.len + 1), runtime.level_count);
    for (0..geometry.stream_count) |stream_index| {
        for (0..layers.len) |layer_index| {
            try expectClose(
                scalarLayerTransmittance(layers[layer_index], geometry.u[stream_index]),
                runtime.adjacent(stream_index, layer_index),
                1.0e-15,
            );
        }

        try expectClose(
            scalarPathTransmittance(layers[0..], geometry.u[stream_index], 0, layers.len),
            runtime.get(stream_index, layers.len, 0),
            1.0e-15,
        );
        try expectClose(
            scalarPathTransmittance(layers[0..], geometry.u[stream_index], 0, 2),
            runtime.get(stream_index, 0, 2),
            1.0e-15,
        );
        try expectClose(
            scalarPathTransmittance(layers[0..], geometry.u[stream_index], 1, 3),
            runtime.get(stream_index, 3, 1),
            1.0e-15,
        );
    }
}

test "dynamic attenuation expands every level pair from layer cache" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const layers = testLayers();
    var data: [8 * 4 * 4]f64 = undefined;
    var layer_transmittance: [8 * 3]f64 = undefined;

    const dynamic = try attenuation.fillDynamicWithLayerCache(
        &data,
        &layer_transmittance,
        &layers,
        .{},
        &geometry,
        false,
    );

    try std.testing.expectEqual(@as(usize, geometry.stream_count), dynamic.stream_count);
    try std.testing.expectEqual(@as(usize, layers.len + 1), dynamic.level_count);
    for (0..geometry.stream_count) |stream_index| {
        for (0..layers.len + 1) |from_level| {
            for (0..layers.len + 1) |to_level| {
                try expectClose(
                    scalarPathTransmittance(layers[0..], geometry.u[stream_index], from_level, to_level),
                    dynamic.get(stream_index, from_level, to_level),
                    1.0e-15,
                );
            }
        }
    }
}

test "pseudo-spherical correction replaces top-to-level attenuation only" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const layers = testLayers();
    const curved_grid = testCurvedGrid();
    var layer_transmittance: [32]f64 = undefined;
    var top_to_level: [40]f64 = undefined;

    const runtime = try attenuation.fillRuntimeInBuffers(
        &layer_transmittance,
        &top_to_level,
        &layers,
        curved_grid,
        &geometry,
        true,
    );

    const stream_index = geometry.solarIndex();
    try expectClose(
        scalarLayerTransmittance(layers[0], geometry.u[stream_index]),
        runtime.adjacent(stream_index, 0),
        1.0e-15,
    );
    try expectClose(
        scalarCurvedTopToLevel(curved_grid, geometry.u[stream_index], 0),
        runtime.get(stream_index, layers.len, 0),
        1.0e-15,
    );
    try expectClose(
        scalarPathTransmittance(layers[0..], geometry.u[stream_index], 0, 2),
        runtime.get(stream_index, 0, 2),
        1.0e-15,
    );
}

test "enabled pseudo-spherical correction rejects missing curved grid" {
    const geometry = try gauss_angles.GaussGeometry.init(4, 0.58, 0.64);
    const layers = testLayers();
    var layer_transmittance: [32]f64 = undefined;
    var top_to_level: [40]f64 = undefined;

    try std.testing.expectError(
        error.UnsupportedRadiativeTransferControls,
        attenuation.fillRuntimeInBuffers(
            &layer_transmittance,
            &top_to_level,
            &layers,
            .{},
            &geometry,
            true,
        ),
    );
}

fn testLayers() [3]layer_depths.LayerOptics {
    // testLayers -------------------------------------------------------------------------------------------- |
    // Build deterministic optical-depth rows for attenuation tests.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .{ .total_optical_depth = 0.017 },
        .{ .total_optical_depth = 0.031 },
        .{ .total_optical_depth = 0.043 },
    };
}

fn testCurvedGrid() attenuation.CurvedSunPathGrid {
    // testCurvedGrid ---------------------------------------------------------------------------------------- |
    // Build a small valid pseudo-spherical support grid with one sample in each lower level span.             |
    // --------------------------------------------------------------------------------------------------------|
    return .{
        .samples = &.{
            .{ .altitude_km = 0.5, .thickness_km = 0.2, .optical_depth = 0.012 },
            .{ .altitude_km = 1.8, .thickness_km = 0.2, .optical_depth = 0.018 },
            .{ .altitude_km = 3.2, .thickness_km = 0.2, .optical_depth = 0.024 },
        },
        .level_sample_starts = &.{ 0, 1, 2, 3 },
        .level_altitudes_km = &.{ 0.0, 1.0, 2.5, 4.0 },
    };
}

fn scalarLayerTransmittance(layer: layer_depths.LayerOptics, stream_mu: f64) f64 {
    // scalarLayerTransmittance ------------------------------------------------------------------------------ |
    // Independent scalar adjacent-layer direct-beam survival.                                                 |
    // --------------------------------------------------------------------------------------------------------|
    return std.math.exp(-layer.total_optical_depth / @max(stream_mu, 1.0e-6));
}

fn scalarPathTransmittance(
    layers: []const layer_depths.LayerOptics,
    stream_mu: f64,
    from_level: usize,
    to_level: usize,
) f64 {
    // scalarPathTransmittance ------------------------------------------------------------------------------- |
    // Independent scalar product of adjacent layer survival between two levels.                               |
    // --------------------------------------------------------------------------------------------------------|
    const start = @min(from_level, to_level);
    const end = @max(from_level, to_level);
    var product: f64 = 1.0;

    for (start..end) |layer_index| {
        product *= scalarLayerTransmittance(layers[layer_index], stream_mu);
    }
    return product;
}

fn scalarCurvedTopToLevel(
    curved_grid: attenuation.CurvedSunPathGrid,
    stream_mu: f64,
    level: usize,
) f64 {
    // scalarCurvedTopToLevel -------------------------------------------------------------------------------- |
    // Independent scalar pseudo-spherical top-to-level support-sample integral.                               |
    // --------------------------------------------------------------------------------------------------------|
    const mu = std.math.clamp(stream_mu, -1.0, 1.0);
    const sin2theta = @max(1.0 - mu * mu, 0.0);
    const level_radius = earth_radius_km + curved_grid.level_altitudes_km[level];
    const sqrx_sin2theta = sin2theta * level_radius * level_radius;
    var optical_depth_sum: f64 = 0.0;

    for (curved_grid.level_sample_starts[level]..curved_grid.samples.len) |sample_index| {
        const sample = curved_grid.samples[sample_index];
        const sample_radius = earth_radius_km + sample.altitude_km;
        const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
        const numerator = sample.optical_depth * sample_radius;
        optical_depth_sum += numerator / @max(denominator, spherical_denominator_floor);
    }

    return std.math.exp(-optical_depth_sum);
}

fn expectClose(expected: f64, actual: f64, tolerance: f64) !void {
    // expectClose ------------------------------------------------------------------------------------------- |
    // Compare scalar attenuation values with roundoff tolerance.                                              |
    // --------------------------------------------------------------------------------------------------------|
    try std.testing.expectApproxEqAbs(expected, actual, tolerance);
}
