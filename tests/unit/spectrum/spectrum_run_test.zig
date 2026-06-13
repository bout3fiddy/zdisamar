const std = @import("std");
const builtin = @import("builtin");
const internal = @import("internal");

const controls = internal.rtm.controls;
const jacobian_states = internal.rtm.jacobian_states;
const layer_depths = internal.optics.layer_depths;
const radiance_results = internal.spectrum.radiance_results;
const radiance_wavelengths = internal.spectrum.radiance_wavelengths;
const readers = internal.assets.readers;
const sampling_table = internal.spectrum.sampling_table;
const solve = internal.rtm.solve;
const solar_lookup = internal.spectrum.solar_lookup;
const solar_table = internal.setup.solar_table;
const spectrum_run = internal.spectrum.spectrum_run;

const public_python_baseline_path =
    "scratch/o2a-canonical-evidence/public-python-baseline.json";
const max_public_python_baseline_bytes: usize = 160 << 20;

test "preferred radiance worker count keeps small batches single-threaded" {
    try std.testing.expectEqual(
        @as(usize, 1),
        spectrum_run.preferredRadianceWorkerCount(spectrum_run.min_parallel_radiance_count - 1),
    );
}

test "radianceAtWavelength wires optics direct transport and radiance scaling" {
    const allocator = std.testing.allocator;
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(allocator);

    const support_count = tables.layers.support_mid_altitudes_km.len;
    const layer_count = tables.layers.layer_pressures_hpa.len;
    const line_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);

    const expected_support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(expected_support);
    const actual_support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(actual_support);
    const expected_layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(expected_layers);
    const actual_layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(actual_layers);
    const source_levels = try allocator.alloc(internal.optics.source_levels.SourceLevel, layer_count + 1);
    defer allocator.free(source_levels);
    const curved_samples = try allocator.alloc(internal.optics.curved_sun_path.CurvedSunPathSample, support_count);
    defer allocator.free(curved_samples);
    const curved_level_starts = try allocator.alloc(usize, layer_count + 1);
    defer allocator.free(curved_level_starts);
    const curved_level_altitudes = try allocator.alloc(f64, layer_count + 1);
    defer allocator.free(curved_level_altitudes);

    const wavelength_nm = 760.0;
    var case = internal.input.defaults.referenceCase();
    case.spectral_grid = .{
        .start_nm = wavelength_nm,
        .end_nm = wavelength_nm,
        .sample_count = 1,
    };
    var profile_lines = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
        allocator,
        case,
    );
    defer profile_lines.deinit(allocator);

    const surface_albedo = 0.4;
    const solar_irradiance = 141.5;
    const angles = solve.ViewAngles{
        .solar_mu = 0.62,
        .view_mu = 0.48,
        .relative_azimuth_rad = 0.35,
    };
    const solve_config = controls.SolveConfig{
        .derivative_mode = .none,
        .derivative_state_mask = 0,
        .controls = .{
            .scattering = .none,
            .integrate_source_function = false,
        },
    };

    try profile_lines.fillSupportLineSigmaAtWavelengthIndex(tables.layers, 0, line_sigma, null);
    try layer_depths.fillSupportOpticsAtWavelength(
        wavelength_nm,
        tables.layers,
        line_sigma,
        tables.cia,
        tables.aerosol,
        expected_support,
        null,
    );
    try layer_depths.reduceLayerOpticsFromSupportRows(tables.layers, expected_support, expected_layers, null);
    layer_depths.fillLayerAerosolJacobians(tables.aerosol, solve_config.derivative_state_mask, expected_layers);

    const expected_reflectance = solve.directSurfaceOnly(
        angles,
        surface_albedo,
        testTotalOpticalDepth(expected_layers),
        solve_config.derivative_mode,
        solve_config.derivative_state_mask,
    );
    const expected = radiance_results.scaleReflectanceToRadiance(
        solve_config,
        expected_reflectance,
        angles.solar_mu,
        solar_irradiance,
    );

    var memory = internal.cache.transport_worker_memory.TransportWorkerMemory{};
    const actual = try spectrum_run.radianceAtWavelength(
        wavelength_nm,
        0,
        angles,
        surface_albedo,
        tables.layers,
        profile_lines,
        tables.cia,
        tables.aerosol,
        tables.phase,
        solar_irradiance,
        solve_config,
        .{
            .line_sigma_cm2_per_molecule = line_sigma,
            .support = actual_support,
            .layers = actual_layers,
            .source_levels = source_levels,
            .curved_samples = curved_samples,
            .curved_level_starts = curved_level_starts,
            .curved_level_altitudes_km = curved_level_altitudes,
        },
        &memory,
    );

    try std.testing.expectApproxEqAbs(expected.radiance, actual.radiance, 1.0e-14);
    try std.testing.expectApproxEqAbs(expected.jacobian[0], actual.jacobian[0], 1.0e-14);
    try std.testing.expectApproxEqAbs(0.0, actual.jacobian[1], 0.0);
    try std.testing.expectApproxEqAbs(
        expected_layers[0].total_optical_depth,
        actual_layers[0].total_optical_depth,
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        expected_layers[1].total_optical_depth,
        actual_layers[1].total_optical_depth,
        0.0,
    );
    try std.testing.expectApproxEqAbs(
        expected_support[1].gas_scattering_optical_depth,
        actual_support[1].gas_scattering_optical_depth,
        0.0,
    );
}

