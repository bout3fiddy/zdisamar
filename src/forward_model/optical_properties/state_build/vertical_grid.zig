const std = @import("std");
const AtmosphereModel = @import("../../../input/Atmosphere.zig");
const Scene = @import("../../../input/Scene.zig").Scene;
const ReferenceData = @import("../../../input/ReferenceData.zig");
const ParticleProfiles = @import("../shared/particle_profiles.zig");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");

const Allocator = std.mem.Allocator;

// vertical_grid.zig -----------------------------------------------------------------------------------------|
// Builds owned vertical-grid arrays before optical-property layer accumulation.                              |
//                                                                                                            |
// called by                                                                                                  |
//   context.zig during PreparationContext.init.                                                              |
//                                                                                                            |
// main paths                                                                                                 |
//   explicit interval grid        : use scene atmosphere interval controls.                                  |
//   DISAMAR-parity support grid   : expand intervals into reference-style support rows.                      |
//   legacy evenly divided profile : split the climatology profile into the requested layer count.            |
//                                                                                                            |
// hot path                                                                                                   |
//   Runs once per prepared scene, before all layer and sublayer optical-property rows are accumulated.       |
//                                                                                                            |
// memory                                                                                                     |
//   OwnedVerticalGrid owns parallel arrays for layer and sublayer altitude, pressure, interval, and support  |
//   metadata. Context deinitializes the grid unless its fields have been consumed by later preparation data. |
// -----------------------------------------------------------------------------------------------------------|

