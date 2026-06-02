const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../root.zig");

// attenuation.zig --------------------------------------------------------------------------------------------|
// Direct-beam attenuation builder. It answers: how much path survival remains between two levels?             |
//                                                                                                             |
// used by                                                                                                     |
//   execute.zig prepares attenuation before RT_fc and scattering-order transport                              |
//   workspace.zig reuses caller-owned buffers across repeated forward runs                                    |
//   orders.zig and reflectance.zig read the attenuation values                                                |
//                                                                                                             |
// main paths                                                                                                  |
//   fillAttenuationDynamicWithGrid                                                                            |
//     -> fillAttenuationDynamicWithGridInBuffer                                                               |
//     -> fillAttenuationDynamicWithGridInBufferAndLayerCache                                                  |
//     -> fillLayerTransmittance                                                                               |
//     -> fillDynamicAttenuationFromLayerCache                                                                 |
//     -> optional pseudo-spherical top-path override                                                          |
//                                                                                                             |
//   fillRuntimeAttenuationWithGridInBuffers                                                                   |
//     -> fillLayerTransmittance                                                                               |
//     -> fillRuntimeTopToLevelFromLayerCache                                                                  |
//     -> optional pseudo-spherical top-path override                                                          |
//                                                                                                             |
//   fillAttenuationTangentDynamic                                                                             |
//     -> derivative of the dynamic path for one Jacobian state                                                |
//                                                                                                             |
// math                                                                                                        |
//   transmittance = exp(-optical_depth / mu)                                                                  |
//   mu is the cosine of the ray zenith angle                                                                  |
//                                                                                                             |
// storage                                                                                                     |
//   dynamic path : full [direction, from_level, to_level] table                                               |
//   runtime path : adjacent-layer table plus top-to-level table                                               |
//                                                                                                             |
// direction index                                                                                             |
//   imu = 0 .. n_gauss - 1  Gauss quadrature directions                                                       |
//   imu = geo.viewIdx()     viewing direction                                                                 |
//   imu = geo.n_gauss + 1   solar direction                                                                   |
// ------------------------------------------------------------------------------------------------------------|

// ------------------------------------------------------------------------------------------------------------|
// ------------------------------------------------------------------------------------------------------------|
// tradeoff: fixed level scratch cap                                                                           |
// Keep stack scratch arrays at max_levels = 65; larger layer counts use generic fallback loops.               |
// ------------------------------------------------------------------------------------------------------------|
// The fallback uses the same attenuation math. The tradeoff is memory and speed: common O2 A routes get       |
// small fixed local arrays, while unusual larger grids avoid writing past those arrays.                       |
pub const max_levels: usize = 65;
// end tradeoff: fixed level scratch cap ----------------------------------------------------------------------|

// numerical guards -------------------------------------------------------------------------------------------|
// direction_cosine_floor keeps exp(-tau / mu) finite for near-grazing directions.                             |
// spherical_denominator_floor keeps curved-path fractions finite when the ray skims a level radius.           |
// earth_radius_km is the spherical-shell radius used by the pseudo-spherical support-grid path.               |
// ------------------------------------------------------------------------------------------------------------|
const direction_cosine_floor: f64 = 1.0e-6;
const spherical_denominator_floor: f64 = 1.0e-12;
const earth_radius_km: f64 = 6371.0;