test "radianceAtWavelength checks caller-owned row shapes" {
    const allocator = std.testing.allocator;
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(allocator);

    const support_count = tables.layers.support_mid_altitudes_km.len;
    const layer_count = tables.layers.layer_pressures_hpa.len;
    const line_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(line_sigma);
    @memset(line_sigma, 0.0);
    var case = internal.input.defaults.referenceCase();
    case.spectral_grid = .{
        .start_nm = 760.0,
        .end_nm = 760.0,
        .sample_count = 1,
    };
    var profile_lines = try internal.cache.profile_line_memory.buildO2ProfileLineValues(
        allocator,
        case,
    );
    defer profile_lines.deinit(allocator);
    const support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(support);
    const layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(layers);
    const source_levels = try allocator.alloc(internal.optics.source_levels.SourceLevel, layer_count + 1);
    defer allocator.free(source_levels);
    const curved_samples = try allocator.alloc(internal.optics.curved_sun_path.CurvedSunPathSample, support_count);
    defer allocator.free(curved_samples);
    const curved_level_starts = try allocator.alloc(usize, layer_count + 1);
    defer allocator.free(curved_level_starts);
    const short_curved_level_altitudes = try allocator.alloc(f64, layer_count);
    defer allocator.free(short_curved_level_altitudes);
    var memory = internal.cache.transport_worker_memory.TransportWorkerMemory{};

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.radianceAtWavelength(
            760.0,
            0,
            .{ .solar_mu = 0.62, .view_mu = 0.48 },
            0.4,
            tables.layers,
            profile_lines,
            tables.cia,
            tables.aerosol,
            tables.phase,
            141.5,
            .{ .controls = .{ .scattering = .none, .integrate_source_function = false } },
            .{
                .line_sigma_cm2_per_molecule = line_sigma,
                .support = support,
                .layers = layers,
                .source_levels = source_levels,
                .curved_samples = curved_samples,
                .curved_level_starts = curved_level_starts,
                .curved_level_altitudes_km = short_curved_level_altitudes,
            },
            &memory,
        ),
    );
}

