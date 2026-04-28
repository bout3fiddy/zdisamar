const std = @import("std");
const ReferenceData = @import("../../../input/ReferenceData.zig");
const gauss_legendre = @import("../../../common/math/quadrature/gauss_legendre.zig");
const State = @import("state.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedSublayer = State.PreparedSublayer;
const SharedRtmGeometry = State.SharedRtmGeometry;
const SharedRtmLayerGeometry = State.SharedRtmLayerGeometry;
const SharedRtmLevelGeometry = State.SharedRtmLevelGeometry;

const max_dynamic_gauss_order: usize = 128;
pub const invalid_support_row_index: u32 = std.math.maxInt(u32);

pub const ResolvedGaussRule = struct {
    nodes: []const f64,
    weights: []const f64,
};

pub const GaussRuleScratch = struct {
    nodes: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
    weights: [max_dynamic_gauss_order]f64 = [_]f64{0.0} ** max_dynamic_gauss_order,
};

pub const SharedRtmInterval = struct {
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    support_sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState = null,
};

pub const SharedSupportSlices = struct {
    sublayers: []const PreparedSublayer,
    strong_line_states: ?[]const ReferenceData.StrongLinePreparedState,
};

pub fn usesSharedRtmGrid(self: *const PreparedOpticalState, transport_layer_count: usize) bool {
    if (!self.intervalSemanticsUseReducedSharedRtmLayers()) return false;
    return transport_layer_count == self.layers.len;
}

pub fn cachedSharedRtmGeometry(
    self: *const PreparedOpticalState,
    transport_layer_count: usize,
) ?*const SharedRtmGeometry {
    if (!self.shared_rtm_geometry.isValidFor(transport_layer_count)) return null;
    return &self.shared_rtm_geometry;
}

pub fn resolveGaussRule(order: usize, scratch: *GaussRuleScratch) ResolvedGaussRule {
    if (order == 0) unreachable;
    if (order > max_dynamic_gauss_order) {
        @panic("gauss-legendre order exceeds shared RTM scratch capacity");
    }

    if (order <= 10) {
        const rule = gauss_legendre.rule(@intCast(order)) catch unreachable;
        @memcpy(scratch.nodes[0..order], rule.nodes[0..order]);
        @memcpy(scratch.weights[0..order], rule.weights[0..order]);
    } else {
        gauss_legendre.fillNodesAndWeights(
            @intCast(order),
            scratch.nodes[0..order],
            scratch.weights[0..order],
        ) catch unreachable;
    }

    return .{
        .nodes = scratch.nodes[0..order],
        .weights = scratch.weights[0..order],
    };
}

pub fn intervalAltitudeAtNode(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_node: f64,
) f64 {
    const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);
    return lower_altitude_km + 0.5 * (normalized_node + 1.0) * altitude_span_km;
}

pub fn intervalWeightKm(
    lower_altitude_km: f64,
    upper_altitude_km: f64,
    normalized_weight: f64,
) f64 {
    const altitude_span_km = @max(upper_altitude_km - lower_altitude_km, 0.0);
    return 0.5 * normalized_weight * altitude_span_km;
}

pub fn sharedRtmInterval(
    self: *const PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    layer: State.PreparedLayer,
) SharedRtmInterval {
    const start_index: usize = @intCast(layer.sublayer_start_index);
    const count: usize = @intCast(layer.sublayer_count);
    const stop_index = start_index + count;
    return .{
        .lower_altitude_km = layer.bottom_altitude_km,
        .upper_altitude_km = layer.top_altitude_km,
        .support_sublayers = sublayers[start_index..stop_index],
        .strong_line_states = if (self.strong_line_states) |states|
            states[start_index..stop_index]
        else
            null,
    };
}

pub fn sharedSupportSlices(
    self: *const PreparedOpticalState,
    sublayers: []const PreparedSublayer,
    support_start_index: usize,
    support_count: usize,
) SharedSupportSlices {
    const support_stop_index = support_start_index + support_count;
    return .{
        .sublayers = sublayers[support_start_index..support_stop_index],
        .strong_line_states = if (self.strong_line_states) |states|
            states[support_start_index..support_stop_index]
        else
            null,
    };
}