// OwnedVerticalGrid -----------------------------------------------------------------------------------------|
// Owned layer and sublayer grid arrays prepared before optical-property accumulation.                        |
//                                                                                                            |
// layout(64-bit)                                                                                             |
// size: 224 B (0.219 KiB), align: 8 B                                                                        |
//                                                                                                            |
// memory                                                                                                     |
// [  0.. 63] layer altitude/pressure slices: 4 x []f64                                                       |
// [ 64..111] layer interval/start/count slices: 3 x []u32                                                    |
// [112..207] sublayer altitude/pressure/mid/support slices: 6 x []f64                                        |
// [208..223] sublayer_interval_indices_1based: []u32                                                         |
//                                                                                                            |
// cache span: 4 cache lines at 64 B per line                                                                 |
// footprint: per instance = 224 B; referenced grid arrays are out of line                                    |
// -----------------------------------------------------------------------------------------------------------|
pub const OwnedVerticalGrid = struct {
    layer_top_altitudes_km: []f64,
    layer_bottom_altitudes_km: []f64,
    layer_top_pressures_hpa: []f64,
    layer_bottom_pressures_hpa: []f64,
    layer_interval_indices_1based: []u32,
    layer_sublayer_starts: []u32,
    layer_sublayer_counts: []u32,
    sublayer_top_altitudes_km: []f64,
    sublayer_bottom_altitudes_km: []f64,
    sublayer_top_pressures_hpa: []f64,
    sublayer_bottom_pressures_hpa: []f64,
    sublayer_mid_altitudes_km: []f64,
    sublayer_support_weights_km: []f64,
    sublayer_interval_indices_1based: []u32,

    pub fn borrow(self: *const OwnedVerticalGrid) ParticleProfiles.PreparedVerticalGrid {
        return .{
            .layer_top_altitudes_km = self.layer_top_altitudes_km,
            .layer_bottom_altitudes_km = self.layer_bottom_altitudes_km,
            .layer_interval_indices_1based = self.layer_interval_indices_1based,
            .sublayer_top_altitudes_km = self.sublayer_top_altitudes_km,
            .sublayer_bottom_altitudes_km = self.sublayer_bottom_altitudes_km,
            .sublayer_mid_altitudes_km = self.sublayer_mid_altitudes_km,
            .sublayer_support_weights_km = self.sublayer_support_weights_km,
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
        allocator.free(self.sublayer_top_altitudes_km);
        allocator.free(self.sublayer_bottom_altitudes_km);
        allocator.free(self.sublayer_top_pressures_hpa);
        allocator.free(self.sublayer_bottom_pressures_hpa);
        allocator.free(self.sublayer_mid_altitudes_km);
        allocator.free(self.sublayer_support_weights_km);
        allocator.free(self.sublayer_interval_indices_1based);
        self.* = undefined;
    }
};

pub fn build(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    // build -------------------------------------------------------------------------------------------------|
    // Select explicit interval-grid or legacy evenly divided vertical-grid construction.                     |
    //                                                                                                        |
    // hot path                                                                                               |
    // optical-state preparation builds this grid before layer accumulation.                                  |
    // -------------------------------------------------------------------------------------------------------|

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
    // buildExplicit -----------------------------------------------------------------------------------------|
    // Build grid arrays from explicit interval definitions.                                                  |
    //                                                                                                        |
    // hot path                                                                                               |
    // fills layer/sublayer altitude, pressure, interval, and label fields before layer accumulation.         |
    //                                                                                                        |
    // math                                                                                                   |
    // p(f) = exp(log(p_bottom) + (log(p_top) - log(p_bottom)) * f).                                          |
    // Altitude is linear in f when explicit altitude bounds exist.                                           |
    // -------------------------------------------------------------------------------------------------------|

    const AltitudeBounds = struct {
        top_altitude_km: f64,
        bottom_altitude_km: f64,
    };

    const intervals = scene.atmosphere.interval_grid.intervals;
    const disamar_support_grid = usesDisamarParitySupportGrid(scene);
    const sublayer_order: usize = @max(@as(usize, scene.atmosphere.sublayer_divisions), 1);
    var layer_count: usize = intervals.len;
    var total_sublayer_count: usize = 0;
    if (disamar_support_grid) {
        layer_count = 0;
        total_sublayer_count = 1;
        for (intervals) |interval| {
            const interval_layer_count = @as(usize, interval.altitude_divisions) + 1;
            layer_count += interval_layer_count;
            total_sublayer_count += interval_layer_count * (sublayer_order + 1);
        }
    } else {
        for (intervals) |interval| total_sublayer_count += interval.altitude_divisions;
    }

    var grid = try allocate(allocator, layer_count, total_sublayer_count);
    errdefer grid.deinit(allocator);

    if (disamar_support_grid) {
        return buildExplicitDisamarParity(
            allocator,
            scene,
            profile,
            &grid,
            sublayer_order,
        );
    }

    var sublayer_cursor: usize = 0;
    var source_interval_index = intervals.len;
    var output_layer_index: usize = 0;
    while (source_interval_index > 0) : (output_layer_index += 1) {
        source_interval_index -= 1;
        const interval = intervals[source_interval_index];
        const index = output_layer_index;
        const has_altitude_bounds = interval.hasAltitudeBounds();
        const layer_altitudes: AltitudeBounds = choose_layer_altitudes: {
            if (has_altitude_bounds) {
                break :choose_layer_altitudes .{
                    .top_altitude_km = interval.top_altitude_km,
                    .bottom_altitude_km = interval.bottom_altitude_km,
                };
            }

            break :choose_layer_altitudes .{
                .top_altitude_km = profile.interpolateAltitudeForPressure(interval.top_pressure_hpa),
                .bottom_altitude_km = profile.interpolateAltitudeForPressure(interval.bottom_pressure_hpa),
            };
        };

        grid.layer_top_altitudes_km[index] = layer_altitudes.top_altitude_km;
        grid.layer_bottom_altitudes_km[index] = layer_altitudes.bottom_altitude_km;
        grid.layer_top_pressures_hpa[index] = interval.top_pressure_hpa;
        grid.layer_bottom_pressures_hpa[index] = interval.bottom_pressure_hpa;
        grid.layer_interval_indices_1based[index] = if (disamar_support_grid)
            @intCast(output_layer_index + 1)
        else
            interval.index_1based;
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = interval.altitude_divisions;

        {
            const log_bottom_pressure = @log(@max(interval.bottom_pressure_hpa, 1.0e-9));
            const log_top_pressure = @log(@max(interval.top_pressure_hpa, 1.0e-9));
            const layer_altitude_span_km = layer_altitudes.top_altitude_km -
                layer_altitudes.bottom_altitude_km;

            for (0..interval.altitude_divisions) |sublayer_index| {
                const division_count_f = @as(f64, @floatFromInt(interval.altitude_divisions));
                const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / division_count_f;
                const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / division_count_f;

                // math: sublayer pressures are log-linear between interval bottom/top pressures.
                const bottom_pressure_hpa =
                    @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * bottom_fraction);
                const top_pressure_hpa =
                    @exp(log_bottom_pressure + (log_top_pressure - log_bottom_pressure) * top_fraction);
                const sublayer_altitudes: AltitudeBounds = choose_sublayer_altitudes: {
                    if (has_altitude_bounds) {
                        break :choose_sublayer_altitudes .{
                            .top_altitude_km = layer_altitudes.bottom_altitude_km +
                                layer_altitude_span_km * top_fraction,
                            .bottom_altitude_km = layer_altitudes.bottom_altitude_km +
                                layer_altitude_span_km * bottom_fraction,
                        };
                    }

                    break :choose_sublayer_altitudes .{
                        .top_altitude_km = profile.interpolateAltitudeForPressure(top_pressure_hpa),
                        .bottom_altitude_km = profile.interpolateAltitudeForPressure(bottom_pressure_hpa),
                    };
                };
                const global_index = sublayer_cursor + sublayer_index;

                grid.sublayer_top_altitudes_km[global_index] = sublayer_altitudes.top_altitude_km;
                grid.sublayer_bottom_altitudes_km[global_index] = sublayer_altitudes.bottom_altitude_km;
                grid.sublayer_top_pressures_hpa[global_index] = top_pressure_hpa;
                grid.sublayer_bottom_pressures_hpa[global_index] = bottom_pressure_hpa;
                grid.sublayer_mid_altitudes_km[global_index] =
                    0.5 * (sublayer_altitudes.top_altitude_km + sublayer_altitudes.bottom_altitude_km);
                grid.sublayer_support_weights_km[global_index] =
                    @max(sublayer_altitudes.top_altitude_km - sublayer_altitudes.bottom_altitude_km, 0.0);
                grid.sublayer_interval_indices_1based[global_index] = interval.index_1based;
            }
        }
        sublayer_cursor += interval.altitude_divisions;
    }
    return grid;
}

