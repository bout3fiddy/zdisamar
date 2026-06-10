const std = @import("std");
const internal = @import("internal");

const common = internal.forward_model.radiative_transfer;
const phase_functions = internal.forward_model.optical_properties.shared.phase_functions;
const prepareSolveConfig = common.prepareSolveConfig;
const fillSourceInterfacesFromLayers = common.fillSourceInterfacesFromLayers;

test "radiative-transfer core row layouts match documented hot-path comments" {
    try std.testing.expectEqual(@as(usize, 64), @sizeOf(common.RadiativeTransferPerformanceThresholds));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(common.RadiativeTransferPerformanceThresholds));

    try std.testing.expectEqual(@as(usize, 176), @sizeOf(common.LayerInput));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(common.LayerInput));
    try expectOffset(common.LayerInput, "gas_absorption_optical_depth", 0);
    try expectOffset(common.LayerInput, "gas_scattering_optical_depth", 8);
    try expectOffset(common.LayerInput, "cia_optical_depth", 16);
    try expectOffset(common.LayerInput, "aerosol_optical_depth", 24);
    try expectOffset(common.LayerInput, "aerosol_scattering_optical_depth", 32);
    try expectOffset(common.LayerInput, "optical_depth", 40);
    try expectOffset(common.LayerInput, "scattering_optical_depth", 48);
    try expectOffset(common.LayerInput, "single_scatter_albedo", 56);
    try expectOffset(common.LayerInput, "optical_depth_jacobian", 64);
    try expectOffset(common.LayerInput, "scattering_optical_depth_jacobian", 88);
    try expectOffset(common.LayerInput, "single_scatter_albedo_jacobian", 112);
    try expectOffset(common.LayerInput, "solar_mu", 136);
    try expectOffset(common.LayerInput, "view_mu", 144);
    try expectOffset(common.LayerInput, "phase", 152);

    try std.testing.expectEqual(@as(usize, 64), @sizeOf(common.SourceInterfaceInput));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(common.SourceInterfaceInput));
    try expectOffset(common.SourceInterfaceInput, "source_weight", 0);
    try expectOffset(common.SourceInterfaceInput, "rtm_weight", 8);
    try expectOffset(common.SourceInterfaceInput, "ksca_above", 16);
    try expectOffset(common.SourceInterfaceInput, "phase_above", 24);
    try expectOffset(common.SourceInterfaceInput, "phase_max_index_above", 48);
    try expectOffset(common.SourceInterfaceInput, "phase_max_index_below", 56);

    try std.testing.expectEqual(@as(usize, 64), @sizeOf(common.RtmQuadratureLevel));
    try std.testing.expectEqual(@as(usize, 8), @alignOf(common.RtmQuadratureLevel));
    try expectOffset(common.RtmQuadratureLevel, "altitude_km", 0);
    try expectOffset(common.RtmQuadratureLevel, "weight", 8);
    try expectOffset(common.RtmQuadratureLevel, "ksca", 16);
    try expectOffset(common.RtmQuadratureLevel, "aerosol_ksca_above_per_km", 24);
    try expectOffset(common.RtmQuadratureLevel, "aerosol_ksca_below_per_km", 32);
    try expectOffset(common.RtmQuadratureLevel, "aerosol_ksca_jacobian", 40);
    try expectOffset(common.RtmQuadratureLevel, "phase_aerosol_weight", 48);
    try expectOffset(common.RtmQuadratureLevel, "phase_rayleigh2_weight", 56);
}

test "radiative-transfer thresholds keep tangent order cap opt-in" {
    const default_thresholds = common.RadiativeTransferPerformanceThresholds.o2a_default;
    try std.testing.expect(default_thresholds.shouldEvaluateAerosolTangent(0));
    try std.testing.expect(default_thresholds.shouldEvaluateAerosolTangent(128));

    const fast_tangent_thresholds: common.RadiativeTransferPerformanceThresholds = .{
        .aerosol_tangent_order_cap = 11,
    };
    try std.testing.expect(fast_tangent_thresholds.shouldEvaluateAerosolTangent(11));
    try std.testing.expect(!fast_tangent_thresholds.shouldEvaluateAerosolTangent(12));
}

test "prepare config accepts current derivative modes" {
    const value_config = try prepareSolveConfig(.{
        .derivative_mode = .none,
    });
    try std.testing.expectEqual(common.DerivativeMode.none, value_config.derivative_mode);

    const twenty_stream_config = try prepareSolveConfig(.{
        .derivative_mode = .none,
        .rtm_controls = .{ .n_streams = 20 },
    });
    try std.testing.expectEqual(@as(u16, 20), twenty_stream_config.rtm_controls.n_streams);

    const jacobian_config = try prepareSolveConfig(.{
        .derivative_mode = .semi_analytical,
    });
    try std.testing.expectEqual(common.DerivativeMode.semi_analytical, jacobian_config.derivative_mode);
}

test "execute prepared config returns reflectance without jacobian for value mode" {
    const rtm_config = try prepareSolveConfig(.{
        .derivative_mode = .none,
    });

    const result = try common.executePrepared(std.testing.allocator, rtm_config, .{});
    try std.testing.expect(result.jacobian == null);
}

test "source interface builder preserves the top boundary weight and halves the bottom boundary weight" {
    const layer0_phase = phase_functions.phaseCoefficientsFromCompact(.{ 1.0, 0.10, 0.0, 0.0 });
    const layer1_phase = phase_functions.phaseCoefficientsFromCompact(.{ 1.0, 0.30, 0.0, 0.0 });
    const layers = [_]common.LayerInput{
        .{
            .scattering_optical_depth = 0.20,
            .phase = common.LayerPhase.fromUnitPhase(&layer0_phase),
        },
        .{
            .scattering_optical_depth = 0.40,
            .phase = common.LayerPhase.fromUnitPhase(&layer1_phase),
        },
    };
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[0].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.40), source_interfaces[1].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.20), source_interfaces[2].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[1].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), source_interfaces[2].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.10), source_interfaces[0].phase_above.coefficient(1), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[1].phase_above.coefficient(1), 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.30), source_interfaces[2].phase_above.coefficient(1), 1.0e-12);
    try std.testing.expectEqual(@as(usize, 1), source_interfaces[0].phase_max_index_above);
    try std.testing.expectEqual(@as(usize, 1), source_interfaces[1].phase_max_index_above);
    try std.testing.expectEqual(@as(usize, 1), source_interfaces[2].phase_max_index_above);
    try std.testing.expectEqual(@as(usize, 0), source_interfaces[0].phase_max_index_below);
    try std.testing.expectEqual(@as(usize, 1), source_interfaces[1].phase_max_index_below);
    try std.testing.expectEqual(@as(usize, 1), source_interfaces[2].phase_max_index_below);
}

fn expectOffset(comptime Struct: type, comptime field_name: []const u8, expected: usize) !void {
    try std.testing.expectEqual(expected, @offsetOf(Struct, field_name));
}
