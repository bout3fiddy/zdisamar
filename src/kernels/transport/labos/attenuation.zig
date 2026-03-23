//! Purpose:
//!   Own LABOS inter-level attenuation tables and pseudo-spherical path-length
//!   adjustments.
//!
//! Physics:
//!   Computes direct-beam attenuation between transport levels and applies the
//!   pseudo-spherical correction used for the top-level path.
//!
//! Vendor:
//!   LABOS attenuation stages
//!
//! Design:
//!   The attenuation builders are kept separate from the basis algebra so the
//!   solver facade can share the same attenuation logic across the resolved and
//!   synthetic single-layer paths.
//!
//! Invariants:
//!   Plane-parallel attenuation is symmetric in level indices. Pseudo-spherical
//!   corrections only change the top-level path segment.
//!
//! Validation:
//!   See `tests/unit/transport_labos_test.zig` for attenuation smoke coverage
//!   and scenario validation.

const std = @import("std");
const math = std.math;
const Allocator = std.mem.Allocator;
const basis = @import("basis.zig");
const common = @import("../common.zig");

pub const AttenArray = struct {
    pub const max_levels: usize = 65;

    data: [basis.max_nmutot][max_levels][max_levels]f64,
    nmutot: usize,
    nlayer: usize,

    pub fn get(self: *const AttenArray, imu: usize, from: usize, to: usize) f64 {
        return self.data[imu][from][to];
    }

    fn set(self: *AttenArray, imu: usize, from: usize, to: usize, val: f64) void {
        self.data[imu][from][to] = val;
    }
};

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

fn pseudoSphericalDirectionCosine(
    geo: *const basis.Geometry,
    layer: common.LayerInput,
    imu: usize,
) f64 {
    if (imu == geo.viewIdx()) return layer.view_mu;
    if (imu == geo.n_gauss + 1) return layer.solar_mu;
    return geo.u[imu];
}

fn applyPseudoSphericalTopLevelAttenuation(
    atten: *AttenArray,
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
            cumulative *= math.exp(-layers[level].optical_depth / u);
            atten.set(imu, top_level, level, cumulative);
        }
    }
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
            cumulative *= math.exp(-layers[level].optical_depth / u);
            atten.set(imu, top_level, level, cumulative);
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
    const rearth_km = 6371.0;
    const top_level = pseudo_spherical_grid.level_sample_starts.len - 1;
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
                sumkext += (sample.optical_depth * sample_radius) / @max(denominator, 1.0e-12);
            }
            atten.set(imu, top_level, level, math.exp(-sumkext));
        }
    }
}

pub fn fillAttenuation(
    layers: []const common.LayerInput,
    geo: *const basis.Geometry,
    use_spherical_correction: bool,
) AttenArray {
    const nlayer = layers.len;
    var atten: AttenArray = undefined;
    atten.nmutot = geo.nmutot;
    atten.nlayer = nlayer;

    for (0..geo.nmutot) |imu| {
        for (0..nlayer + 1) |from| {
            for (0..nlayer + 1) |to| {
                atten.data[imu][from][to] = 1.0;
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
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);
                atten.data[imu][ilFrom_idx - 1][ilTo] = atten.data[imu][ilFrom_idx][ilTo] * atten_lay;
            }
        }
    }

    for (0..nlayer + 1) |ilTo| {
        for (ilTo..nlayer + 1) |ilFrom| {
            for (0..geo.nmutot) |imu| {
                atten.data[imu][ilFrom][ilTo] = atten.data[imu][ilTo][ilFrom];
            }
        }
    }

    if (use_spherical_correction) {
        applyPseudoSphericalTopLevelAttenuation(&atten, layers, geo);
    }

    return atten;
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
    var atten = try DynamicAttenArray.init(allocator, geo.nmutot, nlevel);

    for (0..nlayer) |ilTo_0| {
        const ilTo = ilTo_0 + 1;
        var ilFrom_idx = ilTo;
        while (ilFrom_idx >= 1) : (ilFrom_idx -= 1) {
            const layer_idx = ilFrom_idx - 1;
            for (0..geo.nmutot) |imu| {
                const u = @max(geo.u[imu], 1.0e-6);
                const atten_lay = math.exp(-layers[layer_idx].optical_depth / u);
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