fn buildExplicitDisamarParity(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
    grid: *OwnedVerticalGrid,
    sublayer_order: usize,
) !OwnedVerticalGrid {
    // buildExplicitDisamarParity ----------------------------------------------------------------------------|
    // Build DISAMAR-parity support rows from explicit interval bounds and quadrature division points.        |
    //                                                                                                        |
    // hot path                                                                                               |
    // O2 A retrievals refresh this grid every state evaluation. Use stack scratch for common small orders    |
    // and allocate only when the requested support order exceeds that stack storage.                         |
    //                                                                                                        |
    // math                                                                                                   |
    // z_node = z_lower + 0.5 * (x_gauss + 1) * (z_upper - z_lower).                                          |
    // weight_km = 0.5 * w_gauss * (z_upper - z_lower).                                                       |
    // -------------------------------------------------------------------------------------------------------|

    const AltitudeBounds = struct {
        top_altitude_km: f64,
        bottom_altitude_km: f64,
    };
    const Boundary = struct {
        altitude_km: f64,
        pressure_hpa: f64,
    };

    const intervals = scene.atmosphere.interval_grid.intervals;

    var stack_support_nodes: [10]f64 = undefined;
    var stack_support_weights: [10]f64 = undefined;

    var dynamic_support_nodes: []f64 = &.{};
    defer if (dynamic_support_nodes.len != 0) allocator.free(dynamic_support_nodes);

    var dynamic_support_weights: []f64 = &.{};
    defer if (dynamic_support_weights.len != 0) allocator.free(dynamic_support_weights);

    const use_stack_support_nodes = sublayer_order <= stack_support_nodes.len;
    const support_nodes, const support_weights = if (use_stack_support_nodes) stack: {
        const nodes = stack_support_nodes[0..sublayer_order];
        const weights = stack_support_weights[0..sublayer_order];

        try gauss_legendre.fillNodesAndWeights(
            @intCast(sublayer_order),
            nodes,
            weights,
        );

        break :stack .{ nodes, weights };
    } else dynamic: {
        dynamic_support_nodes = try allocator.alloc(f64, sublayer_order);
        dynamic_support_weights = try allocator.alloc(f64, sublayer_order);

        try gauss_legendre.fillNodesAndWeights(
            @intCast(sublayer_order),
            dynamic_support_nodes,
            dynamic_support_weights,
        );

        break :dynamic .{ dynamic_support_nodes, dynamic_support_weights };
    };

    var layer_cursor: usize = 0;
    var support_cursor: usize = 0;
    var stack_rtm_nodes: [gauss_legendre.max_disamar_division_points]f64 = undefined;
    var source_interval_index = intervals.len;
    while (source_interval_index > 0) {
        source_interval_index -= 1;
        const interval = intervals[source_interval_index];
        const parity_interval_index_1based: u32 = @intCast((intervals.len - source_interval_index));
        const has_altitude_bounds = interval.hasAltitudeBounds();
        const interval_altitudes: AltitudeBounds = choose_interval_altitudes: {
            if (has_altitude_bounds) {
                break :choose_interval_altitudes .{
                    .top_altitude_km = interval.top_altitude_km,
                    .bottom_altitude_km = interval.bottom_altitude_km,
                };
            }

            break :choose_interval_altitudes .{
                .top_altitude_km = profile.interpolateAltitudeForPressureSpline(interval.top_pressure_hpa),
                .bottom_altitude_km = profile.interpolateAltitudeForPressureSpline(interval.bottom_pressure_hpa),
            };
        };
        const interval_layer_count: usize = @as(usize, interval.altitude_divisions) + 1;
        const interior_node_count = interval_layer_count - 1;

        var dynamic_rtm_nodes: []f64 = &.{};
        defer if (dynamic_rtm_nodes.len != 0) allocator.free(dynamic_rtm_nodes);

        const use_stack_rtm_nodes = interior_node_count <= stack_rtm_nodes.len;
        const rtm_nodes: []f64 = if (use_stack_rtm_nodes)
            stack_rtm_nodes[0..interior_node_count]
        else dynamic: {
            dynamic_rtm_nodes = try allocator.alloc(f64, interior_node_count);
            break :dynamic dynamic_rtm_nodes;
        };

        if (interior_node_count > 0) {
            try gauss_legendre.fillDisamarDivPointsIntervalNodes(
                @intCast(interior_node_count),
                interval_altitudes.bottom_altitude_km,
                interval_altitudes.top_altitude_km,
                rtm_nodes,
            );
        }

        if (layer_cursor == 0) {
            grid.sublayer_top_altitudes_km[support_cursor] = interval_altitudes.bottom_altitude_km;
            grid.sublayer_bottom_altitudes_km[support_cursor] = interval_altitudes.bottom_altitude_km;
            grid.sublayer_top_pressures_hpa[support_cursor] = interval.bottom_pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[support_cursor] = interval.bottom_pressure_hpa;
            grid.sublayer_mid_altitudes_km[support_cursor] = interval_altitudes.bottom_altitude_km;
            grid.sublayer_support_weights_km[support_cursor] = 0.0;
        }

        // The shared boundary row between adjacent pressure intervals belongs to
        // the interval currently being materialized in the vendor diagnostic output.
        grid.sublayer_interval_indices_1based[support_cursor] = parity_interval_index_1based;

        var previous_boundary_altitude_km = interval_altitudes.bottom_altitude_km;
        var previous_boundary_pressure_hpa = interval.bottom_pressure_hpa;
        for (0..interval_layer_count) |local_layer_index| {
            const next_boundary: Boundary = choose_next_boundary: {
                if (local_layer_index == interior_node_count) {
                    break :choose_next_boundary .{
                        .altitude_km = interval_altitudes.top_altitude_km,
                        .pressure_hpa = interval.top_pressure_hpa,
                    };
                }

                const altitude_km = rtm_nodes[local_layer_index];
                break :choose_next_boundary .{
                    .altitude_km = altitude_km,
                    .pressure_hpa = profile.interpolatePressureLogSpline(altitude_km),
                };
            };

            const global_layer_index = layer_cursor + local_layer_index;
            grid.layer_top_altitudes_km[global_layer_index] = next_boundary.altitude_km;
            grid.layer_bottom_altitudes_km[global_layer_index] = previous_boundary_altitude_km;
            grid.layer_top_pressures_hpa[global_layer_index] = next_boundary.pressure_hpa;
            grid.layer_bottom_pressures_hpa[global_layer_index] = previous_boundary_pressure_hpa;
            grid.layer_interval_indices_1based[global_layer_index] = parity_interval_index_1based;
            grid.layer_sublayer_starts[global_layer_index] = @intCast(support_cursor);
            grid.layer_sublayer_counts[global_layer_index] = @intCast(sublayer_order + 2);

            const layer_span_km = @max(next_boundary.altitude_km - previous_boundary_altitude_km, 0.0);
            for (0..sublayer_order) |support_index| {
                const global_support_index = support_cursor + 1 + support_index;
                const support_altitude_km = previous_boundary_altitude_km +
                    0.5 * (support_nodes[support_index] + 1.0) * layer_span_km;

                grid.sublayer_top_altitudes_km[global_support_index] = next_boundary.altitude_km;
                grid.sublayer_bottom_altitudes_km[global_support_index] = previous_boundary_altitude_km;
                grid.sublayer_top_pressures_hpa[global_support_index] = next_boundary.pressure_hpa;
                grid.sublayer_bottom_pressures_hpa[global_support_index] = previous_boundary_pressure_hpa;
                grid.sublayer_mid_altitudes_km[global_support_index] = support_altitude_km;
                grid.sublayer_support_weights_km[global_support_index] =
                    0.5 * support_weights[support_index] * layer_span_km;
                grid.sublayer_interval_indices_1based[global_support_index] = parity_interval_index_1based;
            }

            const upper_boundary_index = support_cursor + sublayer_order + 1;
            grid.sublayer_top_altitudes_km[upper_boundary_index] = next_boundary.altitude_km;
            grid.sublayer_bottom_altitudes_km[upper_boundary_index] = next_boundary.altitude_km;
            grid.sublayer_top_pressures_hpa[upper_boundary_index] = next_boundary.pressure_hpa;
            grid.sublayer_bottom_pressures_hpa[upper_boundary_index] = next_boundary.pressure_hpa;
            grid.sublayer_mid_altitudes_km[upper_boundary_index] = next_boundary.altitude_km;
            grid.sublayer_support_weights_km[upper_boundary_index] = 0.0;
            grid.sublayer_interval_indices_1based[upper_boundary_index] = parity_interval_index_1based;

            support_cursor = upper_boundary_index;
            previous_boundary_altitude_km = next_boundary.altitude_km;
            previous_boundary_pressure_hpa = next_boundary.pressure_hpa;
        }

        layer_cursor += interval_layer_count;
    }

    std.debug.assert(layer_cursor == grid.layer_top_altitudes_km.len);
    std.debug.assert(support_cursor + 1 == grid.sublayer_mid_altitudes_km.len);
    return grid.*;
}