test "radianceAtWavelength matches canonical transport probes" {
    const allocator = std.testing.allocator;
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(allocator);

    const support_count = tables.layers.support_mid_altitudes_km.len;
    const layer_count = tables.layers.layer_pressures_hpa.len;
    var profile_lines = try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengths(
        allocator,
        internal.input.defaults.referenceCase(),
        transport_probe_wavelengths_nm[0..],
    );
    defer profile_lines.deinit(allocator);

    const line_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(line_sigma);
    const support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(support);
    const layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(layers);
    const source_rows = try allocator.alloc(internal.optics.source_levels.SourceLevel, layer_count + 1);
    defer allocator.free(source_rows);
    const curved_samples = try allocator.alloc(internal.optics.curved_sun_path.CurvedSunPathSample, support_count);
    defer allocator.free(curved_samples);
    const curved_level_starts = try allocator.alloc(usize, layer_count + 1);
    defer allocator.free(curved_level_starts);
    const curved_level_altitudes = try allocator.alloc(f64, layer_count + 1);
    defer allocator.free(curved_level_altitudes);

    var memory = internal.cache.transport_worker_memory.TransportWorkerMemory{};
    defer memory.deinit(allocator);

    const case = internal.input.defaults.referenceCase();
    const solar_sin = @sin(std.math.degreesToRadians(case.geometry.solar_zenith_deg));
    const view_sin = @sin(std.math.degreesToRadians(case.geometry.viewing_zenith_deg));
    const angles = solve.ViewAngles{
        .solar_mu = @sqrt(@max(1.0 - solar_sin * solar_sin, 0.0)),
        .view_mu = @sqrt(@max(1.0 - view_sin * view_sin, 0.0)),

        .relative_azimuth_rad = std.math.degreesToRadians(@mod(180.0 - case.geometry.relative_azimuth_deg, 360.0)),
    };
    const solve_config = controls.SolveConfig{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth) |
            jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        .controls = .{
            .scattering = .multiple,
            .n_streams = @intCast(case.rtm.stream_count),
            .performance_thresholds = controls.PerformanceThresholds.o2a_default,
            .use_spherical_correction = case.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
    try memory.ensureCapacity(
        allocator,
        layer_count + 1,
        case.rtm.stream_count,
        40,
        40,
        true,
    );

    for (transport_probe_evidence, 0..) |expected, wavelength_index| {
        const solar_irradiance = try solar_lookup.irradianceAtWavelength(
            tables.solar,
            expected.wavelength_nm,
        );
        const scale = angles.solar_mu * solar_irradiance / std.math.pi;

        const actual = try spectrum_run.radianceAtWavelength(
            expected.wavelength_nm,
            wavelength_index,
            angles,
            expected.surface_albedo,
            tables.layers,
            profile_lines,
            tables.cia,
            tables.aerosol,
            tables.phase,
            solar_irradiance,
            solve_config,
            .{
                .line_sigma_cm2_per_molecule = line_sigma,
                .support = support,
                .layers = layers,
                .source_levels = source_rows,
                .curved_samples = curved_samples,
                .curved_level_starts = curved_level_starts,
                .curved_level_altitudes_km = curved_level_altitudes,
            },
            &memory,
        );

        try std.testing.expectApproxEqAbs(
            expected.reflectance,
            actual.radiance / scale,
            1.0e-13,
        );
        try std.testing.expectApproxEqRel(expected.radiance, actual.radiance, 1.0e-13);
        try std.testing.expectApproxEqRel(
            expected.aerosol_optical_depth_radiance_jacobian,
            actual.jacobian[0],
            radiance_jacobian_relative_tolerance,
        );
        try std.testing.expectApproxEqRel(
            expected.aerosol_layer_mid_pressure_radiance_jacobian,
            actual.jacobian[1],
            radiance_jacobian_relative_tolerance,
        );
        try std.testing.expectApproxEqAbs(
            expected.aerosol_optical_depth_reflectance_jacobian,
            actual.jacobian[0] / scale,
            1.0e-13,
        );
        try std.testing.expectApproxEqAbs(
            expected.aerosol_layer_mid_pressure_reflectance_jacobian,
            actual.jacobian[1] / scale,
            1.0e-13,
        );
    }
}

test "runO2ASpectrum matches canonical full spectrum" {
    if (builtin.mode == .Debug) return error.SkipZigTest;
    if (!std.process.hasEnvVarConstant("ZDISAMAR_RUN_FULL_SPECTRUM_CANONICAL")) return error.SkipZigTest;

    const allocator = std.testing.allocator;
    const evidence_bytes = try std.fs.cwd().readFileAlloc(
        allocator,
        public_python_baseline_path,
        max_public_python_baseline_bytes,
    );
    defer allocator.free(evidence_bytes);

    var baseline = try std.json.parseFromSlice(PublicPythonBaselineEvidence, allocator, evidence_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer baseline.deinit();
    const expected = baseline.value.spectrum.one_shot;

    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(allocator);

    const case = internal.input.defaults.referenceCase();
    var owned_sampling = try sampling_table.buildO2SpectrumSamplingTable(
        allocator,
        case,
        tables.instrument,
        tables.lines,
    );
    defer owned_sampling.deinit(allocator);
    const table = owned_sampling.view();

    var wavelengths = try radiance_wavelengths.buildRadianceWavelengthList(allocator, table);
    defer wavelengths.deinit(allocator);

    const exact_wavelengths_nm = try allocator.alloc(f64, wavelengths.wavelengths.len);
    defer allocator.free(exact_wavelengths_nm);
    for (wavelengths.wavelengths, exact_wavelengths_nm) |row, *wavelength_nm| {
        wavelength_nm.* = row.wavelength_nm;
    }

    var profile_lines =
        try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengthsWithCutoffGrid(
            allocator,
            case,
            exact_wavelengths_nm,
            exact_wavelengths_nm,
            true,
            true,
            null,
            1,
            &.{},
        );
    defer profile_lines.deinit(allocator);

    const support_count = tables.layers.support_mid_altitudes_km.len;
    const layer_count = tables.layers.layer_pressures_hpa.len;
    const product_count = table.rows.len;
    const dense_count = wavelengths.wavelengths.len;

    try std.testing.expectEqual(@as(usize, 701), expected.sample_count);
    try std.testing.expectEqual(expected.sample_count, product_count);
    try std.testing.expectEqual(expected.sample_count, expected.wavelength_nm.len);
    try std.testing.expectEqual(expected.sample_count, expected.radiance.len);
    try std.testing.expectEqual(expected.sample_count, expected.irradiance.len);
    try std.testing.expectEqual(expected.sample_count, expected.reflectance.len);
    try std.testing.expectEqual(
        expected.sample_count,
        expected.reflectance_jacobian.aerosol_optical_depth.len,
    );
    try std.testing.expectEqual(
        expected.sample_count,
        expected.reflectance_jacobian.aerosol_layer_mid_pressure_hpa.len,
    );
    try std.testing.expectEqual(@as(usize, 3874), dense_count);

    const dense = try allocator.alloc(radiance_results.RadianceResult, dense_count);
    defer allocator.free(dense);
    const product_wavelengths = try allocator.alloc(f64, product_count);
    defer allocator.free(product_wavelengths);
    const raw_radiance = try allocator.alloc(radiance_results.RadianceResult, product_count);
    defer allocator.free(raw_radiance);
    const raw_irradiance = try allocator.alloc(f64, product_count);
    defer allocator.free(raw_irradiance);
    const product_radiance = try allocator.alloc(radiance_results.RadianceResult, product_count);
    defer allocator.free(product_radiance);
    const product_irradiance = try allocator.alloc(f64, product_count);
    defer allocator.free(product_irradiance);
    const reflectance = try allocator.alloc(f64, product_count);
    defer allocator.free(reflectance);
    const jacobian = try allocator.alloc(jacobian_states.Vector, product_count);
    defer allocator.free(jacobian);
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(allocator);
    defer solar_memory.deinit();

    const solar_sin = @sin(std.math.degreesToRadians(case.geometry.solar_zenith_deg));
    const view_sin = @sin(std.math.degreesToRadians(case.geometry.viewing_zenith_deg));
    const angles = solve.ViewAngles{
        .solar_mu = @sqrt(@max(1.0 - solar_sin * solar_sin, 0.0)),
        .view_mu = @sqrt(@max(1.0 - view_sin * view_sin, 0.0)),

        .relative_azimuth_rad = std.math.degreesToRadians(@mod(180.0 - case.geometry.relative_azimuth_deg, 360.0)),
    };
    const solve_config = controls.SolveConfig{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth) |
            jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        .controls = .{
            .scattering = .multiple,
            .n_streams = @intCast(case.rtm.stream_count),
            .performance_thresholds = controls.PerformanceThresholds.o2a_default,
            .use_spherical_correction = case.geometry.pseudo_spherical,
            .integrate_source_function = true,
            .renorm_phase_function = true,
        },
    };
    const worker_count = spectrum_run.preferredRadianceWorkerCount(dense_count);
    var transport_workers = try prepareTransportWorkers(
        allocator,
        worker_count,
        support_count,
        layer_count,
        layer_count + 1,
        case.rtm.stream_count,
        40,
        40,
        true,
    );
    defer transport_workers.deinit(allocator);

    const summary = try spectrum_run.runO2ASpectrum(
        table,
        wavelengths.view(),
        angles,
        0.2,
        tables.layers,
        profile_lines,
        tables.cia,
        tables.aerosol,
        tables.phase,
        tables.solar,
        solve_config,
        .{},
        true,
        null,
        worker_count,
        .{
            .dense_radiance = dense,
            .wavelengths_nm = product_wavelengths,
            .raw_radiance = raw_radiance,
            .raw_irradiance = raw_irradiance,
            .radiance = product_radiance,
            .irradiance = product_irradiance,
            .reflectance = reflectance,
            .jacobian = jacobian,
        },
        transport_workers.workers,
        &solar_memory,
    );

    try std.testing.expectEqual(expected.sample_count, summary.sample_count);
    for (0..expected.sample_count) |index| {
        try expectFullSpectrumApproxAbs(
            "wavelength_nm",
            index,
            expected.wavelength_nm[index],
            expected.wavelength_nm[index],
            product_wavelengths[index],
            0.0,
        );
        try expectFullSpectrumApproxAbs(
            "reflectance",
            index,
            expected.wavelength_nm[index],
            expected.reflectance[index],
            reflectance[index],
            1.0e-13,
        );
        try expectFullSpectrumApproxAbs(
            "radiance",
            index,
            expected.wavelength_nm[index],
            expected.radiance[index],
            product_radiance[index].radiance,
            1.0e-13,
        );
        try expectFullSpectrumApproxAbs(
            "irradiance",
            index,
            expected.wavelength_nm[index],
            expected.irradiance[index],
            product_irradiance[index],
            1.0e-13,
        );
        try expectFullSpectrumApproxAbs(
            "aerosol_optical_depth_reflectance_jacobian",
            index,
            expected.wavelength_nm[index],
            expected.reflectance_jacobian.aerosol_optical_depth[index],
            jacobian[index][jacobian_states.stateIndex(.aerosol_optical_depth)],
            1.0e-13,
        );
        try expectFullSpectrumApproxAbs(
            "aerosol_layer_mid_pressure_hpa_reflectance_jacobian",
            index,
            expected.wavelength_nm[index],
            expected.reflectance_jacobian.aerosol_layer_mid_pressure_hpa[index],
            jacobian[index][jacobian_states.stateIndex(.aerosol_layer_mid_pressure_hpa)],
            1.0e-13,
        );
    }
}

test "runO2ASpectrum assembles direct-route product reflectance across workers" {
    const allocator = std.testing.allocator;
    var tables = try internal.setup.o2_run_tables.buildO2RunTables(
        allocator,
        internal.input.defaults.referenceCase(),
    );
    defer tables.deinit(allocator);

    var sampling_rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 758.0,
            .radiance_wavelength_nm = 758.0,
            .irradiance_wavelength_nm = 758.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
    };
    const table = sampling_table.SpectrumSamplingTable{ .rows = sampling_rows[0..] };
    var wavelengths = try radiance_wavelengths.buildRadianceWavelengthList(allocator, table);
    defer wavelengths.deinit(allocator);

    const exact_wavelengths_nm = [_]f64{ 758.0, 760.0 };
    const case = internal.input.defaults.referenceCase();
    var profile_lines = try internal.cache.profile_line_memory.buildO2ProfileLineValuesForWavelengths(
        allocator,
        case,
        exact_wavelengths_nm[0..],
    );
    defer profile_lines.deinit(allocator);

    const support_count = tables.layers.support_mid_altitudes_km.len;
    const layer_count = tables.layers.layer_pressures_hpa.len;
    const expected_line_sigma = try allocator.alloc(f64, support_count);
    defer allocator.free(expected_line_sigma);
    const expected_support = try allocator.alloc(layer_depths.SupportOptics, support_count);
    defer allocator.free(expected_support);
    const expected_layers = try allocator.alloc(layer_depths.LayerOptics, layer_count);
    defer allocator.free(expected_layers);

    var dense: [2]radiance_results.RadianceResult = undefined;
    var product_wavelengths: [2]f64 = undefined;
    var raw_radiance: [2]radiance_results.RadianceResult = undefined;
    var raw_irradiance: [2]f64 = undefined;
    var product_radiance: [2]radiance_results.RadianceResult = undefined;
    var product_irradiance: [2]f64 = undefined;
    var reflectance: [2]f64 = undefined;
    var jacobian: [2]jacobian_states.Vector = undefined;
    var transport_workers = try prepareTransportWorkers(
        allocator,
        2,
        support_count,
        layer_count,
        0,
        0,
        0,
        0,
        false,
    );
    defer transport_workers.deinit(allocator);
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(allocator);
    defer solar_memory.deinit();

    const angles = solve.ViewAngles{ .solar_mu = 0.62, .view_mu = 0.48 };
    const surface_albedo = 0.35;
    const solve_config = controls.SolveConfig{
        .derivative_mode = .none,
        .derivative_state_mask = 0,
        .controls = .{ .scattering = .none, .integrate_source_function = false },
    };

    const summary = try spectrum_run.runO2ASpectrum(
        table,
        wavelengths.view(),
        angles,
        surface_albedo,
        tables.layers,
        profile_lines,
        tables.cia,
        tables.aerosol,
        tables.phase,
        tables.solar,
        solve_config,
        .{},
        true,
        null,
        2,
        true,
        .{
            .dense_radiance = dense[0..],
            .wavelengths_nm = product_wavelengths[0..],
            .raw_radiance = raw_radiance[0..],
            .raw_irradiance = raw_irradiance[0..],
            .radiance = product_radiance[0..],
            .irradiance = product_irradiance[0..],
            .reflectance = reflectance[0..],
            .jacobian = jacobian[0..],
        },
        transport_workers.workers,
        &solar_memory,
    );

    var expected_reflectance_sum: f64 = 0.0;
    for (exact_wavelengths_nm, 0..) |wavelength_nm, wavelength_index| {
        try profile_lines.fillSupportLineSigmaAtWavelengthIndex(
            tables.layers,
            wavelength_index,
            expected_line_sigma,
            null,
        );
        try layer_depths.fillSupportOpticsAtWavelength(
            wavelength_nm,
            tables.layers,
            expected_line_sigma,
            tables.cia,
            tables.aerosol,
            expected_support,
            null,
        );
        try layer_depths.reduceLayerOpticsFromSupportRows(tables.layers, expected_support, expected_layers, null);
        layer_depths.fillLayerAerosolJacobians(tables.aerosol, solve_config.derivative_state_mask, expected_layers);

        const expected_transport = solve.directSurfaceOnly(
            angles,
            surface_albedo,
            testTotalOpticalDepth(expected_layers),
            solve_config.derivative_mode,
            solve_config.derivative_state_mask,
        );
        expected_reflectance_sum += expected_transport.reflectance;

        try std.testing.expectApproxEqAbs(wavelength_nm, product_wavelengths[wavelength_index], 0.0);
        try std.testing.expectApproxEqAbs(
            expected_transport.reflectance,
            reflectance[wavelength_index],
            1.0e-14,
        );
        try std.testing.expectApproxEqAbs(
            expected_transport.jacobian[0],
            jacobian[wavelength_index][0],
            1.0e-14,
        );
        try std.testing.expectApproxEqAbs(0.0, jacobian[wavelength_index][1], 0.0);
    }

    try std.testing.expectEqual(@as(usize, 2), summary.sample_count);
    try std.testing.expectApproxEqAbs(expected_reflectance_sum, summary.reflectance_sum, 1.0e-14);
}

