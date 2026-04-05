const std = @import("std");
const internal = @import("zdisamar_internal");
const phase_functions = internal.kernels.optics.prepare.phase_functions;

const common = internal.kernels.transport.common;
const labos = internal.kernels.transport.labos;
const execute = labos.execute;

fn legacyPhaseCoefficients(values: [phase_functions.legacy_phase_coefficient_count]f64) [phase_functions.phase_coefficient_count]f64 {
    return phase_functions.phaseCoefficientsFromLegacy(values);
}

test "labos reflectance increases with surface albedo" {
    const layers = [_]common.LayerInput{.{
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .solar_mu = 0.6,
        .view_mu = 0.7,
        .phase_coefficients = phase_functions.zeroPhaseCoefficients(),
    }};

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const result_low = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.05,
        .layers = &layers,
    });
    const result_high = try execute(std.testing.allocator, route, .{
        .mu0 = 0.6,
        .muv = 0.7,
        .optical_depth = 0.3,
        .single_scatter_albedo = 0.9,
        .surface_albedo = 0.5,
        .layers = &layers,
    });
    try std.testing.expect(result_high.toa_reflectance_factor > result_low.toa_reflectance_factor);
}

test "labos reflectance increases with single scatter albedo" {
    const make_layer = struct {
        fn f(ssa: f64) common.LayerInput {
            return .{
                .optical_depth = 0.4,
                .single_scatter_albedo = ssa,
                .solar_mu = 0.5,
                .view_mu = 0.6,
                .phase_coefficients = phase_functions.zeroPhaseCoefficients(),
            };
        }
    }.f;

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });

    const layer_low = [_]common.LayerInput{make_layer(0.3)};
    const result_low = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.4,
        .single_scatter_albedo = 0.3,
        .surface_albedo = 0.05,
        .layers = &layer_low,
    });

    const layer_high = [_]common.LayerInput{make_layer(0.99)};
    const result_high = try execute(std.testing.allocator, route, .{
        .mu0 = 0.5,
        .muv = 0.6,
        .optical_depth = 0.4,
        .single_scatter_albedo = 0.99,
        .surface_albedo = 0.05,
        .layers = &layer_high,
    });

    try std.testing.expect(result_high.toa_reflectance_factor > result_low.toa_reflectance_factor);
}

test "labos supports 48 transport layers without collapsing to the synthetic single-layer fallback" {
    var layers: [48]common.LayerInput = undefined;
    for (&layers, 0..) |*layer, index| {
        const lower_haze = index < 24;
        layer.* = .{
            .optical_depth = if (lower_haze) 0.024 else 0.011,
            .scattering_optical_depth = if (lower_haze) 0.004 else 0.010,
            .single_scatter_albedo = if (lower_haze) 0.17 else 0.92,
            .solar_mu = 0.52,
            .view_mu = 0.63,
            .phase_coefficients = if (lower_haze)
                legacyPhaseCoefficients(.{ 1.0, 0.02, 0.0, 0.0 })
            else
                legacyPhaseCoefficients(.{ 1.0, 0.58, 0.21, 0.07 }),
        };
    }

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });

    const result_multi = try execute(std.testing.allocator, route, .{
        .mu0 = 0.52,
        .muv = 0.63,
        .optical_depth = 0.84,
        .single_scatter_albedo = 0.54,
        .surface_albedo = 0.12,
        .layers = &layers,
    });
    const result_single = try execute(std.testing.allocator, route, .{
        .mu0 = 0.52,
        .muv = 0.63,
        .optical_depth = 0.84,
        .single_scatter_albedo = 0.54,
        .surface_albedo = 0.12,
    });

    try std.testing.expect(result_multi.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result_multi.toa_reflectance_factor <= 2.0);
    try std.testing.expect(@abs(
        result_multi.toa_reflectance_factor - result_single.toa_reflectance_factor,
    ) > 1.0e-5);
}