pub fn buildSharedRtmGeometry(
    allocator: std.mem.Allocator,
    self: *const PreparedOpticalState,
) !SharedRtmGeometry {
    const transport_layer_count = self.transportLayerCount();
    if (!usesSharedRtmGrid(self, transport_layer_count)) return .{};
    const sublayers = self.sublayers orelse return .{};

    const layers = try allocator.alloc(SharedRtmLayerGeometry, transport_layer_count);
    errdefer allocator.free(layers);
    const levels = try allocator.alloc(SharedRtmLevelGeometry, transport_layer_count + 1);
    errdefer allocator.free(levels);
    @memset(layers, .{});
    @memset(levels, .{});

    for (self.layers, 0..) |layer, layer_index| {
        layers[layer_index] = .{
            .lower_altitude_km = layer.bottom_altitude_km,
            .upper_altitude_km = layer.top_altitude_km,
            .midpoint_altitude_km = 0.5 * (layer.bottom_altitude_km + layer.top_altitude_km),
            .thickness_km = @max(layer.top_altitude_km - layer.bottom_altitude_km, 0.0),
            .support_start_index = layer.sublayer_start_index,
            .support_count = layer.sublayer_count,
        };
    }

    for (levels) |*level| {
        level.* = .{
            .particle_above_support_row_index = invalid_support_row_index,
            .particle_below_support_row_index = invalid_support_row_index,
        };
    }

    if (self.layers.len == 0) return .{ .layers = layers, .levels = levels };

    const first_layer = self.layers[0];
    const first_support_row_index: usize = @intCast(first_layer.sublayer_start_index);
    levels[0] = .{
        .altitude_km = sublayers[first_support_row_index].altitude_km,
        .weight_km = 0.0,
        .support_start_index = first_layer.sublayer_start_index,
        .support_count = first_layer.sublayer_count,
        .support_row_index = @intCast(first_support_row_index),
        .particle_above_support_row_index = firstActiveSupportRowIndex(first_layer),
        .particle_below_support_row_index = invalid_support_row_index,
    };

    for (1..self.layers.len) |level_index| {
        const below_layer = self.layers[level_index - 1];
        const above_layer = self.layers[level_index];
        const boundary_support_row_index: usize = @intCast(above_layer.sublayer_start_index);
        levels[level_index] = .{
            .altitude_km = sublayers[boundary_support_row_index].altitude_km,
            .weight_km = 0.0,
            .support_start_index = above_layer.sublayer_start_index,
            .support_count = above_layer.sublayer_count,
            .support_row_index = @intCast(boundary_support_row_index),
            .particle_above_support_row_index = firstActiveSupportRowIndex(above_layer),
            .particle_below_support_row_index = lastActiveSupportRowIndex(below_layer),
        };
    }

    const last_layer = self.layers[self.layers.len - 1];
    const last_support_row_index: usize =
        @as(usize, @intCast(last_layer.sublayer_start_index)) +
        @as(usize, @intCast(last_layer.sublayer_count)) -
        1;
    levels[self.layers.len] = .{
        .altitude_km = sublayers[last_support_row_index].altitude_km,
        .weight_km = 0.0,
        .support_start_index = last_layer.sublayer_start_index,
        .support_count = last_layer.sublayer_count,
        .support_row_index = @intCast(last_support_row_index),
        .particle_above_support_row_index = invalid_support_row_index,
        .particle_below_support_row_index = lastActiveSupportRowIndex(last_layer),
    };

    var interval_rule_scratch: GaussRuleScratch = .{};
    var interval_start: usize = 0;
    while (interval_start < self.layers.len) {
        const interval_index_1based = self.layers[interval_start].interval_index_1based;
        var interval_stop = interval_start + 1;
        while (interval_stop < self.layers.len and self.layers[interval_stop].interval_index_1based == interval_index_1based) {
            interval_stop += 1;
        }

        const interval_first_layer = self.layers[interval_start];
        const interval_last_layer = self.layers[interval_stop - 1];
        const interior_level_count = interval_stop - interval_start - 1;
        if (interior_level_count > 0) {
            const rule = resolveGaussRule(interior_level_count, &interval_rule_scratch);
            for (0..interior_level_count) |offset| {
                levels[interval_start + 1 + offset].weight_km = intervalWeightKm(
                    interval_first_layer.bottom_altitude_km,
                    interval_last_layer.top_altitude_km,
                    rule.weights[offset],
                );
            }
        }
        interval_start = interval_stop;
    }

    return .{
        .layers = layers,
        .levels = levels,
    };
}

fn firstActiveSupportRowIndex(layer: State.PreparedLayer) u32 {
    const start_index: usize = @intCast(layer.sublayer_start_index);
    const count: usize = @intCast(layer.sublayer_count);
    if (count <= 2) return invalid_support_row_index;
    return @intCast(start_index + 1);
}

fn lastActiveSupportRowIndex(layer: State.PreparedLayer) u32 {
    const start_index: usize = @intCast(layer.sublayer_start_index);
    const count: usize = @intCast(layer.sublayer_count);
    if (count <= 2) return invalid_support_row_index;
    return @intCast(start_index + count - 2);
}

pub fn levelAltitudeFromSublayers(
    sublayers: []const PreparedSublayer,
    level: usize,
) f64 {
    if (sublayers.len == 0) return 0.0;
    if (level == 0) {
        const first = sublayers[0];
        return @max(first.altitude_km - 0.5 * first.path_length_cm / 1.0e5, 0.0);
    }
    if (level >= sublayers.len) {
        const last = sublayers[sublayers.len - 1];
        return @max(last.altitude_km + 0.5 * last.path_length_cm / 1.0e5, 0.0);
    }
    const sample = sublayers[level];
    return @max(sample.altitude_km - 0.5 * sample.path_length_cm / 1.0e5, 0.0);
}