// DynamicAttenArray ------------------------------------------------------------------------------------------|
// Full attenuation matrix for all direction/from/to level pairs.                                              |
// Some transport paths need arbitrary level-pair lookups, not only adjacent or top-to-level paths.            |
//                                                                                                             |
// data[(imu * nlevel + from) * nlevel + to] stores T(from -> to)                                              |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] allocator : Allocator                                                                              |
// [16..31] data      : []f64                                                                                  |
// [32..39] nmutot    : usize                                                                                  |
// [40..47] nlevel    : usize                                                                                  |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: data carries referenced storage; referenced storage is not included in size                    |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                    |
pub const DynamicAttenArray = struct {
    allocator: Allocator,
    data: []f64,
    nmutot: usize,
    nlevel: usize,

    fn init(allocator: Allocator, nmutot: usize, nlevel: usize) !DynamicAttenArray {
        // DynamicAttenArray.init -----------------------------------------------------------------------------|
        // Allocate the full table and initialize every pair to neutral survival.                              |
        // ----------------------------------------------------------------------------------------------------|

        const data = try allocator.alloc(f64, nmutot * nlevel * nlevel);

        for (data) |*value| value.* = 1.0;

        return .{
            .allocator = allocator,
            .data = data,
            .nmutot = nmutot,
            .nlevel = nlevel,
        };
    }

    pub fn deinit(self: *DynamicAttenArray) void {
        // DynamicAttenArray.deinit ---------------------------------------------------------------------------|
        // Release the owned full attenuation table.                                                           |
        // ----------------------------------------------------------------------------------------------------|

        self.allocator.free(self.data);
        self.* = undefined;
    }

    fn index(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) usize {
        // DynamicAttenArray.index ----------------------------------------------------------------------------|
        // Levels are matrix axes inside each direction block.                                                 |
        // ----------------------------------------------------------------------------------------------------|

        return (imu * self.nlevel + from) * self.nlevel + to;
    }

    pub fn get(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) f64 {
        // DynamicAttenArray.get ------------------------------------------------------------------------------|
        // Read T(from -> to) from the full [direction, from, to] table.                                       |
        // ----------------------------------------------------------------------------------------------------|

        return self.data[self.index(imu, from, to)];
    }

    pub fn set(self: *DynamicAttenArray, imu: usize, from: usize, to: usize, value: f64) void {
        // DynamicAttenArray.set ------------------------------------------------------------------------------|
        // Write T(from -> to) into the full [direction, from, to] table.                                      |
        // ----------------------------------------------------------------------------------------------------|

        self.data[self.index(imu, from, to)] = value;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// RuntimeAttenArray ------------------------------------------------------------------------------------------|
// Borrowed attenuation view for the runtime path.                                                             |
// Avoids the full [direction, from, to] table unless a caller asks for a non-cached pair.                     |
//                                                                                                             |
// layer_transmittance stores adjacent layer survival                                                          |
// top_to_level stores direct survival from the top level to each lower level                                  |
//                                                                                                             |
// hot path                                                                                                    |
//   repeated : level-to-level attenuation lookups during LABOS transport                                      |
//   costly   : non-adjacent fallback multiplies adjacent cached values                                        |
//   memory   : borrowed arrays; this view does not own storage                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 48 B (0.047 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] layer_transmittance : []const f64                                                                  |
// [16..31] top_to_level        : []const f64                                                                  |
// [32..39] nmutot              : usize                                                                        |
// [40..47] nlevel              : usize                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// out-of-line: layer_transmittance and top_to_level carry referenced storage                                  |
// footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above                    |
pub const RuntimeAttenArray = struct {
    layer_transmittance: []const f64,
    top_to_level: []const f64,
    nmutot: usize,
    nlevel: usize,

    inline fn nlayer(self: *const RuntimeAttenArray) usize {
        // RuntimeAttenArray.nlayer ---------------------------------------------------------------------------|
        // nlevel includes the surface/bottom level and the top boundary; nlayer is                            |
        // one less than that.                                                                                 |
        // ----------------------------------------------------------------------------------------------------|

        return self.nlevel - 1;
    }

    pub inline fn adjacent(self: *const RuntimeAttenArray, imu: usize, layer_index: usize) f64 {
        // RuntimeAttenArray.adjacent -------------------------------------------------------------------------|
        // Adjacent layer lookup uses [direction, layer] storage.                                              |
        // ----------------------------------------------------------------------------------------------------|

        return self.layer_transmittance[layerTransmittanceIndex(self.nlayer(), imu, layer_index)];
    }

    pub fn get(self: *const RuntimeAttenArray, imu: usize, from: usize, to: usize) f64 {
        // RuntimeAttenArray.get ------------------------------------------------------------------------------|
        // Return attenuation between two levels using the cheapest available                                  |
        // representation.                                                                                     |
        //                                                                                                     |
        // Same-level and adjacent-level values are direct. Other pairs multiply                               |
        // adjacent cached layer values on demand.                                                             |
        // ----------------------------------------------------------------------------------------------------|

        if (from == to) return 1.0;
        if (from == self.nlevel - 1) return self.top_to_level[imu * self.nlevel + to];
        if (from + 1 == to) return self.adjacent(imu, from);
        if (to + 1 == from) return self.adjacent(imu, to);

        // non-adjacent attenuation = product of adjacent layer transmittances between levels.
        const start = @min(from, to);
        const end = @max(from, to);
        var product: f64 = 1.0;

        for (start..end) |layer_index| product *= self.adjacent(imu, layer_index);

        return product;
    }
};
// ------------------------------------------------------------------------------------------------------------|

fn layerTransmittanceIndex(nlayer: usize, imu: usize, layer_index: usize) usize {
    // layerTransmittanceIndex --------------------------------------------------------------------------------|
    // Flat [direction, layer] table. Direction is the outer stride so one                                     |
    // direction's layers are contiguous.                                                                      |
    // --------------------------------------------------------------------------------------------------------|

    return imu * nlayer + layer_index;
}

fn fillLayerTransmittance(
    layer_transmittance: []f64,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
) void {
    // fillLayerTransmittance ---------------------------------------------------------------------------------|
    // Convert per-layer optical depth into one-layer direct-beam survival for                                 |
    // every direction.                                                                                        |
    //                                                                                                         |
    // Later routines reuse these exponentials while building top-to-level and                                 |
    // level-pair products.                                                                                    |
    //                                                                                                         |
    // math                                                                                                    |
    //   T_layer(imu, layer)                                                                                   |
    //     = exp(-tau_layer / max(mu_imu, direction_cosine_floor))                                             |
    //                                                                                                         |
    // direction_cosine_floor keeps grazing directions finite.                                                 |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : before LABOS order transport builds dynamic/runtime attenuation caches                     |
    //   does     : converts layer optical depths into per-stream transmittance rows                           |
    //   reads    : layer optical depths, geometry stream cosines, layer transmittance output                  |
    //   feeds    : fillRuntimeTopToLevelFromLayerCache and fillDynamicAttenuationFromLayerCache               |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    std.debug.assert(layer_transmittance.len >= geo.nmutot * nlayer);

    for (0..geo.nmutot) |imu| {
        const u = @max(geo.u[imu], direction_cosine_floor);

        for (layers, 0..) |layer, layer_index| {
            layer_transmittance[layerTransmittanceIndex(nlayer, imu, layer_index)] =
                math.exp(-layer.optical_depth / u);
        }
    }
}

fn pseudoSphericalDirectionCosine(
    geo: *const basis.Geometry,
    layer: common.LayerInput,
    imu: usize,
) f64 {
    // pseudoSphericalDirectionCosine -------------------------------------------------------------------------|
    // Pick the direction cosine used by the pseudo-spherical shortcut.                                        |
    //                                                                                                         |
    // Solar and viewing paths can have layer-dependent direction cosines. The                                 |
    // Gauss quadrature directions keep the geometry value from Geometry.u.                                    |
    // --------------------------------------------------------------------------------------------------------|

    if (imu == geo.viewIdx()) return layer.view_mu;
    if (imu == geo.n_gauss + 1) return layer.solar_mu;
    return geo.u[imu];
}

fn applyPseudoSphericalTopLevelAttenuationDynamic(
    atten: *DynamicAttenArray,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
) void {
    // applyPseudoSphericalTopLevelAttenuationDynamic ---------------------------------------------------------|
    // Override top-to-level values in the full dynamic table using per-layer                                  |
    // pseudo-spherical direction cosines.                                                                     |
    //                                                                                                         |
    // This only writes paths from the top level down. Other level pairs remain the                            |
    // plane-parallel products already built in the table.                                                     |
    // --------------------------------------------------------------------------------------------------------|

    const top_level = layers.len;

    for (0..geo.nmutot) |imu| {
        var cumulative: f64 = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), direction_cosine_floor);

            // pseudo-spherical top attenuation multiplies exp(-tau_layer / directional_mu_layer).
            cumulative *= math.exp(-layers[level].optical_depth / u);

            atten.set(imu, top_level, level, cumulative);
        }
    }
}

