//! Purpose:
//!   Own vertical-grid allocation and explicit-vs-legacy construction for
//!   optics preparation.
//!
//! Physics:
//!   Materializes the layer and sublayer altitude/pressure contracts that
//!   later optics preparation stages consume.
//!
//! Vendor:
//!   `optics preparation vertical grid`
//!
//! Design:
//!   Keep grid allocation and ordering policy separate from the coupled
//!   absorber/materialization loop in `builder.zig`.
//!
//! Invariants:
//!   Explicit interval grids preserve declared interval identity while laying
//!   out sublayers in the bottom-up transport order expected downstream.
//!
//! Validation:
//!   O2 A forward-shape and transport smoke tests cover the resulting grid.

const std = @import("std");
const AtmosphereModel = @import("../../../model/Atmosphere.zig");
const Scene = @import("../../../model/Scene.zig").Scene;
const ReferenceData = @import("../../../model/ReferenceData.zig");
const ParticleProfiles = @import("../prepare/particle_profiles.zig");

const Allocator = std.mem.Allocator;

pub const OwnedVerticalGrid = struct {
    layer_top_altitudes_km: []f64,
    layer_bottom_altitudes_km: []f64,
    layer_top_pressures_hpa: []f64,
    layer_bottom_pressures_hpa: []f64,
    layer_interval_indices_1based: []u32,
    layer_sublayer_starts: []u32,
    layer_sublayer_counts: []u32,
    layer_subcolumn_labels: []AtmosphereModel.PartitionLabel,
    sublayer_top_altitudes_km: []f64,
    sublayer_bottom_altitudes_km: []f64,
    sublayer_top_pressures_hpa: []f64,
    sublayer_bottom_pressures_hpa: []f64,
    sublayer_mid_altitudes_km: []f64,
    sublayer_interval_indices_1based: []u32,
    sublayer_subcolumn_labels: []AtmosphereModel.PartitionLabel,

    pub fn borrow(self: *const OwnedVerticalGrid) ParticleProfiles.PreparedVerticalGrid {
        return .{
            .layer_top_altitudes_km = self.layer_top_altitudes_km,
            .layer_bottom_altitudes_km = self.layer_bottom_altitudes_km,
            .layer_interval_indices_1based = self.layer_interval_indices_1based,
            .sublayer_top_altitudes_km = self.sublayer_top_altitudes_km,
            .sublayer_bottom_altitudes_km = self.sublayer_bottom_altitudes_km,
            .sublayer_mid_altitudes_km = self.sublayer_mid_altitudes_km,
            .sublayer_parent_interval_indices_1based = self.sublayer_interval_indices_1based,
        };
    }

    pub fn deinit(self: *OwnedVerticalGrid, allocator: Allocator) void {
        allocator.free(self.layer_top_altitudes_km);
        allocator.free(self.layer_bottom_altitudes_km);
        allocator.free(self.layer_top_pressures_hpa);
        allocator.free(self.layer_bottom_pressures_hpa);
        allocator.free(self.layer_interval_indices_1based);
        allocator.free(self.layer_sublayer_starts);
        allocator.free(self.layer_sublayer_counts);
        allocator.free(self.layer_subcolumn_labels);
        allocator.free(self.sublayer_top_altitudes_km);
        allocator.free(self.sublayer_bottom_altitudes_km);
        allocator.free(self.sublayer_top_pressures_hpa);
        allocator.free(self.sublayer_bottom_pressures_hpa);
        allocator.free(self.sublayer_mid_altitudes_km);
        allocator.free(self.sublayer_interval_indices_1based);
        allocator.free(self.sublayer_subcolumn_labels);
        self.* = undefined;
    }
};

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    if (scene.atmosphere.interval_grid.enabled()) {
        return buildExplicit(allocator, scene, profile);
    }
    return buildLegacy(allocator, scene, profile);
}

