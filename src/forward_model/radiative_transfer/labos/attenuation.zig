const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../root.zig");

pub const max_levels: usize = 65;

// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: allocator=16 B, data=16 B, nmutot=8 B, nlevel=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: data carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const DynamicAttenArray = struct {
    allocator: Allocator,
    data: []f64,
    nmutot: usize,
    nlevel: usize,

    fn init(allocator: Allocator, nmutot: usize, nlevel: usize) !DynamicAttenArray {
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
        self.allocator.free(self.data);
        self.* = undefined;
    }

    fn index(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) usize {
        return (imu * self.nlevel + from) * self.nlevel + to;
    }

    pub fn get(self: *const DynamicAttenArray, imu: usize, from: usize, to: usize) f64 {
        return self.data[self.index(imu, from, to)];
    }

    pub fn set(self: *DynamicAttenArray, imu: usize, from: usize, to: usize, value: f64) void {
        self.data[self.index(imu, from, to)] = value;
    }
};

// hot path:
//   when: LABOS transport and pseudo-spherical paths request level-to-level attenuation
//   work: serves cached adjacent and top-to-level transmittance values
//   data: layer transmittance arrays, top-to-level arrays, runtime geometry dimensions
//   follow: RuntimeAttenArray.get and transportToOtherLevels callers
// layout(64-bit):
//   size: 48 B, align: 8 B
//   field storage: layer_transmittance=16 B, top_to_level=16 B, nmutot=8 B, nlevel=8 B; padding: 0 B (0 bits)
//   unused bits: 0 padding + 0 bool-storage slack = 0 bits
//   out-of-line: layer_transmittance, top_to_level carry references/descriptors; referenced storage is not included in size
//   count: runtime/owner dependent; arrays, slices, and stack values determine live instances
//   footprint: per instance = 48 B (0.047 KiB); total also includes referenced storage above
pub const RuntimeAttenArray = struct {
    layer_transmittance: []const f64,
    top_to_level: []const f64,
    nmutot: usize,
    nlevel: usize,

    inline fn nlayer(self: *const RuntimeAttenArray) usize {
        return self.nlevel - 1;
    }

    pub inline fn adjacent(self: *const RuntimeAttenArray, imu: usize, layer_index: usize) f64 {
        return self.layer_transmittance[layerTransmittanceIndex(self.nlayer(), imu, layer_index)];
    }

    pub fn get(self: *const RuntimeAttenArray, imu: usize, from: usize, to: usize) f64 {
        if (from == to) return 1.0;
        if (from == self.nlevel - 1) return self.top_to_level[imu * self.nlevel + to];
        if (from + 1 == to) return self.adjacent(imu, from);
        if (to + 1 == from) return self.adjacent(imu, to);

        // math: non-adjacent attenuation = product of adjacent layer transmittances between levels.
        const start = @min(from, to);
        const end = @max(from, to);
        var product: f64 = 1.0;
        for (start..end) |layer_index| product *= self.adjacent(imu, layer_index);
        return product;
    }
};

fn layerTransmittanceIndex(nlayer: usize, imu: usize, layer_index: usize) usize {
    return imu * nlayer + layer_index;
}

// hot path:
//   when: before LABOS order transport builds dynamic/runtime attenuation caches
//   work: converts layer optical depths into per-stream transmittance rows
//   data: layer optical depths, geometry stream cosines, layer transmittance output
//   follow: fillRuntimeTopToLevelFromLayerCache and fillDynamicAttenuationFromLayerCache
//   math: T_layer(imu,l) = exp(-tau_l / max(mu_imu, 1e-6)).
fn fillLayerTransmittance(
    layer_transmittance: []f64,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
) void {
    const nlayer = layers.len;
    std.debug.assert(layer_transmittance.len >= geo.nmutot * nlayer);
    for (0..geo.nmutot) |imu| {
        const u = @max(geo.u[imu], 1.0e-6);
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
    if (imu == geo.viewIdx()) return layer.view_mu;
    if (imu == geo.n_gauss + 1) return layer.solar_mu;
    return geo.u[imu];
}

fn applyPseudoSphericalTopLevelAttenuationDynamic(
    atten: *DynamicAttenArray,
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
) void {
    const top_level = layers.len;
    for (0..geo.nmutot) |imu| {
        var cumulative: f64 = 1.0;
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), 1.0e-6);
            // math: pseudo-spherical shortcut top attenuation multiplies exp(-tau_l / directional_mu_l).
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
            // math: top_to_level(level) = product_{l=level}^{top-1} T_layer(l).
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
    const top_level = layers.len;
    const nlevel = top_level + 1;
    for (0..geo.nmutot) |imu| {
        const top_offset = imu * nlevel;
        var cumulative: f64 = 1.0;
        top_to_level[top_offset + top_level] = 1.0;
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const u = @max(pseudoSphericalDirectionCosine(geo, layers[level], imu), 1.0e-6);
            // math: pseudo-spherical runtime top_to_level = product exp(-tau_l / directional_mu_l).
            cumulative *= math.exp(-layers[level].optical_depth / u);
            top_to_level[top_offset + level] = cumulative;
        }
    }
}