fn fillRuntimeTopToLevelFromLayerCache(
    top_to_level: []f64,
    layer_transmittance: []const f64,
    nmutot: usize,
    nlayer: usize,
) void {
    // fillRuntimeTopToLevelFromLayerCache --------------------------------------------------------------------|
    // Build compact direct survival from the top level to every lower level using                             |
    // the already-computed adjacent layer table.                                                              |
    //                                                                                                         |
    // top_to_level[imu, level] stores T(top -> level).                                                        |
    // --------------------------------------------------------------------------------------------------------|

    const nlevel = nlayer + 1;
    std.debug.assert(top_to_level.len >= nmutot * nlevel);
    std.debug.assert(layer_transmittance.len >= nmutot * nlayer);

    for (0..nmutot) |imu| {
        const top_offset = imu * nlevel;
        const layer_offset = imu * nlayer;
        top_to_level[top_offset + nlayer] = 1.0;
        var cumulative: f64 = 1.0;
        var level = nlayer;

        while (level > 0) {
            level -= 1;

            // top_to_level(level) multiplies the layer transmittance from this level up to the top.
            cumulative *= layer_transmittance[layer_offset + level];

            top_to_level[top_offset + level] = cumulative;
        }
    }
}

fn applyPseudoSphericalRuntimeTopToLevel(
    top_to_level: []f64,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
) void {
    // applyPseudoSphericalRuntimeTopToLevel ------------------------------------------------------------------|
    // Override runtime top-to-level values using per-layer pseudo-spherical                                   |
    // direction cosines.                                                                                      |
    //                                                                                                         |
    // Runtime storage has no full level-pair table, so only top-to-level values are                           |
    // replaced here.                                                                                          |
    // --------------------------------------------------------------------------------------------------------|

    const top_level = layers.len;
    const nlevel = top_level + 1;

    for (0..geo.nmutot) |imu| {
        const top_offset = imu * nlevel;
        var cumulative: f64 = 1.0;
        top_to_level[top_offset + top_level] = 1.0;
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), direction_cosine_floor);

            // pseudo-spherical top_to_level multiplies exp(-tau_layer / directional_mu_layer).
            cumulative *= math.exp(-layers[level].optical_depth / u);

            top_to_level[top_offset + level] = cumulative;
        }
    }
}

fn levelAltitudeFromPseudoSphericalGrid(
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    level: usize,
) f64 {
    // levelAltitudeFromPseudoSphericalGrid -------------------------------------------------------------------|
    // Recover a level altitude from the pseudo-spherical support grid.                                        |
    //                                                                                                         |
    // Prefer explicit level altitudes. If they are absent, infer a level boundary                             |
    // from the first support sample that belongs to that level.                                               |
    // --------------------------------------------------------------------------------------------------------|

    if (pseudo_spherical_grid.level_altitudes_km.len != 0) {
        return pseudo_spherical_grid.level_altitudes_km[level];
    }
    if (level == 0) {
        const first = pseudo_spherical_grid.samples[0];

        return @max(first.altitude_km - 0.5 * first.thickness_km, 0.0);
    }

    const start_index = pseudo_spherical_grid.level_sample_starts[level];
    if (start_index >= pseudo_spherical_grid.samples.len) {
        const last = pseudo_spherical_grid.samples[pseudo_spherical_grid.samples.len - 1];

        return @max(last.altitude_km + 0.5 * last.thickness_km, 0.0);
    }

    const sample = pseudo_spherical_grid.samples[start_index];

    return @max(sample.altitude_km - 0.5 * sample.thickness_km, 0.0);
}

