const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = internal.retrieval;
const export_spec = internal.exporter_spec;

fn preparePlanWithAllocator(allocator: std.mem.Allocator) !void {
    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .measurement_count_hint = 16,
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 16,
            },
        },
    });
    defer plan.deinit();
}

fn resolveExperiment(allocator: std.mem.Allocator, source: []const u8) !*zdisamar.canonical_config.ResolvedExperiment {
    var document = try zdisamar.canonical_config.Document.parse(
        allocator,
        "inline.yaml",
        ".",
        source,
    );
    defer document.deinit();
    return document.resolve(allocator);
}

fn canonicalExecutionWithAllocator(allocator: std.mem.Allocator) !void {
    const source =
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: allocation-failure-execution
        \\  workspace: alloc-failure
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
        \\        model: plane_parallel
        \\        solar_zenith_deg: 30.0
        \\        viewing_zenith_deg: 8.0
        \\        relative_azimuth_deg: 145.0
        \\      atmosphere:
        \\        layering:
        \\          layer_count: 12
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
        \\        albedo: 0.08
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
        \\      id: alloc-failure-scene
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

    var experiment = try resolveExperiment(allocator, source);
    var experiment_owned = true;
    errdefer if (experiment_owned) experiment.deinit();

    var program = try zdisamar.canonical_config.compileResolved(allocator, experiment);
    experiment_owned = false;
    defer program.deinit();

    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var outcome = try program.execute(allocator, &engine);
    defer outcome.deinit();
}

fn makeResult(allocator: std.mem.Allocator) !zdisamar.Result {
    const dataset_hashes = &[_][]const u8{
        "sha256:test-cross-sections",
        "sha256:test-lut",
    };
    var provenance: zdisamar.Provenance = .{
        .plan_id = 42,
        .workspace_label = "alloc-export",
        .scene_id = "scene-export",
        .dataset_hashes = dataset_hashes,
    };
    provenance.setPluginVersions(&[_][]const u8{
        "builtin.netcdf_cf@0.1.0",
    });
    return zdisamar.Result.init(allocator, 42, "alloc-export", "scene-export", provenance);
}

fn makeOutputRoot(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn exportWriteWithAllocator(allocator: std.mem.Allocator) !void {
    var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("allocation-failure-export", &path_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const destination_uri = try std.fmt.allocPrint(allocator, "file://{s}/scene.nc", .{root});
    defer allocator.free(destination_uri);

    var result = try makeResult(allocator);
    defer result.deinit(allocator);

    const report = try zdisamar.exporters.writer.write(
        allocator,
        .{
            .plugin_id = "builtin.netcdf_cf",
            .format = .netcdf_cf,
            .destination_uri = destination_uri,
            .dataset_name = "scene-export",
        },
        export_spec.ExportView.fromResult(&result),
    );
    if (report.files_written == 0) return error.UnexpectedExportReport;
}

fn retrievalDoasWithAllocator(allocator: std.mem.Allocator) !void {
    var product = try retrieval.common.surrogate_forward.testEvaluator().evaluateProduct(
        allocator,
        retrieval.common.surrogate_forward.testEvaluator().context,
        .{
            .id = "scene-doas-truth",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 32 },
            .surface = .{ .albedo = 0.13 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.08, .layer_center_km = 2.8, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic, .wavelength_shift_nm = 0.008 },
        },
    );
    defer product.deinit(allocator);

    const problem: retrieval.common.contracts.RetrievalProblem = .{
        .scene = .{
            .id = "scene-doas",
            .spectral_grid = .{ .start_nm = 759.5, .end_nm = 765.5, .sample_count = 32 },
            .surface = .{ .albedo = 0.08 },
            .aerosol = .{ .enabled = true, .optical_depth = 0.05, .layer_center_km = 2.8, .layer_width_km = 1.0 },
            .observation_model = .{ .instrument = .synthetic },
        },
        .inverse_problem = .{
            .id = "inverse-doas",
            .state_vector = .{
                .parameters = &[_]zdisamar.StateParameter{
                    .{ .name = "surface_albedo", .target = .surface_albedo, .transform = .logit, .prior = .{ .enabled = true, .mean = 0.1, .sigma = 0.05 }, .bounds = .{ .enabled = true, .min = 0.0, .max = 1.0 } },
                    .{ .name = "aerosol_tau", .target = .aerosol_optical_depth_550_nm, .transform = .log, .prior = .{ .enabled = true, .mean = 0.07, .sigma = 0.03 }, .bounds = .{ .enabled = true, .min = 1.0e-4, .max = 1.0 } },
                    .{ .name = "wavelength_shift", .target = .wavelength_shift_nm, .prior = .{ .enabled = true, .mean = 0.0, .sigma = 0.03 }, .bounds = .{ .enabled = true, .min = -0.1, .max = 0.1 } },
                },
            },
            .measurements = .{
                .product_name = "radiance",
                .observable = .radiance,
                .sample_count = 32,
                .source = .{ .external_observation = .{ .name = "truth" } },
                .error_model = .{ .from_source_noise = true, .floor = 1.0e-5 },
            },
        },
        .derivative_mode = .numerical,
        .jacobians_requested = true,
        .observed_measurement = .{
            .source_name = "truth",
            .observable = .radiance,
            .product_name = "radiance",
            .sample_count = 32,
            .product = .init(&product),
        },
    };

    var result = try retrieval.doas.solver.solveWithTestEvaluator(allocator, problem);
    defer result.deinit(allocator);
}

test "engine preparePlan cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, preparePlanWithAllocator, .{});
}

test "canonical execution cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, canonicalExecutionWithAllocator, .{});
}

test "export writer cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, exportWriteWithAllocator, .{});
}

test "retrieval setup cleans up after allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, retrievalDoasWithAllocator, .{});
}
