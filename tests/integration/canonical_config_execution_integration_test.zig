const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");

fn makeOutputRoot(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/canonical-config-exec/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn replaceAllAlloc(
    allocator: std.mem.Allocator,
    haystack: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    var output = std.ArrayList(u8).empty;
    defer output.deinit(allocator);

    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, haystack, cursor, needle)) |match_index| {
        try output.appendSlice(allocator, haystack[cursor..match_index]);
        try output.appendSlice(allocator, replacement);
        cursor = match_index + needle.len;
    }
    try output.appendSlice(allocator, haystack[cursor..]);
    return output.toOwnedSlice(allocator);
}

fn coarsenTwinExampleYaml(
    allocator: std.mem.Allocator,
    source: []const u8,
) ![]u8 {
    // Keep the twin-example routing coverage in `test-fast`, but avoid running
    // the full-resolution scientific example under DebugAllocator.
    const fewer_layers = try replaceAllAlloc(allocator, source, "layer_count: 48", "layer_count: 6");
    defer allocator.free(fewer_layers);
    const fewer_samples = try replaceAllAlloc(allocator, fewer_layers, "step_nm: 0.01", "step_nm: 0.50");
    defer allocator.free(fewer_samples);
    return replaceAllAlloc(allocator, fewer_samples, "max_iterations: 8", "max_iterations: 2");
}

fn executeResolvedSource(
    source_name: []const u8,
    base_dir: []const u8,
    source: []const u8,
    engine: *zdisamar.Engine,
) !struct { program: zdisamar.canonical_config.ExecutionProgram, outcome: zdisamar.canonical_config.ExecutionOutcome } {
    var document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        source_name,
        base_dir,
        source,
    );
    defer document.deinit();

    var resolved: ?*zdisamar.canonical_config.ResolvedExperiment = try document.resolve(std.testing.allocator);
    errdefer if (resolved) |owned| owned.deinit();
    const program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, resolved.?);
    resolved = null;
    errdefer {
        var owned = program;
        owned.deinit();
    }
    const outcome = try program.execute(std.testing.allocator, engine);
    return .{ .program = program, .outcome = outcome };
}

fn simulateSceneProduct(
    allocator: std.mem.Allocator,
    plan: *const zdisamar.PreparedPlan,
    scene: zdisamar.Scene,
) !internal.kernels.transport.measurement.MeasurementSpaceProduct {
    var prepared_optics = try plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);
    return internal.kernels.transport.measurement.simulateProduct(
        allocator,
        &scene,
        plan.transport_route,
        &prepared_optics,
        .{
            .transport = plan.providers.transport,
            .surface = plan.providers.surface,
            .instrument = plan.providers.instrument,
            .noise = plan.providers.noise,
        },
    );
}