fn applyPseudoSphericalTopLevelAttenuationDynamicWithGrid(
    atten: *DynamicAttenArray,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
) void {
    // applyPseudoSphericalTopLevelAttenuationDynamicWithGrid -------------------------------------------------|
    // Replace the dynamic top-to-level path with a spherical-path integral through                            |
    // the prepared support samples.                                                                           |
    //                                                                                                         |
    // spherical slant optical depth adds this fraction                                                        |
    //                                                                                                         |
    //              tau_sample * r_sample                                                                      |
    //   ------------------------------------------------------------------------------------------------------|
    //   sqrt(r_sample^2 - r_level^2 * sin(theta)^2)                                                           |
    //                                                                                                         |
    // The support grid follows the curved path more closely than one layer-wide                               |
    // direction cosine.                                                                                       |
    // Earth radius and altitude samples are in kilometers. Attenuation remains                                |
    // dimensionless.                                                                                          |
    // --------------------------------------------------------------------------------------------------------|

    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: pseudo-spherical prepared-grid cap                                                            |
    // Use the prepared-grid fast path only for <= 65 levels and <= 512 support samples.                       |
    // --------------------------------------------------------------------------------------------------------|
    // The fallback below uses the same spherical slant optical-depth formula. The cap keeps local radius      |
    // caches bounded on the stack; larger support grids pay the slower generic loop instead.                  |
    if (top_level + 1 <= max_levels and pseudo_spherical_grid.samples.len <= max_pseudo_spherical_fast_samples) {
        applyPseudoSphericalTopLevelAttenuationDynamicWithPreparedGrid(
            atten,
            pseudo_spherical_grid,
            geo,
            top_level,
        );
        return;
    }
    // end tradeoff: pseudo-spherical prepared-grid cap -------------------------------------------------------|

    for (0..geo.nmutot) |imu| {
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const level_radius = earth_radius_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
            const sqrx_sin2theta = sin2theta * level_radius * level_radius;
            var sumkext: f64 = 0.0;

            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const sample = pseudo_spherical_grid.samples[index];

                if (sample.optical_depth <= 0.0) continue;

                const sample_radius = earth_radius_km + sample.altitude_km;
                const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
                const numerator = sample.optical_depth * sample_radius;

                // add one spherical slant optical-depth sample:
                //              tau_sample * r_sample
                //   -------------------------------------------
                //   sqrt(r_sample^2 - r_level^2 * sin(theta)^2)
                // denominator floor keeps grazing paths finite.
                sumkext += numerator / @max(denominator, spherical_denominator_floor);
            }

            // T(top -> level) = exp(-sum of spherical slant optical depths).
            atten.set(imu, top_level, level, math.exp(-sumkext));
        }
    }
}

fn applyPseudoSphericalRuntimeTopToLevelWithGrid(
    top_to_level: []f64,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
) void {
    // applyPseudoSphericalRuntimeTopToLevelWithGrid ----------------------------------------------------------|
    // Replace runtime top-to-level values with the same spherical-path integral                               |
    // used by the dynamic grid path.                                                                          |
    //                                                                                                         |
    // Writes only top_to_level[imu, level], not adjacent layer transmittance.                                 |
    // --------------------------------------------------------------------------------------------------------|

    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: runtime pseudo-spherical prepared-grid cap                                                    |
    // Use the prepared-grid fast path only for <= 65 levels and <= 512 support samples.                       |
    // --------------------------------------------------------------------------------------------------------|
    // The fallback below writes the same top-to-level attenuation values. The cap keeps the precomputed       |
    // radius arrays bounded; larger support grids use the generic loop instead of oversized stack arrays.     |
    if (top_level + 1 <= max_levels and pseudo_spherical_grid.samples.len <= max_pseudo_spherical_fast_samples) {
        applyPseudoSphericalRuntimeTopToLevelWithPreparedGrid(
            top_to_level,
            pseudo_spherical_grid,
            geo,
            top_level,
        );
        return;
    }
    // end tradeoff: runtime pseudo-spherical prepared-grid cap -----------------------------------------------|

    const nlevel = top_level + 1;

    for (0..geo.nmutot) |imu| {
        const top_offset = imu * nlevel;
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        top_to_level[top_offset + top_level] = 1.0;
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const level_radius = earth_radius_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
            const sqrx_sin2theta = sin2theta * level_radius * level_radius;
            var sumkext: f64 = 0.0;

            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const sample = pseudo_spherical_grid.samples[index];

                if (sample.optical_depth <= 0.0) continue;

                const sample_radius = earth_radius_km + sample.altitude_km;
                const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
                const numerator = sample.optical_depth * sample_radius;

                // add one spherical slant optical-depth sample:
                //              tau_sample * r_sample
                //   -------------------------------------------
                //   sqrt(r_sample^2 - r_level^2 * sin(theta)^2)
                // denominator floor keeps grazing paths finite.
                sumkext += numerator / @max(denominator, spherical_denominator_floor);
            }

            // top_to_level = exp(-sum of spherical slant optical depths).
            top_to_level[top_offset + level] = math.exp(-sumkext);
        }
    }
}