test "gatherProductRows gathers radiance irradiance and active Jacobian lanes" {
    var rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
        .{
            .nominal_wavelength_nm = 761.0,
            .radiance_wavelength_nm = 761.0,
            .irradiance_wavelength_nm = 761.0,
            .radiance_integration = .{
                .side_start = 0,
                .sample_count = 2,
                .encoding = .side_samples,
            },
            .irradiance_integration = .{
                .side_start = 0,
                .sample_count = 2,
                .encoding = .side_samples,
            },
        },
    };
    const offsets = [_]f64{ -1.0, 1.0 };
    const weights = [_]f64{ 0.25, 0.75 };
    const table = sampling_table.SpectrumSamplingTable{
        .rows = &rows,
        .kernel_storage = .{
            .offsets_nm = offsets[0..],
            .weights = weights[0..],
        },
    };
    const sample_indices = [_]u32{ 1, 0, 2 };
    var row_refs = [_]radiance_wavelengths.RadianceSampleIndexRef{
        .{ .start = 0 },
        .{ .start = 1 },
    };
    var dense = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 200.0 } },
        .{ .radiance = 30.0, .jacobian = .{ 3.0, 300.0 } },
    };
    var solar_rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = 759.0, .irradiance = 100.0 },
        .{ .wavelength_nm = 760.0, .irradiance = 200.0 },
        .{ .wavelength_nm = 761.0, .irradiance = 300.0 },
        .{ .wavelength_nm = 762.0, .irradiance = 500.0 },
    };
    const solar = solar_table.SolarTable{
        .rows = solar_rows[0..],
        .spline_second_derivatives = &.{},
    };
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer solar_memory.deinit();

    var out_wavelengths: [2]f64 = undefined;
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    try spectrum_run.gatherProductRows(
        .{
            .derivative_mode = .semi_analytical,
            .derivative_state_mask = jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
        },
        table,
        .{
            .rows = row_refs[0..],
            .sample_indices = sample_indices[0..],
            .wavelengths = &.{},
        },
        dense[0..],
        solar,
        &solar_memory,
        out_wavelengths[0..],
        out_radiance[0..],
        out_irradiance[0..],
    );

    try std.testing.expectApproxEqAbs(760.0, out_wavelengths[0], 0.0);
    try std.testing.expectApproxEqAbs(761.0, out_wavelengths[1], 0.0);
    try std.testing.expectApproxEqAbs(20.0, out_radiance[0].radiance, 0.0);
    try std.testing.expectEqual(jacobian_states.Vector{ 2.0, 200.0 }, out_radiance[0].jacobian);
    try std.testing.expectApproxEqAbs(25.0, out_radiance[1].radiance, 0.0);
    try std.testing.expectApproxEqAbs(0.0, out_radiance[1].jacobian[0], 0.0);
    try std.testing.expectApproxEqAbs(250.0, out_radiance[1].jacobian[1], 0.0);
    try std.testing.expectApproxEqAbs(200.0, out_irradiance[0], 0.0);
    try std.testing.expectApproxEqAbs(425.0, out_irradiance[1], 0.0);
    try std.testing.expectEqual(@as(u32, 2), solar_memory.values.count());
}