fn levelAltitudeFromPseudoSphericalGrid(
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    level: usize,
) f64 {
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
    // UNITS:
    //   The Earth radius and altitude samples are in kilometers; attenuation
    //   remains dimensionless.
    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;
    if (top_level + 1 <= max_levels and pseudo_spherical_grid.samples.len <= max_pseudo_spherical_fast_samples) {
        applyPseudoSphericalTopLevelAttenuationDynamicWithPreparedGrid(
            atten,
            pseudo_spherical_grid,
            geo,
            top_level,
        );
        return;
    }

    const rearth_km = 6371.0;
    for (0..geo.nmutot) |imu| {
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        atten.set(imu, top_level, top_level, 1.0);
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const level_radius = rearth_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
            const sqrx_sin2theta = sin2theta * level_radius * level_radius;
            var sumkext: f64 = 0.0;
            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const sample = pseudo_spherical_grid.samples[index];
                if (sample.optical_depth <= 0.0) continue;
                const sample_radius = rearth_km + sample.altitude_km;
                const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
                const numerator = sample.optical_depth * sample_radius;
                // math: spherical slant tau += tau_sample * r_sample / sqrt(r_sample^2 - r_level^2 sin(theta)^2).
                sumkext += numerator / @max(denominator, 1.0e-12);
            }
            // math: T(top->level) = exp(-sum spherical slant optical depths).
            atten.set(imu, top_level, level, math.exp(-sumkext));
        }
    }
}

fn applyPseudoSphericalRuntimeTopToLevelWithGrid(
    top_to_level: []f64,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
) void {
    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;
    if (top_level + 1 <= max_levels and pseudo_spherical_grid.samples.len <= max_pseudo_spherical_fast_samples) {
        applyPseudoSphericalRuntimeTopToLevelWithPreparedGrid(
            top_to_level,
            pseudo_spherical_grid,
            geo,
            top_level,
        );
        return;
    }

    const rearth_km = 6371.0;
    const nlevel = top_level + 1;
    for (0..geo.nmutot) |imu| {
        const top_offset = imu * nlevel;
        const u = std.math.clamp(geo.u[imu], -1.0, 1.0);
        const sin2theta = @max(1.0 - u * u, 0.0);
        top_to_level[top_offset + top_level] = 1.0;
        var level = top_level;
        while (level > 0) {
            level -= 1;
            const level_radius = rearth_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
            const sqrx_sin2theta = sin2theta * level_radius * level_radius;
            var sumkext: f64 = 0.0;
            for (pseudo_spherical_grid.level_sample_starts[level]..pseudo_spherical_grid.samples.len) |index| {
                const sample = pseudo_spherical_grid.samples[index];
                if (sample.optical_depth <= 0.0) continue;
                const sample_radius = rearth_km + sample.altitude_km;
                const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
                const numerator = sample.optical_depth * sample_radius;
                // math: spherical slant tau += tau_sample * r_sample / sqrt(r_sample^2 - r_level^2 sin(theta)^2).
                sumkext += numerator / @max(denominator, 1.0e-12);
            }
            // math: top_to_level = exp(-sum spherical slant optical depths).
            top_to_level[top_offset + level] = math.exp(-sumkext);
        }
    }
}

const max_pseudo_spherical_fast_samples: usize = 512;

// hot path:
//   when: pseudo-spherical runtime attenuation uses a prepared support grid
//   work: applies top-to-level attenuation from prepared samples across streams and levels
//   data: prepared pseudo-spherical samples, runtime attenuation cache, layer grid levels
//   follow: sample order from forward_input pseudo-spherical buffers
fn applyPseudoSphericalRuntimeTopToLevelWithPreparedGrid(
    top_to_level: []f64,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    top_level: usize,
) void {
    const rearth_km = 6371.0;
    const nlevel = top_level + 1;
    var level_radius_sq: [max_levels]f64 = undefined;
    var sample_radius_sq: [max_pseudo_spherical_fast_samples]f64 = undefined;
    var sample_weighted_radius: [max_pseudo_spherical_fast_samples]f64 = undefined;

    for (0..nlevel) |level| {
        const radius = rearth_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
        level_radius_sq[level] = radius * radius;
    }
    for (pseudo_spherical_grid.samples, 0..) |sample, index| {
        const radius = rearth_km + sample.altitude_km;
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
                // math: prepared-grid spherical tau reuses tau_sample * r_sample and radius squares.
                sumkext += sample_weighted_radius[index] / @max(denominator, 1.0e-12);
            }
            top_to_level[top_offset + level] = math.exp(-sumkext);
        }
    }
}

