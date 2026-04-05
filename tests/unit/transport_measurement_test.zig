const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const phase_functions = internal.kernels.optics.prepare.phase_functions;
const Scene = zdisamar.Scene;
const common = internal.kernels.transport.common;
const labos = internal.kernels.transport.labos;
const MeasurementSpace = internal.kernels.transport.measurement;
const MeasurementSpaceShim = internal.kernels.transport.measurement_space;
const MeasurementForwardInput = MeasurementSpace.forward_input;
const MeasurementSpectral = MeasurementSpace.spectral_eval;
const MeasurementTestSupport = MeasurementSpace.test_support;
const SummaryWorkspace = MeasurementSpace.SummaryWorkspace;
const calibration = internal.kernels.spectra.calibration;
const configuredForwardInput = MeasurementForwardInput.configuredForwardInput;
const simulateSummary = MeasurementSpace.simulateSummary;
const simulateSummaryWithWorkspace = MeasurementSpace.simulateSummaryWithWorkspace;
const simulateProduct = MeasurementSpace.simulateProduct;
const SpectralEvaluationCache = MeasurementSpectral.SpectralEvaluationCache;
const cachedForwardAtWavelength = MeasurementSpectral.cachedForwardAtWavelength;
const radianceFromForward = MeasurementSpectral.radianceFromForward;
const buildTestPreparedOpticalState = MeasurementTestSupport.buildTestPreparedOpticalState;
const buildQuadratureSensitivePreparedOpticalState = MeasurementTestSupport.buildQuadratureSensitivePreparedOpticalState;
const buildNonuniformQuadraturePreparedOpticalState = MeasurementTestSupport.buildNonuniformQuadraturePreparedOpticalState;
const buildSingleSubdivisionPreparedOpticalState = MeasurementTestSupport.buildSingleSubdivisionPreparedOpticalState;
const testProviders = MeasurementTestSupport.testProviders;

fn legacyPhaseCoefficients(values: [phase_functions.legacy_phase_coefficient_count]f64) [phase_functions.phase_coefficient_count]f64 {
    return phase_functions.phaseCoefficientsFromLegacy(values);
}
const fillSyntheticIntegratedSourceField = MeasurementTestSupport.fillSyntheticIntegratedSourceField;
const inputWithQuadrature = MeasurementTestSupport.inputWithQuadrature;
const fillLegacyMidpointQuadratureLevels = MeasurementTestSupport.fillLegacyMidpointQuadratureLevels;
const ensureBufferCapacity = MeasurementSpace.workspace.ensureBufferCapacity;

test "configured forward input preserves prepared source-function boundary weights" {
    const scene: Scene = .{
        .id = "measurement-source-interfaces",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [8]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [8]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expectEqual(@as(usize, 5), input.source_interfaces.len);
    try std.testing.expectApproxEqRel(
        input.layers[0].scattering_optical_depth,
        input.source_interfaces[0].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[0].rtm_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[1].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[2].source_weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[3].source_weight, 1.0e-12);
    try std.testing.expect(input.source_interfaces[1].rtm_weight > 0.0);
    try std.testing.expect(input.source_interfaces[2].rtm_weight > 0.0);
    try std.testing.expect(input.source_interfaces[3].rtm_weight > 0.0);
    try std.testing.expectApproxEqRel(
        input.layers[1].scattering_optical_depth,
        input.source_interfaces[1].rtm_weight * input.source_interfaces[1].ksca_above,
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        input.layers[2].scattering_optical_depth,
        input.source_interfaces[2].rtm_weight * input.source_interfaces[2].ksca_above,
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        input.layers[3].scattering_optical_depth,
        input.source_interfaces[3].rtm_weight * input.source_interfaces[3].ksca_above,
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        input.layers[1].phase_coefficients[1],
        input.source_interfaces[1].phase_coefficients_above[1],
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        input.layers[2].phase_coefficients[1],
        input.source_interfaces[2].phase_coefficients_above[1],
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        0.5 * input.layers[3].scattering_optical_depth,
        input.source_interfaces[4].source_weight,
        1.0e-12,
    );
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.source_interfaces[4].rtm_weight, 1.0e-12);
}

test "configured forward input wires pseudo-spherical attenuation samples from prepared sublayers" {
    const scene: Scene = .{
        .id = "measurement-pseudo-spherical-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [8]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [8]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expect(input.pseudo_spherical_grid.isValidFor(input.layers.len));
    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expectEqual(@as(usize, 8), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 4, 6, 8 }, input.pseudo_spherical_grid.level_sample_starts);
    try std.testing.expectEqualSlices(f64, &.{ 0.75, 2.75, 7.75, 11.75, 12.25 }, input.pseudo_spherical_grid.level_altitudes_km);
    try std.testing.expectApproxEqRel(@as(f64, 0.75), input.pseudo_spherical_grid.samples[0].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].optical_depth, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].optical_depth, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].optical_depth > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[4].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[6].thickness_km, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[5].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[7].optical_depth > 0.0);
}

test "configured forward input builds adding pseudo-spherical subgrid within prepared RTM layers" {
    const scene: Scene = .{
        .id = "measurement-adding-pseudo-spherical-subgrid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 90.0,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [8]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [8]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expect(input.pseudo_spherical_grid.isValidFor(input.layers.len));
    try std.testing.expectEqual(@as(usize, 8), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 2, 4, 6, 8 }, input.pseudo_spherical_grid.level_sample_starts);
    try std.testing.expectEqualSlices(f64, &.{ 0.75, 2.75, 7.75, 11.75, 12.25 }, input.pseudo_spherical_grid.level_altitudes_km);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[0].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[2].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[4].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.pseudo_spherical_grid.samples[6].thickness_km, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[5].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[7].thickness_km > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[3].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[5].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[7].optical_depth > 0.0);
}