test "gatherProductRows resets stale solar memory and rejects malformed shapes" {
    var rows = [_]sampling_table.SpectrumSamplingRow{
        .{
            .nominal_wavelength_nm = 760.0,
            .radiance_wavelength_nm = 760.0,
            .irradiance_wavelength_nm = 760.0,
            .radiance_integration = sampling_table.IntegrationKernelRef.disabled(),
            .irradiance_integration = sampling_table.IntegrationKernelRef.disabled(),
        },
    };
    const table = sampling_table.SpectrumSamplingTable{ .rows = &rows };
    const sample_indices = [_]u32{0};
    var row_refs = [_]radiance_wavelengths.RadianceSampleIndexRef{.{ .start = 0 }};
    var dense = [_]radiance_results.RadianceResult{.{ .radiance = 3.0 }};
    var solar_rows = [_]readers.SolarAssetRow{
        .{ .wavelength_nm = 760.0, .irradiance = 22.0 },
    };
    const solar = solar_table.SolarTable{
        .rows = solar_rows[0..],
        .spline_second_derivatives = &.{},
    };
    var solar_memory = internal.cache.solar_irradiance_memory.SolarIrradianceMemory.init(std.testing.allocator);
    defer solar_memory.deinit();
    try solar_memory.reserve(1);
    solar_memory.putAssumeCapacity(760.0, 999.0);

    var out_wavelengths: [1]f64 = undefined;
    var out_radiance: [1]radiance_results.RadianceResult = undefined;
    var out_irradiance: [1]f64 = undefined;
    try spectrum_run.gatherProductRows(
        .{},
        table,
        .{
            .rows = row_refs[0..],
            .sample_indices = sample_indices[0..],
            .wavelengths = &.{},
        },
        dense[0..],
        solar,
        &solar_memory,
        out_wavelengths[0..],
        out_radiance[0..],
        out_irradiance[0..],
    );

    try std.testing.expectApproxEqAbs(22.0, out_irradiance[0], 0.0);
    try std.testing.expectEqual(@as(u32, 1), solar_memory.values.count());

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.gatherProductRows(
            .{},
            table,
            .{
                .rows = &.{},
                .sample_indices = sample_indices[0..],
                .wavelengths = &.{},
            },
            dense[0..],
            solar,
            &solar_memory,
            out_wavelengths[0..],
            out_radiance[0..],
            out_irradiance[0..],
        ),
    );
}