// ------------------------------------------------------------------------------------------------------------|
// ------------------------------------------------------------------------------------------------------------|
// tradeoff: fixed pseudo-spherical sample cap                                                                 |
// Keep prepared-grid sample scratch arrays at max_pseudo_spherical_fast_samples = 512.                        |
// ------------------------------------------------------------------------------------------------------------|
// Larger support grids use the generic loop. That preserves the spherical-path calculation while avoiding     |
// oversized stack arrays for rare grids.                                                                      |
const max_pseudo_spherical_fast_samples: usize = 512;
// end tradeoff: fixed pseudo-spherical sample cap ------------------------------------------------------------|

fn applyPseudoSphericalRuntimeTopToLevelWithPreparedGrid(
    top_to_level: []f64,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    top_level: usize,
) void {
    // applyPseudoSphericalRuntimeTopToLevelWithPreparedGrid --------------------------------------------------|
    // Use precomputed radius terms while writing runtime top-to-level attenuation.                            |
    //                                                                                                         |
    // Moves radius squares and tau*r products out of the inner direction/level                                |
    // accumulation loop.                                                                                      |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : pseudo-spherical runtime attenuation uses a prepared support grid                          |
    //   does     : applies top-to-level attenuation from prepared samples across streams and levels           |
    //   reads    : prepared pseudo-spherical samples, runtime attenuation cache, layer grid levels            |
    //   feeds    : sample order from forward_input pseudo-spherical buffers                                   |
    // --------------------------------------------------------------------------------------------------------|

    const nlevel = top_level + 1;
    var level_radius_sq: [max_levels]f64 = undefined;
    var sample_radius_sq: [max_pseudo_spherical_fast_samples]f64 = undefined;
    var sample_weighted_radius: [max_pseudo_spherical_fast_samples]f64 = undefined;

    // level_radius_sq is indexed by level. sample_* arrays are indexed by the
    // original support-sample order.
    for (0..nlevel) |level| {
        const radius = earth_radius_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
        level_radius_sq[level] = radius * radius;
    }

    for (pseudo_spherical_grid.samples, 0..) |sample, index| {
        const radius = earth_radius_km + sample.altitude_km;
        sample_radius_sq[index] = radius * radius;
        sample_weighted_radius[index] = if (sample.optical_depth > 0.0) sample.optical_depth * radius else 0.0;
    }

    for (0..geo.nmutot) |imu| {
        const top_offset = imu * nlevel;
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        top_to_level[top_offset + top_level] = 1.0;
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const sqrx_sin2theta = sin2theta * level_radius_sq[level];
            var sumkext: f64 = 0.0;

            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const denominator = @sqrt(@abs(sample_radius_sq[index] - sqrx_sin2theta));

                // Same fraction as the full grid path; numerator and radius
                // squares are already precomputed. The denominator floor keeps grazing paths finite.
                sumkext += sample_weighted_radius[index] / @max(denominator, spherical_denominator_floor);
            }

            top_to_level[top_offset + level] = math.exp(-sumkext);
        }
    }
}

fn applyPseudoSphericalTopLevelAttenuationDynamicWithPreparedGrid(
    atten: *DynamicAttenArray,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    top_level: usize,
) void {
    // applyPseudoSphericalTopLevelAttenuationDynamicWithPreparedGrid -----------------------------------------|
    // Use precomputed radius terms while writing the full dynamic top-path row.                               |
    //                                                                                                         |
    // The dynamic table is still [direction, from_level, to_level]; this helper                               |
    // writes values[top_level, level] inside each direction block.                                            |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : pseudo-spherical dynamic attenuation uses a prepared support grid                          |
    //   does     : writes top-level attenuation samples across streams and levels                             |
    //   reads    : prepared pseudo-spherical samples, attenuation table, geometry stream count                |
    //   feeds    : applyPseudoSphericalTopLevelAttenuationDynamicWithGrid callers                             |
    // --------------------------------------------------------------------------------------------------------|

    const nlevel = top_level + 1;
    const stream_stride = nlevel * nlevel;
    var level_radius_sq: [max_levels]f64 = undefined;
    var sample_radius_sq: [max_pseudo_spherical_fast_samples]f64 = undefined;
    var sample_weighted_radius: [max_pseudo_spherical_fast_samples]f64 = undefined;

    // These local arrays mirror the runtime prepared-grid path so the inner
    // loop only does the level-dependent denominator and sum.
    for (0..nlevel) |level| {
        const radius = earth_radius_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
        level_radius_sq[level] = radius * radius;
    }

    for (pseudo_spherical_grid.samples, 0..) |sample, index| {
        const radius = earth_radius_km + sample.altitude_km;
        sample_radius_sq[index] = radius * radius;
        sample_weighted_radius[index] = if (sample.optical_depth > 0.0) sample.optical_depth * radius else 0.0;
    }

    for (0..geo.nmutot) |imu| {
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        const values = atten.data[imu * stream_stride .. (imu + 1) * stream_stride];
        values[top_level * nlevel + top_level] = 1.0;
        var level = top_level;

        while (level > 0) {
            level -= 1;

            const sqrx_sin2theta = sin2theta * level_radius_sq[level];
            var sumkext: f64 = 0.0;

            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const denominator = @sqrt(@abs(sample_radius_sq[index] - sqrx_sin2theta));

                // Same fraction as the full grid path; numerator and radius
                // squares are already precomputed. The denominator floor keeps grazing paths finite.
                sumkext += sample_weighted_radius[index] / @max(denominator, spherical_denominator_floor);
            }

            values[top_level * nlevel + level] = math.exp(-sumkext);
        }
    }
}

