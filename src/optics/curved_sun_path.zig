const atmosphere_layers = @import("../setup/atmosphere_layers.zig");
const layer_depths = @import("layer_depths.zig");

// curved_sun_path.zig ----------------------------------------------------------------------------------------|
// Builds pseudo-spherical direct-beam attenuation samples from shared support-row optics.                     |
//                                                                                                             |
//   path, which delegates to shared support rows and emits only active support samples for the shared-RTM     |
//   geometry. The support-row optical depths are already wavelength-specific.                                 |
//                                                                                                             |
// boundary                                                                                                    |
//   This module only maps support-row storage into the curved-path sample grid. Path geometry factors are     |
//   applied later by LABOS attenuation code.                                                                  |
// ------------------------------------------------------------------------------------------------------------|

// CurvedSunPathSample ----------------------------------------------------------------------------------------|
// One support-grid sample for pseudo-spherical direct-beam attenuation.                                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 24 B (0.023 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] altitude_km   : f64                                                                                |
// [ 8..15] thickness_km  : f64                                                                                |
// [16..23] optical_depth : f64                                                                                |
//                                                                                                             |
// footprint: per instance = 24 B (0.023 KiB); total = per instance * active support-row count                 |
pub const CurvedSunPathSample = struct {
    altitude_km: f64 = 0.0,
    thickness_km: f64 = 0.0,
    optical_depth: f64 = 0.0,
};
// ------------------------------------------------------------------------------------------------------------|

pub fn fillCurvedSunPathSamples(
    layer_grid: atmosphere_layers.LayerGrid,
    support_rows: []const layer_depths.SupportOptics,
    out_samples: []CurvedSunPathSample,
    level_sample_starts: []usize,
    level_altitudes_km: []f64,
) !usize {
    // fillCurvedSunPathSamples -------------------------------------------------------------------------------|
    // Expand each layer's active support rows into pseudo-spherical attenuation samples.                      |
    //                                                                                                         |
    // math                                                                                                    |
    //   thickness_km = support_path_length_cm / 1e5                                                           |
    //   sample optical depth is the already-integrated support-row total optical depth.                       |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layer_grid.layer_pressures_hpa.len;
    if (support_rows.len != layer_grid.support_mid_altitudes_km.len or
        level_sample_starts.len != layer_count + 1 or
        level_altitudes_km.len != layer_count + 1)
    {
        return error.InvalidShape;
    }

    const required_sample_count = activeSupportSampleCount(layer_grid);
    if (out_samples.len < required_sample_count) return error.InvalidShape;

    for (level_altitudes_km, 0..) |*altitude_km, level_index| {
        altitude_km.* = layer_grid.support_mid_altitudes_km[boundarySupportRowIndex(layer_grid, level_index)];
    }

    var sample_index: usize = 0;
    const support_count: usize = @intCast(layer_grid.layer_support_count);
    for (0..layer_count) |layer_index| {
        level_sample_starts[layer_index] = sample_index;

        const support_start: usize = @intCast(layer_grid.layer_support_starts[layer_index]);
        if (support_start + support_count > support_rows.len) return error.InvalidShape;
        if (support_count <= 2) continue;

        for (support_rows[support_start + 1 .. support_start + support_count - 1]) |support| {
            out_samples[sample_index] = .{
                .altitude_km = support.altitude_km,
                .thickness_km = support.path_length_cm / 1.0e5,
                .optical_depth = support.total_optical_depth,
            };
            sample_index += 1;
        }
    }

    level_sample_starts[layer_count] = sample_index;
    return sample_index;
}

fn activeSupportSampleCount(layer_grid: atmosphere_layers.LayerGrid) usize {
    // activeSupportSampleCount -------------------------------------------------------------------------------|
    // Count active support rows after excluding lower and upper boundary rows from each layer span.           |
    // --------------------------------------------------------------------------------------------------------|
    const support_count: usize = @intCast(layer_grid.layer_support_count);
    if (support_count <= 2) return 0;
    return layer_grid.layer_support_starts.len * (support_count - 2);
}

fn boundarySupportRowIndex(layer_grid: atmosphere_layers.LayerGrid, level_index: usize) usize {
    // boundarySupportRowIndex --------------------------------------------------------------------------------|
    // Map a model level to the shared boundary support row used for level altitudes.                          |
    // --------------------------------------------------------------------------------------------------------|
    if (level_index == layer_grid.layer_pressures_hpa.len) {
        const last_layer = level_index - 1;
        return @as(usize, @intCast(layer_grid.layer_support_starts[last_layer])) +
            @as(usize, @intCast(layer_grid.layer_support_count)) -
            1;
    }

    return @intCast(layer_grid.layer_support_starts[level_index]);
}
