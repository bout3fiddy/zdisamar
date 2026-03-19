const std = @import("std");
const common = @import("common.zig");
const phase_functions = @import("../optics/prepare/phase_functions.zig");

pub const LayerResponse = struct {
    reflectance: f64,
    transmittance: f64,
    direct_down_transmittance: f64,
    direct_up_transmittance: f64,
    source_reflectance: f64,
    downward_source: f64,
};

pub const Error = error{
    SingularDoublingDenominator,
};

const DeltaEddingtonScaledLayer = struct {
    optical_depth: f64,
    single_scatter_albedo: f64,
    backscatter_fraction: f64,
};

pub fn propagateHomogeneous(
    optical_depth: f64,
    single_scatter_albedo: f64,
    backscatter_fraction: f64,
    solar_mu: f64,
    view_mu: f64,
    doublings: u32,
) Error!LayerResponse {
    const subdivisions = std.math.pow(f64, 2.0, @as(f64, @floatFromInt(doublings)));
    const base_transmittance = std.math.exp(-optical_depth / subdivisions);
    const base_reflectance = (1.0 - base_transmittance) * single_scatter_albedo * backscatter_fraction;
    const beam_intercepted = 1.0 - std.math.exp(-optical_depth / @max(solar_mu, 0.05));
    const half_layer_diffuse_escape = std.math.sqrt(base_transmittance);
    const upward_source = beam_intercepted *
        single_scatter_albedo *
        backscatter_fraction *
        half_layer_diffuse_escape;
    const downward_source = beam_intercepted *
        single_scatter_albedo *
        (1.0 - backscatter_fraction) *
        half_layer_diffuse_escape;

    var response = LayerResponse{
        .reflectance = base_reflectance,
        .transmittance = base_transmittance,
        .direct_down_transmittance = std.math.exp(-optical_depth / @max(solar_mu, 0.05)),
        .direct_up_transmittance = std.math.exp(-optical_depth / @max(view_mu, 0.05)),
        .source_reflectance = upward_source,
        .downward_source = downward_source,
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
            .direct_down_transmittance = response.direct_down_transmittance,
            .direct_up_transmittance = response.direct_up_transmittance,
            .source_reflectance = response.source_reflectance,
            .downward_source = response.downward_source,
        };
    }

    return response;
}

pub fn propagateLayer(layer: common.LayerInput, doublings: u32) Error!LayerResponse {
    const scaled = deltaEddingtonScale(layer);
    return propagateHomogeneous(
        scaled.optical_depth,
        scaled.single_scatter_albedo,
        scaled.backscatter_fraction,
        layer.solar_mu,
        layer.view_mu,
        doublings,
    );
}

pub fn surfaceBoundary(albedo: f64) LayerResponse {
    const clamped_albedo = std.math.clamp(albedo, 0.0, 1.0);
    return .{
        .reflectance = clamped_albedo,
        .transmittance = 0.0,
        .direct_down_transmittance = 1.0,
        .direct_up_transmittance = 1.0,
        .source_reflectance = clamped_albedo,
        .downward_source = 0.0,
    };
}

pub fn addUpperOverLower(upper: LayerResponse, lower: LayerResponse) Error!LayerResponse {
    const denominator = 1.0 - upper.reflectance * lower.reflectance;
    if (@abs(denominator) <= 1.0e-9) {
        return error.SingularDoublingDenominator;
    }

    return .{
        .reflectance = upper.reflectance +
            (upper.transmittance * upper.transmittance * lower.reflectance) / denominator,
        .transmittance = (upper.transmittance * lower.transmittance) / denominator,
        .direct_down_transmittance = upper.direct_down_transmittance * lower.direct_down_transmittance,
        .direct_up_transmittance = upper.direct_up_transmittance * lower.direct_up_transmittance,
        .source_reflectance = upper.source_reflectance +
            (upper.direct_down_transmittance * upper.transmittance * lower.source_reflectance),
        .downward_source = (lower.transmittance * upper.downward_source) +
            (upper.direct_down_transmittance * lower.downward_source),
    };
}

fn deltaEddingtonScale(layer: common.LayerInput) DeltaEddingtonScaledLayer {
    const asymmetry_factor = std.math.clamp(layer.phase_coefficients[1], -0.95, 0.95);
    const forward_peak_fraction = std.math.clamp(asymmetry_factor * asymmetry_factor, 0.0, 0.95);
    const extinction_scale = @max(1.0 - layer.single_scatter_albedo * forward_peak_fraction, 1.0e-6);
    const scaled_single_scatter_albedo = std.math.clamp(
        layer.single_scatter_albedo * (1.0 - forward_peak_fraction) / extinction_scale,
        0.0,
        0.999,
    );
    const scaled_asymmetry = if (@abs(1.0 + asymmetry_factor) <= 1.0e-6)
        asymmetry_factor
    else
        asymmetry_factor / (1.0 + asymmetry_factor);
    return .{
        .optical_depth = layer.optical_depth * extinction_scale,
        .single_scatter_albedo = scaled_single_scatter_albedo,
        .backscatter_fraction = phase_functions.backscatterFractionFromAsymmetry(scaled_asymmetry),
    };
}

test "doubling propagation preserves bounded reflectance and transmittance" {
    const response = try propagateHomogeneous(0.8, 0.95, 0.35, 0.8, 0.9, 3);
    try std.testing.expect(response.reflectance >= 0.0);
    try std.testing.expect(response.transmittance > 0.0);
    try std.testing.expect(response.transmittance <= 1.0);
    try std.testing.expect(response.source_reflectance >= 0.0);
}

test "doubling propagation rejects singular reflectance denominators" {
    try std.testing.expectError(error.SingularDoublingDenominator, propagateHomogeneous(1000.0, 2.0, 0.5, 0.8, 0.8, 1));
}

test "doubling propagation uses 2^n optical-depth subdivision" {
    const one_doubling = try propagateHomogeneous(0.8, 0.95, 0.5, 0.8, 0.8, 1);
    const base_transmittance = std.math.exp(-0.8 / 2.0);
    const base_reflectance = (1.0 - base_transmittance) * 0.95 * 0.5;
    const denominator = 1.0 - base_reflectance * base_reflectance;
    const expected = (base_transmittance * base_transmittance) / denominator;
    try std.testing.expectApproxEqAbs(expected, one_doubling.transmittance, 1.0e-12);
}

test "doubling can add a layer over a reflective surface" {
    const upper = try propagateHomogeneous(0.4, 0.9, 0.25, 0.8, 0.85, 2);
    const combined = try addUpperOverLower(upper, surfaceBoundary(0.08));
    try std.testing.expect(combined.source_reflectance > upper.source_reflectance);
    try std.testing.expect(combined.reflectance >= upper.reflectance);
}

test "delta-Eddington scaling reduces forward-peak extinction and raises backscatter" {
    const scaled = deltaEddingtonScale(.{
        .optical_depth = 0.4,
        .single_scatter_albedo = 1.0,
        .phase_coefficients = .{ 1.0, 0.7, 0.49, 0.343 },
    });
    try std.testing.expect(scaled.optical_depth < 0.4);
    try std.testing.expect(scaled.single_scatter_albedo > 0.99);
    try std.testing.expect(scaled.backscatter_fraction > phase_functions.backscatterFraction(.{ 1.0, 0.7, 0.49, 0.343 }));
}