test "configured forward input leaves pseudo-spherical attenuation grid empty when prepared sublayers are unavailable" {
    const scene: Scene = .{
        .id = "measurement-pseudo-spherical-grid-fallback",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .limb,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .limb,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    const owned_sublayers = prepared.sublayers.?;
    prepared.sublayers = null;
    defer {
        std.testing.allocator.free(owned_sublayers);
        prepared.deinit(std.testing.allocator);
    }

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 0), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqual(@as(usize, 0), input.pseudo_spherical_grid.level_sample_starts.len);
}

test "configured forward input builds prepared adding RTM quadrature on sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-adding-direct-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expectEqual(@as(usize, 5), input.source_interfaces.len);
    try std.testing.expect(input.rtm_controls.integrate_source_function);
    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[0].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[1].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[2].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[3].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[1].ksca > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[2].ksca, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[3].ksca > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].ksca, 1.0e-12);

    var lower_interval_scattering: f64 = 0.0;
    for (input.layers[0..2]) |layer| lower_interval_scattering += @max(layer.scattering_optical_depth, 0.0);
    var upper_interval_scattering: f64 = 0.0;
    for (input.layers[2..4]) |layer| upper_interval_scattering += @max(layer.scattering_optical_depth, 0.0);
    try std.testing.expectApproxEqRel(
        lower_interval_scattering,
        input.rtm_quadrature.levels[1].weightedScattering(),
        1.0e-12,
    );
    try std.testing.expectApproxEqRel(
        upper_interval_scattering,
        input.rtm_quadrature.levels[3].weightedScattering(),
        1.0e-12,
    );
}

test "configured forward input builds prepared labos RTM quadrature on sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-labos-direct-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(common.TransportFamily.labos, route.family);
    try std.testing.expect(input.rtm_controls.integrate_source_function);
    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[0].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[1].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[2].weight, 1.0e-12);
    try std.testing.expect(input.rtm_quadrature.levels[3].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].weight, 1.0e-12);
}

test "configured forward input builds prepared adding RTM quadrature from nonuniform sublayer intervals" {
    const scene: Scene = .{
        .id = "measurement-adding-nonuniform-grid",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 1,
            .sublayer_divisions = 4,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 4), input.layers.len);
    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[0].weight, 1.0e-12);
    const expected_total_span_km = 10.0;
    const three_point_weights = [_]f64{ 0.5555555555555556, 0.8888888888888888, 0.5555555555555556 };
    const three_point_nodes = [_]f64{ -0.7745966692414834, 0.0, 0.7745966692414834 };
    for (0..3) |index| {
        try std.testing.expectApproxEqRel(
            0.5 * three_point_weights[index] * expected_total_span_km,
            input.rtm_quadrature.levels[index + 1].weight,
            1.0e-12,
        );
        try std.testing.expectApproxEqRel(
            0.5 * (three_point_nodes[index] + 1.0) * expected_total_span_km,
            input.rtm_quadrature.levels[index + 1].altitude_km,
            1.0e-12,
        );
    }
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[4].weight, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 0.20355732173984167), input.rtm_quadrature.levels[1].phase_coefficients[1], 1.0e-12);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[1].phase_coefficients[1] - @as(f64, 0.24)) > 1.0e-2);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[2].phase_coefficients[1] - @as(f64, 0.38)) > 1.0e-2);

    const legacy_middle_weight = 2.5 * (10.0 / 7.5);
    try std.testing.expect(@abs(input.rtm_quadrature.levels[2].weight - legacy_middle_weight) > 1.0e-3);

    var total_scattering: f64 = 0.0;
    for (input.layers) |layer| total_scattering += @max(layer.scattering_optical_depth, 0.0);

    var quadrature_scattering: f64 = 0.0;
    for (input.rtm_quadrature.levels[1..5]) |level| {
        quadrature_scattering += level.weightedScattering();
    }
    try std.testing.expectApproxEqRel(total_scattering, quadrature_scattering, 1.0e-12);
}