pub fn fillAttenuationDynamic(
    allocator: Allocator,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) !DynamicAttenArray {
    // fillAttenuationDynamic ---------------------------------------------------------------------------------|
    // Convenience entry point for callers that do not provide a pseudo-spherical                              |
    // support grid.                                                                                           |
    // --------------------------------------------------------------------------------------------------------|

    return fillAttenuationDynamicWithGrid(
        allocator,
        layers,
        .{},
        geo,
        use_spherical_correction,
    );
}

pub fn fillAttenuationDynamicWithGrid(
    allocator: Allocator,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) !DynamicAttenArray {
    // fillAttenuationDynamicWithGrid -------------------------------------------------------------------------|
    // Allocate and fill the full dynamic attenuation table.                                                   |
    //                                                                                                         |
    // used by                                                                                                 |
    //   execute.zig when no workspace-owned attenuation buffer is available.                                  |
    //                                                                                                         |
    // Returns an owning DynamicAttenArray. Caller must deinit it.                                             |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    const data = try allocator.alloc(f64, geo.nmutot * nlevel * nlevel);

    return fillAttenuationDynamicWithGridInBuffer(
        allocator,
        data,
        layers,
        pseudo_spherical_grid,
        geo,
        use_spherical_correction,
    );
}

pub fn fillAttenuationTangentDynamic(
    allocator: Allocator,
    layers: []const common.LayerInput,
    state: common.Jacobian.State,
    geo: *const basis.Geometry,
) !DynamicAttenArray {
    // fillAttenuationTangentDynamic --------------------------------------------------------------------------|
    // Fill the derivative of the full attenuation table for one Jacobian state.                               |
    //                                                                                                         |
    // d exp(-tau / mu) = exp(-tau / mu) * (-(d tau) / mu)                                                     |
    //                                                                                                         |
    // This is the tangent path for layer optical-depth changes, not the                                       |
    // pseudo-spherical support-grid correction.                                                               |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : LABOS tangent routes request derivative attenuation                                        |
    //   does     : fills dynamic attenuation derivatives for layer optical-depth perturbations                |
    //   reads    : base layers, derivative layers, geometry streams, attenuation tangent buffer               |
    //   feeds    : nonIntegratedReflectanceTangent and ordersScatTangent                                      |
    // dT_layer/dx = exp(-tau_layer / mu) * (-(d tau_layer/dx) / mu).                                          |
    // Path derivatives then use the product rule.                                                             |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    const data = try allocator.alloc(f64, geo.nmutot * nlevel * nlevel);
    var atten = DynamicAttenArray{
        .allocator = allocator,
        .data = data[0 .. geo.nmutot * nlevel * nlevel],
        .nmutot = geo.nmutot,
        .nlevel = nlevel,
    };

    for (0..geo.nmutot) |imu| {
        for (0..nlevel) |from| {
            for (0..nlevel) |to| {
                atten.set(imu, from, to, 0.0);
            }
        }
    }

    for (0..nlayer) |ilTo_0| {
        const ilTo = ilTo_0 + 1;
        var ilFrom_idx = ilTo;

        while (ilFrom_idx >= 1) : (ilFrom_idx -= 1) {
            const layer_idx = ilFrom_idx - 1;

            for (0..geo.nmutot) |imu| {
                const u = @max(geo.u[imu], direction_cosine_floor);
                const trans = math.exp(-layers[layer_idx].optical_depth / u);
                const dtrans = trans * (-common.Jacobian.get(layers[layer_idx].optical_depth_jacobian, state) / u);

                // d(product * T_layer) = d(product) * T_layer + product * dT_layer.
                atten.set(
                    imu,
                    ilFrom_idx - 1,
                    ilTo,
                    atten.get(imu, ilFrom_idx, ilTo) * trans +
                        cumulativeBaseTransmittance(layers, geo, imu, ilFrom_idx, ilTo) * dtrans,
                );
            }
        }
    }

    for (0..nlevel) |ilTo| {
        for (ilTo..nlevel) |ilFrom| {
            for (0..geo.nmutot) |imu| {
                atten.set(imu, ilFrom, ilTo, atten.get(imu, ilTo, ilFrom));
            }
        }
    }

    return atten;
}

