const std = @import("std");

pub const LayerResponse = struct {
    reflectance: f64,
    transmittance: f64,
};

pub fn propagateHomogeneous(optical_depth: f64, single_scatter_albedo: f64, doublings: u32) LayerResponse {
    const base_transmittance = std.math.exp(-optical_depth / @as(f64, @floatFromInt(@max(doublings, 1))));
    const base_reflectance = (1.0 - base_transmittance) * single_scatter_albedo * 0.5;

    var response = LayerResponse{
        .reflectance = base_reflectance,
        .transmittance = base_transmittance,
    };

    var i: u32 = 0;
    while (i < doublings) : (i += 1) {
        const denominator = 1.0 - response.reflectance * response.reflectance;
        response = .{
            .reflectance = response.reflectance + (response.transmittance * response.transmittance * response.reflectance) / denominator,
            .transmittance = (response.transmittance * response.transmittance) / denominator,
        };
    }

    return response;
}

test "doubling propagation preserves bounded reflectance and transmittance" {
    const response = propagateHomogeneous(0.8, 0.95, 3);
    try std.testing.expect(response.reflectance >= 0.0);
    try std.testing.expect(response.transmittance > 0.0);
    try std.testing.expect(response.transmittance <= 1.0);
}