test "labos supports 80 transport layers without collapsing to the synthetic single-layer fallback" {
    var layers: [80]common.LayerInput = undefined;
    for (&layers, 0..) |*layer, index| {
        const lower_haze = index < 36;
        layer.* = .{
            .optical_depth = if (lower_haze) 0.016 else 0.009,
            .scattering_optical_depth = if (lower_haze) 0.003 else 0.008,
            .single_scatter_albedo = if (lower_haze) 0.19 else 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.61,
            .phase_coefficients = if (lower_haze)
                legacyPhaseCoefficients(.{ 1.0, 0.03, 0.0, 0.0 })
            else
                legacyPhaseCoefficients(.{ 1.0, 0.51, 0.18, 0.06 }),
        };
    }

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });

    const result_multi = try execute(std.testing.allocator, route, .{
        .mu0 = 0.48,
        .muv = 0.61,
        .optical_depth = 0.88,
        .single_scatter_albedo = 0.53,
        .surface_albedo = 0.11,
        .layers = &layers,
    });
    const result_single = try execute(std.testing.allocator, route, .{
        .mu0 = 0.48,
        .muv = 0.61,
        .optical_depth = 0.88,
        .single_scatter_albedo = 0.53,
        .surface_albedo = 0.11,
    });

    try std.testing.expect(result_multi.toa_reflectance_factor >= 0.0);
    try std.testing.expect(result_multi.toa_reflectance_factor <= 2.0);
    try std.testing.expect(@abs(
        result_multi.toa_reflectance_factor - result_single.toa_reflectance_factor,
    ) > 1.0e-5);
}

test "labos spherical correction falls back to layer-dependent solar and view attenuation without explicit grid" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.3,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.2,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const geo = labos.Geometry.init(3, 0.8, 0.9);
    const plane = labos.fillAttenuation(&layers, &geo, false);
    const spherical = labos.fillAttenuation(&layers, &geo, true);
    var plane_dynamic = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, false);
    defer plane_dynamic.deinit();
    var spherical_dynamic = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer spherical_dynamic.deinit();

    try std.testing.expectApproxEqAbs(plane.get(0, 0, 1), spherical.get(0, 0, 1), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.viewIdx(), 1, 0), spherical.get(geo.viewIdx(), 1, 0), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.n_gauss + 1, 1, 0), spherical.get(geo.n_gauss + 1, 1, 0), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.viewIdx(), 0, 2), spherical.get(geo.viewIdx(), 0, 2), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane.get(geo.n_gauss + 1, 0, 2), spherical.get(geo.n_gauss + 1, 0, 2), 1.0e-12);
    try std.testing.expect(plane.get(geo.viewIdx(), 2, 0) != spherical.get(geo.viewIdx(), 2, 0));
    try std.testing.expect(plane.get(geo.n_gauss + 1, 2, 0) != spherical.get(geo.n_gauss + 1, 2, 0));
    try std.testing.expectApproxEqAbs(plane_dynamic.get(geo.viewIdx(), 0, 2), spherical_dynamic.get(geo.viewIdx(), 0, 2), 1.0e-12);
    try std.testing.expectApproxEqAbs(plane_dynamic.get(geo.n_gauss + 1, 0, 2), spherical_dynamic.get(geo.n_gauss + 1, 0, 2), 1.0e-12);
    try std.testing.expect(plane_dynamic.get(geo.viewIdx(), 2, 0) != spherical_dynamic.get(geo.viewIdx(), 2, 0));
    try std.testing.expect(plane_dynamic.get(geo.n_gauss + 1, 2, 0) != spherical_dynamic.get(geo.n_gauss + 1, 2, 0));
}

