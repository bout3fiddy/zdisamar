const std = @import("std");

const readers = @import("../assets/readers.zig");
const hashing = @import("../common/hashing.zig");
const o2_case = @import("../input/o2_case.zig");
const gauss_legendre = @import("../common/math/gauss_legendre.zig");
const spline = @import("../common/math/spline.zig");

const Allocator = std.mem.Allocator;
const boltzmann_hpa_cm3_per_k = 1.380658e-19;

const oxygen_volume_mixing_ratio = 0.20946;
const centimeters_per_kilometer = 1.0e5;
const max_spline_profile_rows: usize = 256;

// AtmosphereProfileTable -------------------------------------------------------------------------------------|
// Owner for densified setup-profile rows.                                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []AtmosphereProfileRow                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows owns setup-profile rows and is released by deinit.                                                   |
pub const AtmosphereProfileTable = struct {
    rows: []readers.AtmosphereProfileRow,

    pub fn deinit(self: *AtmosphereProfileTable, allocator: Allocator) void {
        // AtmosphereProfileTable.deinit ----------------------------------------------------------------------|
        // Release parsed profile rows owned by the layer setup table.                                         |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.rows);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// LayerQuadrature --------------------------------------------------------------------------------------------|
// Canonical altitude quadrature rows retained by structural order.                                            |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 88 B (0.086 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] support_order        : usize                                                                       |
// [ 8..23] support_nodes        : []f64                                                                       |
// [24..39] support_weights      : []f64                                                                       |
// [40..55] interval_orders      : []u32                                                                       |
// [56..71] interval_node_starts : []u32                                                                       |
// [72..87] interval_nodes       : []f64                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   support_nodes/support_weights own the ordinary Gauss-Legendre rule on [-1, 1]. interval_orders owns the   |
//   distinct DISAMAR node-only orders used by atmosphere intervals. interval_node_starts has one sentinel     |
//   row so interval_nodes[start..end] returns canonical DISAMAR roots on [-1, 1].                             |
//                                                                                                             |
// hot path                                                                                                    |
//   of evaluateRetrievalState.                                                                                |
pub const LayerQuadrature = struct {
    support_order: usize,
    support_nodes: []f64,
    support_weights: []f64,
    interval_orders: []u32,
    interval_node_starts: []u32,
    interval_nodes: []f64,

    pub fn deinit(self: *LayerQuadrature, allocator: Allocator) void {
        // LayerQuadrature.deinit -----------------------------------------------------------------------------|
        // Release retained canonical support and interval quadrature rows.                                    |
        // ----------------------------------------------------------------------------------------------------|
        allocator.free(self.support_nodes);
        allocator.free(self.support_weights);
        allocator.free(self.interval_orders);
        allocator.free(self.interval_node_starts);
        allocator.free(self.interval_nodes);
        self.* = undefined;
    }

    pub fn intervalNodes(self: LayerQuadrature, order: usize) error{InvalidControl}![]const f64 {
        // LayerQuadrature.intervalNodes ----------------------------------------------------------------------|
        // Return the canonical DISAMAR node row for one altitude-division order.                              |
        // ----------------------------------------------------------------------------------------------------|
        if (order == 0) return self.interval_nodes[0..0];

        for (self.interval_orders, 0..) |candidate_order, index| {
            if (@as(usize, candidate_order) != order) continue;

            const start: usize = @intCast(self.interval_node_starts[index]);
            const end: usize = @intCast(self.interval_node_starts[index + 1]);
            return self.interval_nodes[start..end];
        }

        return error.InvalidControl;
    }
};
// ------------------------------------------------------------------------------------------------------------|

// LayerGrid --------------------------------------------------------------------------------------------------|
// Computed atmosphere layer and support-row setup arrays.                                                     |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 400 B (0.391 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0.. 15] source_profile                 : AtmosphereProfileTable                                          |
// [ 16.. 31] spectroscopy_profile           : AtmosphereProfileTable                                          |
// [ 32.. 39] interval_count                 : usize                                                           |
// [ 40.. 47] configured_layer_count         : usize                                                           |
// [ 48.. 55] sublayer_divisions             : usize                                                           |
// [ 56.. 63] surface_pressure_hpa           : f64                                                             |
// [ 64..223] layer f64 arrays               : 10 slice headers                                                |
// [224..271] layer u32 arrays               : 3 slice headers                                                 |
// [272..383] support f64 arrays             : 7 slice headers                                                 |
// [384..399] support u32 arrays             : 1 slice header                                                  |
//                                                                                                             |
// referenced storage                                                                                          |
//   Every array is owned. source_profile holds the canonical densified climatology used for vertical setup.   |
//   spectroscopy_profile holds the canonical raw vendor pressure nodes with densified altitudes for line/CIA  |
//   profile caches. Layer rows hold boundaries and lower-boundary representative thermodynamics. Support rows |
//   hold the boundary/active samples.                                                                         |
pub const LayerGrid = struct {
    source_profile: AtmosphereProfileTable,
    spectroscopy_profile: AtmosphereProfileTable,
    interval_count: usize,
    configured_layer_count: usize,
    sublayer_divisions: usize,
    surface_pressure_hpa: f64,
    layer_top_altitudes_km: []f64,
    layer_bottom_altitudes_km: []f64,
    layer_top_pressures_hpa: []f64,
    layer_bottom_pressures_hpa: []f64,
    layer_mid_altitudes_km: []f64,
    layer_pressures_hpa: []f64,
    layer_temperatures_k: []f64,
    layer_air_number_densities_cm3: []f64,
    layer_o2_number_densities_cm3: []f64,
    layer_path_lengths_cm: []f64,
    layer_interval_indices_1based: []u32,
    layer_support_starts: []u32,
    layer_support_counts: []u32,
    support_mid_altitudes_km: []f64,
    support_pressures_hpa: []f64,
    support_temperatures_k: []f64,
    support_air_number_densities_cm3: []f64,
    support_o2_number_densities_cm3: []f64,
    support_path_lengths_km: []f64,
    support_path_lengths_cm: []f64,
    support_interval_indices_1based: []u32,

    pub fn deinit(self: *LayerGrid, allocator: Allocator) void {
        // LayerGrid.deinit -----------------------------------------------------------------------------------|
        // Release computed layer/support arrays and the parsed source profile rows.                           |
        // ----------------------------------------------------------------------------------------------------|
        self.source_profile.deinit(allocator);
        self.spectroscopy_profile.deinit(allocator);
        allocator.free(self.layer_top_altitudes_km);
        allocator.free(self.layer_bottom_altitudes_km);
        allocator.free(self.layer_top_pressures_hpa);
        allocator.free(self.layer_bottom_pressures_hpa);
        allocator.free(self.layer_mid_altitudes_km);
        allocator.free(self.layer_pressures_hpa);
        allocator.free(self.layer_temperatures_k);
        allocator.free(self.layer_air_number_densities_cm3);
        allocator.free(self.layer_o2_number_densities_cm3);
        allocator.free(self.layer_path_lengths_cm);
        allocator.free(self.layer_interval_indices_1based);
        allocator.free(self.layer_support_starts);
        allocator.free(self.layer_support_counts);
        allocator.free(self.support_mid_altitudes_km);
        allocator.free(self.support_pressures_hpa);
        allocator.free(self.support_temperatures_k);
        allocator.free(self.support_air_number_densities_cm3);
        allocator.free(self.support_o2_number_densities_cm3);
        allocator.free(self.support_path_lengths_km);
        allocator.free(self.support_path_lengths_cm);
        allocator.free(self.support_interval_indices_1based);
        self.* = undefined;
    }
};
// ------------------------------------------------------------------------------------------------------------|

pub fn hashAll(hasher: *std.hash.Wyhash, layers: LayerGrid) void {
    // hashAll ----------------------------------------------------------------------------------------------- |
    // Hash the layer/support arrays read while filling optics and source/curved-sun rows.                     |
    // --------------------------------------------------------------------------------------------------------|
    for ([_]usize{
        layers.interval_count,
        layers.configured_layer_count,
        layers.sublayer_divisions,
    }) |value| hashing.updateValue(hasher, value);
    hashing.updateValue(hasher, layers.surface_pressure_hpa);
    for ([_][]const f64{
        layers.layer_top_altitudes_km,
        layers.layer_bottom_altitudes_km,
        layers.layer_top_pressures_hpa,
        layers.layer_bottom_pressures_hpa,
        layers.layer_mid_altitudes_km,
        layers.layer_pressures_hpa,
        layers.layer_temperatures_k,
        layers.layer_air_number_densities_cm3,
        layers.layer_o2_number_densities_cm3,
        layers.layer_path_lengths_cm,
        layers.support_mid_altitudes_km,
        layers.support_pressures_hpa,
        layers.support_temperatures_k,
        layers.support_air_number_densities_cm3,
        layers.support_o2_number_densities_cm3,
        layers.support_path_lengths_km,
        layers.support_path_lengths_cm,
    }) |values| hasher.update(std.mem.sliceAsBytes(values));
    for ([_][]const u32{
        layers.layer_interval_indices_1based,
        layers.layer_support_starts,
        layers.layer_support_counts,
        layers.support_interval_indices_1based,
    }) |values| hasher.update(std.mem.sliceAsBytes(values));
}
// ------------------------------------------------------------------------------------------------------------|

pub fn buildLayerQuadrature(allocator: Allocator, case: o2_case.O2Case) !LayerQuadrature {
    // buildLayerQuadrature -----------------------------------------------------------------------------------|
    // Precompute canonical support and interval quadrature roots for one structural atmosphere shape.         |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Orders come only from case.atmosphere.sublayer_divisions and interval.altitude_divisions. Retrieval   |
    //   state updates change pressure bounds, so the canonical roots and weights remain valid across every    |
    //   OE iteration for the prepared case.                                                                   |
    // --------------------------------------------------------------------------------------------------------|
    const support_order = @max(case.atmosphere.sublayer_divisions, @as(usize, 1));
    if (support_order > gauss_legendre.max_fixed_rule_order) return error.InvalidControl;

    var quadrature = LayerQuadrature{
        .support_order = support_order,
        .support_nodes = try allocator.alloc(f64, support_order),
        .support_weights = &.{},
        .interval_orders = &.{},
        .interval_node_starts = &.{},
        .interval_nodes = &.{},
    };
    errdefer allocator.free(quadrature.support_nodes);

    quadrature.support_weights = try allocator.alloc(f64, support_order);
    errdefer allocator.free(quadrature.support_weights);
    try gauss_legendre.fillCanonicalNodesAndWeights(
        @intCast(support_order),
        quadrature.support_nodes,
        quadrature.support_weights,
    );

    for (case.atmosphere.intervals) |interval| {
        if (interval.altitude_divisions > gauss_legendre.max_disamar_division_points) return error.InvalidControl;
    }
    const distinct_interval_order_count = countDistinctIntervalOrders(case.atmosphere.intervals);
    const total_interval_node_count = countDistinctIntervalNodes(case.atmosphere.intervals);
    quadrature.interval_orders = try allocator.alloc(u32, distinct_interval_order_count);
    errdefer allocator.free(quadrature.interval_orders);
    quadrature.interval_node_starts = try allocator.alloc(u32, distinct_interval_order_count + 1);
    errdefer allocator.free(quadrature.interval_node_starts);
    quadrature.interval_nodes = try allocator.alloc(f64, total_interval_node_count);
    errdefer allocator.free(quadrature.interval_nodes);

    var order_cursor: usize = 0;
    var node_cursor: usize = 0;
    for (case.atmosphere.intervals) |interval| {
        const order = interval.altitude_divisions;
        if (order == 0 or intervalOrderAlreadyStored(quadrature.interval_orders[0..order_cursor], order)) continue;

        const next_node_cursor = node_cursor + order;
        if (next_node_cursor > std.math.maxInt(u32)) return error.InvalidControl;
        quadrature.interval_orders[order_cursor] = @intCast(order);
        quadrature.interval_node_starts[order_cursor] = @intCast(node_cursor);
        try gauss_legendre.fillCanonicalDisamarDivPointNodes(
            @intCast(order),
            quadrature.interval_nodes[node_cursor..next_node_cursor],
        );
        order_cursor += 1;
        node_cursor = next_node_cursor;
    }
    quadrature.interval_node_starts[order_cursor] = @intCast(node_cursor);

    std.debug.assert(order_cursor == quadrature.interval_orders.len);
    std.debug.assert(node_cursor == quadrature.interval_nodes.len);
    return quadrature;
}

pub fn build(allocator: Allocator, case: o2_case.O2Case) !LayerGrid {
    // build --------------------------------------------------------------------------------------------------|
    // Load and densify atmosphere profile rows, then compute DISAMAR layer/support placement.                 |
    // --------------------------------------------------------------------------------------------------------|
    var quadrature = try buildLayerQuadrature(allocator, case);
    defer quadrature.deinit(allocator);
    return buildWithQuadrature(allocator, case, quadrature);
}

pub fn buildWithQuadrature(
    allocator: Allocator,
    case: o2_case.O2Case,
    quadrature: LayerQuadrature,
) !LayerGrid {
    // buildWithQuadrature ------------------------------------------------------------------------------------|
    // Build profile rows, then compute layer/support placement from retained canonical quadrature.            |
    // --------------------------------------------------------------------------------------------------------|
    const raw_profile_rows = try readers.readAtmosphereProfile(allocator, case.atmosphere.profile.path);
    defer allocator.free(raw_profile_rows);

    const dense_profile_rows = try densifyVendorPressureGrid(
        allocator,
        .{ .rows = raw_profile_rows },
        case.atmosphere.surface_pressure_hpa,
    );
    var dense_profile_owned = true;
    errdefer if (dense_profile_owned) allocator.free(dense_profile_rows);

    const profile = ProfileView{ .rows = dense_profile_rows };
    const spectroscopy_profile_rows = try buildSpectroscopyProfileRows(
        allocator,
        .{ .rows = raw_profile_rows },
        profile,
    );

    dense_profile_owned = false;
    return buildWithOwnedProfiles(allocator, case, dense_profile_rows, spectroscopy_profile_rows, quadrature);
}

pub fn buildFromPreparedProfiles(
    allocator: Allocator,
    case: o2_case.O2Case,
    source_profile_rows: []const readers.AtmosphereProfileRow,
    spectroscopy_profile_rows: []const readers.AtmosphereProfileRow,
    quadrature: LayerQuadrature,
) !LayerGrid {
    // buildFromPreparedProfiles ------------------------------------------------------------------------------|
    // Rebuild layer/support rows from retained atmosphere profiles without file I/O or profile densification. |
    //                                                                                                         |
    // boundary                                                                                                |
    //   Retrieval pressure states move interval boundaries only. The densified climatology and spectroscopy   |
    //   retrieval.zig` RetrievalPreparedCase profile_preparation reuse.                                       |
    //                                                                                                         |
    // ownership                                                                                               |
    //   The returned LayerGrid owns duplicated profile rows so ordinary LayerGrid.deinit remains correct.     |
    // --------------------------------------------------------------------------------------------------------|
    const owned_source_profile_rows = try allocator.dupe(readers.AtmosphereProfileRow, source_profile_rows);
    var source_profile_owned = true;
    errdefer if (source_profile_owned) allocator.free(owned_source_profile_rows);
    const owned_spectroscopy_profile_rows =
        try allocator.dupe(readers.AtmosphereProfileRow, spectroscopy_profile_rows);
    var spectroscopy_profile_owned = true;
    errdefer if (spectroscopy_profile_owned) allocator.free(owned_spectroscopy_profile_rows);

    source_profile_owned = false;
    spectroscopy_profile_owned = false;
    return buildWithOwnedProfiles(
        allocator,
        case,
        owned_source_profile_rows,
        owned_spectroscopy_profile_rows,
        quadrature,
    );
}

fn buildWithOwnedProfiles(
    allocator: Allocator,
    case: o2_case.O2Case,
    dense_profile_rows: []readers.AtmosphereProfileRow,
    spectroscopy_profile_rows: []readers.AtmosphereProfileRow,
    quadrature: LayerQuadrature,
) !LayerGrid {
    // buildWithOwnedProfiles ---------------------------------------------------------------------------------|
    // Compute layer/support placement from caller-owned profile rows that transfer into the returned grid.    |
    // --------------------------------------------------------------------------------------------------------|
    var dense_profile_owned = true;
    errdefer if (dense_profile_owned) allocator.free(dense_profile_rows);
    var spectroscopy_profile_owned = true;
    errdefer if (spectroscopy_profile_owned) allocator.free(spectroscopy_profile_rows);

    const profile = ProfileView{ .rows = dense_profile_rows };
    const intervals = case.atmosphere.intervals;
    const support_order = @max(case.atmosphere.sublayer_divisions, @as(usize, 1));
    if (quadrature.support_order != support_order) return error.InvalidControl;
    var layer_count: usize = 0;
    var support_count: usize = 1;
    for (intervals) |interval| {
        const interval_layer_count = interval.altitude_divisions + 1;
        layer_count += interval_layer_count;
        support_count += interval_layer_count * (support_order + 1);
    }

    var grid = try allocate(allocator, dense_profile_rows, spectroscopy_profile_rows, layer_count, support_count);
    dense_profile_owned = false;
    spectroscopy_profile_owned = false;
    errdefer grid.deinit(allocator);
    grid.interval_count = intervals.len;
    grid.configured_layer_count = case.atmosphere.layer_count;
    grid.sublayer_divisions = case.atmosphere.sublayer_divisions;
    grid.surface_pressure_hpa = case.atmosphere.surface_pressure_hpa;

    const support_nodes = quadrature.support_nodes;
    const support_weights = quadrature.support_weights;

    var layer_cursor: usize = 0;
    var support_cursor: usize = 0;
    var rtm_nodes_stack: [gauss_legendre.max_disamar_division_points]f64 = undefined;
    var source_interval_index = intervals.len;
    while (source_interval_index > 0) {
        source_interval_index -= 1;
        const interval = intervals[source_interval_index];
        const rtm_interval_index_1based: u32 = @intCast(intervals.len - source_interval_index);
        const interval_top_altitude_km = profile.interpolateAltitudeForPressureSpline(interval.top_pressure_hpa);
        const interval_bottom_altitude_km =
            profile.interpolateAltitudeForPressureSpline(interval.bottom_pressure_hpa);
        const interval_layer_count = interval.altitude_divisions + 1;
        const interior_node_count = interval_layer_count - 1;
        if (interior_node_count > rtm_nodes_stack.len) return error.InvalidControl;
        const rtm_nodes = rtm_nodes_stack[0..interior_node_count];
        if (interior_node_count > 0) {
            const canonical_nodes = try quadrature.intervalNodes(interior_node_count);
            try gauss_legendre.scaleIntervalNodes(
                canonical_nodes,
                interval_bottom_altitude_km,
                interval_top_altitude_km,
                rtm_nodes,
            );
        }

        if (layer_cursor == 0) {
            fillSupportRow(
                &grid,
                &profile,
                support_cursor,
                interval_bottom_altitude_km,
                0.0,
                rtm_interval_index_1based,
            );
        }
        grid.support_interval_indices_1based[support_cursor] = rtm_interval_index_1based;

        var previous_boundary_altitude_km = interval_bottom_altitude_km;
        var previous_boundary_pressure_hpa = interval.bottom_pressure_hpa;
        for (0..interval_layer_count) |local_layer_index| {
            const next_boundary_altitude_km, const next_boundary_pressure_hpa =
                if (local_layer_index == interior_node_count)
                    .{ interval_top_altitude_km, interval.top_pressure_hpa }
                else next_boundary: {
                    const node_altitude_km = rtm_nodes[local_layer_index];
                    break :next_boundary .{
                        node_altitude_km,
                        profile.interpolatePressureLogSpline(node_altitude_km),
                    };
                };

            const global_layer_index = layer_cursor + local_layer_index;
            grid.layer_top_altitudes_km[global_layer_index] = next_boundary_altitude_km;
            grid.layer_bottom_altitudes_km[global_layer_index] = previous_boundary_altitude_km;
            grid.layer_top_pressures_hpa[global_layer_index] = next_boundary_pressure_hpa;
            grid.layer_bottom_pressures_hpa[global_layer_index] = previous_boundary_pressure_hpa;
            grid.layer_interval_indices_1based[global_layer_index] = rtm_interval_index_1based;
            grid.layer_support_starts[global_layer_index] = @intCast(support_cursor);
            grid.layer_support_counts[global_layer_index] = @intCast(support_order + 2);

            const layer_span_km = @max(next_boundary_altitude_km - previous_boundary_altitude_km, 0.0);
            var weighted_altitude_km: f64 = 0.0;
            var weight_sum_km: f64 = 0.0;
            for (0..support_order) |support_index| {
                const global_support_index = support_cursor + 1 + support_index;
                const support_altitude_km = previous_boundary_altitude_km +
                    0.5 * (support_nodes[support_index] + 1.0) * layer_span_km;
                const support_weight_km = 0.5 * support_weights[support_index] * layer_span_km;
                fillSupportRow(
                    &grid,
                    &profile,
                    global_support_index,
                    support_altitude_km,
                    support_weight_km,
                    rtm_interval_index_1based,
                );
                weighted_altitude_km += support_altitude_km * support_weight_km;
                weight_sum_km += support_weight_km;
            }

            const upper_boundary_index = support_cursor + support_order + 1;
            fillSupportRow(
                &grid,
                &profile,
                upper_boundary_index,
                next_boundary_altitude_km,
                0.0,
                rtm_interval_index_1based,
            );

            const divisor = @max(weight_sum_km, 1.0e-12);
            grid.layer_mid_altitudes_km[global_layer_index] = weighted_altitude_km / divisor;

            // Representative thermodynamics use the lower-boundary support row.
            grid.layer_pressures_hpa[global_layer_index] = grid.support_pressures_hpa[support_cursor];
            grid.layer_temperatures_k[global_layer_index] = grid.support_temperatures_k[support_cursor];
            grid.layer_air_number_densities_cm3[global_layer_index] =
                grid.support_air_number_densities_cm3[support_cursor];
            grid.layer_o2_number_densities_cm3[global_layer_index] =
                grid.layer_air_number_densities_cm3[global_layer_index] * oxygen_volume_mixing_ratio;
            grid.layer_path_lengths_cm[global_layer_index] = weight_sum_km * centimeters_per_kilometer;

            support_cursor = upper_boundary_index;
            previous_boundary_altitude_km = next_boundary_altitude_km;
            previous_boundary_pressure_hpa = next_boundary_pressure_hpa;
        }

        layer_cursor += interval_layer_count;
    }

    std.debug.assert(layer_cursor == grid.layer_top_altitudes_km.len);
    std.debug.assert(support_cursor + 1 == grid.support_mid_altitudes_km.len);
    return grid;
}

fn countDistinctIntervalOrders(intervals: []const o2_case.VerticalInterval) usize {
    // countDistinctIntervalOrders ----------------------------------------------------------------------------|
    // Count nonzero altitude-division orders that need one retained DISAMAR canonical node row.               |
    // --------------------------------------------------------------------------------------------------------|
    var count: usize = 0;

    for (intervals, 0..) |interval, index| {
        const order = interval.altitude_divisions;

        if (order == 0) continue;
        if (intervalOrderAlreadyPresent(intervals[0..index], order)) continue;

        count += 1;
    }

    return count;
}

fn countDistinctIntervalNodes(intervals: []const o2_case.VerticalInterval) usize {
    // countDistinctIntervalNodes -----------------------------------------------------------------------------|
    // Count the packed canonical node slots needed by the distinct interval orders.                           |
    // --------------------------------------------------------------------------------------------------------|
    var count: usize = 0;

    for (intervals, 0..) |interval, index| {
        const order = interval.altitude_divisions;

        if (order == 0) continue;
        if (intervalOrderAlreadyPresent(intervals[0..index], order)) continue;

        count += order;
    }

    return count;
}

fn intervalOrderAlreadyPresent(intervals: []const o2_case.VerticalInterval, order: usize) bool {
    // intervalOrderAlreadyPresent ----------------------------------------------------------------------------|
    // Scan currently seen interval rows for a matching altitude-division order.                               |
    // --------------------------------------------------------------------------------------------------------|
    for (intervals) |interval| {
        if (interval.altitude_divisions == order) return true;
    }
    return false;
}

fn intervalOrderAlreadyStored(orders: []const u32, order: usize) bool {
    // intervalOrderAlreadyStored -----------------------------------------------------------------------------|
    // Scan the packed retained order table while building LayerQuadrature.                                    |
    // --------------------------------------------------------------------------------------------------------|
    for (orders) |candidate_order| {
        if (@as(usize, candidate_order) == order) return true;
    }
    return false;
}

fn densifyVendorPressureGrid(
    allocator: Allocator,
    profile: ProfileView,
    surface_pressure_hpa: f64,
) ![]readers.AtmosphereProfileRow {
    // densifyVendorPressureGrid ------------------------------------------------------------------------------|
    // Build the O2 A setup profile used before layer/support placement.                                       |
    //                                                                                                         |
    //   ClimatologyProfile.densifyVendorPressureGrid before state_build vertical setup.                       |
    //                                                                                                         |
    // math                                                                                                    |
    //   Added pressures are spaced in log-pressure. Altitudes are solved from hydrostatic increments with     |
    //   two-point DISAMAR Gauss support and shifted so the requested surface pressure sits at altitude zero.  |
    // --------------------------------------------------------------------------------------------------------|
    if (profile.rows.len < 2) return allocator.dupe(readers.AtmosphereProfileRow, profile.rows);

    const scale_height_guess_km = 8.0;
    var dense_row_count: usize = 1;
    for (profile.rows[0 .. profile.rows.len - 1], profile.rows[1..]) |lower, upper| {
        const safe_lower_pressure = @max(lower.pressure_hpa, 1.0e-9);
        const safe_upper_pressure = @max(upper.pressure_hpa, 1.0e-9);
        const delta_z_guess = scale_height_guess_km * @log(safe_lower_pressure / safe_upper_pressure);
        const additional_levels: usize = @intFromFloat(@floor(@max(delta_z_guess, 0.0)));
        dense_row_count += additional_levels + 1;
    }

    const dense_pressures_hpa = try allocator.alloc(f64, dense_row_count);
    defer allocator.free(dense_pressures_hpa);
    const dense_temperatures_k = try allocator.alloc(f64, dense_row_count);
    defer allocator.free(dense_temperatures_k);
    const dense_altitudes_km = try allocator.alloc(f64, dense_row_count);
    defer allocator.free(dense_altitudes_km);
    const dense_altitudes_gp_km = try allocator.alloc(f64, (dense_row_count - 1) * 2);
    defer allocator.free(dense_altitudes_gp_km);

    var dense_index: usize = 0;
    dense_pressures_hpa[dense_index] = profile.rows[0].pressure_hpa;
    for (profile.rows[0 .. profile.rows.len - 1], profile.rows[1..]) |lower, upper| {
        const safe_lower_pressure = @max(lower.pressure_hpa, 1.0e-9);
        const safe_upper_pressure = @max(upper.pressure_hpa, 1.0e-9);
        const delta_z_guess = scale_height_guess_km * @log(safe_lower_pressure / safe_upper_pressure);
        const additional_levels: usize = @intFromFloat(@floor(@max(delta_z_guess, 0.0)));
        if (additional_levels > 0) {
            const delta_nodes_lnp = @log(safe_lower_pressure / safe_upper_pressure);
            const delta_lnp = delta_nodes_lnp / @as(f64, @floatFromInt(additional_levels + 1));
            for (0..additional_levels) |_| {
                dense_index += 1;
                dense_pressures_hpa[dense_index] = dense_pressures_hpa[dense_index - 1] * @exp(-delta_lnp);
            }
        }
        dense_index += 1;
        dense_pressures_hpa[dense_index] = upper.pressure_hpa;
    }
    std.debug.assert(dense_index + 1 == dense_row_count);

    for (dense_pressures_hpa, 0..) |pressure_hpa, index| {
        dense_temperatures_k[index] = profile.interpolateTemperatureForPressureSpline(pressure_hpa);
    }

    var gauss_nodes_01: [2]f64 = undefined;
    var gauss_weights_01: [2]f64 = undefined;
    try gauss_legendre.fillDisamarDivPoints01(2, gauss_nodes_01[0..], gauss_weights_01[0..]);

    const universal_gas_constant = 8.3144621;
    const mean_molecular_weight_air = 28.964e-3;
    const safe_surface_pressure_hpa = @max(surface_pressure_hpa, 1.0e-9);
    const dense_log_pressures = try allocator.alloc(f64, dense_row_count);
    defer allocator.free(dense_log_pressures);

    for (dense_pressures_hpa, 0..) |pressure_hpa, index| {
        dense_log_pressures[index] = @log(@max(pressure_hpa, 1.0e-9));
        dense_altitudes_km[index] = scale_height_guess_km *
            (@log(safe_surface_pressure_hpa) - dense_log_pressures[index]);
    }

    for (0..dense_row_count - 1) |interval_index| {
        const dlnp = dense_log_pressures[interval_index] - dense_log_pressures[interval_index + 1];
        for (0..2) |gauss_index| {
            const gp_index = interval_index * 2 + gauss_index;
            dense_altitudes_gp_km[gp_index] = scale_height_guess_km *
                (@log(safe_surface_pressure_hpa) -
                    (dense_log_pressures[interval_index + 1] + dlnp * gauss_nodes_01[gauss_index]));
        }
    }

    const previous_altitudes_km = try allocator.dupe(f64, dense_altitudes_km);
    defer allocator.free(previous_altitudes_km);

    var iteration: usize = 0;
    while (iteration < 6) : (iteration += 1) {
        dense_altitudes_km[0] = 0.0;
        for (1..dense_row_count) |pressure_index| {
            const gp_start = (pressure_index - 1) * 2;
            const dlnp = dense_log_pressures[pressure_index - 1] - dense_log_pressures[pressure_index];
            var interval_altitude_increment_km: f64 = 0.0;

            for (0..2) |gauss_index| {
                const gp_index = gp_start + gauss_index;
                const pressure_gp_hpa = @exp(
                    dense_log_pressures[pressure_index] + dlnp * gauss_nodes_01[gauss_index],
                );
                const temperature_gp_k = profile.interpolateTemperatureForPressureSpline(pressure_gp_hpa);
                const gravity = gravitationalAccelerationMetersPerSecondSquared(
                    45.0,
                    dense_altitudes_gp_km[gp_index],
                );
                const scale_height_km = 1.0e-3 * universal_gas_constant * temperature_gp_k /
                    mean_molecular_weight_air / gravity;

                interval_altitude_increment_km += gauss_weights_01[gauss_index] * dlnp * scale_height_km;
            }

            dense_altitudes_km[pressure_index] =
                dense_altitudes_km[pressure_index - 1] + interval_altitude_increment_km;
        }

        var chi2: f64 = 0.0;
        for (dense_altitudes_km, previous_altitudes_km) |altitude_km, previous_altitude_km| {
            const delta = altitude_km - previous_altitude_km;
            chi2 += delta * delta;
        }
        if (chi2 < 1.0e-6) break;
        @memcpy(previous_altitudes_km, dense_altitudes_km);
    }

    const surface_altitude_shift_km = linearSampleDescending(
        dense_pressures_hpa,
        dense_altitudes_km,
        safe_surface_pressure_hpa,
    );

    const dense_rows = try allocator.alloc(readers.AtmosphereProfileRow, dense_row_count);
    errdefer allocator.free(dense_rows);
    for (0..dense_row_count) |index| {
        const pressure_hpa = dense_pressures_hpa[index];
        const temperature_k = dense_temperatures_k[index];
        dense_rows[index] = .{
            .altitude_km = dense_altitudes_km[index] - surface_altitude_shift_km,
            .pressure_hpa = pressure_hpa,
            .temperature_k = temperature_k,
            .air_number_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k,
        };
    }

    return dense_rows;
}

fn buildSpectroscopyProfileRows(
    allocator: Allocator,
    source_profile: ProfileView,
    dense_profile: ProfileView,
) ![]readers.AtmosphereProfileRow {
    // buildSpectroscopyProfileRows -------------------------------------------------------------------------- |
    // Build spectroscopy-profile rows for line/CIA profile caches.                                            |
    // The row count stays on the vendor pressure nodes; altitude is mapped through the densified profile.     |
    // --------------------------------------------------------------------------------------------------------|
    const rows = try allocator.alloc(readers.AtmosphereProfileRow, source_profile.rows.len);
    errdefer allocator.free(rows);

    for (source_profile.rows, rows) |source_row, *target_row| {
        const pressure_hpa = source_row.pressure_hpa;
        const temperature_k = source_row.temperature_k;
        target_row.* = .{
            .altitude_km = dense_profile.interpolateAltitudeForPressureSpline(pressure_hpa),
            .pressure_hpa = pressure_hpa,
            .temperature_k = temperature_k,
            .air_number_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k,
        };
    }

    return rows;
}

fn allocate(
    allocator: Allocator,
    profile_rows: []readers.AtmosphereProfileRow,
    spectroscopy_profile_rows: []readers.AtmosphereProfileRow,
    layer_count: usize,
    support_count: usize,
) !LayerGrid {
    // allocate -----------------------------------------------------------------------------------------------|
    // Allocate all layer and support arrays owned by LayerGrid before the builder fills them.                 |
    // --------------------------------------------------------------------------------------------------------|
    const layer_top_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_altitudes_km);
    const layer_bottom_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_altitudes_km);
    const layer_top_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_top_pressures_hpa);
    const layer_bottom_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_bottom_pressures_hpa);
    const layer_mid_altitudes_km = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_mid_altitudes_km);
    const layer_pressures_hpa = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_pressures_hpa);
    const layer_temperatures_k = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_temperatures_k);
    const layer_air_number_densities_cm3 = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_air_number_densities_cm3);
    const layer_o2_number_densities_cm3 = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_o2_number_densities_cm3);
    const layer_path_lengths_cm = try allocator.alloc(f64, layer_count);
    errdefer allocator.free(layer_path_lengths_cm);
    const layer_interval_indices_1based = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_interval_indices_1based);
    const layer_support_starts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_support_starts);
    const layer_support_counts = try allocator.alloc(u32, layer_count);
    errdefer allocator.free(layer_support_counts);
    const support_mid_altitudes_km = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_mid_altitudes_km);
    const support_pressures_hpa = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_pressures_hpa);
    const support_temperatures_k = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_temperatures_k);
    const support_air_number_densities_cm3 = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_air_number_densities_cm3);
    const support_o2_number_densities_cm3 = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_o2_number_densities_cm3);
    const support_path_lengths_km = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_path_lengths_km);
    const support_path_lengths_cm = try allocator.alloc(f64, support_count);
    errdefer allocator.free(support_path_lengths_cm);
    const support_interval_indices_1based = try allocator.alloc(u32, support_count);
    errdefer allocator.free(support_interval_indices_1based);

    return .{
        .source_profile = .{ .rows = profile_rows },
        .spectroscopy_profile = .{ .rows = spectroscopy_profile_rows },
        .interval_count = 0,
        .configured_layer_count = 0,
        .sublayer_divisions = 0,
        .surface_pressure_hpa = 0.0,
        .layer_top_altitudes_km = layer_top_altitudes_km,
        .layer_bottom_altitudes_km = layer_bottom_altitudes_km,
        .layer_top_pressures_hpa = layer_top_pressures_hpa,
        .layer_bottom_pressures_hpa = layer_bottom_pressures_hpa,
        .layer_mid_altitudes_km = layer_mid_altitudes_km,
        .layer_pressures_hpa = layer_pressures_hpa,
        .layer_temperatures_k = layer_temperatures_k,
        .layer_air_number_densities_cm3 = layer_air_number_densities_cm3,
        .layer_o2_number_densities_cm3 = layer_o2_number_densities_cm3,
        .layer_path_lengths_cm = layer_path_lengths_cm,
        .layer_interval_indices_1based = layer_interval_indices_1based,
        .layer_support_starts = layer_support_starts,
        .layer_support_counts = layer_support_counts,
        .support_mid_altitudes_km = support_mid_altitudes_km,
        .support_pressures_hpa = support_pressures_hpa,
        .support_temperatures_k = support_temperatures_k,
        .support_air_number_densities_cm3 = support_air_number_densities_cm3,
        .support_o2_number_densities_cm3 = support_o2_number_densities_cm3,
        .support_path_lengths_km = support_path_lengths_km,
        .support_path_lengths_cm = support_path_lengths_cm,
        .support_interval_indices_1based = support_interval_indices_1based,
    };
}

