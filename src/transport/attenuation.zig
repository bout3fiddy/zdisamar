const std = @import("std");

const gauss_angles = @import("gauss_angles.zig");
const jacobian_states = @import("jacobian_states.zig");
const layer_depths = @import("../optics/layer_depths.zig");
const curved_sun_path = @import("../optics/curved_sun_path.zig");

const math = std.math;

pub const max_levels: usize = 65;

const direction_cosine_floor: f64 = 1.0e-6;
const spherical_denominator_floor: f64 = 1.0e-12;
const earth_radius_km: f64 = 6371.0;

// attenuation.zig ------------------------------------------------------------------------------------------- |
// Direct-beam attenuation tables for LABOS transport.                                                         |
//                                                                                                             |
// provenance                                                                                                  |
//   Ports main:`src/forward_model/radiative_transfer/labos/attenuation.zig` runtime and dynamic buffer-fill   |
//   paths over the new explicit `LayerOptics`, `GaussGeometry`, and `CurvedSunPathSample` rows.               |
//                                                                                                             |
// math                                                                                                        |
//   layer transmittance = exp(-tau_layer / max(mu, direction_cosine_floor))                                   |
//                                                                                                             |
//   pseudo-spherical top paths use                                                                            |
//                                                                                                             |
//              tau_sample * r_sample                                                                          |
//   -------------------------------------------                                                               |
//   sqrt(r_sample^2 - r_level^2 * sin(theta)^2)                                                               |
//                                                                                                             |
// storage                                                                                                     |
//   DynamicAttenuation : [direction, from_level, to_level] full table                                         |
//   RuntimeAttenuation : adjacent layer table plus top-to-level table                                         |
//                                                                                                             |
// memory                                                                                                      |
//   These views own no heap storage. Later transport worker memory owns the backing arrays and passes them    |
//   into these fill functions.                                                                                |
// ------------------------------------------------------------------------------------------------------------|

pub const Error = error{
    InvalidShape,
    UnsupportedRadiativeTransferControls,
};