test "postprocessAndAssembleProductRows carries integrated radiance irradiance and Jacobians" {
    const solve_config: controls.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_layer_mid_pressure_hpa),
    };
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 200.0 } },
    };
    const raw_irradiance = [_]f64{ 100.0, 200.0 };
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    var out_reflectance: [2]f64 = undefined;
    var out_jacobian: [2]jacobian_states.Vector = undefined;

    const summary = try spectrum_run.postprocessAndAssembleProductRows(
        solve_config,
        true,
        true,
        .{ .gain = 2.0, .offset = 1.0 },
        .{ .gain = 0.5, .offset = 2.0 },
        &.{},
        &.{},
        0.25,
        raw_radiance[0..],
        raw_irradiance[0..],
        out_radiance[0..],
        out_irradiance[0..],
        out_reflectance[0..],
        out_jacobian[0..],
    );

    const row0_scale = std.math.pi / (52.0 * 0.25);
    const row1_scale = std.math.pi / (102.0 * 0.25);
    try std.testing.expectApproxEqAbs(21.0, out_radiance[0].radiance, 0.0);
    try std.testing.expectEqual(jacobian_states.Vector{ 0.0, 200.0 }, out_radiance[0].jacobian);
    try std.testing.expectApproxEqAbs(41.0, out_radiance[1].radiance, 0.0);
    try std.testing.expectEqual(jacobian_states.Vector{ 0.0, 400.0 }, out_radiance[1].jacobian);
    try std.testing.expectEqual([2]f64{ 52.0, 102.0 }, out_irradiance);
    try std.testing.expectApproxEqAbs(21.0 * row0_scale, out_reflectance[0], 1.0e-14);
    try std.testing.expectApproxEqAbs(41.0 * row1_scale, out_reflectance[1], 1.0e-14);
    try std.testing.expectApproxEqAbs(0.0, out_jacobian[0][0], 0.0);
    try std.testing.expectApproxEqAbs(200.0 * row0_scale, out_jacobian[0][1], 1.0e-14);
    try std.testing.expectApproxEqAbs(0.0, out_jacobian[1][0], 0.0);
    try std.testing.expectApproxEqAbs(400.0 * row1_scale, out_jacobian[1][1], 1.0e-14);
    try std.testing.expectEqual(@as(usize, 2), summary.sample_count);
    try std.testing.expectApproxEqAbs(out_reflectance[0] + out_reflectance[1], summary.reflectance_sum, 1.0e-14);
}

test "postprocessAndAssembleProductRows convolves non-integrated product rows" {
    const solve_config: controls.SolveConfig = .{
        .derivative_mode = .semi_analytical,
        .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth),
    };
    const kernel = [_]f64{ 1.0, 1.0, 1.0 };
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0, .jacobian = .{ 1.0, 100.0 } },
        .{ .radiance = 20.0, .jacobian = .{ 2.0, 200.0 } },
        .{ .radiance = 40.0, .jacobian = .{ 4.0, 400.0 } },
    };
    const raw_irradiance = [_]f64{ 100.0, 200.0, 300.0 };
    var out_radiance: [3]radiance_results.RadianceResult = undefined;
    var out_irradiance: [3]f64 = undefined;
    var out_reflectance: [3]f64 = undefined;
    var out_jacobian: [3]jacobian_states.Vector = undefined;

    const summary = try spectrum_run.postprocessAndAssembleProductRows(
        solve_config,
        false,
        false,
        .{},
        .{},
        kernel[0..],
        kernel[0..],
        0.5,
        raw_radiance[0..],
        raw_irradiance[0..],
        out_radiance[0..],
        out_irradiance[0..],
        out_reflectance[0..],
        out_jacobian[0..],
    );

    const expected_radiance = [_]f64{ 15.0, 70.0 / 3.0, 30.0 };
    const expected_irradiance = [_]f64{ 150.0, 200.0, 250.0 };
    const expected_jacobian = [_]f64{ 1.5, 7.0 / 3.0, 3.0 };
    for (expected_radiance, expected_irradiance, expected_jacobian, 0..) |radiance, irradiance, jacobian, index| {
        const scale = std.math.pi / (irradiance * 0.5);
        try std.testing.expectApproxEqAbs(radiance, out_radiance[index].radiance, 1.0e-14);
        try std.testing.expectApproxEqAbs(jacobian, out_radiance[index].jacobian[0], 1.0e-14);
        try std.testing.expectApproxEqAbs(0.0, out_radiance[index].jacobian[1], 0.0);
        try std.testing.expectApproxEqAbs(irradiance, out_irradiance[index], 1.0e-14);
        try std.testing.expectApproxEqAbs(radiance * scale, out_reflectance[index], 1.0e-14);
        try std.testing.expectApproxEqAbs(jacobian * scale, out_jacobian[index][0], 1.0e-14);
        try std.testing.expectApproxEqAbs(0.0, out_jacobian[index][1], 0.0);
    }
    try std.testing.expectEqual(@as(usize, 3), summary.sample_count);
    try std.testing.expectApproxEqAbs(15.0 + 70.0 / 3.0 + 30.0, summary.radiance_sum, 1.0e-14);
}