fn buildLegacy(
    allocator: Allocator,
    scene: *const Scene,
    profile: *const ReferenceData.ClimatologyProfile,
) !OwnedVerticalGrid {
    // buildLegacy -------------------------------------------------------------------------------------------|
    // Build the evenly divided vertical grid used by legacy atmosphere controls.                             |
    //                                                                                                        |
    // hot path                                                                                               |
    // fills layer and sublayer altitude, pressure, and support-weight arrays before accumulation.            |
    //                                                                                                        |
    // math                                                                                                   |
    // z_layer(i) = z_bottom + i * (z_top - z_bottom) / layer_count.                                          |
    // z_sublayer(f) = z_layer_bottom + f * layer_span.                                                       |
    // -------------------------------------------------------------------------------------------------------|

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
        const layer_top_altitude =
            bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index + 1));
        const layer_bottom_altitude =
            bottom_altitude_km + layer_span_km * @as(f64, @floatFromInt(index));

        grid.layer_top_altitudes_km[index] = layer_top_altitude;
        grid.layer_bottom_altitudes_km[index] = layer_bottom_altitude;
        grid.layer_top_pressures_hpa[index] = profile.interpolatePressure(layer_top_altitude);
        grid.layer_bottom_pressures_hpa[index] = profile.interpolatePressure(layer_bottom_altitude);
        grid.layer_interval_indices_1based[index] = @intCast(index + 1);
        grid.layer_sublayer_starts[index] = @intCast(sublayer_cursor);
        grid.layer_sublayer_counts[index] = @intCast(sublayer_divisions);

        for (0..sublayer_divisions) |sublayer_index| {
            const division_count_f = @as(f64, @floatFromInt(sublayer_divisions));
            const top_fraction = @as(f64, @floatFromInt(sublayer_index + 1)) / division_count_f;
            const bottom_fraction = @as(f64, @floatFromInt(sublayer_index)) / division_count_f;
            const sublayer_top_altitude = layer_bottom_altitude + layer_span_km * top_fraction;
            const sublayer_bottom_altitude = layer_bottom_altitude + layer_span_km * bottom_fraction;
            const global_index = sublayer_cursor + sublayer_index;

            grid.sublayer_top_altitudes_km[global_index] = sublayer_top_altitude;
            grid.sublayer_bottom_altitudes_km[global_index] = sublayer_bottom_altitude;
            grid.sublayer_top_pressures_hpa[global_index] =
                profile.interpolatePressure(sublayer_top_altitude);
            grid.sublayer_bottom_pressures_hpa[global_index] =
                profile.interpolatePressure(sublayer_bottom_altitude);
            grid.sublayer_mid_altitudes_km[global_index] =
                0.5 * (sublayer_top_altitude + sublayer_bottom_altitude);
            grid.sublayer_support_weights_km[global_index] =
                @max(sublayer_top_altitude - sublayer_bottom_altitude, 0.0);
            grid.sublayer_interval_indices_1based[global_index] = @intCast(index + 1);
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
    const sublayer_support_weights_km = try allocator.alloc(f64, total_sublayer_count);
    errdefer allocator.free(sublayer_support_weights_km);
    const sublayer_interval_indices_1based = try allocator.alloc(u32, total_sublayer_count);
    errdefer allocator.free(sublayer_interval_indices_1based);

    return .{
        .layer_top_altitudes_km = layer_top_altitudes_km,
        .layer_bottom_altitudes_km = layer_bottom_altitudes_km,
        .layer_top_pressures_hpa = layer_top_pressures_hpa,
        .layer_bottom_pressures_hpa = layer_bottom_pressures_hpa,
        .layer_interval_indices_1based = layer_interval_indices_1based,
        .layer_sublayer_starts = layer_sublayer_starts,
        .layer_sublayer_counts = layer_sublayer_counts,
        .sublayer_top_altitudes_km = sublayer_top_altitudes_km,
        .sublayer_bottom_altitudes_km = sublayer_bottom_altitudes_km,
        .sublayer_top_pressures_hpa = sublayer_top_pressures_hpa,
        .sublayer_bottom_pressures_hpa = sublayer_bottom_pressures_hpa,
        .sublayer_mid_altitudes_km = sublayer_mid_altitudes_km,
        .sublayer_support_weights_km = sublayer_support_weights_km,
        .sublayer_interval_indices_1based = sublayer_interval_indices_1based,
    };
}

fn usesDisamarParitySupportGrid(scene: *const Scene) bool {
    const radiance_mode = scene.observation_model.resolvedChannelControls(.radiance).response.integration_mode;
    const irradiance_mode = scene.observation_model.resolvedChannelControls(.irradiance).response.integration_mode;

    return radiance_mode == .disamar_hr_grid or irradiance_mode == .disamar_hr_grid;
}