test "prepared adding RTM quadrature recomputes node phase from prepared sublayer state" {
    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const surrogate_layers = [_]common.LayerInput{
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.95, 0.0, 0.0 }),
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.95, 0.0, 0.0 }),
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.95, 0.0, 0.0 }),
        },
        .{
            .optical_depth = 0.125,
            .scattering_optical_depth = 0.125,
            .single_scatter_albedo = 1.0,
            .phase_coefficients = legacyPhaseCoefficients(.{ 1.0, 0.95, 0.0, 0.0 }),
        },
    };
    var levels: [5]common.RtmQuadratureLevel = undefined;
    const has_quadrature = internal.kernels.optics.preparation.transport.fillRtmQuadratureAtWavelengthWithLayers(&prepared, 435.0, &surrogate_layers, &levels);

    try std.testing.expect(has_quadrature);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), levels[0].weight, 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), levels[4].weight, 1.0e-12);
    try std.testing.expect(@abs(levels[1].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expect(@abs(levels[2].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expect(@abs(levels[3].phase_coefficients[1] - @as(f64, 0.95)) > 1.0e-1);
    try std.testing.expectApproxEqRel(@as(f64, 0.20355732173984167), levels[1].phase_coefficients[1], 1.0e-12);
}

test "prepared adding live route uses nonuniform quadrature weights instead of the legacy midpoint surrogate" {
    const scene: Scene = .{
        .id = "measurement-adding-nonuniform-live",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.03,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 54.0,
            .viewing_zenith_deg = 46.0,
            .relative_azimuth_deg = 78.0,
        },
        .atmosphere = .{
            .layer_count = 1,
            .sublayer_divisions = 4,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildNonuniformQuadraturePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    var legacy_levels: [5]common.RtmQuadratureLevel = undefined;
    for (input.rtm_quadrature.levels, 0..) |level, index| {
        legacy_levels[index] = level;
    }
    fillLegacyMidpointQuadratureLevels(&prepared, input.layers, &legacy_levels);

    const providers = testProviders();
    const forward_new = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        input,
    );
    const forward_legacy = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        inputWithQuadrature(input, &legacy_levels),
    );

    try std.testing.expect(std.math.isFinite(forward_new.toa_reflectance_factor));
    try std.testing.expect(std.math.isFinite(forward_legacy.toa_reflectance_factor));
    try std.testing.expect(forward_new.toa_reflectance_factor > 0.0);
    try std.testing.expect(forward_legacy.toa_reflectance_factor > 0.0);
    try std.testing.expect(@abs(
        forward_new.toa_reflectance_factor - forward_legacy.toa_reflectance_factor,
    ) > 1.0e-8);
}

test "prepared adding live route falls back when no explicit RTM quadrature nodes exist" {
    const scene: Scene = .{
        .id = "measurement-adding-single-subdivision",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.04,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 52.0,
            .viewing_zenith_deg = 44.0,
            .relative_azimuth_deg = 70.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 1,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildSingleSubdivisionPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [2]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [2]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expectEqual(@as(usize, 2), input.layers.len);
    try std.testing.expectEqual(@as(usize, 0), input.rtm_quadrature.levels.len);
    try std.testing.expect(input.source_interfaces[1].rtm_weight > 0.0);

    const providers = testProviders();
    const forward_fallback = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        input,
    );
    const zero_quadrature = [_]common.RtmQuadratureLevel{
        .{},
        .{},
        .{},
    };
    const forward_bad = try providers.transport.executePrepared(
        std.testing.allocator,
        route,
        inputWithQuadrature(input, &zero_quadrature),
    );

    try std.testing.expect(std.math.isFinite(forward_fallback.toa_reflectance_factor));
    try std.testing.expect(forward_fallback.toa_reflectance_factor > 0.0);
    try std.testing.expect(@abs(
        forward_fallback.toa_reflectance_factor - forward_bad.toa_reflectance_factor,
    ) > 1.0e-8);
}

test "configured forward input preserves pseudo-spherical attenuation when only one sublayer division is requested" {
    const scene: Scene = .{
        .id = "measurement-pseudo-spherical-single-subdivision",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 52.0,
            .viewing_zenith_deg = 44.0,
            .relative_azimuth_deg = 70.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 1,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildSingleSubdivisionPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [2]common.LayerInput = undefined;
    var pseudo_spherical_layers: [2]common.LayerInput = undefined;
    var source_interfaces: [3]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [3]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [2]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [3]usize = undefined;
    var pseudo_spherical_level_altitudes: [3]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );

    try std.testing.expect(input.pseudo_spherical_grid.isValidFor(input.layers.len));
    try std.testing.expectEqual(@as(usize, 2), input.pseudo_spherical_grid.samples.len);
    try std.testing.expectEqualSlices(usize, &.{ 0, 1, 2 }, input.pseudo_spherical_grid.level_sample_starts);
    try std.testing.expectEqualSlices(f64, &.{ 0.0, 3.0, 9.0 }, input.pseudo_spherical_grid.level_altitudes_km);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), input.pseudo_spherical_grid.samples[0].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 6.0), input.pseudo_spherical_grid.samples[1].altitude_km, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 3.0), input.pseudo_spherical_grid.samples[0].thickness_km, 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 6.0), input.pseudo_spherical_grid.samples[1].thickness_km, 1.0e-12);
    try std.testing.expect(input.pseudo_spherical_grid.samples[0].optical_depth > 0.0);
    try std.testing.expect(input.pseudo_spherical_grid.samples[1].optical_depth > 0.0);
}

test "cached forward execution preserves prepared adding RTM quadrature and its reflectance semantics" {
    const scene: Scene = .{
        .id = "measurement-adding-direct-execution",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    const route_direct = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = false,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);
    var integrated_cache = SpectralEvaluationCache.init(std.testing.allocator);
    defer integrated_cache.deinit();
    var direct_cache = SpectralEvaluationCache.init(std.testing.allocator);
    defer direct_cache.deinit();
    var integrated_layers: [4]common.LayerInput = undefined;
    var integrated_pseudo_layers: [4]common.LayerInput = undefined;
    var integrated_interfaces: [5]common.SourceInterfaceInput = undefined;
    var integrated_rtm_quadrature: [5]common.RtmQuadratureLevel = undefined;
    var integrated_pseudo_samples: [4]common.PseudoSphericalSample = undefined;
    var integrated_pseudo_level_starts: [5]usize = undefined;
    var integrated_pseudo_level_altitudes: [5]f64 = undefined;
    var direct_layers: [4]common.LayerInput = undefined;
    var direct_pseudo_layers: [4]common.LayerInput = undefined;
    var direct_interfaces: [5]common.SourceInterfaceInput = undefined;
    var direct_rtm_quadrature: [5]common.RtmQuadratureLevel = undefined;
    var direct_pseudo_samples: [4]common.PseudoSphericalSample = undefined;
    var direct_pseudo_level_starts: [5]usize = undefined;
    var direct_pseudo_level_altitudes: [5]f64 = undefined;
    const providers = testProviders();

    const integrated_sample = try cachedForwardAtWavelength(
        std.testing.allocator,
        &scene,
        route_integrated,
        &prepared,
        435.0,
        10.0,
        providers,
        &integrated_layers,
        &integrated_pseudo_layers,
        &integrated_interfaces,
        &integrated_rtm_quadrature,
        &integrated_pseudo_samples,
        &integrated_pseudo_level_starts,
        &integrated_pseudo_level_altitudes,
        &integrated_cache,
    );
    const direct_sample = try cachedForwardAtWavelength(
        std.testing.allocator,
        &scene,
        route_direct,
        &prepared,
        435.0,
        10.0,
        providers,
        &direct_layers,
        &direct_pseudo_layers,
        &direct_interfaces,
        &direct_rtm_quadrature,
        &direct_pseudo_samples,
        &direct_pseudo_level_starts,
        &direct_pseudo_level_altitudes,
        &direct_cache,
    );

    const explicit_input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &integrated_layers,
        &integrated_pseudo_layers,
        &integrated_interfaces,
        &integrated_rtm_quadrature,
        &integrated_pseudo_samples,
        &integrated_pseudo_level_starts,
        &integrated_pseudo_level_altitudes,
    );
    var fallback_interfaces: [5]common.SourceInterfaceInput = undefined;
    common.fillSourceInterfacesFromLayers(explicit_input.layers, &fallback_interfaces);
    const explicit_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        explicit_input,
    );
    const geo = labos.Geometry.init(route_integrated.rtm_controls.nGauss(), explicit_input.mu0, explicit_input.muv);
    var synthetic_ud: [5]labos.UDField = undefined;
    fillSyntheticIntegratedSourceField(&geo, &synthetic_ud);
    const explicit_reflectance = labos.calcIntegratedReflectance(
        explicit_input.layers,
        explicit_input.source_interfaces,
        explicit_input.rtm_quadrature,
        &synthetic_ud,
        explicit_input.layers.len,
        0,
        &geo,
    );
    const fallback_reflectance = labos.calcIntegratedReflectance(
        explicit_input.layers,
        &fallback_interfaces,
        .{},
        &synthetic_ud,
        explicit_input.layers.len,
        0,
        &geo,
    );

    const cached_radiance = radianceFromForward(
        &scene,
        &prepared,
        providers,
        435.0,
        10.0,
        0.0,
        explicit_forward,
    );
    try std.testing.expect(explicit_input.rtm_quadrature.isValidFor(explicit_input.layers.len));
    try std.testing.expectApproxEqRel(
        cached_radiance,
        integrated_sample.radiance,
        1.0e-12,
    );
    try std.testing.expect(explicit_reflectance > 0.0);
    try std.testing.expect(@abs(fallback_reflectance - explicit_reflectance) > 1.0e-6);

    try std.testing.expect(@abs(
        direct_sample.radiance - integrated_sample.radiance,
    ) > 1.0e-8);
    try std.testing.expect(@abs(
        direct_sample.jacobian - integrated_sample.jacobian,
    ) > 1.0e-10);
}