fn fillSupportRow(
    grid: *LayerGrid,
    profile: *const ProfileView,
    index: usize,
    altitude_km: f64,
    path_length_km: f64,
    interval_index_1based: u32,
) void {
    // fillSupportRow -----------------------------------------------------------------------------------------|
    // Fill one boundary or active support row from the DISAMAR profile thermodynamics route.                  |
    //                                                                                                         |
    //   reference O2 A route, so support pressure and temperature come from profile spline sampling at the    |
    //   support altitude. The geometric-mean pressure fallback is for non-canonical interval grids.           |
    // --------------------------------------------------------------------------------------------------------|
    const pressure_hpa = profile.interpolatePressureLogSpline(altitude_km);
    const temperature_k = profile.interpolateTemperatureSpline(altitude_km);
    const air_density_cm3 = pressure_hpa / @max(temperature_k, 1.0e-9) / boltzmann_hpa_cm3_per_k;
    grid.support_mid_altitudes_km[index] = altitude_km;
    grid.support_pressures_hpa[index] = pressure_hpa;
    grid.support_temperatures_k[index] = temperature_k;
    grid.support_air_number_densities_cm3[index] = air_density_cm3;
    grid.support_o2_number_densities_cm3[index] = air_density_cm3 * oxygen_volume_mixing_ratio;
    grid.support_path_lengths_km[index] = @max(path_length_km, 0.0);
    grid.support_path_lengths_cm[index] = grid.support_path_lengths_km[index] * centimeters_per_kilometer;
    grid.support_interval_indices_1based[index] = interval_index_1based;
}

