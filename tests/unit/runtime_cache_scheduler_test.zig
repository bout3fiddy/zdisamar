const std = @import("std");
const zdisamar = @import("zdisamar");
const internal = @import("zdisamar_internal");
const DatasetCache = internal.runtime.cache.DatasetCache;
const LUTCache = internal.runtime.cache.LUTCache;
const PlanCache = internal.runtime.cache.PlanCache;
const PreparedLayout = internal.runtime.cache.PreparedLayout;
const BatchRunner = internal.runtime.scheduler.BatchRunner;
const BatchJob = internal.runtime.scheduler.BatchJob;

fn makeLutCompatibilityScene() zdisamar.Scene {
    return .{
        .id = "cache-lut-compatibility",
        .geometry = .{
            .model = .plane_parallel,
            .solar_zenith_deg = 60.0,
            .viewing_zenith_deg = 30.0,
            .relative_azimuth_deg = 120.0,
        },
        .surface = .{
            .kind = .lambertian,
            .albedo = 0.20,
        },
        .spectral_grid = .{
            .start_nm = 758.0,
            .end_nm = 770.0,
            .sample_count = 121,
        },
        .atmosphere = .{
            .layer_count = 24,
            .sublayer_divisions = 3,
        },
        .observation_model = .{
            .regime = .nadir,
            .instrument = .synthetic,
            .sampling = .native,
            .noise_model = .shot_noise,
            .instrument_line_fwhm_nm = 0.38,
            .high_resolution_step_nm = 0.01,
            .high_resolution_half_span_nm = 1.14,
        },
        .lut_controls = .{
            .xsec = .{
                .mode = .generate,
                .min_temperature_k = 180.0,
                .max_temperature_k = 325.0,
                .min_pressure_hpa = 0.03,
                .max_pressure_hpa = 1050.0,
                .temperature_grid_count = 10,
                .pressure_grid_count = 20,
                .temperature_coefficient_count = 5,
                .pressure_coefficient_count = 10,
            },
        },
    };
}

test "dataset and lut caches track owned entries with explicit updates" {
    var datasets = DatasetCache.init(std.testing.allocator);
    defer datasets.deinit();

    var luts = LUTCache.init(std.testing.allocator);
    defer luts.deinit();

    try datasets.upsert("climatology.base", "sha256:dataset-a");
    try datasets.upsert("climatology.base", "sha256:dataset-b");
    try luts.upsert("climatology.base", "temperature_273", .{
        .spectral_bins = 480,
        .layer_count = 32,
        .coefficient_count = 8,
    });

    try std.testing.expectEqual(@as(usize, 1), datasets.count());
    try std.testing.expectEqualStrings("sha256:dataset-b", datasets.get("climatology.base").?.dataset_hash);
    try std.testing.expectEqual(@as(usize, 1), luts.count());
}

test "plan cache and batch runner execute against thread-bound prepared plans" {
    const Counters = struct {
        executed: usize = 0,
    };

    const callbacks = struct {
        fn execute(
            ctx_ptr: ?*anyopaque,
            thread: *zdisamar.Workspace,
            job: BatchJob,
            prepared: *const PreparedLayout,
        ) !void {
            _ = thread;
            _ = job;
            _ = prepared;
            const counters: *Counters = @ptrCast(@alignCast(ctx_ptr.?));
            counters.executed += 1;
        }
    };

    var plans = PlanCache.init(std.testing.allocator, .{ .max_entries = 8 });
    defer plans.deinit();
    try plans.put(11, .{ .measurement_capacity = 48 });

    var thread = zdisamar.Workspace.init("thread-a");

    var runner = BatchRunner.init(std.testing.allocator);
    defer runner.deinit();
    try runner.enqueue(.{ .plan_id = 11, .scene_id = "scene-1" });
    try runner.enqueue(.{ .plan_id = 11, .scene_id = "scene-2" });

    var counters: Counters = .{};
    try runner.run(&thread, &plans, &counters, callbacks.execute);

    try std.testing.expectEqual(@as(usize, 2), counters.executed);
    try std.testing.expectEqual(@as(u64, 2), runner.completed_jobs);
    try std.testing.expectEqual(@as(u64, 2), plans.get(11).?.run_count);
}

test "engine can repeatedly prepare and dispose plans without exhausting cache capacity" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{ .max_prepared_plans = 1 });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    var last_plan_id: u64 = 0;
    var iteration: usize = 0;
    while (iteration < 4) : (iteration += 1) {
        var plan = try engine.preparePlan(.{});
        try std.testing.expect(plan.id > last_plan_id);
        try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
        last_plan_id = plan.id;
        plan.deinit();
    }

    try std.testing.expectEqual(@as(usize, 1), engine.plan_cache.count());
}

test "prepared plans reject LUT reuse across mismatched scientific inputs" {
    var engine = zdisamar.Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const scene = makeLutCompatibilityScene();
    const compatibility = scene.lutCompatibilityKey();

    var plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .id = scene.id,
            .observation_regime = scene.observation_model.regime,
            .spectral_grid = scene.spectral_grid,
            .layer_count_hint = scene.atmosphere.layer_count,
            .measurement_count_hint = scene.spectral_grid.sample_count,
            .lut_compatibility = compatibility,
        },
    });
    defer plan.deinit();

    try std.testing.expect(plan.prepared_layout.lut_compatibility.matches(compatibility));

    var request = zdisamar.Request.init(scene);
    try request.validateForPlan(&plan);

    try engine.registerLUTArtifactWithCompatibility("generated.xsec.o2", scene.id, .{
        .spectral_bins = scene.spectral_grid.sample_count,
        .layer_count = scene.atmosphere.layer_count,
        .coefficient_count = scene.lut_controls.xsec.coefficientCount(),
    }, compatibility);
    try std.testing.expect(
        engine.lut_cache.getCompatible("generated.xsec.o2", scene.id, compatibility) != null,
    );

    var mismatched_request = zdisamar.Request.init(scene);
    mismatched_request.scene.geometry.relative_azimuth_deg = 90.0;
    try std.testing.expectError(error.InvalidRequest, mismatched_request.validateForPlan(&plan));
    try std.testing.expect(
        engine.lut_cache.getCompatible(
            "generated.xsec.o2",
            scene.id,
            mismatched_request.scene.lutCompatibilityKey(),
        ) == null,
    );
}