// hot path:
//   when: pseudo-spherical dynamic attenuation uses a prepared support grid
//   work: writes top-level attenuation samples across streams and levels
//   data: prepared pseudo-spherical samples, attenuation table, geometry stream count
//   follow: applyPseudoSphericalTopLevelAttenuationDynamicWithGrid callers
fn applyPseudoSphericalTopLevelAttenuationDynamicWithPreparedGrid(
    atten: *DynamicAttenArray,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    top_level: usize,
) void {
    const rearth_km = 6371.0;
    const nlevel = top_level + 1;
    const stream_stride = nlevel * nlevel;
    var level_radius_sq: [max_levels]f64 = undefined;
    var sample_radius_sq: [max_pseudo_spherical_fast_samples]f64 = undefined;
    var sample_weighted_radius: [max_pseudo_spherical_fast_samples]f64 = undefined;

    for (0..nlevel) |level| {
        const radius = rearth_km + levelAltitudeFromPseudoSphericalGrid(pseudo_spherical_grid, level);
        level_radius_sq[level] = radius * radius;
    }
    for (pseudo_spherical_grid.samples, 0..) |sample, index| {
        const radius = rearth_km + sample.altitude_km;
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
                // math: prepared-grid spherical tau reuses tau_sample * r_sample and radius squares.
                sumkext += sample_weighted_radius[index] / @max(denominator, 1.0e-12);
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

// hot path:
//   when: LABOS tangent routes request derivative attenuation
//   work: fills dynamic attenuation derivatives for layer optical-depth perturbations
//   data: base layers, derivative layers, geometry streams, attenuation tangent buffer
//   follow: nonIntegratedReflectanceTangent and ordersScatTangent
//   math: dT_l/dx = exp(-tau_l/mu) * (-(d tau_l/dx) / mu); path derivatives use product rule.
pub fn fillAttenuationTangentDynamic(
    allocator: Allocator,
    layers: []const common.LayerInput,
    state: common.Jacobian.State,
    geo: *const basis.Geometry,
) !DynamicAttenArray {
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
                const u = @max(geo.u[imu], 1.0e-6);
                const trans = math.exp(-layers[layer_idx].optical_depth / u);
                const dtrans = trans * (-common.Jacobian.get(layers[layer_idx].optical_depth_jacobian, state) / u);
                // math: d(product*T_l) = d(product)*T_l + product*dT_l.
                atten.set(
                    imu,
                    ilFrom_idx - 1,
                    ilTo,
                    atten.get(imu, ilFrom_idx, ilTo) * trans + cumulativeBaseTransmittance(layers, geo, imu, ilFrom_idx, ilTo) * dtrans,
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
    var value: f64 = 1.0;
    if (from_level >= to_level) return value;
    const u = @max(geo.u[imu], 1.0e-6);
    for (from_level..to_level) |layer_idx| {
        if (layer_idx >= layers.len) break;
        // math: base path transmittance = product_l exp(-tau_l / mu).
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
    return fillAttenuationDynamicWithGridInBufferRepeatedExp(
        allocator,
        data,
        layers,
        pseudo_spherical_grid,
        geo,
        use_spherical_correction,
    );
}

// hot path:
//   when: layer-resolved LABOS builds attenuation for dynamic geometry
//   work: fills layer transmittance and expands it into level-pair attenuation tables
//   data: layer transmittance cache, attenuation table, geometry levels and streams
//   follow: fillDynamicAttenuationFromLayerCache and pseudo-spherical overlays
pub fn fillAttenuationDynamicWithGridInBufferAndLayerCache(
    allocator: Allocator,
    data: []f64,
    layer_transmittance: []f64,
    layers: []const common.LayerInput,
    pseudo_spherical_grid: common.PseudoSphericalGrid,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) DynamicAttenArray {
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

// hot path:
//   when: dynamic attenuation expands adjacent layer transmittance into all level pairs
//   work: accumulates transmittance products between source and target optical levels
//   data: layer transmittance cache, attenuation table, source/target level indexes
//   follow: attenuation index layout consumed by ordersScatInternal
fn fillDynamicAttenuationFromLayerCache(
    atten: *DynamicAttenArray,
    layer_transmittance: []const f64,
    nlayer: usize,
) void {
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
                const u = @max(geo.u[imu], 1.0e-6);
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);
                // math: dynamic fallback T(from-1,to) = T(from,to) * exp(-tau_layer / mu).
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