test "labos dynamic spherical correction uses pseudo-spherical sample grid when provided" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.27,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const pseudo_samples = [_]common.PseudoSphericalSample{
        .{ .altitude_km = 1.0, .thickness_km = 2.0, .optical_depth = 0.14 },
        .{ .altitude_km = 3.0, .thickness_km = 2.0, .optical_depth = 0.13 },
        .{ .altitude_km = 8.0, .thickness_km = 4.0, .optical_depth = 0.08 },
        .{ .altitude_km = 12.0, .thickness_km = 4.0, .optical_depth = 0.06 },
    };
    const pseudo_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
    };
    const rearth_km = 6371.0;
    const geo = labos.Geometry.init(3, 0.8, 0.9);
    var spherical = try labos.fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, pseudo_grid, &geo, true);
    defer spherical.deinit();
    var fallback = try labos.fillAttenuationDynamic(std.testing.allocator, &layers, &geo, true);
    defer fallback.deinit();

    const view_u = geo.u[geo.viewIdx()];
    const sin2theta = 1.0 - view_u * view_u;
    const expected_surface = blk: {
        var sumkext: f64 = 0.0;
        for (pseudo_samples) |sample| {
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sin2theta * rearth_km * rearth_km));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk std.math.exp(-sumkext);
    };
    const expected_mid = blk: {
        var sumkext: f64 = 0.0;
        const level_radius = rearth_km + 6.0;
        const sqrx_sin2theta = sin2theta * level_radius * level_radius;
        for (pseudo_samples[2..]) |sample| {
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk std.math.exp(-sumkext);
    };

    try std.testing.expectApproxEqRel(expected_surface, spherical.get(geo.viewIdx(), 2, 0), 1.0e-12);
    try std.testing.expectApproxEqRel(expected_mid, spherical.get(geo.viewIdx(), 2, 1), 1.0e-12);
    try std.testing.expect(@abs(spherical.get(geo.viewIdx(), 2, 0) - fallback.get(geo.viewIdx(), 2, 0)) > 1.0e-6);
    try std.testing.expectApproxEqAbs(fallback.get(geo.viewIdx(), 0, 2), spherical.get(geo.viewIdx(), 0, 2), 1.0e-12);
}

test "labos dynamic spherical correction prefers explicit pseudo-spherical level altitudes" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.27,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.45,
            .view_mu = 0.55,
        },
        .{
            .optical_depth = 0.14,
            .single_scatter_albedo = 0.9,
            .solar_mu = 0.50,
            .view_mu = 0.60,
        },
    };
    const pseudo_samples = [_]common.PseudoSphericalSample{
        .{ .altitude_km = 0.75, .thickness_km = 0.0, .optical_depth = 0.0 },
        .{ .altitude_km = 4.25, .thickness_km = 1.0, .optical_depth = 0.14 },
        .{ .altitude_km = 7.75, .thickness_km = 1.0, .optical_depth = 0.0 },
        .{ .altitude_km = 10.0, .thickness_km = 1.0, .optical_depth = 0.08 },
    };
    const pseudo_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
        .level_altitudes_km = &.{ 0.75, 7.75, 12.25 },
    };
    const inferred_grid: common.PseudoSphericalGrid = .{
        .samples = &pseudo_samples,
        .level_sample_starts = &.{ 0, 2, 4 },
    };
    const rearth_km = 6371.0;
    const geo = labos.Geometry.init(3, 0.8, 0.9);
    var explicit = try labos.fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, pseudo_grid, &geo, true);
    defer explicit.deinit();
    var inferred = try labos.fillAttenuationDynamicWithGrid(std.testing.allocator, &layers, inferred_grid, &geo, true);
    defer inferred.deinit();

    const view_u = geo.u[geo.viewIdx()];
    const sin2theta = 1.0 - view_u * view_u;
    const expected_mid = blk: {
        var sumkext: f64 = 0.0;
        const level_radius = rearth_km + 7.75;
        const sqrx_sin2theta = sin2theta * level_radius * level_radius;
        for (pseudo_samples[2..]) |sample| {
            if (sample.optical_depth <= 0.0) continue;
            const sample_radius = rearth_km + sample.altitude_km;
            const denominator = @sqrt(@abs(sample_radius * sample_radius - sqrx_sin2theta));
            sumkext += (sample.optical_depth * sample_radius) / denominator;
        }
        break :blk std.math.exp(-sumkext);
    };

    try std.testing.expectApproxEqRel(expected_mid, explicit.get(geo.viewIdx(), 2, 1), 1.0e-12);
    try std.testing.expect(@abs(
        explicit.get(geo.viewIdx(), 2, 1) - inferred.get(geo.viewIdx(), 2, 1),
    ) > 1.0e-9);
}