test "canonical execution runs a forward-only program and writes outputs" {
    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("forward", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const yaml = try std.fmt.allocPrint(
        std.testing.allocator,
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: forward-only
        \\  workspace: exec-forward
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 60.0
        \\        viewing_zenith_deg: 30.0
        \\        relative_azimuth_deg: 120.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 12
        \\      bands:
        \\        band_1:
        \\          start_nm: 760.8
        \\          end_nm: 761.2
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.20
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\
        \\experiment:
        \\  simulation:
        \\    from: base
        \\    scene:
        \\      id: truth_scene
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\
        \\outputs:
        \\  - from: truth_radiance
        \\    format: netcdf_cf
        \\    destination_uri: file://{s}/truth.nc
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ,
        .{root},
    );
    defer std.testing.allocator.free(yaml);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("forward.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), execution.outcome.stage_outcomes.len);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.measurement_space_product != null);
    try std.testing.expectEqual(@as(usize, 1), execution.outcome.outputs.len);
    const truth_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/truth.nc", .{root});
    defer std.testing.allocator.free(truth_path);
    try std.fs.cwd().access(truth_path, .{});
}

test "canonical execution applies deterministic stage noise when requested" {
    const base_yaml =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: stage-noise
        \\  workspace: exec-stage-noise
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 60.0
        \\        viewing_zenith_deg: 30.0
        \\        relative_azimuth_deg: 120.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 12
        \\      bands:
        \\        band_1:
        \\          start_nm: 760.8
        \\          end_nm: 761.2
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.20
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\        noise:
        \\          model: shot_noise
        \\          seed: 12345
        \\
        \\experiment:
        \\  simulation:
        \\    from: base
        \\    scene:
        \\      id: truth_scene
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\        apply_noise: false
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    const noisy_yaml = try replaceAllAlloc(
        std.testing.allocator,
        base_yaml,
        "apply_noise: false",
        "apply_noise: true",
    );
    defer std.testing.allocator.free(noisy_yaml);

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const clean_execution = try executeResolvedSource("clean.yaml", ".", base_yaml, &engine);
    defer {
        var outcome = clean_execution.outcome;
        outcome.deinit();
        var program = clean_execution.program;
        program.deinit();
    }

    const noisy_execution_a = try executeResolvedSource("noisy-a.yaml", ".", noisy_yaml, &engine);
    defer {
        var outcome = noisy_execution_a.outcome;
        outcome.deinit();
        var program = noisy_execution_a.program;
        program.deinit();
    }

    const noisy_execution_b = try executeResolvedSource("noisy-b.yaml", ".", noisy_yaml, &engine);
    defer {
        var outcome = noisy_execution_b.outcome;
        outcome.deinit();
        var program = noisy_execution_b.program;
        program.deinit();
    }

    const clean = clean_execution.outcome.stage_outcomes[0].result.measurement_space_product.?;
    const noisy_a = noisy_execution_a.outcome.stage_outcomes[0].result.measurement_space_product.?;
    const noisy_b = noisy_execution_b.outcome.stage_outcomes[0].result.measurement_space_product.?;
    const noisy_a_summary = noisy_execution_a.outcome.stage_outcomes[0].result.measurement_space.?;
    const noisy_b_summary = noisy_execution_b.outcome.stage_outcomes[0].result.measurement_space.?;

    try std.testing.expectEqual(clean.radiance.len, noisy_a.radiance.len);
    try std.testing.expectEqualSlices(f64, noisy_a.radiance, noisy_b.radiance);
    try std.testing.expectEqualSlices(f64, noisy_a.reflectance, noisy_b.reflectance);
    try std.testing.expectEqualSlices(f64, clean.noise_sigma, noisy_a.noise_sigma);
    try std.testing.expectEqual(noisy_a.summary.sample_count, noisy_a_summary.sample_count);
    try std.testing.expectApproxEqAbs(noisy_a.summary.mean_radiance, noisy_a_summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(noisy_a.summary.mean_reflectance, noisy_a_summary.mean_reflectance, 1.0e-12);
    try std.testing.expectApproxEqAbs(noisy_b.summary.mean_radiance, noisy_b_summary.mean_radiance, 1.0e-12);
    try std.testing.expectApproxEqAbs(noisy_b.summary.mean_reflectance, noisy_b_summary.mean_reflectance, 1.0e-12);

    var found_delta = false;
    for (clean.radiance, noisy_a.radiance) |clean_value, noisy_value| {
        if (!std.math.approxEqAbs(f64, clean_value, noisy_value, 1.0e-12)) {
            found_delta = true;
            break;
        }
    }
    try std.testing.expect(found_delta);
}

test "canonical execution stores synthesized fallback sigma when apply_noise has no source sigma" {
    const yaml =
        \\schema_version: 1
        \\metadata:
        \\  id: fallback-noise
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 35.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 12
        \\      bands:
        \\        band_1:
        \\          start_nm: 760.8
        \\          end_nm: 761.2
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: line_by_line
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.20
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\
        \\experiment:
        \\  simulation:
        \\    from: base
        \\    scene:
        \\      id: truth_scene
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\        apply_noise: true
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("fallback-noise.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    const product = execution.outcome.stage_outcomes[0].result.measurement_space_product.?;
    try std.testing.expectEqual(product.radiance.len, product.noise_sigma.len);
    try std.testing.expectEqual(product.radiance.len, product.radiance_noise_sigma.len);
    try std.testing.expect(product.noise_sigma[0] > 0.0);
    try std.testing.expect(product.radiance_noise_sigma[0] > 0.0);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.measurement_space.?.mean_noise_sigma > 0.0);
}

test "canonical execution resolves measured-channel observation config from ingest support data" {
    const yaml =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: measured-support-data
        \\  workspace: exec-measured
        \\
        \\inputs:
        \\  assets:
        \\    isrf_metadata:
        \\      kind: file
        \\      path: data/examples/irr_rad_channels_operational_isrf_table_demo.txt
        \\      format: spectral_ascii
        \\    refspec_metadata:
        \\      kind: file
        \\      path: data/examples/irr_rad_channels_operational_refspec_demo.txt
        \\      format: spectral_ascii
        \\  ingests:
        \\    isrf_demo:
        \\      adapter: spectral_ascii
        \\      asset: isrf_metadata
        \\    refspec_demo:
        \\      adapter: spectral_ascii
        \\      asset: refspec_metadata
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: none
        \\    scene:
        \\      geometry:
        \\        model: pseudo_spherical
        \\        solar_zenith_deg: 31.7
        \\        viewing_zenith_deg: 7.9
        \\        relative_azimuth_deg: 143.4
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 16
        \\      bands:
        \\        o2a:
        \\          start_nm: 760.8
        \\          end_nm: 761.2
        \\          step_nm: 0.2
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.06
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\        sampling:
        \\          mode: measured_channels
        \\          high_resolution_step_nm: 0.08
        \\          high_resolution_half_span_nm: 0.32
        \\        spectral_response:
        \\          shape: table
        \\          table:
        \\            from_ingest: isrf_demo.instrument_line_shape_table
        \\        illumination:
        \\          solar_spectrum:
        \\            from_ingest: refspec_demo.operational_solar_spectrum
        \\        supporting_data:
        \\          weighted_reference_grid:
        \\            from_ingest: refspec_demo.operational_refspec_grid
        \\        calibration:
        \\          wavelength_shift_nm: 0.0
        \\          multiplicative_offset: 1.0
        \\          stray_light: 0.0
        \\        noise:
        \\          model: shot_noise
        \\
        \\experiment:
        \\  simulation:
        \\    from: base
        \\    scene:
        \\      id: measured_scene
        \\    products:
        \\      truth_radiance:
        \\        kind: measurement_space
        \\        observable: radiance
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
        \\  require_resolved_stage_references: true
    ;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("measured-support.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    const scene = execution.program.stages[0].stage.scene;
    try std.testing.expectEqual(zdisamar.Instrument.SamplingMode.measured_channels, scene.observation_model.sampling);
    try std.testing.expect(scene.observation_model.instrument_line_shape_table.nominal_count > 0);
    try std.testing.expect(scene.observation_model.operational_solar_spectrum.enabled());
    try std.testing.expect(scene.observation_model.operational_refspec_grid.enabled());
    try std.testing.expectEqual(@as(usize, 1), execution.outcome.stage_outcomes.len);
    const product = execution.outcome.stage_outcomes[0].result.measurement_space_product.?;
    try std.testing.expectEqual(@as(usize, 3), product.wavelengths.len);
}

test "canonical execution hydrates ingest-backed radiance observations onto the ingest channel grid" {
    const yaml =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: ingest-retrieval
        \\  workspace: exec-ingest-retrieval
        \\
        \\inputs:
        \\  assets:
        \\    observed_input:
        \\      kind: file
        \\      path: data/examples/irr_rad_channels_demo.txt
        \\      format: spectral_ascii
        \\  ingests:
        \\    observed:
        \\      adapter: spectral_ascii
        \\      asset: observed_input
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: semi_analytical
        \\    scene:
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 16
        \\      bands:
        \\        band_1:
        \\          start_nm: 405.0
        \\          end_nm: 406.0
        \\          step_nm: 0.25
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: tropomi
        \\        sampling:
        \\          mode: native
        \\        noise:
        \\          model: snr_from_input
        \\
        \\experiment:
        \\  retrieval:
        \\    from: base
        \\    scene:
        \\      id: ingest_retrieval_scene
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\      measurement:
        \\        source: observed.radiance
        \\        observable: radiance
        \\        mask:
        \\          exclude:
        \\            - [405.45, 405.55]
        \\        error_model:
        \\          from_source_noise: true
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
        \\            sigma: 0.02
        \\    products:
        \\      fitted_radiance:
        \\        kind: fitted_measurement
        \\      jacobian:
        \\        kind: jacobian
        \\      averaging_kernel:
        \\        kind: averaging_kernel
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const execution = try executeResolvedSource("ingest-retrieval.yaml", ".", yaml, &engine);
    defer {
        var outcome = execution.outcome;
        outcome.deinit();
        var program = execution.program;
        program.deinit();
    }

    try std.testing.expectEqual(zdisamar.Result.Status.success, execution.outcome.stage_outcomes[0].result.status);
    try std.testing.expectEqual(zdisamar.DataBindingKind.ingest, execution.program.stages[0].stage.inverse.?.measurements.source.kind());
    try std.testing.expectEqual(zdisamar.Instrument.SamplingMode.measured_channels, execution.program.stages[0].stage.scene.observation_model.sampling);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval != null);
    try std.testing.expectEqual(@as(u32, 2), execution.outcome.stage_outcomes[0].result.retrieval.?.observed_measurement.?.sample_count);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval.?.jacobian != null);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval.?.averaging_kernel != null);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval.?.posterior_covariance != null);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval_products.jacobian != null);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval_products.averaging_kernel != null);
    try std.testing.expect(execution.outcome.stage_outcomes[0].result.retrieval_products.posterior_covariance != null);
}