test "postprocessAndAssembleProductRows rejects inconsistent product shapes" {
    const raw_radiance = [_]radiance_results.RadianceResult{
        .{ .radiance = 10.0 },
        .{ .radiance = 20.0 },
    };
    const raw_irradiance = [_]f64{100.0};
    const full_raw_irradiance = [_]f64{ 100.0, 200.0 };
    var out_radiance: [2]radiance_results.RadianceResult = undefined;
    var out_irradiance: [2]f64 = undefined;
    var out_reflectance: [2]f64 = undefined;
    var out_jacobian: [2]jacobian_states.Vector = undefined;

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.postprocessAndAssembleProductRows(
            .{},
            true,
            true,
            .{},
            .{},
            &.{},
            &.{},
            1.0,
            raw_radiance[0..],
            raw_irradiance[0..],
            out_radiance[0..],
            out_irradiance[0..],
            out_reflectance[0..],
            out_jacobian[0..],
        ),
    );

    try std.testing.expectError(
        error.ShapeMismatch,
        spectrum_run.postprocessAndAssembleProductRows(
            .{
                .derivative_mode = .semi_analytical,
                .derivative_state_mask = jacobian_states.stateMask(.aerosol_optical_depth),
            },
            true,
            true,
            .{},
            .{},
            &.{},
            &.{},
            1.0,
            raw_radiance[0..],
            full_raw_irradiance[0..],
            out_radiance[0..],
            out_irradiance[0..],
            out_reflectance[0..],
            &.{},
        ),
    );
}

// TransportProbeEvidence -------------------------------------------------------------------------------------|
// One-wavelength transport result at one O2 A probe wavelength.                                               |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 64 B (0.062 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] wavelength_nm                                      : f64                                           |
// [ 8..15] surface_albedo                                     : f64                                           |
// [16..23] reflectance                                        : f64                                           |
// [24..31] radiance                                           : f64                                           |
// [32..39] aerosol_optical_depth_reflectance_jacobian         : f64                                           |
// [40..47] aerosol_layer_mid_pressure_reflectance_jacobian    : f64                                           |
// [48..55] aerosol_optical_depth_radiance_jacobian            : f64                                           |
// [56..63] aerosol_layer_mid_pressure_radiance_jacobian       : f64                                           |
const TransportProbeEvidence = struct {
    wavelength_nm: f64,
    surface_albedo: f64,
    reflectance: f64,
    radiance: f64,
    aerosol_optical_depth_reflectance_jacobian: f64,
    aerosol_layer_mid_pressure_reflectance_jacobian: f64,
    aerosol_optical_depth_radiance_jacobian: f64,
    aerosol_layer_mid_pressure_radiance_jacobian: f64,
};
// ------------------------------------------------------------------------------------------------------------|

// Canonical expected values for configured forward inputs, transport, and radiance scaling.
const transport_probe_evidence = [_]TransportProbeEvidence{
    .{
        .wavelength_nm = 758.0,
        .surface_albedo = 0.2,
        .reflectance = 2.29993940259671200e-1,
        .radiance = 1.79116911721170940e13,
        .aerosol_optical_depth_reflectance_jacobian = 1.18128432103037900e-1,
        .aerosol_layer_mid_pressure_reflectance_jacobian = 1.73670761003215180e-4,
        .aerosol_optical_depth_radiance_jacobian = 9.19972061910463900e12,
        .aerosol_layer_mid_pressure_radiance_jacobian = 1.35252999848779320e10,
    },
    .{
        .wavelength_nm = 760.0,
        .surface_albedo = 0.2,
        .reflectance = 4.44799106979073100e-2,
        .radiance = 3.45040801666285840e12,
        .aerosol_optical_depth_reflectance_jacobian = 9.43744316080887100e-2,
        .aerosol_layer_mid_pressure_reflectance_jacobian = 4.79663021351987800e-3,
        .aerosol_optical_depth_radiance_jacobian = 7.32083968423682500e12,
        .aerosol_layer_mid_pressure_radiance_jacobian = 3.72085534391032900e11,
    },
    .{
        .wavelength_nm = 765.0,
        .surface_albedo = 0.2,
        .reflectance = 1.55241963571654300e-1,
        .radiance = 1.16969133634011620e13,
        .aerosol_optical_depth_reflectance_jacobian = 1.18268436065057520e-1,
        .aerosol_layer_mid_pressure_reflectance_jacobian = 1.41979287256224840e-3,
        .aerosol_optical_depth_radiance_jacobian = 8.91109348561807600e12,
        .aerosol_layer_mid_pressure_radiance_jacobian = 1.06976192791260220e11,
    },
    .{
        .wavelength_nm = 767.0,
        .surface_albedo = 0.2,
        .reflectance = 2.21472234161068870e-1,
        .radiance = 1.70104200086156910e13,
        .aerosol_optical_depth_reflectance_jacobian = 1.18482166027144400e-1,
        .aerosol_layer_mid_pressure_reflectance_jacobian = 2.52173955696529250e-4,
        .aerosol_optical_depth_radiance_jacobian = 9.10015386482493400e12,
        .aerosol_layer_mid_pressure_radiance_jacobian = 1.93684997032736200e10,
    },
    .{
        .wavelength_nm = 776.0,
        .surface_albedo = 0.2,
        .reflectance = 2.33612924092933000e-1,
        .radiance = 1.77817953692175300e13,
        .aerosol_optical_depth_reflectance_jacobian = 1.18064267591028280e-1,
        .aerosol_layer_mid_pressure_reflectance_jacobian = 1.26237327430141310e-4,
        .aerosol_optical_depth_radiance_jacobian = 8.98663742544077300e12,
        .aerosol_layer_mid_pressure_radiance_jacobian = 9.60874203786223200e9,
    },
};