// CurvedSunPathGrid ----------------------------------------------------------------------------------------- |
// Borrowed pseudo-spherical support rows and level metadata.                                                  |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] samples            : []const CurvedSunPathSample                                                   |
// [16..31] level_sample_starts: []const usize                                                                 |
// [32..47] level_altitudes_km : []const f64                                                                   |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: all slices are borrowed from optics/transport worker memory                             |
// footprint: per instance = 48 B (0.047 KiB); referenced rows are caller-owned                                |
pub const CurvedSunPathGrid = struct {
    samples: []const curved_sun_path.CurvedSunPathSample = &.{},
    level_sample_starts: []const usize = &.{},
    level_altitudes_km: []const f64 = &.{},

    pub fn isValidFor(self: CurvedSunPathGrid, layer_count: usize) bool {
        // CurvedSunPathGrid.isValidFor ---------------------------------------------------------------------- |
        // Validate the level-indexed pseudo-spherical support view.                                           |
        // ----------------------------------------------------------------------------------------------------|
        const level_count = layer_count + 1;
        if (self.level_sample_starts.len != level_count) return false;
        if (self.level_altitudes_km.len != level_count) return false;
        if (level_count == 0) return false;
        if (self.level_sample_starts[level_count - 1] != self.samples.len) return false;

        var previous: usize = 0;
        for (self.level_sample_starts) |start| {
            if (start < previous or start > self.samples.len) return false;
            previous = start;
        }
        return true;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// DynamicAttenuation ---------------------------------------------------------------------------------------- |
// Full direct-beam attenuation table for all direction/from/to level pairs.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] data        : []f64                                                                                |
// [16..23] stream_count: usize                                                                                |
// [24..31] level_count : usize                                                                                |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: data is borrowed from transport worker memory                                           |
// footprint: per instance = 32 B (0.031 KiB); referenced table has stream_count * level_count^2 f64 rows      |
pub const DynamicAttenuation = struct {
    data: []f64,
    stream_count: usize,
    level_count: usize,

    fn index(self: *const DynamicAttenuation, stream_index: usize, from_level: usize, to_level: usize) usize {
        // DynamicAttenuation.index -------------------------------------------------------------------------- |
        // Levels are matrix axes inside each direction block.                                                 |
        // ----------------------------------------------------------------------------------------------------|
        return (stream_index * self.level_count + from_level) * self.level_count + to_level;
    }

    pub fn get(self: *const DynamicAttenuation, stream_index: usize, from_level: usize, to_level: usize) f64 {
        // DynamicAttenuation.get ---------------------------------------------------------------------------- |
        // Read T(from -> to) from the full [direction, from, to] table.                                       |
        // ----------------------------------------------------------------------------------------------------|
        return self.data[self.index(stream_index, from_level, to_level)];
    }

    pub fn set(
        self: *DynamicAttenuation,
        stream_index: usize,
        from_level: usize,
        to_level: usize,
        value: f64,
    ) void {
        // DynamicAttenuation.set ---------------------------------------------------------------------------- |
        // Write T(from -> to) into the full [direction, from, to] table.                                      |
        // ----------------------------------------------------------------------------------------------------|
        self.data[self.index(stream_index, from_level, to_level)] = value;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RuntimeAttenuation ---------------------------------------------------------------------------------------- |
// Compact attenuation view for the integrated-source runtime path.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] layer_transmittance : []const f64                                                                  |
// [16..31] top_to_level        : []const f64                                                                  |
// [32..39] stream_count        : usize                                                                        |
// [40..47] level_count         : usize                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// referenced storage: both slices are borrowed from transport worker memory                                   |
// footprint: per instance = 48 B (0.047 KiB); referenced rows are caller-owned                                |
pub const RuntimeAttenuation = struct {
    layer_transmittance: []const f64,
    top_to_level: []const f64,
    stream_count: usize,
    level_count: usize,

    pub inline fn adjacent(self: *const RuntimeAttenuation, stream_index: usize, layer_index: usize) f64 {
        // RuntimeAttenuation.adjacent ----------------------------------------------------------------------- |
        // Adjacent layer lookup uses [direction, layer] storage.                                              |
        // ----------------------------------------------------------------------------------------------------|
        const layer_count = self.level_count - 1;
        return self.layer_transmittance[layerTransmittanceIndex(layer_count, stream_index, layer_index)];
    }

    pub fn get(self: *const RuntimeAttenuation, stream_index: usize, from_level: usize, to_level: usize) f64 {
        // RuntimeAttenuation.get ---------------------------------------------------------------------------- |
        // Return direct-beam survival between two levels using the compact storage when possible.             |
        // ----------------------------------------------------------------------------------------------------|
        if (from_level == to_level) return 1.0;
        if (from_level == self.level_count - 1) return self.top_to_level[stream_index * self.level_count + to_level];
        if (from_level + 1 == to_level) return self.adjacent(stream_index, from_level);
        if (to_level + 1 == from_level) return self.adjacent(stream_index, to_level);

        const start = @min(from_level, to_level);
        const end = @max(from_level, to_level);
        var product: f64 = 1.0;
        for (start..end) |layer_index| {
            product *= self.adjacent(stream_index, layer_index);
        }
        return product;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn dynamicRequiredLength(stream_count: usize, layer_count: usize) usize {
    // dynamicRequiredLength --------------------------------------------------------------------------------- |
    // Return the f64 count needed by DynamicAttenuation backing storage.                                      |
    // --------------------------------------------------------------------------------------------------------|
    const level_count = layer_count + 1;
    return stream_count * level_count * level_count;
}

pub fn layerTransmittanceRequiredLength(stream_count: usize, layer_count: usize) usize {
    // layerTransmittanceRequiredLength ---------------------------------------------------------------------- |
    // Return the f64 count needed by adjacent layer survival storage.                                         |
    // --------------------------------------------------------------------------------------------------------|
    return stream_count * layer_count;
}

pub fn topToLevelRequiredLength(stream_count: usize, layer_count: usize) usize {
    // topToLevelRequiredLength ------------------------------------------------------------------------------ |
    // Return the f64 count needed by top-to-level survival storage.                                           |
    // --------------------------------------------------------------------------------------------------------|
    return stream_count * (layer_count + 1);
}

pub fn fillDynamicWithLayerCache(
    data: []f64,
    layer_transmittance: []f64,
    layers: []const layer_depths.LayerOptics,
    curved_grid: CurvedSunPathGrid,
    geometry: *const gauss_angles.GaussGeometry,
    use_spherical_correction: bool,
) Error!DynamicAttenuation {
    // fillDynamicWithLayerCache ----------------------------------------------------------------------------- |
    // Fill a full dynamic attenuation table using a caller-provided layer-transmittance cache.                |
    //                                                                                                         |
    // math                                                                                                    |
    //   T(from - 1 -> to) = T(from -> to) * T_layer(from - 1)                                                 |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layers.len;
    const level_count = layer_count + 1;
    try requireCurvedGrid(curved_grid, layer_count, use_spherical_correction);
    if (data.len < dynamicRequiredLength(geometry.stream_count, layer_count) or
        layer_transmittance.len < layerTransmittanceRequiredLength(geometry.stream_count, layer_count))
    {
        return error.InvalidShape;
    }

    fillLayerTransmittance(layer_transmittance, layers, geometry);

    var attenuation = DynamicAttenuation{
        .data = data[0..dynamicRequiredLength(geometry.stream_count, layer_count)],
        .stream_count = geometry.stream_count,
        .level_count = level_count,
    };
    fillDynamicFromLayerTransmittance(&attenuation, layer_transmittance, layer_count);

    if (use_spherical_correction) {
        applyCurvedTopToLevelDynamic(&attenuation, curved_grid, geometry);
    }

    return attenuation;
}

pub fn fillDynamicTangent(
    data: []f64,
    layers: []const layer_depths.LayerOptics,
    state: jacobian_states.State,
    geometry: *const gauss_angles.GaussGeometry,
) Error!DynamicAttenuation {
    // fillDynamicTangent ------------------------------------------------------------------------------------ |
    // Fill the derivative of the full direct-beam attenuation table for one Jacobian state.                   |
    //                                                                                                         |
    // provenance                                                                                              |
    //   Ports main:`radiative_transfer/labos/attenuation.zig` `fillAttenuationTangentDynamic` without the     |
    //   old heap allocation. The non-integrated LABOS tangent route uses this only for layer optical-depth    |
    //   derivatives; pseudo-spherical Jacobian weighting is an integrated-source route.                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   d exp(-tau / mu) = exp(-tau / mu) * (-(d tau) / mu)                                                   |
    //   d(product * T_layer) = d(product) * T_layer + product * dT_layer                                      |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layers.len;
    const level_count = layer_count + 1;
    if (data.len < dynamicRequiredLength(geometry.stream_count, layer_count)) return error.InvalidShape;

    var attenuation = DynamicAttenuation{
        .data = data[0..dynamicRequiredLength(geometry.stream_count, layer_count)],
        .stream_count = geometry.stream_count,
        .level_count = level_count,
    };
    @memset(attenuation.data, 0.0);

    for (1..level_count) |to_level| {
        var from_level_index = to_level;

        while (from_level_index >= 1) : (from_level_index -= 1) {
            const layer_index = from_level_index - 1;

            for (0..geometry.stream_count) |stream_index| {
                const mu = @max(geometry.u[stream_index], direction_cosine_floor);
                const transmittance = math.exp(-layers[layer_index].total_optical_depth / mu);
                const optical_depth_tangent =
                    jacobian_states.get(layers[layer_index].optical_depth_jacobian, state);
                const layer_tangent = transmittance * (-optical_depth_tangent / mu);
                const path_tangent = attenuation.get(stream_index, from_level_index, to_level);
                const base_path = cumulativeBaseTransmittance(
                    layers,
                    geometry,
                    stream_index,
                    from_level_index,
                    to_level,
                );

                attenuation.set(
                    stream_index,
                    from_level_index - 1,
                    to_level,
                    path_tangent * transmittance + base_path * layer_tangent,
                );
            }
        }
    }

    for (0..level_count) |to_level| {
        for (to_level..level_count) |from_level| {
            for (0..geometry.stream_count) |stream_index| {
                attenuation.set(
                    stream_index,
                    from_level,
                    to_level,
                    attenuation.get(stream_index, to_level, from_level),
                );
            }
        }
    }

    return attenuation;
}

pub fn fillRuntimeInBuffers(
    layer_transmittance: []f64,
    top_to_level: []f64,
    layers: []const layer_depths.LayerOptics,
    curved_grid: CurvedSunPathGrid,
    geometry: *const gauss_angles.GaussGeometry,
    use_spherical_correction: bool,
) Error!RuntimeAttenuation {
    // fillRuntimeInBuffers ---------------------------------------------------------------------------------- |
    // Fill compact adjacent and top-to-level attenuation buffers without allocation.                          |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layers.len;
    const level_count = layer_count + 1;
    try requireCurvedGrid(curved_grid, layer_count, use_spherical_correction);
    if (layer_transmittance.len < layerTransmittanceRequiredLength(geometry.stream_count, layer_count) or
        top_to_level.len < topToLevelRequiredLength(geometry.stream_count, layer_count))
    {
        return error.InvalidShape;
    }

    fillLayerTransmittance(layer_transmittance, layers, geometry);
    fillRuntimeTopToLevelFromLayerTransmittance(
        top_to_level,
        layer_transmittance,
        geometry.stream_count,
        layer_count,
    );

    if (use_spherical_correction) {
        applyCurvedTopToLevelRuntime(top_to_level, curved_grid, geometry);
    }

    const layer_transmittance_len = layerTransmittanceRequiredLength(geometry.stream_count, layer_count);
    const top_to_level_len = topToLevelRequiredLength(geometry.stream_count, layer_count);
    return .{
        .layer_transmittance = layer_transmittance[0..layer_transmittance_len],
        .top_to_level = top_to_level[0..top_to_level_len],
        .stream_count = geometry.stream_count,
        .level_count = level_count,
    };
}

fn layerTransmittanceIndex(layer_count: usize, stream_index: usize, layer_index: usize) usize {
    // layerTransmittanceIndex ------------------------------------------------------------------------------- |
    // Flat [direction, layer] table index.                                                                    |
    // --------------------------------------------------------------------------------------------------------|
    return stream_index * layer_count + layer_index;
}

fn fillLayerTransmittance(
    layer_transmittance: []f64,
    layers: []const layer_depths.LayerOptics,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // fillLayerTransmittance -------------------------------------------------------------------------------- |
    // Convert per-layer optical depth into adjacent direct-beam survival for every stream.                    |
    // --------------------------------------------------------------------------------------------------------|
    const layer_count = layers.len;
    for (0..geometry.stream_count) |stream_index| {
        const mu = @max(geometry.u[stream_index], direction_cosine_floor);

        for (layers, 0..) |layer, layer_index| {
            layer_transmittance[layerTransmittanceIndex(layer_count, stream_index, layer_index)] =
                math.exp(-layer.total_optical_depth / mu);
        }
    }
}

fn fillRuntimeTopToLevelFromLayerTransmittance(
    top_to_level: []f64,
    layer_transmittance: []const f64,
    stream_count: usize,
    layer_count: usize,
) void {
    // fillRuntimeTopToLevelFromLayerTransmittance ----------------------------------------------------------- |
    // Build top-to-level survival from adjacent layer transmittance rows.                                     |
    // --------------------------------------------------------------------------------------------------------|
    const level_count = layer_count + 1;
    for (0..stream_count) |stream_index| {
        const top_offset = stream_index * level_count;
        const layer_offset = stream_index * layer_count;
        top_to_level[top_offset + layer_count] = 1.0;
        var cumulative: f64 = 1.0;
        var level = layer_count;

        while (level > 0) {
            level -= 1;
            cumulative *= layer_transmittance[layer_offset + level];
            top_to_level[top_offset + level] = cumulative;
        }
    }
}

fn cumulativeBaseTransmittance(
    layers: []const layer_depths.LayerOptics,
    geometry: *const gauss_angles.GaussGeometry,
    stream_index: usize,
    from_level: usize,
    to_level: usize,
) f64 {
    // cumulativeBaseTransmittance --------------------------------------------------------------------------- |
    // Rebuild the unchanged base path product multiplied by one layer tangent.                                |
    // --------------------------------------------------------------------------------------------------------|
    if (from_level >= to_level) return 1.0;

    const mu = @max(geometry.u[stream_index], direction_cosine_floor);
    var value: f64 = 1.0;
    for (from_level..to_level) |layer_index| {
        if (layer_index >= layers.len) break;
        value *= math.exp(-layers[layer_index].total_optical_depth / mu);
    }
    return value;
}

fn fillDynamicFromLayerTransmittance(
    attenuation: *DynamicAttenuation,
    layer_transmittance: []const f64,
    layer_count: usize,
) void {
    // fillDynamicFromLayerTransmittance --------------------------------------------------------------------- |
    // Expand adjacent layer survival into every level pair in the full dynamic table.                         |
    // --------------------------------------------------------------------------------------------------------|
    const level_count = layer_count + 1;
    const stream_stride = level_count * level_count;

    for (0..attenuation.stream_count) |stream_index| {
        const stream_offset = stream_index * stream_stride;
        const layer_offset = stream_index * layer_count;
        const values = attenuation.data[stream_offset .. stream_offset + stream_stride];

        for (0..level_count) |level| {
            values[level * level_count + level] = 1.0;
        }

        for (1..level_count) |to_level| {
            var from_level_index = to_level;

            while (from_level_index >= 1) : (from_level_index -= 1) {
                const layer_index = from_level_index - 1;
                const value = values[from_level_index * level_count + to_level] *
                    layer_transmittance[layer_offset + layer_index];

                values[(from_level_index - 1) * level_count + to_level] = value;
                values[to_level * level_count + from_level_index - 1] = value;
            }
        }
    }
}

fn applyCurvedTopToLevelRuntime(
    top_to_level: []f64,
    curved_grid: CurvedSunPathGrid,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // applyCurvedTopToLevelRuntime -------------------------------------------------------------------------- |
    // Replace runtime top-to-level values with spherical-path support-sample integration.                     |
    // --------------------------------------------------------------------------------------------------------|
    const top_level = curved_grid.level_sample_starts.len - 1;
    const level_count = top_level + 1;

    for (0..geometry.stream_count) |stream_index| {
        const top_offset = stream_index * level_count;
        top_to_level[top_offset + top_level] = 1.0;
        fillCurvedTopToLevelForStream(
            top_to_level[top_offset..][0..level_count],
            curved_grid,
            geometry.u[stream_index],
        );
    }
}

fn applyCurvedTopToLevelDynamic(
    attenuation: *DynamicAttenuation,
    curved_grid: CurvedSunPathGrid,
    geometry: *const gauss_angles.GaussGeometry,
) void {
    // applyCurvedTopToLevelDynamic -------------------------------------------------------------------------- |
    // Replace dynamic top-to-level values with spherical-path support-sample integration.                     |
    // --------------------------------------------------------------------------------------------------------|
    const top_level = curved_grid.level_sample_starts.len - 1;
    const level_count = top_level + 1;

    for (0..geometry.stream_count) |stream_index| {
        const values = attenuation.data[stream_index * level_count * level_count ..][0 .. level_count * level_count];
        const top_row = values[top_level * level_count ..][0..level_count];
        top_row[top_level] = 1.0;
        fillCurvedTopToLevelForStream(top_row, curved_grid, geometry.u[stream_index]);
    }
}

fn fillCurvedTopToLevelForStream(
    top_row: []f64,
    curved_grid: CurvedSunPathGrid,
    stream_mu: f64,
) void {
    // fillCurvedTopToLevelForStream ------------------------------------------------------------------------- |
    // Integrate pseudo-spherical support samples for one stream's top-to-level path.                          |
    // --------------------------------------------------------------------------------------------------------|
    const top_level = curved_grid.level_sample_starts.len - 1;
    const mu = math.clamp(stream_mu, -1.0, 1.0);
    const sin2theta = @max(1.0 - mu * mu, 0.0);
    var level = top_level;

    while (level > 0) {
        level -= 1;

        const level_radius = earth_radius_km + curved_grid.level_altitudes_km[level];
        const sqrx_sin2theta = sin2theta * level_radius * level_radius;
        var optical_depth_sum: f64 = 0.0;

        for (curved_grid.level_sample_starts[level]..curved_grid.samples.len) |sample_index| {
            const sample = curved_grid.samples[sample_index];
            if (sample.optical_depth <= 0.0) continue;

            const sample_radius = earth_radius_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
            const numerator = sample.optical_depth * sample_radius;
            optical_depth_sum += numerator / @max(denominator, spherical_denominator_floor);
        }

        top_row[level] = math.exp(-optical_depth_sum);
    }
}

fn requireCurvedGrid(
    curved_grid: CurvedSunPathGrid,
    layer_count: usize,
    use_spherical_correction: bool,
) Error!void {
    // requireCurvedGrid ------------------------------------------------------------------------------------- |
    // Enforce that enabled pseudo-spherical correction has a valid support grid.                              |
    // --------------------------------------------------------------------------------------------------------|
    if (use_spherical_correction and !curved_grid.isValidFor(layer_count)) {
        return error.UnsupportedRadiativeTransferControls;
    }
}