// ProfileView ------------------------------------------------------------------------------------------------|
// Borrowed profile interpolation view used while building LayerGrid arrays.                                   |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 16 B (0.016 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [0..15] rows : []AtmosphereProfileRow                                                                       |
//                                                                                                             |
// referenced storage                                                                                          |
//   rows borrows LayerGrid.source_profile rows during setup.                                                  |
const ProfileView = struct {
    rows: []const readers.AtmosphereProfileRow,

    fn interpolateTemperatureSpline(self: ProfileView, altitude_km: f64) f64 {
        // interpolateTemperatureSpline -----------------------------------------------------------------------|
        // Sample profile temperature by altitude with the retained endpoint-secant spline route.              |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateAltitudeField(altitude_km, .temperature_k);
        }
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].temperature_k;
        if (altitude_km >= self.rows[self.rows.len - 1].altitude_km) {
            return self.rows[self.rows.len - 1].temperature_k;
        }

        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        var temperatures_k: [max_spline_profile_rows]f64 = undefined;
        for (self.rows, 0..) |row, index| {
            altitudes_km[index] = row.altitude_km;
            temperatures_k[index] = row.temperature_k;
        }
        return spline.sampleEndpointSecant(
            altitudes_km[0..self.rows.len],
            temperatures_k[0..self.rows.len],
            altitude_km,
        ) catch self.interpolateAltitudeField(altitude_km, .temperature_k);
    }

    fn interpolatePressureLogSpline(self: ProfileView, altitude_km: f64) f64 {
        // interpolatePressureLogSpline -----------------------------------------------------------------------|
        // Sample profile pressure by altitude in log-pressure space with spline interpolation.                |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolatePressureLogLinear(altitude_km);
        }
        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].pressure_hpa;
        if (altitude_km >= self.rows[self.rows.len - 1].altitude_km) {
            return self.rows[self.rows.len - 1].pressure_hpa;
        }

        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        for (self.rows, 0..) |row, index| {
            altitudes_km[index] = row.altitude_km;
            log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
        }
        const log_pressure = spline.sampleEndpointSecant(
            altitudes_km[0..self.rows.len],
            log_pressures[0..self.rows.len],
            altitude_km,
        ) catch return self.interpolatePressureLogLinear(altitude_km);
        return @exp(log_pressure);
    }

    fn interpolateAltitudeForPressureSpline(self: ProfileView, pressure_hpa: f64) f64 {
        // interpolateAltitudeForPressureSpline ---------------------------------------------------------------|
        // Invert the pressure profile in log-pressure space with spline interpolation.                        |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateAltitudeForPressure(pressure_hpa);
        }

        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;
        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].altitude_km;
        }

        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].altitude_km;
        }

        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        var altitudes_km: [max_spline_profile_rows]f64 = undefined;
        if (descending) {
            for (self.rows, 0..) |_, index| {
                const reversed_index = self.rows.len - 1 - index;
                log_pressures[index] = @log(@max(self.rows[reversed_index].pressure_hpa, 1.0e-9));
                altitudes_km[index] = self.rows[reversed_index].altitude_km;
            }
        } else {
            for (self.rows, 0..) |row, index| {
                log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
                altitudes_km[index] = row.altitude_km;
            }
        }
        return spline.sampleEndpointSecant(
            log_pressures[0..self.rows.len],
            altitudes_km[0..self.rows.len],
            @log(safe_pressure_hpa),
        ) catch self.interpolateAltitudeForPressure(safe_pressure_hpa);
    }

    fn interpolateTemperatureForPressureSpline(self: ProfileView, pressure_hpa: f64) f64 {
        // interpolateTemperatureForPressureSpline ------------------------------------------------------------|
        // Sample temperature by pressure using the retained endpoint-secant spline in log-pressure space.     |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;
        if (self.rows.len < 3 or self.rows.len > max_spline_profile_rows) {
            return self.interpolateTemperatureForPressureLogLinear(pressure_hpa);
        }

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].temperature_k;
        }

        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].temperature_k;
        }

        var log_pressures: [max_spline_profile_rows]f64 = undefined;
        var temperatures_k: [max_spline_profile_rows]f64 = undefined;
        if (descending) {
            for (self.rows, 0..) |_, index| {
                const reversed_index = self.rows.len - 1 - index;
                log_pressures[index] = @log(@max(self.rows[reversed_index].pressure_hpa, 1.0e-9));
                temperatures_k[index] = self.rows[reversed_index].temperature_k;
            }
        } else {
            for (self.rows, 0..) |row, index| {
                log_pressures[index] = @log(@max(row.pressure_hpa, 1.0e-9));
                temperatures_k[index] = row.temperature_k;
            }
        }
        return spline.sampleEndpointSecant(
            log_pressures[0..self.rows.len],
            temperatures_k[0..self.rows.len],
            @log(safe_pressure_hpa),
        ) catch self.interpolateTemperatureForPressureLogLinear(safe_pressure_hpa);
    }

    fn interpolateTemperatureForPressureLogLinear(self: ProfileView, pressure_hpa: f64) f64 {
        // interpolateTemperatureForPressureLogLinear ---------------------------------------------------------|
        // Sample temperature in log-pressure space when the spline route is unavailable.                      |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].temperature_k;
        }

        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].temperature_k;
        }

        const log_pressure = @log(safe_pressure_hpa);
        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            const in_segment = if (descending)
                safe_pressure_hpa <= left.pressure_hpa and safe_pressure_hpa >= right.pressure_hpa
            else
                safe_pressure_hpa >= left.pressure_hpa and safe_pressure_hpa <= right.pressure_hpa;
            if (!in_segment) continue;

            const left_log_pressure = @log(@max(left.pressure_hpa, 1.0e-9));
            const right_log_pressure = @log(@max(right.pressure_hpa, 1.0e-9));
            const span = right_log_pressure - left_log_pressure;
            if (@abs(span) <= 1.0e-12) return right.temperature_k;

            const weight = (log_pressure - left_log_pressure) / span;
            return left.temperature_k + weight * (right.temperature_k - left.temperature_k);
        }

        return self.rows[self.rows.len - 1].temperature_k;
    }

    fn interpolateAltitudeForPressure(self: ProfileView, pressure_hpa: f64) f64 {
        // interpolateAltitudeForPressure ---------------------------------------------------------------------|
        // Invert the pressure profile with monotonic log-linear segment interpolation.                        |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;

        const safe_pressure_hpa = @max(pressure_hpa, 1.0e-9);
        const first_pressure_hpa = self.rows[0].pressure_hpa;
        const last_pressure_hpa = self.rows[self.rows.len - 1].pressure_hpa;
        const descending = first_pressure_hpa >= last_pressure_hpa;

        if ((descending and safe_pressure_hpa >= first_pressure_hpa) or
            (!descending and safe_pressure_hpa <= first_pressure_hpa))
        {
            return self.rows[0].altitude_km;
        }

        if ((descending and safe_pressure_hpa <= last_pressure_hpa) or
            (!descending and safe_pressure_hpa >= last_pressure_hpa))
        {
            return self.rows[self.rows.len - 1].altitude_km;
        }

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            const in_segment = if (descending)
                safe_pressure_hpa <= left.pressure_hpa and safe_pressure_hpa >= right.pressure_hpa
            else
                safe_pressure_hpa >= left.pressure_hpa and safe_pressure_hpa <= right.pressure_hpa;
            if (!in_segment) continue;

            const left_log_pressure = @log(@max(left.pressure_hpa, 1.0e-9));
            const right_log_pressure = @log(@max(right.pressure_hpa, 1.0e-9));
            const span = right_log_pressure - left_log_pressure;
            if (@abs(span) <= 1.0e-12) return left.altitude_km;

            const weight = (@log(safe_pressure_hpa) - left_log_pressure) / span;
            return left.altitude_km + weight * (right.altitude_km - left.altitude_km);
        }

        return self.rows[self.rows.len - 1].altitude_km;
    }

    fn interpolatePressureLogLinear(self: ProfileView, altitude_km: f64) f64 {
        // interpolatePressureLogLinear -----------------------------------------------------------------------|
        // Sample pressure by altitude using log-linear segments when spline interpolation is unavailable.     |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;

        if (altitude_km <= self.rows[0].altitude_km) return self.rows[0].pressure_hpa;

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km > right.altitude_km) continue;

            const span = right.altitude_km - left.altitude_km;
            if (@abs(span) <= 1.0e-12) return left.pressure_hpa;

            const weight = (altitude_km - left.altitude_km) / span;
            const left_log_pressure = @log(@max(left.pressure_hpa, 1.0e-9));
            const right_log_pressure = @log(@max(right.pressure_hpa, 1.0e-9));
            return @exp(left_log_pressure + weight * (right_log_pressure - left_log_pressure));
        }

        return self.rows[self.rows.len - 1].pressure_hpa;
    }

    fn interpolateAltitudeField(
        self: ProfileView,
        altitude_km: f64,
        comptime field: std.meta.FieldEnum(readers.AtmosphereProfileRow),
    ) f64 {
        // interpolateAltitudeField ---------------------------------------------------------------------------|
        // Sample a scalar atmosphere profile field by altitude with linear interpolation.                     |
        // ----------------------------------------------------------------------------------------------------|
        if (self.rows.len == 0) return 0.0;

        if (altitude_km <= self.rows[0].altitude_km) return @field(self.rows[0], @tagName(field));

        for (self.rows[0 .. self.rows.len - 1], self.rows[1..]) |left, right| {
            if (altitude_km > right.altitude_km) continue;

            const span = right.altitude_km - left.altitude_km;
            if (@abs(span) <= 1.0e-12) return @field(left, @tagName(field));

            const weight = (altitude_km - left.altitude_km) / span;
            return @field(left, @tagName(field)) + weight *
                (@field(right, @tagName(field)) - @field(left, @tagName(field)));
        }

        return @field(self.rows[self.rows.len - 1], @tagName(field));
    }
};

