const std = @import("std");

pub const LayerResponse = struct {
    reflectance: f64,
    transmittance: f64,
};

pub const Error = error{
    SingularDoublingDenominator,
};

pub fn propagateHomogeneous(optical_depth: f64, single_scatter_albedo: f64, doublings: u32) Error!LayerResponse {
    const subdivisions = std.math.pow(f64, 2.0, @as(f64, @floatFromInt(doublings)));
    const base_transmittance = std.math.exp(-optical_depth / subdivisions);
    const base_reflectance = (1.0 - base_transmittance) * single_scatter_albedo * 0.5;

    var response = LayerResponse{
        .reflectance = base_reflectance,
        .transmittance = base_transmittance,
    };

    var i: u32 = 0;
    while (i < doublings) : (i += 1) {
        const denominator = 1.0 - response.reflectance * response.reflectance;
        if (@abs(denominator) <= 1.0e-9) {
            return error.SingularDoublingDenominator;
        }
        response = .{
            .reflectance = response.reflectance + (response.transmittance * response.transmittance * response.reflectance) / denominator,
            .transmittance = (response.transmittance * response.transmittance) / denominator,
        };
    }

    return response;
}

test "doubling propagation preserves bounded reflectance and transmittance" {
    const response = try propagateHomogeneous(0.8, 0.95, 3);
    try std.testing.expect(response.reflectance >= 0.0);
    try std.testing.expect(response.transmittance > 0.0);
    try std.testing.expect(response.transmittance <= 1.0);
}

test "doubling propagation rejects singular reflectance denominators" {
    try std.testing.expectError(error.SingularDoublingDenominator, propagateHomogeneous(1000.0, 2.0, 1));
}

test "doubling propagation uses 2^n optical-depth subdivision" {
    const one_doubling = try propagateHomogeneous(0.8, 0.95, 1);
    const base_transmittance = std.math.exp(-0.8 / 2.0);
    const base_reflectance = (1.0 - base_transmittance) * 0.95 * 0.5;
    const denominator = 1.0 - base_reflectance * base_reflectance;
    const expected = (base_transmittance * base_transmittance) / denominator;
    try std.testing.expectApproxEqAbs(expected, one_doubling.transmittance, 1.0e-12);
}
