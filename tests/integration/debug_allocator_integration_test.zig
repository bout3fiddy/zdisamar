const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const retrieval = internal.retrieval;
const export_spec = internal.exporter_spec;

fn makeOutputRoot(prefix: []const u8, buffer: []u8) ![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "zig-cache/{s}-{d}",
        .{ prefix, @as(u64, @intCast(@abs(std.time.nanoTimestamp()))) },
    );
}

fn canonicalExecutionSource(root: []const u8) ![]u8 {
    return std.fmt.allocPrint(
        std.testing.allocator,
        \\schema_version: 1
        \\
        \\metadata:
        \\  id: debug-allocator
        \\  workspace: debug-allocator
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
        \\        albedo: 0.07
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
}

fn resolveExperiment(
    allocator: std.mem.Allocator,
    source_name: []const u8,
    source: []const u8,
) !*zdisamar.canonical_config.ResolvedExperiment {
    var document = try zdisamar.canonical_config.Document.parse(
        allocator,
        source_name,
        ".",
        source,
    );
    defer document.deinit();
    return document.resolve(allocator);
}

fn makeResult(allocator: std.mem.Allocator) !zdisamar.Result {
    const dataset_hashes = &[_][]const u8{
        "sha256:test-cross-sections",
        "sha256:test-lut",
    };
    var provenance: zdisamar.Provenance = .{
        .plan_id = 17,
        .workspace_label = "debug-export",
        .scene_id = "debug-scene",
        .dataset_hashes = dataset_hashes,
    };
    provenance.setPluginVersions(&[_][]const u8{
        "builtin.netcdf_cf@0.1.0",
    });
    return zdisamar.Result.init(allocator, 17, "debug-export", "debug-scene", provenance);
}

test "debug allocator covers repeated forward execution and workspace reset" {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(da.deinit() == .ok);
    const allocator = da.allocator();

    var engine = zdisamar.Engine.init(allocator, .{ .max_prepared_plans = 32 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var workspace = engine.createWorkspace("debug-forward");
    var iteration: usize = 0;
    while (iteration < 3) : (iteration += 1) {
        if (iteration != 0) workspace.reset();

        var plan = try engine.preparePlan(.{
            .scene_blueprint = .{
                .measurement_count_hint = 24,
                .spectral_grid = .{
                    .start_nm = 405.0,
                    .end_nm = 465.0,
                    .sample_count = 24,
                },
            },
        });
        defer plan.deinit();

        const request = zdisamar.Request.init(.{
            .id = "debug-forward-scene",
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 24,
            },
        });
        var result = try engine.execute(&plan, &workspace, &request);
        defer result.deinit(allocator);
        try std.testing.expectEqual(zdisamar.Result.Status.success, result.status);
    }
}

test "debug allocator covers canonical execution and exporter emission" {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(da.deinit() == .ok);
    const allocator = da.allocator();

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("debug-allocator-canonical", &root_buffer);
    defer std.fs.cwd().deleteTree(root) catch {};

    const source = try canonicalExecutionSource(root);
    defer std.testing.allocator.free(source);

    var experiment = try resolveExperiment(allocator, "debug-allocator.yaml", source);
    errdefer experiment.deinit();

    var program = try zdisamar.canonical_config.compileResolved(allocator, experiment);
    defer program.deinit();

    var engine = zdisamar.Engine.init(allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var outcome = try program.execute(allocator, &engine);
    defer outcome.deinit();

    try std.testing.expectEqual(@as(usize, 1), outcome.outputs.len);
    var truth_path_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const truth_path = try std.fmt.bufPrint(&truth_path_buffer, "{s}/truth.nc", .{root});
    try std.fs.cwd().access(truth_path, .{});
}

test "debug allocator covers retrieval execution with the test evaluator" {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(da.deinit() == .ok);
    const allocator = da.allocator();

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
    try std.testing.expectEqual(retrieval.common.contracts.Method.doas, result.method);
}

test "debug allocator covers exporter emission on a standalone result" {
    var da = std.heap.DebugAllocator(.{}){};
    defer std.debug.assert(da.deinit() == .ok);
    const allocator = da.allocator();

    var root_buffer: [std.fs.max_path_bytes]u8 = undefined;
    const root = try makeOutputRoot("debug-allocator-export", &root_buffer);
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
            .dataset_name = "debug-scene",
        },
        export_spec.ExportView.fromResult(&result),
    );
    try std.testing.expectEqual(@as(u32, 1), report.files_written);
}