test "prepared adding RTM quadrature keeps the lower boundary inert and activates all prepared RTM samples" {
    const scene: Scene = .{
        .id = "measurement-adding-boundary-weights",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .integrate_source_function = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const baseline_input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );
    const geo = labos.Geometry.init(route_integrated.rtm_controls.nGauss(), baseline_input.mu0, baseline_input.muv);
    var synthetic_ud: [5]labos.UDField = undefined;
    fillSyntheticIntegratedSourceField(&geo, &synthetic_ud);
    const baseline_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        baseline_input.rtm_quadrature,
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );
    var boundary_quadrature = rtm_quadrature_levels;
    boundary_quadrature[0].ksca = 9.0;
    boundary_quadrature[0].phase_coefficients[1] = 0.95;
    const boundary_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        .{ .levels = &boundary_quadrature },
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );
    var interior_quadrature = rtm_quadrature_levels;
    interior_quadrature[1].ksca *= 1.5;
    interior_quadrature[1].phase_coefficients[1] = 0.60;
    const interior_integrated = labos.calcIntegratedReflectance(
        baseline_input.layers,
        baseline_input.source_interfaces,
        .{ .levels = &interior_quadrature },
        &synthetic_ud,
        baseline_input.layers.len,
        0,
        &geo,
    );

    try std.testing.expect(baseline_input.rtm_quadrature.isValidFor(baseline_input.layers.len));
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[0].weight, 1.0e-12);
    try std.testing.expect(rtm_quadrature_levels[1].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[2].weight, 1.0e-12);
    try std.testing.expect(rtm_quadrature_levels[3].weight > 0.0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), rtm_quadrature_levels[4].weight, 1.0e-12);
    try std.testing.expectApproxEqRel(
        baseline_integrated,
        boundary_integrated,
        1.0e-12,
    );
    try std.testing.expect(@abs(
        baseline_integrated - interior_integrated,
    ) > 1.0e-8);
}

test "prepared adding live route consumes RTM quadrature while the lower boundary stays inert" {
    const scene: Scene = .{
        .id = "measurement-adding-live-quadrature",
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .surface = .{
            .albedo = 0.05,
        },
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 53.13,
            .viewing_zenith_deg = 48.19,
            .relative_azimuth_deg = 75.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
    };
    const route_integrated = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 6,
            .integrate_source_function = true,
        },
    });

    var prepared = try buildQuadratureSensitivePreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var layer_inputs: [4]common.LayerInput = undefined;
    var pseudo_spherical_layers: [4]common.LayerInput = undefined;
    var source_interfaces: [5]common.SourceInterfaceInput = undefined;
    var rtm_quadrature_levels: [5]common.RtmQuadratureLevel = undefined;
    var pseudo_spherical_samples: [4]common.PseudoSphericalSample = undefined;
    var pseudo_spherical_level_starts: [5]usize = undefined;
    var pseudo_spherical_level_altitudes: [5]f64 = undefined;
    const input = configuredForwardInput(
        &scene,
        route_integrated,
        &prepared,
        435.0,
        &layer_inputs,
        &pseudo_spherical_layers,
        &source_interfaces,
        &rtm_quadrature_levels,
        &pseudo_spherical_samples,
        &pseudo_spherical_level_starts,
        &pseudo_spherical_level_altitudes,
    );
    const providers = testProviders();
    const baseline = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        input,
    );

    const boundary_index: usize = 0;
    var interior_index: usize = 0;
    for (1..input.rtm_quadrature.levels.len) |ilevel| {
        if (interior_index == 0 and input.rtm_quadrature.levels[ilevel].weight > 0.0) {
            interior_index = ilevel;
        }
    }

    try std.testing.expect(input.rtm_quadrature.isValidFor(input.layers.len));
    try std.testing.expect(interior_index != 0);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), input.rtm_quadrature.levels[boundary_index].weight, 1.0e-12);
    try std.testing.expect(baseline.toa_reflectance_factor > 0.0);

    var boundary_quadrature = rtm_quadrature_levels;
    boundary_quadrature[boundary_index].ksca = 25.0;
    boundary_quadrature[boundary_index].phase_coefficients[1] = 0.95;
    const boundary_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        inputWithQuadrature(input, &boundary_quadrature),
    );

    var interior_quadrature = rtm_quadrature_levels;
    interior_quadrature[interior_index].ksca *= 4.0;
    interior_quadrature[interior_index].phase_coefficients[1] = 0.95;
    const interior_forward = try providers.transport.executePrepared(
        std.testing.allocator,
        route_integrated,
        inputWithQuadrature(input, &interior_quadrature),
    );

    try std.testing.expectApproxEqRel(
        baseline.toa_reflectance_factor,
        boundary_forward.toa_reflectance_factor,
        1.0e-10,
    );
    try std.testing.expect(@abs(
        baseline.toa_reflectance_factor - interior_forward.toa_reflectance_factor,
    ) > 1.0e-6);
}