fn cumulativeBaseTransmittance(
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
    imu: usize,
    from_level: usize,
    to_level: usize,
) f64 {
    // cumulativeBaseTransmittance ----------------------------------------------------------------------------|
    // Rebuild the base attenuation product used by the tangent path.                                          |
    //                                                                                                         |
    // The derivative recurrence needs both dT and the unchanged product that dT is                            |
    // multiplying.                                                                                            |
    // --------------------------------------------------------------------------------------------------------|

    var value: f64 = 1.0;
    if (from_level >= to_level) return value;

    const u = @max(geo.u[imu], direction_cosine_floor);

    for (from_level..to_level) |layer_idx| {
        if (layer_idx >= layers.len) break;

        // base path transmittance multiplies exp(-tau_layer / mu) across layers.
        value *= math.exp(-layers[layer_idx].optical_depth / u);
    }

    return value;
}

pub fn fillAttenuationDynamicWithGridInBuffer(
    allocator: Allocator,
    data: []f64,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) DynamicAttenArray {
    // fillAttenuationDynamicWithGridInBuffer -----------------------------------------------------------------|
    // Fill a caller-provided dynamic attenuation buffer.                                                      |
    //                                                                                                         |
    // For normal layer counts, build a temporary [direction, layer] cache once and                            |
    // expand it into the full table. For larger counts, use the repeated-exp path                             |
    // to avoid fixed local arrays that are too small.                                                         |
    // --------------------------------------------------------------------------------------------------------|

    // --------------------------------------------------------------------------------------------------------|
    // --------------------------------------------------------------------------------------------------------|
    // tradeoff: dynamic attenuation cache cap                                                                 |
    // Use the layer-transmittance cache only when layers.len <= max_levels = 65.                              |
    // --------------------------------------------------------------------------------------------------------|
    // The cached path avoids repeated exponentials while expanding the full dynamic attenuation table.        |
    // Larger layer counts use the repeated-exp fallback below so the fixed local cache cannot overflow.       |
    if (layers.len <= max_levels) {
        var layer_transmittance: [basis.max_nmutot * max_levels]f64 = undefined;

        return fillAttenuationDynamicWithGridInBufferAndLayerCache(
            allocator,
            data,
            layer_transmittance[0 .. geo.nmutot * layers.len],
            layers,
            pseudo_spherical_grid,
            geo,
            use_spherical_correction,
        );
    }
    // end tradeoff: dynamic attenuation cache cap ------------------------------------------------------------|

    return fillAttenuationDynamicWithGridInBufferRepeatedExp(
        allocator,
        data,
        layers,
        pseudo_spherical_grid,
        geo,
        use_spherical_correction,
    );
}

pub fn fillAttenuationDynamicWithGridInBufferAndLayerCache(
    allocator: Allocator,
    data: []f64,
    layer_transmittance: []f64,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) DynamicAttenArray {
    // fillAttenuationDynamicWithGridInBufferAndLayerCache ----------------------------------------------------|
    // Build one-layer transmittance first, then expand it into all level                                      |
    // pairs, then optionally replace top-to-level values with pseudo-spherical                                |
    // values.                                                                                                 |
    //                                                                                                         |
    // `data` becomes the full [direction, from_level, to_level] table.                                        |
    // `layer_transmittance` is temporary [direction, layer] cache storage.                                    |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : layer-resolved LABOS builds attenuation for dynamic geometry                               |
    //   does     : fills layer transmittance and expands it into level-pair attenuation tables                |
    //   reads    : layer transmittance cache, attenuation table, geometry levels and streams                  |
    //   feeds    : fillDynamicAttenuationFromLayerCache and pseudo-spherical overlays                         |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    const required_len = geo.nmutot * nlevel * nlevel;
    std.debug.assert(data.len >= required_len);
    std.debug.assert(layer_transmittance.len >= geo.nmutot * nlayer);

    fillLayerTransmittance(layer_transmittance, layers, geo);

    var atten = DynamicAttenArray{
        .allocator = allocator,
        .data = data[0..required_len],
        .nmutot = geo.nmutot,
        .nlevel = nlevel,
    };

    fillDynamicAttenuationFromLayerCache(&atten, layer_transmittance, nlayer);

    if (use_spherical_correction) {
        if (pseudo_spherical_grid.isValidFor(nlayer)) {
            applyPseudoSphericalTopLevelAttenuationDynamicWithGrid(&atten, pseudo_spherical_grid, geo);
        } else {
            applyPseudoSphericalTopLevelAttenuationDynamic(&atten, layers, geo);
        }
    }

    return atten;
}

pub fn fillRuntimeAttenuationWithGridInBuffers(
    layer_transmittance: []f64,
    top_to_level: []f64,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) RuntimeAttenArray {
    // fillRuntimeAttenuationWithGridInBuffers ----------------------------------------------------------------|
    // Fill compact runtime attenuation buffers without allocating.                                            |
    //                                                                                                         |
    // `layer_transmittance` stores adjacent layer survival.                                                   |
    // `top_to_level` stores direct survival from the top level to each level.                                 |
    //                                                                                                         |
    // This is enough for the integrated-source runtime path and avoids the full                               |
    // level-pair matrix unless RuntimeAttenArray.get has to synthesize a pair.                                |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    std.debug.assert(layer_transmittance.len >= geo.nmutot * nlayer);
    std.debug.assert(top_to_level.len >= geo.nmutot * nlevel);

    fillLayerTransmittance(layer_transmittance, layers, geo);

    fillRuntimeTopToLevelFromLayerCache(top_to_level, layer_transmittance, geo.nmutot, nlayer);

    if (use_spherical_correction) {
        if (pseudo_spherical_grid.isValidFor(nlayer)) {
            applyPseudoSphericalRuntimeTopToLevelWithGrid(top_to_level, pseudo_spherical_grid, geo);
        } else {
            applyPseudoSphericalRuntimeTopToLevel(top_to_level, layers, geo);
        }
    }

    return .{
        .layer_transmittance = layer_transmittance[0 .. geo.nmutot * nlayer],
        .top_to_level = top_to_level[0 .. geo.nmutot * nlevel],
        .nmutot = geo.nmutot,
        .nlevel = nlevel,
    };
}