fn buildExplicit(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    const intervals = scene.atmosphere.interval_grid.intervals;
    const layer_count = intervals.len;
    var total_sublayer_count: usize = 0;
    for (intervals) |interval| total_sublayer_count += interval.altitude_divisions;

    var grid = try allocate(allocator, layer_count, total_sublayer_count);
    errdefer grid.deinit(allocator);

    var sublayer_cursor: usize = 0;
    var source_interval_index = intervals.len;
    var output_layer_index: usize = 0;
    while (source_interval_index > 0) : (output_layer_index += 1) {
        source_interval_index -= 1;
        const interval = intervals[source_interval_index];
        const index = output_layer_index;
        const has_altitude_bounds = interval.hasAltitudeBounds();
        const layer_top_altitude_km = if (has_altitude_bounds)
            interval.top_altitude_km
        else
            profile.interpolateAltitudeForPressure(interval.top_pressure_hpa);
        const layer_bottom_altitude_km = if (has_altitude_bounds)
            interval.bottom_altitude_km
        else
            profile.interpolateAltitudeForPressure(interval.bottom_pressure_hpa);

        grid.layer_top_altitudes_km[index] = layer_top_altitude_km;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude_km;
        grid.layer_top_pressures_hpa[index] = interval.top_pressure_hpa;
        grid.layer_bottom_pressures_hpa[index] = interval.bottom_pressure_hpa;
        grid.layer_interval_indices_1based[index] = interval.index_1based;
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = interval.altitude_divisions;
        grid.layer_subcolumn_labels[index] = scene.atmosphere.subcolumns.labelForAltitude(
            0.5 * (layer_top_altitude_km + layer_bottom_altitude_km),
        );

        const log_bottom_pressure = @log(@max(interval.bottom_pressure_hpa, 1.0e-9));
        const log_top_pressure = @log(@max(interval.top_pressure_hpa, 1.0e-9));
        const layer_altitude_span_km = layer_top_altitude_km - layer_bottom_altitude_km;
        for (0..interval.altitude_divisions) |sublayer_index| {
            const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / @as(f64, @floatFromInt(interval.altitude_divisions));
            const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / @as(f64, @floatFromInt(interval.altitude_divisions));
            const bottom_pressure_hpa = @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * bottom_fraction);
            const top_pressure_hpa = @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * top_fraction);
            const bottom_altitude_km = if (has_altitude_bounds)
                layer_bottom_altitude_km + layer_altitude_span_km * bottom_fraction
            else
                profile.interpolateAltitudeForPressure(bottom_pressure_hpa);
            const top_altitude_km = if (has_altitude_bounds)
                layer_bottom_altitude_km + layer_altitude_span_km * top_fraction
            else
                profile.interpolateAltitudeForPressure(top_pressure_hpa);
            const global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = top_altitude_km;
            grid.sublayer_bottom_altitudes_km[global_index] = bottom_altitude_km;
            grid.sublayer_top_pressures_hpa[global_index] = top_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[global_index] = bottom_pressure_hpa;
            grid.sublayer_mid_altitudes_km[global_index] = 0.5 * (top_altitude_km + bottom_altitude_km);
            grid.sublayer_interval_indices_1based[global_index] = interval.index_1based;
            grid.sublayer_subcolumn_labels[global_index] = scene.atmosphere.subcolumns.labelForAltitude(
                grid.sublayer_mid_altitudes_km[global_index],
            );
        }
        sublayer_cursor += interval.altitude_divisions;
    }
    return grid;
}