test "summary workspace sizes adding transport buffers from sublayer hints" {
    const scene: Scene = .{
        .id = "measurement-adding-grid-hint",
        .spectral_grid = .{
            .start_nm = 430.0,
            .end_nm = 440.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route_labos = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    const route_adding = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
        },
    });

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const labos_buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route_labos,
        testProviders(),
    );
    try std.testing.expectEqual(@as(usize, 4), labos_buffers.layer_inputs.len);
    try std.testing.expectEqual(@as(usize, 5), labos_buffers.source_interfaces.len);

    const adding_buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route_adding,
        testProviders(),
    );
    try std.testing.expectEqual(@as(usize, 4), adding_buffers.layer_inputs.len);
    try std.testing.expectEqual(@as(usize, 5), adding_buffers.source_interfaces.len);
}

test "measurement-space simulation supports adding routes on prepared sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-space-adding-sublayers",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .use_adding = true,
            .n_streams = 8,
            .num_orders_max = 4,
            .integrate_source_function = false,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, &scene, route, &prepared, testProviders());
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
}

test "measurement-space simulation supports labos routes on prepared sublayer grids" {
    const scene: Scene = .{
        .id = "measurement-space-labos-sublayers",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .geometry = .{
            .model = .pseudo_spherical,
            .solar_zenith_deg = 56.0,
            .viewing_zenith_deg = 28.0,
            .relative_azimuth_deg = 75.0,
        },
        .atmosphere = .{
            .layer_count = 2,
            .sublayer_divisions = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
        .rtm_controls = .{
            .n_streams = 8,
            .num_orders_max = 4,
            .integrate_source_function = true,
            .use_spherical_correction = true,
        },
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, &scene, route, &prepared, testProviders());
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
}

test "measurement-space simulation composes transport, calibration, convolution, and noise" {
    const scene: Scene = .{
        .id = "measurement-space",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    const summary = try simulateSummary(std.testing.allocator, &scene, route, &prepared, testProviders());
    try std.testing.expectEqual(@as(u32, 16), summary.sample_count);
    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expect(summary.mean_irradiance > 0.0);
    try std.testing.expect(summary.mean_reflectance > 0.0);
    try std.testing.expect(summary.mean_reflectance < 10.0);
    try std.testing.expect(summary.mean_noise_sigma > 0.0);
    try std.testing.expect(summary.mean_jacobian != null);
}

test "measurement-space summary workspace reuses caller-owned buffers and matches full-product summaries" {
    const scene: Scene = .{
        .id = "measurement-summary-workspace",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 16,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const first_summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    const wavelengths_ptr = @intFromPtr(workspace.wavelengths.ptr);
    const radiance_ptr = @intFromPtr(workspace.radiance.ptr);
    const jacobian_ptr = @intFromPtr(workspace.jacobian.ptr);
    const noise_ptr = @intFromPtr(workspace.noise_sigma.ptr);

    const second_summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    try std.testing.expectEqual(wavelengths_ptr, @intFromPtr(workspace.wavelengths.ptr));
    try std.testing.expectEqual(radiance_ptr, @intFromPtr(workspace.radiance.ptr));
    try std.testing.expectEqual(jacobian_ptr, @intFromPtr(workspace.jacobian.ptr));
    try std.testing.expectEqual(noise_ptr, @intFromPtr(workspace.noise_sigma.ptr));

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(first_summary.sample_count, second_summary.sample_count);
    try std.testing.expectApproxEqAbs(first_summary.mean_radiance, second_summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_radiance, product.summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_irradiance, product.summary.mean_irradiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_reflectance, product.summary.mean_reflectance, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_noise_sigma, product.summary.mean_noise_sigma, 1.0e-12);
    try std.testing.expectApproxEqAbs(first_summary.mean_jacobian.?, product.summary.mean_jacobian.?, 1.0e-12);
}

test "measurement-space summary workspace supports routes without jacobians or noise materialization" {
    const scene: Scene = .{
        .id = "measurement-summary-no-noise",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 10,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .none,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    const summary = try simulateSummaryWithWorkspace(
        std.testing.allocator,
        &workspace,
        &scene,
        route,
        &prepared,
        testProviders(),
    );
    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(summary.mean_radiance > 0.0);
    try std.testing.expectEqual(@as(f64, 0.0), summary.mean_noise_sigma);
    try std.testing.expect(summary.mean_jacobian == null);
    try std.testing.expectEqual(@as(usize, 0), workspace.jacobian.len);
    try std.testing.expectEqual(@as(usize, 0), workspace.noise_sigma.len);
    try std.testing.expectEqual(@as(usize, 0), product.noise_sigma.len);
    try std.testing.expect(product.jacobian == null);
}

test "ensureBufferCapacity preserves the original buffer on allocation failure" {
    var storage: [96]u8 = undefined;
    var fixed_buffer = std.heap.FixedBufferAllocator.init(&storage);
    const allocator = fixed_buffer.allocator();

    var buffer = try allocator.alloc(f64, 4);
    errdefer allocator.free(buffer);
    const original_ptr = buffer.ptr;
    const original_len = buffer.len;

    try std.testing.expectError(error.OutOfMemory, ensureBufferCapacity(allocator, &buffer, 32));
    try std.testing.expect(buffer.ptr == original_ptr);
    try std.testing.expectEqual(original_len, buffer.len);

    allocator.free(buffer);
}

test "measurement-space simulate materializes shared noise sigma without channel-specific buffers" {
    const scene: Scene = .{
        .id = "measurement-shared-noise-sigma",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);

    var buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route,
        testProviders(),
    );
    @memset(buffers.noise_sigma.?, 0.0);
    buffers.radiance_noise_sigma = null;
    buffers.irradiance_noise_sigma = null;
    buffers.reflectance_noise_sigma = null;

    const summary = try MeasurementSpaceShim.simulate(
        std.testing.allocator,
        &scene,
        route,
        &prepared,
        testProviders(),
        buffers,
    );

    try std.testing.expect(summary.mean_noise_sigma > 0.0);
    try std.testing.expect(buffers.noise_sigma.?[0] > 0.0);
}

test "measurement-space simulate materializes explicit channel sigma buffers without legacy noise buffer" {
    const scene: Scene = .{
        .id = "measurement-explicit-channel-noise-sigma",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var reference_workspace: SummaryWorkspace = .{};
    defer reference_workspace.deinit(std.testing.allocator);
    const reference_buffers = try reference_workspace.buffers(
        std.testing.allocator,
        &scene,
        route,
        testProviders(),
    );
    const reference_summary = try MeasurementSpaceShim.simulate(
        std.testing.allocator,
        &scene,
        route,
        &prepared,
        testProviders(),
        reference_buffers,
    );

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);
    var buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route,
        testProviders(),
    );
    buffers.noise_sigma = null;
    @memset(buffers.radiance_noise_sigma.?, 0.0);
    @memset(buffers.irradiance_noise_sigma.?, 0.0);
    @memset(buffers.reflectance_noise_sigma.?, 0.0);

    const summary = try MeasurementSpaceShim.simulate(
        std.testing.allocator,
        &scene,
        route,
        &prepared,
        testProviders(),
        buffers,
    );

    try std.testing.expectApproxEqRel(reference_summary.mean_noise_sigma, summary.mean_noise_sigma, 1.0e-12);
    for (reference_buffers.radiance_noise_sigma.?, buffers.radiance_noise_sigma.?) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
    for (reference_buffers.irradiance_noise_sigma.?, buffers.irradiance_noise_sigma.?) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
    for (reference_buffers.reflectance_noise_sigma.?, buffers.reflectance_noise_sigma.?) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
}

test "measurement-space simulate preserves reflectance sigma when only legacy and reflectance buffers are exposed" {
    const scene: Scene = .{
        .id = "measurement-reflectance-sigma-legacy-alias",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var reference_workspace: SummaryWorkspace = .{};
    defer reference_workspace.deinit(std.testing.allocator);
    const reference_buffers = try reference_workspace.buffers(
        std.testing.allocator,
        &scene,
        route,
        testProviders(),
    );
    const reference_summary = try MeasurementSpaceShim.simulate(
        std.testing.allocator,
        &scene,
        route,
        &prepared,
        testProviders(),
        reference_buffers,
    );

    var workspace: SummaryWorkspace = .{};
    defer workspace.deinit(std.testing.allocator);
    var buffers = try workspace.buffers(
        std.testing.allocator,
        &scene,
        route,
        testProviders(),
    );
    @memset(buffers.noise_sigma.?, 0.0);
    @memset(buffers.reflectance_noise_sigma.?, 0.0);
    buffers.radiance_noise_sigma = null;
    buffers.irradiance_noise_sigma = null;

    const summary = try MeasurementSpaceShim.simulate(
        std.testing.allocator,
        &scene,
        route,
        &prepared,
        testProviders(),
        buffers,
    );

    try std.testing.expectApproxEqRel(reference_summary.mean_noise_sigma, summary.mean_noise_sigma, 1.0e-12);
    for (reference_buffers.radiance_noise_sigma.?, buffers.noise_sigma.?) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
    for (reference_buffers.reflectance_noise_sigma.?, buffers.reflectance_noise_sigma.?) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-12);
    }
}

test "measurement-space product materializes spectral vectors and physical fields" {
    const scene: Scene = .{
        .id = "measurement-product",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });
    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 12), product.summary.sample_count);
    try std.testing.expectEqual(@as(usize, 12), product.wavelengths.len);
    try std.testing.expectEqual(product.wavelengths.len, product.radiance.len);
    try std.testing.expect(product.radiance[0] > 0.0);
    try std.testing.expect(product.irradiance[0] > 0.0);
    try std.testing.expect(product.reflectance[0] > 0.0);
    try std.testing.expect(product.noise_sigma[0] > 0.0);
    try std.testing.expect(product.jacobian != null);
    try std.testing.expectEqual(prepared.total_optical_depth, product.total_optical_depth);
    try std.testing.expectEqual(prepared.effective_air_mass_factor, product.effective_air_mass_factor);
    try std.testing.expectEqual(prepared.cia_optical_depth, product.cia_optical_depth);
    try std.testing.expect(product.effective_temperature_k > 0.0);
    try std.testing.expect(product.effective_pressure_hpa > 0.0);
}