fn linearSampleDescending(x_desc: []const f64, y: []const f64, target_x: f64) f64 {
    // linearSampleDescending ---------------------------------------------------------------------------------|
    // Sample y at a descending x value. Used by the dense-profile surface-altitude shift.                     |
    // --------------------------------------------------------------------------------------------------------|
    std.debug.assert(x_desc.len == y.len);
    std.debug.assert(x_desc.len != 0);

    if (target_x >= x_desc[0]) return y[0];
    if (target_x <= x_desc[x_desc.len - 1]) return y[y.len - 1];

    for (
        x_desc[0 .. x_desc.len - 1],
        x_desc[1..],
        y[0 .. y.len - 1],
        y[1..],
    ) |left_x, right_x, left_y, right_y| {
        if (target_x > left_x or target_x < right_x) continue;

        const span = right_x - left_x;
        if (@abs(span) <= 1.0e-12) return right_y;

        const weight = (target_x - left_x) / span;
        return left_y + weight * (right_y - left_y);
    }

    return y[y.len - 1];
}

fn gravitationalAccelerationMetersPerSecondSquared(latitude_deg: f64, altitude_km: f64) f64 {
    // gravitationalAccelerationMetersPerSecondSquared --------------------------------------------------------|
    // DISAMAR gravity approximation used by climatology densification.                                        |
    // --------------------------------------------------------------------------------------------------------|
    const geodetic_flattening_term: f64 = @floatCast(@as(f32, 0.993306));
    const tangent_latitude = std.math.tan(latitude_deg * std.math.pi / 180.0);
    const geodetic_denominator = geodetic_flattening_term + 1.049583e-6 * altitude_km;
    const geodetic_latitude_rad = std.math.atan(tangent_latitude / geodetic_denominator);
    const sin_latitude = std.math.sin(geodetic_latitude_rad);
    const gravity_at_mean_sea_level = 9.78031 + 0.05186 * sin_latitude * sin_latitude;
    return gravity_at_mean_sea_level - 3.086e-3 * altitude_km;
}
// ------------------------------------------------------------------------------------------------------------|