fn fillDynamicAttenuationFromLayerCache(
    atten: *DynamicAttenArray,
    layer_transmittance: []const f64,
    nlayer: usize,
) void {
    // fillDynamicAttenuationFromLayerCache -------------------------------------------------------------------|
    // Expand adjacent layer transmittance into every level pair in the dynamic                                |
    // table.                                                                                                  |
    //                                                                                                         |
    // T(from - 1 -> to) = T(from -> to) * T_layer(from - 1)                                                   |
    //                                                                                                         |
    // Once this table is filled, later transport code can read attenuation with one                           |
    // index calculation instead of multiplying layers inside the transport loop.                              |
    //                                                                                                         |
    // hot path                                                                                                |
    //   runs     : dynamic attenuation expands adjacent layer transmittance into all level pairs              |
    //   does     : accumulates transmittance products between source and target optical levels                |
    //   reads    : layer transmittance cache, attenuation table, source/target level indexes                  |
    //   feeds    : attenuation index layout consumed by ordersScatInternal                                    |
    // --------------------------------------------------------------------------------------------------------|

    const nlevel = nlayer + 1;
    const stream_stride = nlevel * nlevel;
    std.debug.assert(atten.nlevel == nlevel);
    std.debug.assert(atten.data.len >= atten.nmutot * stream_stride);
    std.debug.assert(layer_transmittance.len >= atten.nmutot * nlayer);

    for (0..atten.nmutot) |imu| {
        const stream_offset = imu * stream_stride;
        const layer_offset = imu * nlayer;
        const values = atten.data[stream_offset .. stream_offset + stream_stride];

        for (0..nlevel) |level| {
            values[level * nlevel + level] = 1.0;
        }

        for (1..nlevel) |il_to| {
            var il_from_idx = il_to;

            while (il_from_idx >= 1) : (il_from_idx -= 1) {
                const layer_idx = il_from_idx - 1;
                const value = values[il_from_idx * nlevel + il_to] *
                    layer_transmittance[layer_offset + layer_idx];

                values[(il_from_idx - 1) * nlevel + il_to] = value;
                values[il_to * nlevel + il_from_idx - 1] = value;
            }
        }
    }
}

fn fillAttenuationDynamicWithGridInBufferRepeatedExp(
    allocator: Allocator,
    data: []f64,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) DynamicAttenArray {
    // fillAttenuationDynamicWithGridInBufferRepeatedExp ------------------------------------------------------|
    // Fallback dynamic fill for layer counts that are too large for the local                                 |
    // layer-transmittance cache.                                                                              |
    //                                                                                                         |
    // tradeoff                                                                                                |
    //   Avoids fixed stack arrays that would be too small, but recomputes                                     |
    //   exp(-tau / mu) while expanding paths.                                                                 |
    // --------------------------------------------------------------------------------------------------------|

    const nlayer = layers.len;
    const nlevel = nlayer + 1;
    const required_len = geo.nmutot * nlevel * nlevel;
    std.debug.assert(data.len >= required_len);

    var atten = DynamicAttenArray{
        .allocator = allocator,
        .data = data[0..required_len],
        .nmutot = geo.nmutot,
        .nlevel = nlevel,
    };

    for (0..geo.nmutot) |imu| {
        for (0..nlevel) |level| {
            atten.set(imu, level, level, 1.0);
        }
    }

    for (0..nlayer) |ilTo_0| {
        const ilTo = ilTo_0 + 1;
        var ilFrom_idx = ilTo;

        while (ilFrom_idx >= 1) : (ilFrom_idx -= 1) {
            const layer_idx = ilFrom_idx - 1;

            for (0..geo.nmutot) |imu| {
                const u = @max(geo.u[imu], direction_cosine_floor);
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);

                // dynamic fallback T(from - 1 -> to) = T(from -> to) * exp(-tau_layer / mu).
                atten.set(imu, ilFrom_idx - 1, ilTo, atten.get(imu, ilFrom_idx, ilTo) * atten_lay);
            }
        }
    }

    for (0..nlevel) |ilTo| {
        for (ilTo..nlevel) |ilFrom| {
            for (0..geo.nmutot) |imu| {
                atten.set(imu, ilFrom, ilTo, atten.get(imu, ilTo, ilFrom));
            }
        }
    }

    if (use_spherical_correction) {
        if (pseudo_spherical_grid.isValidFor(nlayer)) {
            applyPseudoSphericalTopLevelAttenuationDynamicWithGrid(&atten, pseudo_spherical_grid, geo);
        } else {
            applyPseudoSphericalTopLevelAttenuationDynamic(&atten, layers, geo);
        }
    }

    return atten;
}