test "measurement-space uses external high-resolution solar spectra when operational metadata provides one" {
    const operational_sigma = [_]f64{ 0.02, 0.02, 0.02 };
    const scene: Scene = .{
        .id = "measurement-operational-solar",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .operational,
            .noise_model = .s5p_operational,
            .ingested_noise_sigma = &operational_sigma,
            .reference_radiance = &.{ 1.0, 1.0, 1.0 },
            .operational_solar_spectrum = .{
                .wavelengths_nm = &[_]f64{ 405.0, 435.0, 465.0 },
                .irradiance = &[_]f64{ 1.0e14, 2.0e14, 3.0e14 },
            },
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(product.irradiance[0] < product.irradiance[1]);
    try std.testing.expect(product.irradiance[1] < product.irradiance[2]);
    try std.testing.expect(product.reflectance[0] > product.reflectance[2]);
}

test "measurement-space uses bundled O2A solar spectra when bundle_default is requested" {
    const scene: Scene = .{
        .id = "measurement-bundled-o2a-solar",
        .spectral_grid = .{
            .start_nm = 760.0,
            .end_nm = 770.0,
            .sample_count = 11,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .solar_spectrum_source = .bundle_default,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expect(product.irradiance[0] > product.irradiance[2]);
    try std.testing.expect(product.irradiance[2] < product.irradiance[5]);
    try std.testing.expect(product.irradiance[5] > product.irradiance[10]);
}

test "measurement-space operational integration uses high-resolution instrument sampling" {
    const operational_sigma = [_]f64{0.02} ** 12;
    const plain_scene: Scene = .{
        .id = "measurement-plain",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const operational_scene: Scene = .{
        .id = "measurement-operational",
        .spectral_grid = plain_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .ingested_noise_sigma = &operational_sigma,
        },
        .atmosphere = plain_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var plain_product = try simulateProduct(std.testing.allocator, &plain_scene, route, &prepared, testProviders());
    defer plain_product.deinit(std.testing.allocator);
    var operational_product = try simulateProduct(std.testing.allocator, &operational_scene, route, &prepared, testProviders());
    defer operational_product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(plain_product.wavelengths[0], operational_product.wavelengths[0], 1.0e-12);
    try std.testing.expect(operational_product.radiance[0] != plain_product.radiance[0]);
    try std.testing.expect(operational_product.irradiance[0] != plain_product.irradiance[0]);
    try std.testing.expect(operational_product.jacobian != null);
}

test "measurement-space honors explicit measured-channel wavelengths from ingest" {
    const sigma = [_]f64{ 0.02, 0.02, 0.02 };
    const measured_wavelengths = [_]f64{ 405.15, 434.85, 464.75 };
    const scene: Scene = .{
        .id = "measurement-measured-wavelength-axis",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.01,
            .measured_wavelengths_nm = &measured_wavelengths,
            .ingested_noise_sigma = &sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(@as(f64, 405.15), product.wavelengths[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 434.85), product.wavelengths[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 464.75), product.wavelengths[2], 1.0e-12);
}

test "measurement-space applies radiance calibration after instrument integration without rescaling irradiance" {
    const base_scene: Scene = .{
        .id = "measurement-calibration-base",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const calibrated_scene: Scene = .{
        .id = "measurement-calibration-adjusted",
        .spectral_grid = base_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .multiplicative_offset = 1.08,
            .stray_light = 0.03,
        },
        .atmosphere = base_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var base_product = try simulateProduct(std.testing.allocator, &base_scene, route, &prepared, testProviders());
    defer base_product.deinit(std.testing.allocator);
    var calibrated_product = try simulateProduct(std.testing.allocator, &calibrated_scene, route, &prepared, testProviders());
    defer calibrated_product.deinit(std.testing.allocator);

    try std.testing.expect(calibrated_product.radiance[0] > base_product.radiance[0]);
    try std.testing.expectApproxEqAbs(base_product.irradiance[0], calibrated_product.irradiance[0], 1.0e-12);
    try std.testing.expect(calibrated_product.reflectance[0] > base_product.reflectance[0]);
}

test "measurement-space propagates radiance pipeline corrections into routed jacobians" {
    const correction_wavelengths = [_]f64{405.0};
    const multiplicative_values = [_]f64{5.0};
    const stray_values = [_]f64{2.0};
    const base_pipeline: zdisamar.Instrument.MeasurementPipeline = .{
        .radiance = .{
            .explicit = true,
            .use_polarization_scrambler = true,
        },
    };
    const corrected_pipeline: zdisamar.Instrument.MeasurementPipeline = .{
        .radiance = .{
            .explicit = true,
            .simple_offsets = .{
                .multiplicative_percent = 1.0,
                .additive_percent_of_first = 0.5,
            },
            .spectral_features = .{
                .additive_amplitude_percent = 0.5,
                .additive_period_nm = 4.0,
                .multiplicative_amplitude_percent = 1.0,
                .multiplicative_period_nm = 4.0,
            },
            .smear_percent = 2.0,
            .multiplicative_nodes = .{
                .wavelengths_nm = correction_wavelengths[0..],
                .values = multiplicative_values[0..],
            },
            .stray_light_nodes = .{
                .wavelengths_nm = correction_wavelengths[0..],
                .values = stray_values[0..],
            },
            .use_polarization_scrambler = false,
        },
    };
    const base_scene: Scene = .{
        .id = "measurement-jacobian-base",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 409.0,
            .sample_count = 5,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .measurement_pipeline = base_pipeline,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const corrected_scene: Scene = .{
        .id = "measurement-jacobian-corrected",
        .spectral_grid = base_scene.spectral_grid,
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .measurement_pipeline = corrected_pipeline,
        },
        .atmosphere = base_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var base_product = try simulateProduct(std.testing.allocator, &base_scene, route, &prepared, testProviders());
    defer base_product.deinit(std.testing.allocator);
    var corrected_product = try simulateProduct(std.testing.allocator, &corrected_scene, route, &prepared, testProviders());
    defer corrected_product.deinit(std.testing.allocator);

    const base_jacobian = base_product.jacobian orelse return error.TestUnexpectedResult;
    const corrected_jacobian = corrected_product.jacobian orelse return error.TestUnexpectedResult;
    const expected_jacobian = try std.testing.allocator.dupe(f64, base_jacobian);
    defer std.testing.allocator.free(expected_jacobian);
    const scratch = try std.testing.allocator.alloc(f64, expected_jacobian.len);
    defer std.testing.allocator.free(scratch);

    try calibration.applySimpleOffsetDerivatives(corrected_pipeline.radiance.simple_offsets, expected_jacobian);
    try calibration.applySpectralFeatureDerivatives(
        corrected_pipeline.radiance.spectral_features,
        base_product.wavelengths,
        expected_jacobian,
    );
    try calibration.applySmear(corrected_pipeline.radiance.smear_percent, expected_jacobian, scratch);
    try calibration.applyMultiplicativeNodes(
        corrected_pipeline.radiance.multiplicative_nodes,
        base_product.wavelengths,
        expected_jacobian,
        scratch,
    );
    try calibration.applyStrayLightNodes(
        corrected_pipeline.radiance.stray_light_nodes,
        base_product.wavelengths,
        expected_jacobian,
        expected_jacobian,
        scratch,
    );
    try calibration.applyPolarizationScramblerBias(
        corrected_pipeline.radiance.use_polarization_scrambler,
        prepared.depolarization_factor,
        base_product.wavelengths,
        expected_jacobian,
    );

    for (expected_jacobian, corrected_jacobian) |expected, actual| {
        try std.testing.expectApproxEqRel(expected, actual, 1.0e-9);
    }
}

test "measurement-space materializes reflectance calibration sigma without channel-noise models" {
    const correction_wavelengths = [_]f64{405.0};
    const multiplicative_values = [_]f64{1.0};
    const scene: Scene = .{
        .id = "measurement-reflectance-calibration-sigma",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 409.0,
            .sample_count = 5,
        },
        .observation_model = .{
            .instrument = .synthetic,
            .regime = .nadir,
            .sampling = .native,
            .noise_model = .none,
            .measurement_pipeline = .{
                .reflectance_calibration = .{
                    .multiplicative_error = .{
                        .wavelengths_nm = correction_wavelengths[0..],
                        .values = multiplicative_values[0..],
                    },
                },
            },
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .none,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var product = try simulateProduct(std.testing.allocator, &scene, route, &prepared, testProviders());
    defer product.deinit(std.testing.allocator);

    try std.testing.expectEqual(product.reflectance.len, product.reflectance_noise_sigma.len);
    try std.testing.expectApproxEqRel(product.reflectance[0] * 0.01, product.reflectance_noise_sigma[0], 1.0e-9);
    try std.testing.expectApproxEqAbs(@as(f64, 0.0), product.noise_sigma[0], 1.0e-12);
}

test "measurement-space operational integration honors explicit isrf table weights" {
    const gaussian_sigma = [_]f64{0.02} ** 12;
    const gaussian_scene: Scene = .{
        .id = "measurement-operational-gaussian",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 465.0,
            .sample_count = 12,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .ingested_noise_sigma = &gaussian_sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    const table_scene: Scene = .{
        .id = "measurement-operational-table",
        .spectral_grid = gaussian_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = &[_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 },
                .weights = &[_]f64{ 0.08, 0.24, 0.36, 0.22, 0.10 },
            },
            .ingested_noise_sigma = &gaussian_sigma,
        },
        .atmosphere = gaussian_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var gaussian_product = try simulateProduct(std.testing.allocator, &gaussian_scene, route, &prepared, testProviders());
    defer gaussian_product.deinit(std.testing.allocator);
    var table_product = try simulateProduct(std.testing.allocator, &table_scene, route, &prepared, testProviders());
    defer table_product.deinit(std.testing.allocator);

    try std.testing.expect(table_product.radiance[0] != gaussian_product.radiance[0]);
    try std.testing.expect(table_product.irradiance[0] != gaussian_product.irradiance[0]);
    try std.testing.expect(table_product.jacobian != null);
}

test "measurement-space operational integration selects wavelength-indexed isrf rows" {
    const indexed_sigma = [_]f64{0.02} ** 3;
    const global_shape_scene: Scene = .{
        .id = "measurement-operational-global-shape",
        .spectral_grid = .{
            .start_nm = 405.0,
            .end_nm = 407.0,
            .sample_count = 3,
        },
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = .{
                .sample_count = 5,
                .offsets_nm = &[_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 },
                .weights = &[_]f64{ 0.08, 0.24, 0.36, 0.22, 0.10 },
            },
            .ingested_noise_sigma = &indexed_sigma,
        },
        .atmosphere = .{
            .layer_count = 2,
        },
    };
    var indexed_table_nominals = [_]f64{ 405.0, 406.0, 407.0 };
    var indexed_table_offsets = [_]f64{ -0.32, -0.16, 0.0, 0.16, 0.32 };
    var indexed_table_weights = [_]f64{
        0.08, 0.24, 0.36, 0.22, 0.10,
        0.18, 0.30, 0.30, 0.15, 0.07,
        0.05, 0.18, 0.34, 0.26, 0.17,
    };
    const indexed_table: zdisamar.InstrumentLineShapeTable = .{
        .nominal_count = 3,
        .sample_count = 5,
        .nominal_wavelengths_nm = indexed_table_nominals[0..],
        .offsets_nm = indexed_table_offsets[0..],
        .weights = indexed_table_weights[0..],
    };
    const indexed_table_scene: Scene = .{
        .id = "measurement-operational-indexed-table",
        .spectral_grid = global_shape_scene.spectral_grid,
        .observation_model = .{
            .instrument = .tropomi,
            .regime = .nadir,
            .sampling = .measured_channels,
            .noise_model = .snr_from_input,
            .wavelength_shift_nm = 0.018,
            .instrument_line_fwhm_nm = 0.54,
            .high_resolution_step_nm = 0.08,
            .high_resolution_half_span_nm = 0.32,
            .instrument_line_shape = global_shape_scene.observation_model.instrument_line_shape,
            .instrument_line_shape_table = indexed_table,
            .ingested_noise_sigma = &indexed_sigma,
        },
        .atmosphere = global_shape_scene.atmosphere,
    };
    const route = try common.prepareRoute(.{
        .regime = .nadir,
        .execution_mode = .scalar,
        .derivative_mode = .semi_analytical,
    });

    var prepared = try buildTestPreparedOpticalState(std.testing.allocator);
    defer prepared.deinit(std.testing.allocator);

    var global_shape_product = try simulateProduct(std.testing.allocator, &global_shape_scene, route, &prepared, testProviders());
    defer global_shape_product.deinit(std.testing.allocator);
    var indexed_table_product = try simulateProduct(std.testing.allocator, &indexed_table_scene, route, &prepared, testProviders());
    defer indexed_table_product.deinit(std.testing.allocator);

    try std.testing.expectApproxEqAbs(global_shape_product.radiance[0], indexed_table_product.radiance[0], 1e-12);
    try std.testing.expect(global_shape_product.radiance[1] != indexed_table_product.radiance[1]);
    try std.testing.expect(global_shape_product.radiance[2] != indexed_table_product.radiance[2]);
}
