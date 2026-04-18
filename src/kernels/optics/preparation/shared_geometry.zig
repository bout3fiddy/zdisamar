const std = @import("std");
const ReferenceData = @import("../../../model/ReferenceData.zig");
const gauss_legendre = @import("../../quadrature/gauss_legendre.zig");
const State = @import("state.zig");

const PreparedOpticalState = State.PreparedOpticalState;
const PreparedSublayer = State.PreparedSublayer;
const SharedRtmGeometry = State.SharedRtmGeometry;
const SharedRtmLayerGeometry = State.SharedRtmLayerGeometry;
const SharedRtmLevelGeometry = State.SharedRtmLevelGeometry;

const max_dynamic_gauss_order: usize = 128;

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
    if (self.interval_semantics == .none) return false;
    const sublayers = self.sublayers orelse return false;
    return transport_layer_count == sublayers.len;
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
        .lower_altitude_km = levelAltitudeFromSublayers(sublayers, start_index),
        .upper_altitude_km = levelAltitudeFromSublayers(sublayers, stop_index),
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

    var interval_rule_scratch: GaussRuleScratch = .{};
    for (self.layers) |layer| {
        const start_index: usize = @intCast(layer.sublayer_start_index);
        const count: usize = @intCast(layer.sublayer_count);
        if (count == 0) continue;

        const interval = sharedRtmInterval(self, sublayers, layer);
        const level_node_count = count - 1;
        const level_rule = if (level_node_count > 0)
            resolveGaussRule(level_node_count, &interval_rule_scratch)
        else
            null;

        levels[start_index] = .{
            .altitude_km = interval.lower_altitude_km,
            .weight_km = 0.0,
            .support_start_index = @intCast(start_index),
            .support_count = @intCast(count),
        };
        for (0..level_node_count) |node_index| {
            levels[start_index + 1 + node_index] = .{
                .altitude_km = intervalAltitudeAtNode(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.nodes[node_index],
                ),
                .weight_km = intervalWeightKm(
                    interval.lower_altitude_km,
                    interval.upper_altitude_km,
                    level_rule.?.weights[node_index],
                ),
                .support_start_index = @intCast(start_index),
                .support_count = @intCast(count),
            };
        }

        const stop_index = start_index + count;
        levels[stop_index] = .{
            .altitude_km = interval.upper_altitude_km,
            .weight_km = 0.0,
            .support_start_index = @intCast(start_index),
            .support_count = @intCast(count),
        };

        for (0..count) |local_layer_index| {
            const lower_altitude_km = levels[start_index + local_layer_index].altitude_km;
            const upper_altitude_km = levels[start_index + local_layer_index + 1].altitude_km;
            layers[start_index + local_layer_index] = .{
                .lower_altitude_km = lower_altitude_km,
                .upper_altitude_km = upper_altitude_km,
                .midpoint_altitude_km = 0.5 * (lower_altitude_km + upper_altitude_km),
                .thickness_km = @max(upper_altitude_km - lower_altitude_km, 0.0),
                .support_start_index = @intCast(start_index),
                .support_count = @intCast(count),
            };
        }
    }

    return .{
        .layers = layers,
        .levels = levels,
    };
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