const transport_probe_wavelengths_nm = [_]f64{ 758.0, 760.0, 765.0, 767.0, 776.0 };

// Radiance Jacobian rows are scaled diagnostics; reflectance/radiance outputs use
// 1e-13 tolerances and Jacobians also pin reflectance space at 1e-13 absolute.
const radiance_jacobian_relative_tolerance: f64 = 1.0e-10;

fn expectFullSpectrumApproxAbs(
    column_name: []const u8,
    index: usize,
    wavelength_nm: f64,
    expected: f64,
    actual: f64,
    tolerance: f64,
) !void {
    // expectFullSpectrumApproxAbs ----------------------------------------------------------------------------|
    // Report the exact full-spectrum row and column when the opt-in integrated transport gate fails.          |
    // --------------------------------------------------------------------------------------------------------|
    if (!std.math.approxEqAbs(f64, expected, actual, tolerance)) {
        std.debug.print(
            "full-spectrum mismatch column={s} index={} wavelength_nm={d:.17} expected={d:.17} actual={d:.17} " ++
                "delta={e:.17} tolerance={e:.17}\n",
            .{ column_name, index, wavelength_nm, expected, actual, actual - expected, tolerance },
        );
        return error.TestExpectedApproxEqAbs;
    }
}

// PublicPythonBaselineEvidence -------------------------------------------------------------------------------|
// Minimal typed view of the O2 A public Python baseline JSON used by the full-spectrum canonical test.        |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 312 B (0.305 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..311] spectrum: PublicPythonSpectrumEvidence                                                           |
const PublicPythonBaselineEvidence = struct {
    spectrum: PublicPythonSpectrumEvidence,
};
// ------------------------------------------------------------------------------------------------------------|

// PublicPythonSpectrumEvidence -------------------------------------------------------------------------------|
// Spectrum run variants recorded by the O2 A public Python baseline.                                          |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 312 B (0.305 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [  0..103] one_shot      : FullSpectrumEvidence                                                             |
// [104..207] session_first : FullSpectrumEvidence                                                             |
// [208..311] session_second: FullSpectrumEvidence                                                             |
const PublicPythonSpectrumEvidence = struct {
    one_shot: FullSpectrumEvidence,
    session_first: FullSpectrumEvidence = .{},
    session_second: FullSpectrumEvidence = .{},
};
// ------------------------------------------------------------------------------------------------------------|

// FullSpectrumEvidence ---------------------------------------------------------------------------------------|
// One 701-row public spectrum and its two requested reflectance-Jacobian columns.                             |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 104 B (0.102 KiB), align: 8 B                                                                         |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] wavelength_nm        : []f64                                                                       |
// [16..31] radiance             : []f64                                                                       |
// [32..47] irradiance           : []f64                                                                       |
// [48..63] reflectance          : []f64                                                                       |
// [64..95] reflectance_jacobian : FullSpectrumReflectanceJacobianEvidence                                     |
// [96..103] sample_count        : usize                                                                       |
const FullSpectrumEvidence = struct {
    wavelength_nm: []f64 = &.{},
    radiance: []f64 = &.{},
    irradiance: []f64 = &.{},
    reflectance: []f64 = &.{},
    reflectance_jacobian: FullSpectrumReflectanceJacobianEvidence = .{},
    sample_count: usize = 0,
};
// ------------------------------------------------------------------------------------------------------------|

// FullSpectrumReflectanceJacobianEvidence --------------------------------------------------------------------|
// Two reflectance-space Jacobian columns requested by the O2 A public baseline capture.                       |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0..15] aerosol_optical_depth            : []f64                                                           |
// [16..31] aerosol_layer_mid_pressure_hpa   : []f64                                                           |
const FullSpectrumReflectanceJacobianEvidence = struct {
    aerosol_optical_depth: []f64 = &.{},
    aerosol_layer_mid_pressure_hpa: []f64 = &.{},
};
// ------------------------------------------------------------------------------------------------------------|

fn prepareTransportWorkers(
    allocator: std.mem.Allocator,
    worker_count: usize,
    support_count: usize,
    layer_count: usize,
    level_count: usize,
    stream_count: usize,
    phase_stride: usize,
    fourier_basis_count: usize,
    needs_local_sum: bool,
) !internal.cache.transport_worker_memory.TransportWorkerMemoryCollection {
    // prepareTransportWorkers ------------------------------------------------------------------------------- |
    // Allocate the same worker-local optics and LABOS rows that root reserves before spectrum prefetch.       |
    // --------------------------------------------------------------------------------------------------------|
    var collection = internal.cache.transport_worker_memory.TransportWorkerMemoryCollection{};
    errdefer collection.deinit(allocator);

    try collection.ensureWorkerCount(allocator, worker_count);
    for (collection.workers[0..worker_count]) |*worker_memory| {
        try worker_memory.ensureOpticsCapacity(allocator, support_count, layer_count);
        if (stream_count != 0) {
            try worker_memory.ensureCapacity(
                allocator,
                level_count,
                stream_count,
                phase_stride,
                fourier_basis_count,
                needs_local_sum,
            );
        }
    }

    return collection;
}

fn testTotalOpticalDepth(layers: []const layer_depths.LayerOptics) f64 {
    // testTotalOpticalDepth ----------------------------------------------------------------------------------|
    // Test-local uses of the scalar direct-route reduction used by LABOS.                                     |
    // --------------------------------------------------------------------------------------------------------|
    var total: f64 = 0.0;
    for (layers) |layer| total += layer.total_optical_depth;
    return total;
}