test "labos anisotropic layers respond to relative azimuth once Fourier terms are enabled" {
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
        },
    });
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.35,
            .scattering_optical_depth = 0.30,
            .single_scatter_albedo = 0.93,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.55, 0.24, 0.08 }),
        },
        .{
            .optical_depth = 0.22,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.91,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.42, 0.16, 0.05 }),
        },
    };

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.57,
        .single_scatter_albedo = 0.92,
        .surface_albedo = 0.12,
        .layers = &layers,
    };
    const result_zero = try execute(std.testing.allocator, route, forward_input);
    const result_oblique = try execute(std.testing.allocator, route, .{
        .mu0 = forward_input.mu0,
        .muv = forward_input.muv,
        .optical_depth = forward_input.optical_depth,
        .single_scatter_albedo = forward_input.single_scatter_albedo,
        .surface_albedo = forward_input.surface_albedo,
        .relative_azimuth_rad = std.math.degreesToRadians(120.0),
        .layers = &layers,
    });

    try std.testing.expect(@abs(result_zero.toa_reflectance_factor - result_oblique.toa_reflectance_factor) > 1.0e-5);
}

test "labos raw-layer integrated source-function fallback stays close to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.35, 0.12, 0.03 }),
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.24, 0.09, 0.02 }),
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        6.0e-3,
    );
}

test "labos single-layer integrated source-function falls back to direct TOA extraction" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.31,
            .scattering_optical_depth = 0.24,
            .single_scatter_albedo = 0.91,
            .solar_mu = 0.59,
            .view_mu = 0.65,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.28, 0.07, 0.01 }),
        },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.31,
        .single_scatter_albedo = 0.91,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(70.0),
        .layers = &layers,
    };
    const result_integrated = try execute(std.testing.allocator, route_integrated, forward_input);
    const result_direct = try execute(std.testing.allocator, route_direct, forward_input);

    try std.testing.expectApproxEqRel(
        result_direct.toa_reflectance_factor,
        result_integrated.toa_reflectance_factor,
        1.0e-12,
    );
}

test "labos integrated source-function path uses explicit source interface metadata" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.35, 0.12, 0.03 }),
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.24, 0.09, 0.02 }),
        },
    };
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(&layers, &source_interfaces);

    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    source_interfaces[1].rtm_weight = 2.0;
    source_interfaces[1].ksca_above = source_interfaces[1].source_weight / source_interfaces[1].rtm_weight;
    source_interfaces[1].source_weight = 0.0;

    const base_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
        .source_interfaces = &source_interfaces,
    };
    const baseline = try execute(std.testing.allocator, route, base_input);
    const direct_baseline = try execute(std.testing.allocator, route_direct, base_input);

    var altered_interfaces = source_interfaces;
    altered_interfaces[1].ksca_above *= 1.8;
    altered_interfaces[1].phase_coefficients_above[1] = 0.60;
    const altered = try execute(std.testing.allocator, route, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });
    const direct_altered = try execute(std.testing.allocator, route_direct, .{
        .mu0 = base_input.mu0,
        .muv = base_input.muv,
        .optical_depth = base_input.optical_depth,
        .single_scatter_albedo = base_input.single_scatter_albedo,
        .surface_albedo = base_input.surface_albedo,
        .relative_azimuth_rad = base_input.relative_azimuth_rad,
        .layers = &layers,
        .source_interfaces = &altered_interfaces,
    });

    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
    try std.testing.expectApproxEqAbs(
        direct_baseline.toa_reflectance_factor,
        direct_altered.toa_reflectance_factor,
        1.0e-10,
    );
}