test "canonical execution rejects retrieval-only external observations without an explicit measurement binding" {
    const yaml =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: retrieval-only
        \\  workspace: exec-retrieval
        \\
        \\templates:
        \\  base:
        \\    plan:
        \\      model_family: disamar_standard
        \\      transport:
        \\        solver: dispatcher
        \\      execution:
        \\        solver_mode: scalar
        \\        derivative_mode: semi_analytical
        \\    scene:
        \\      geometry:
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 16
        \\      bands:
        \\        band_1:
        \\          start_nm: 405.0
        \\          end_nm: 465.0
        \\          step_nm: 2.5
        \\      absorbers:
        \\        o2:
        \\          species: o2
        \\          spectroscopy:
        \\            model: cross_sections
        \\      surface:
        \\        model: lambertian
        \\        albedo: 0.05
        \\      measurement_model:
        \\        regime: nadir
        \\        instrument:
        \\          name: synthetic
        \\        sampling:
        \\          mode: native
        \\
        \\experiment:
        \\  retrieval:
        \\    from: base
        \\    scene:
        \\      id: retrieval_scene
        \\    inverse:
        \\      algorithm:
        \\        name: oe
        \\        provider: builtin.oe_solver
        \\      measurement:
        \\        source: observed_radiance
        \\        observable: radiance
        \\      state:
        \\        surface_albedo:
        \\          target: scene.surface.albedo
        \\          prior:
        \\            mean: 0.05
        \\            sigma: 0.02
        \\        aerosol_tau:
        \\          target: scene.aerosols.plume.optical_depth_550_nm
        \\          prior:
        \\            mean: 0.10
        \\            sigma: 0.05
        \\    products:
        \\      retrieved_state:
        \\        kind: state_vector
        \\      fitted_radiance:
        \\        kind: fitted_measurement
        \\      jacobian:
        \\        kind: jacobian
        \\
        \\outputs: []
        \\
        \\validation:
        \\  strict_unknown_fields: true
    ;

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    try std.testing.expectError(
        error.MissingMeasurementBinding,
        executeResolvedSource("retrieval.yaml", ".", yaml, &engine),
    );
}