fn buildLegacy(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    const layer_count: usize = @max(scene.atmosphere.preparedLayerCount(), @as(u32, 1));
    const sublayer_divisions: usize = @max(@as(u32, scene.atmosphere.sublayer_divisions), @as(u32, 1));
    const total_sublayer_count = layer_count * sublayer_divisions;
    var grid = try allocate(allocator, layer_count, total_sublayer_count);
    errdefer grid.deinit(allocator);

    const bottom_altitude_km = scene.geometry.surface_altitude_km;
    const top_altitude_km = @max(profile.maxAltitude(), bottom_altitude_km + 1.0);
    const layer_span_km = (top_altitude_km - bottom_altitude_km) / @as(f64, @floatFromInt(layer_count));

    var sublayer_cursor: usize = 0;
    for (0..layer_count) |index| {
        const layer_top_altitude = bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index + 1));
        const layer_bottom_altitude = bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index));
        grid.layer_top_altitudes_km[index] = layer_top_altitude;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude;
        grid.layer_top_pressures_hpa[index] = profile.interpolatePressure(layer_top_altitude);
        grid.layer_bottom_pressures_hpa[index] = profile.interpolatePressure(layer_bottom_altitude);
        grid.layer_interval_indices_1based[index] = @intCast(index + 1);
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = @intCast(sublayer_divisions);
        grid.layer_subcolumn_labels[index] = scene.atmosphere.subcolumns.labelForAltitude(
            0.5 * (layer_top_altitude + layer_bottom_altitude),
        );

        for (0..sublayer_divisions) |sublayer_index| {
            const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / @as(f64, @floatFromInt(sublayer_divisions));
            const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / @as(f64, @floatFromInt(sublayer_divisions));
            const sublayer_top_altitude = layer_bottom_altitude + layer_span_km * top_fraction;
            const sublayer_bottom_altitude = layer_bottom_altitude + layer_span_km * bottom_fraction;
            const global_index = sublayer_cursor + sublayer_index;
            grid.sublayer_top_altitudes_km[global_index] = sublayer_top_altitude;
            grid.sublayer_bottom_altitudes_km[global_index] = sublayer_bottom_altitude;
            grid.sublayer_top_pressures_hpa[global_index] = profile.interpolatePressure(sublayer_top_altitude);
            grid.sublayer_bottom_pressures_hpa[global_index] = profile.interpolatePressure(sublayer_bottom_altitude);
            grid.sublayer_mid_altitudes_km[global_index] = 0.5 * (sublayer_top_altitude + sublayer_bottom_altitude);
            grid.sublayer_interval_indices_1based[global_index] = @intCast(index + 1);
            grid.sublayer_subcolumn_labels[global_index] = scene.atmosphere.subcolumns.labelForAltitude(
                grid.sublayer_mid_altitudes_km[global_index],
            );
        }
        sublayer_cursor += sublayer_divisions;
    }
    return grid;
}

fn allocate(
    allocator: Allocator,
    layer_count: usize,
    total_sublayer_count: usize,
) !OwnedVerticalGrid {
    const layer_top_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_altitudes_km);
    const layer_bottom_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_altitudes_km);
    const layer_top_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_pressures_hpa);
    const layer_bottom_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_pressures_hpa);
    const layer_interval_indices_1based = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_interval_indices_1based);
    const layer_sublayer_starts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_sublayer_starts);
    const layer_sublayer_counts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_sublayer_counts);
    const layer_subcolumn_labels = try allocator.alloc(AtmosphereModel.PartitionLabel, layer_count);
    errdefer allocator.free(layer_subcolumn_labels);
    const sublayer_top_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_top_altitudes_km);
    const sublayer_bottom_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_bottom_altitudes_km);
    const sublayer_top_pressures_hpa = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_top_pressures_hpa);
    const sublayer_bottom_pressures_hpa = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_bottom_pressures_hpa);
    const sublayer_mid_altitudes_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_mid_altitudes_km);
    const sublayer_interval_indices_1based = try allocator.alloc(u32, total_sublayer_count);
    errdefer allocator.free(sublayer_interval_indices_1based);
    const sublayer_subcolumn_labels = try allocator.alloc(AtmosphereModel.PartitionLabel, total_sublayer_count);
    errdefer allocator.free(sublayer_subcolumn_labels);

    return .{
        .layer_top_altitudes_km = layer_top_altitudes_km,
        .layer_bottom_altitudes_km = layer_bottom_altitudes_km,
        .layer_top_pressures_hpa = layer_top_pressures_hpa,
        .layer_bottom_pressures_hpa = layer_bottom_pressures_hpa,
        .layer_interval_indices_1based = layer_interval_indices_1based,
        .layer_sublayer_starts = layer_sublayer_starts,
        .layer_sublayer_counts = layer_sublayer_counts,
        .layer_subcolumn_labels = layer_subcolumn_labels,
        .sublayer_top_altitudes_km = sublayer_top_altitudes_km,
        .sublayer_bottom_altitudes_km = sublayer_bottom_altitudes_km,
        .sublayer_top_pressures_hpa = sublayer_top_pressures_hpa,
        .sublayer_bottom_pressures_hpa = sublayer_bottom_pressures_hpa,
        .sublayer_mid_altitudes_km = sublayer_mid_altitudes_km,
        .sublayer_interval_indices_1based = sublayer_interval_indices_1based,
        .sublayer_subcolumn_labels = sublayer_subcolumn_labels,
    };
}