test "labos prepared RTM quadrature participates in integrated source-function reflectance" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.28,
            .scattering_optical_depth = 0.22,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.58,
            .view_mu = 0.64,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.35, 0.12, 0.03 }),
        },
        .{
            .optical_depth = 0.17,
            .scattering_optical_depth = 0.13,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.61,
            .view_mu = 0.67,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.24, 0.09, 0.02 }),
        },
    };

    const rtm_quadrature = [_]common.RtmQuadratureLevel{
        .{ .altitude_km = 0.0, .weight = 0.0, .ksca = 0.0, .phase_coefficients = phase_functions.zeroPhaseCoefficients() },
        .{ .altitude_km = 3.5, .weight = 4.0, .ksca = 0.055, .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.31, 0.10, 0.02 }) },
        .{ .altitude_km = 8.0, .weight = 0.0, .ksca = 0.0, .phase_coefficients = phase_functions.zeroPhaseCoefficients() },
    };

    const route_integrated = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = false,
        },
    });

    const input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.45,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .relative_azimuth_rad = std.math.degreesToRadians(75.0),
        .layers = &layers,
        .rtm_quadrature = .{ .levels = &rtm_quadrature },
    };
    const baseline = try execute(std.testing.allocator, route_integrated, input);
    const direct_baseline = try execute(std.testing.allocator, route_direct, input);

    var altered_rtm_quadrature = rtm_quadrature;
    altered_rtm_quadrature[1].ksca *= 1.8;
    altered_rtm_quadrature[1].phase_coefficients[1] = 0.60;
    const altered = try execute(std.testing.allocator, route_integrated, .{
        .mu0 = input.mu0,
        .muv = input.muv,
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .surface_albedo = input.surface_albedo,
        .relative_azimuth_rad = input.relative_azimuth_rad,
        .layers = input.layers,
        .rtm_quadrature = .{ .levels = &altered_rtm_quadrature },
    });
    const direct_altered = try execute(std.testing.allocator, route_direct, .{
        .mu0 = input.mu0,
        .muv = input.muv,
        .optical_depth = input.optical_depth,
        .single_scatter_albedo = input.single_scatter_albedo,
        .surface_albedo = input.surface_albedo,
        .relative_azimuth_rad = input.relative_azimuth_rad,
        .layers = input.layers,
        .rtm_quadrature = .{ .levels = &altered_rtm_quadrature },
    });

    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - altered.toa_reflectance_factor,
    ) > 1.0e-5);
    try std.testing.expectApproxEqAbs(
        direct_baseline.toa_reflectance_factor,
        direct_altered.toa_reflectance_factor,
        1.0e-10,
    );
}

test "labos spherical correction changes reflectance for layered scalar scenes" {
    const layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.24,
            .scattering_optical_depth = 0.18,
            .single_scatter_albedo = 0.88,
            .solar_mu = 0.42,
            .view_mu = 0.54,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.31, 0.10, 0.02 }),
        },
        .{
            .optical_depth = 0.16,
            .scattering_optical_depth = 0.12,
            .single_scatter_albedo = 0.90,
            .solar_mu = 0.48,
            .view_mu = 0.60,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.26, 0.08, 0.02 }),
        },
    };

    const route_plane = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = false,
        },
    });
    const route_spherical = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 6,
            .use_spherical_correction = true,
        },
    });

    const forward_input = common.ForwardInput{
        .mu0 = 0.60,
        .muv = 0.66,
        .optical_depth = 0.40,
        .single_scatter_albedo = 0.89,
        .surface_albedo = 0.10,
        .layers = &layers,
    };
    const plane = try execute(std.testing.allocator, route_plane, forward_input);
    const spherical = try execute(std.testing.allocator, route_spherical, forward_input);

    try std.testing.expect(@abs(plane.toa_reflectance_factor - spherical.toa_reflectance_factor) > 1.0e-5);
}