test "canonical execution runs revised twin examples with routed outputs" {
    var common_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const common_root = try makeOutputRoot("common", &common_root_buffer);
    defer std.fs.cwd().deleteTree(common_root) catch {};

    var expert_root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const expert_root = try makeOutputRoot("expert", &expert_root_buffer);
    defer std.fs.cwd().deleteTree(expert_root) catch {};

    const common_bytes = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "data/examples/zdisamar_common_use.yaml",
        64 * 1024,
    );
    defer std.testing.allocator.free(common_bytes);
    const common_replacement = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/", .{common_root});
    defer std.testing.allocator.free(common_replacement);
    const common_rooted_yaml = try replaceAllAlloc(std.testing.allocator, common_bytes, "file://out/", common_replacement);
    defer std.testing.allocator.free(common_rooted_yaml);
    const common_yaml = try coarsenTwinExampleYaml(std.testing.allocator, common_rooted_yaml);
    defer std.testing.allocator.free(common_yaml);

    const expert_bytes = try std.fs.cwd().readFileAlloc(
        std.testing.allocator,
        "data/examples/zdisamar_expert_o2a.yaml",
        128 * 1024,
    );
    defer std.testing.allocator.free(expert_bytes);
    const expert_replacement = try std.fmt.allocPrint(std.testing.allocator, "file://{s}/", .{expert_root});
    defer std.testing.allocator.free(expert_replacement);
    const expert_rooted_yaml = try replaceAllAlloc(std.testing.allocator, expert_bytes, "file://out/", expert_replacement);
    defer std.testing.allocator.free(expert_rooted_yaml);
    const expert_yaml = try coarsenTwinExampleYaml(std.testing.allocator, expert_rooted_yaml);
    defer std.testing.allocator.free(expert_yaml);

    var common_document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "zdisamar_common_use.yaml",
        "data/examples",
        common_yaml,
    );
    defer common_document.deinit();

    var common_resolved: ?*zdisamar.canonical_config.ResolvedExperiment = try common_document.resolve(std.testing.allocator);
    defer if (common_resolved) |owned| owned.deinit();

    var common_program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, common_resolved.?);
    common_resolved = null;
    defer common_program.deinit();

    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    try std.testing.expectEqual(@as(usize, 2), common_program.stages.len);
    try std.testing.expectEqual(@as(usize, 2), common_program.outputs.len);
    try std.testing.expectEqualStrings("retrieval", @tagName(common_program.stages[1].kind));
    const common_execution = try common_program.execute(std.testing.allocator, &engine);
    defer {
        var outcome = common_execution;
        outcome.deinit();
    }
    try std.testing.expectEqual(@as(usize, 2), common_execution.stage_outcomes.len);
    try std.testing.expectEqual(zdisamar.Result.Status.success, common_execution.stage_outcomes[1].result.status);

    var expert_document = try zdisamar.canonical_config.Document.parse(
        std.testing.allocator,
        "zdisamar_expert_o2a.yaml",
        "data/examples",
        expert_yaml,
    );
    defer expert_document.deinit();

    var expert_resolved: ?*zdisamar.canonical_config.ResolvedExperiment = try expert_document.resolve(std.testing.allocator);
    defer if (expert_resolved) |owned| owned.deinit();

    var expert_program = try zdisamar.canonical_config.compileResolved(std.testing.allocator, expert_resolved.?);
    expert_resolved = null;
    defer expert_program.deinit();

    try std.testing.expectEqual(@as(usize, 2), expert_program.stages.len);
    try std.testing.expectEqual(@as(usize, 3), expert_program.outputs.len);
    try std.testing.expectEqualStrings("retrieval", @tagName(expert_program.stages[1].kind));
    const expert_inverse = expert_program.stages[1].stage.inverse.?;
    try std.testing.expectEqual(@as(usize, 6), expert_inverse.state_vector.parameters.len);
    try std.testing.expectEqual(@as(@TypeOf(expert_inverse.state_vector.parameters[1].target), .aerosol_layer_center_km), expert_inverse.state_vector.parameters[1].target);
    try std.testing.expectEqual(@as(@TypeOf(expert_inverse.state_vector.parameters[3].target), .wavelength_shift_nm), expert_inverse.state_vector.parameters[3].target);
    try std.testing.expectEqual(@as(@TypeOf(expert_inverse.state_vector.parameters[4].target), .multiplicative_offset), expert_inverse.state_vector.parameters[4].target);
    try std.testing.expectEqual(@as(@TypeOf(expert_inverse.state_vector.parameters[5].target), .stray_light), expert_inverse.state_vector.parameters[5].target);
    try std.testing.expectEqual(@as(usize, 1), expert_inverse.covariance_blocks.len);
    try std.testing.expectEqualSlices(u32, &.{ 0, 1 }, expert_inverse.covariance_blocks[0].parameter_indices);

    var found_jacobian = false;
    var found_averaging_kernel = false;
    var found_posterior_covariance = false;
    for (expert_program.products) |product| {
        if (std.mem.eql(u8, product.name, "jacobian")) {
            found_jacobian = true;
        } else if (std.mem.eql(u8, product.name, "averaging_kernel")) {
            found_averaging_kernel = true;
        } else if (std.mem.eql(u8, product.name, "posterior_covariance")) {
            found_posterior_covariance = true;
        }
    }
    try std.testing.expect(found_jacobian);
    try std.testing.expect(found_averaging_kernel);
    try std.testing.expect(found_posterior_covariance);

    const expert_execution = try expert_program.execute(std.testing.allocator, &engine);
    defer {
        var outcome = expert_execution;
        outcome.deinit();
    }

    try std.testing.expectEqual(@as(usize, 2), expert_execution.stage_outcomes.len);
    try std.testing.expectEqual(zdisamar.Result.Status.success, expert_execution.stage_outcomes[0].result.status);
    try std.testing.expectEqual(zdisamar.Result.Status.success, expert_execution.stage_outcomes[1].result.status);
    try std.testing.expect(expert_execution.stage_outcomes[0].result.measurement_space_product != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval != null);
    try std.testing.expectEqual(@as(usize, 6), expert_execution.stage_outcomes[1].result.retrieval.?.state_estimate.values.len);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval.?.jacobian != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval.?.averaging_kernel != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval.?.posterior_covariance != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval_products.jacobian != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval_products.averaging_kernel != null);
    try std.testing.expect(expert_execution.stage_outcomes[1].result.retrieval_products.posterior_covariance != null);

    const truth_stage = expert_program.stages[0].stage;
    var truth_plan = try engine.preparePlan(truth_stage.plan);
    defer truth_plan.deinit();
    var clean_truth_product = try simulateSceneProduct(std.testing.allocator, &truth_plan, truth_stage.scene);
    defer clean_truth_product.deinit(std.testing.allocator);

    const truth_product = expert_execution.stage_outcomes[0].result.measurement_space_product.?;
    try std.testing.expectEqual(clean_truth_product.radiance.len, truth_product.radiance.len);
    try std.testing.expectEqual(clean_truth_product.wavelengths.len, truth_product.wavelengths.len);
    try std.testing.expect(truth_product.noise_sigma.len > 0);
    try std.testing.expect(truth_product.noise_sigma[0] > 0.0);

    var saw_noise_applied = false;
    for (clean_truth_product.radiance, truth_product.radiance) |clean_radiance, noisy_radiance| {
        if (@abs(clean_radiance - noisy_radiance) > 1.0e-12) {
            saw_noise_applied = true;
            break;
        }
    }
    try std.testing.expect(saw_noise_applied);

    const fitted_product = expert_execution.stage_outcomes[1].result.retrieval_products.fitted_measurement.?;
    try std.testing.expectEqual(truth_product.wavelengths.len, fitted_product.wavelengths.len);
    try std.testing.expectApproxEqAbs(@as(f64, 758.0), truth_product.wavelengths[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 771.0), truth_product.wavelengths[truth_product.wavelengths.len - 1], 1.0e-12);
    for (truth_product.wavelengths, fitted_product.wavelengths) |expected_wavelength, actual_wavelength| {
        try std.testing.expectApproxEqAbs(expected_wavelength, actual_wavelength, 1.0e-12);
    }

    const expert_truth_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/s5p_o2a_truth_radiance.nc", .{expert_root});
    defer std.testing.allocator.free(expert_truth_path);
    try std.fs.cwd().access(expert_truth_path, .{});

    const expert_retrieval_path = try std.fmt.allocPrint(std.testing.allocator, "{s}/s5p_o2a_retrieval.nc", .{expert_root});
    defer std.testing.allocator.free(expert_retrieval_path);
    try std.fs.cwd().access(expert_retrieval_path, .{});

    const expert_fitted_store = try std.fmt.allocPrint(std.testing.allocator, "{s}/s5p_o2a_fitted_radiance.zarr", .{expert_root});
    defer std.testing.allocator.free(expert_fitted_store);
    try std.fs.cwd().access(expert_fitted_store, .{});
}
