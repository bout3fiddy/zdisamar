const std = @import("std");

const Catalog = @import("Catalog.zig").Catalog;
const PlanModule = @import("Plan.zig");
const Plan = PlanModule.Plan;
const Request = @import("Request.zig").Request;
const Result = @import("Result.zig").Result;
const Workspace = @import("Workspace.zig").Workspace;
const Provenance = @import("provenance.zig").Provenance;
const Scene = @import("../model/Scene.zig").Scene;
const errors = @import("errors.zig");
const PluginManifest = @import("../plugins/loader/manifest.zig").PluginManifest;
const CapabilityRegistry = @import("../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;
const PreparedPlanCache = @import("../runtime/cache/PreparedPlanCache.zig").PreparedPlanCache;
const TransportCommon = @import("../kernels/transport/common.zig");
const TransportDispatcher = @import("../kernels/transport/dispatcher.zig");

pub const EngineOptions = struct {
    abi_version: u32 = 1,
    allow_native_plugins: bool = false,
    max_prepared_plans: usize = 64,
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    options: EngineOptions,
    catalog: Catalog = .{},
    registry: CapabilityRegistry = .{},
    next_plan_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, options: EngineOptions) Engine {
        return .{
            .allocator = allocator,
            .options = options,
        };
    }

    pub fn deinit(self: *Engine) void {
        self.registry.deinit(self.allocator);
        self.catalog.deinit(self.allocator);
    }

    pub fn bootstrapBuiltinCatalog(self: *Engine) !void {
        try self.catalog.bootstrapBuiltin(self.allocator);
        try self.registry.bootstrapBuiltin(self.allocator);
    }

    pub fn registerPluginManifest(self: *Engine, manifest: PluginManifest) !void {
        try self.registry.registerManifest(self.allocator, manifest, self.options.allow_native_plugins);
    }

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) !Plan {
        if (!self.catalog.bootstrapped) {
            return errors.Error.CatalogNotBootstrapped;
        }

        try template.validate();

        if (!self.catalog.supportsModelFamily(template.model_family)) {
            return errors.Error.UnsupportedModelFamily;
        }

        if (self.next_plan_id > self.options.max_prepared_plans) {
            return errors.Error.PreparedPlanLimitExceeded;
        }

        if (!std.mem.eql(u8, template.transport, "transport.dispatcher")) {
            return errors.Error.UnsupportedCapability;
        }

        const transport_route = TransportDispatcher.prepare(.{
            .regime = template.scene_blueprint.observation_regime,
            .execution_mode = transportExecutionMode(template.solver_mode),
            .derivative_mode = template.scene_blueprint.derivative_mode,
        }) catch |err| switch (err) {
            error.UnsupportedDerivativeMode => return errors.Error.UnsupportedDerivativeMode,
        };

        const plugin_snapshot = try self.registry.snapshot();
        const prepared_cache = try PreparedPlanCache.initFromBlueprint(
            template.scene_blueprint,
            @intCast(plugin_snapshot.datasetHashes().len),
        );
        const plan = Plan.init(
            self.next_plan_id,
            template,
            transport_route,
            prepared_cache,
            plugin_snapshot,
        );
        self.next_plan_id += 1;
        return plan;
    }

    pub fn createWorkspace(self: *Engine, label: []const u8) Workspace {
        _ = self;
        return Workspace.init(label);
    }

    pub fn execute(self: *Engine, plan: *const Plan, workspace: *Workspace, request: Request) !Result {
        _ = self;
        try plan.assertReady();
        try workspace.beginExecution(plan.id);
        workspace.prepareScratch(&plan.prepared_cache);
        try request.validateForPlan(plan);

        const provenance = Provenance.fromPlan(
            plan,
            workspace.label,
            request.scene.id,
            @tagName(plan.template.solver_mode),
        );

        return Result.init(
            plan.id,
            workspace.label,
            request.scene.id,
            provenance,
        );
    }
};

fn transportExecutionMode(solver_mode: PlanModule.SolverMode) TransportCommon.ExecutionMode {
    return switch (solver_mode) {
        .polarized => .polarized,
        .scalar, .derivative_enabled => .scalar,
    };
}

test "preparePlan validates lifecycle prerequisites and plan templates" {
    var engine = Engine.init(std.testing.allocator, .{ .max_prepared_plans = 1 });
    defer engine.deinit();

    try std.testing.expectError(errors.Error.CatalogNotBootstrapped, engine.preparePlan(.{}));
    try engine.bootstrapBuiltinCatalog();
    try std.testing.expectError(errors.Error.UnsupportedModelFamily, engine.preparePlan(.{ .model_family = "unknown" }));
    try std.testing.expectError(errors.Error.UnsupportedCapability, engine.preparePlan(.{ .transport = "transport.custom" }));

    _ = try engine.preparePlan(.{});
    try std.testing.expectError(errors.Error.PreparedPlanLimitExceeded, engine.preparePlan(.{}));
}

test "preparePlan resolves typed transport routes from plan-time observation and derivative choices" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const scalar_plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .observation_regime = .nadir,
            .derivative_mode = .semi_analytical,
        },
    });
    try std.testing.expectEqual(TransportCommon.TransportFamily.adding, scalar_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.DerivativeMode.semi_analytical, scalar_plan.transport_route.derivative_mode);

    const polarized_plan = try engine.preparePlan(.{
        .solver_mode = .polarized,
        .scene_blueprint = .{
            .observation_regime = .limb,
            .derivative_mode = .analytical_plugin,
        },
    });
    try std.testing.expectEqual(TransportCommon.TransportFamily.labos, polarized_plan.transport_route.family);
    try std.testing.expectEqual(TransportCommon.ExecutionMode.polarized, polarized_plan.transport_route.execution_mode);
    try std.testing.expectEqual(TransportCommon.Regime.limb, polarized_plan.transport_route.regime);
}

test "execute enforces workspace plan binding and derivative-mode contracts" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const scalar_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .none } });
    const derivative_plan = try engine.preparePlan(.{ .scene_blueprint = .{ .derivative_mode = .semi_analytical } });

    var workspace = engine.createWorkspace("unit");
    const scene: Scene = .{ .id = "scene", .spectral_grid = .{ .sample_count = 4 } };
    var request = Request.init(scene);
    _ = try engine.execute(&scalar_plan, &workspace, request);

    request.expected_derivative_mode = .semi_analytical;
    try std.testing.expectError(errors.Error.DerivativeModeMismatch, engine.execute(&scalar_plan, &workspace, request));
    try std.testing.expectError(errors.Error.WorkspacePlanMismatch, engine.execute(&derivative_plan, &workspace, Request.init(scene)));
}

test "prepared plans keep plugin snapshots when registry changes later" {
    var engine = Engine.init(std.testing.allocator, .{ .allow_native_plugins = true });
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const first_plan = try engine.preparePlan(.{});

    try engine.registerPluginManifest(.{
        .id = "example.extra_dataset",
        .package = "disamar_standard",
        .version = "0.2.0",
        .lane = .declarative,
        .capabilities = &[_]@import("../plugins/loader/manifest.zig").CapabilityDecl{
            .{ .slot = "data.pack", .name = "example.extra_dataset" },
        },
        .provenance = .{
            .dataset_hashes = &[_][]const u8{
                "sha256:example-extra-dataset",
            },
        },
    });

    const second_plan = try engine.preparePlan(.{});

    try std.testing.expect(second_plan.plugin_snapshot.generation > first_plan.plugin_snapshot.generation);
    try std.testing.expect(second_plan.plugin_snapshot.pluginVersions().len > first_plan.plugin_snapshot.pluginVersions().len);

    var workspace = engine.createWorkspace("snapshot-suite");
    const request = Request.init(.{
        .id = "scene-snapshot",
        .spectral_grid = .{ .sample_count = 8 },
    });
    const first_result = try engine.execute(&first_plan, &workspace, request);
    workspace.reset();
    const second_result = try engine.execute(&second_plan, &workspace, request);

    try std.testing.expect(second_result.provenance.plugin_versions.len > first_result.provenance.plugin_versions.len);
    try std.testing.expect(second_result.provenance.dataset_hashes.len > first_result.provenance.dataset_hashes.len);
}

test "prepared plans own reusable cache hints and workspaces own reusable scratch" {
    var engine = Engine.init(std.testing.allocator, .{});
    defer engine.deinit();
    try engine.bootstrapBuiltinCatalog();

    const plan = try engine.preparePlan(.{
        .scene_blueprint = .{
            .spectral_grid = .{
                .start_nm = 405.0,
                .end_nm = 465.0,
                .sample_count = 121,
            },
            .layer_count_hint = 48,
            .state_parameter_count_hint = 3,
            .measurement_count_hint = 121,
        },
    });

    var workspace = engine.createWorkspace("cache-suite");
    const request = Request.init(.{
        .id = "scene-cache",
        .atmosphere = .{ .layer_count = 48 },
        .spectral_grid = .{ .start_nm = 405.0, .end_nm = 465.0, .sample_count = 121 },
    });
    _ = try engine.execute(&plan, &workspace, request);

    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.spectral_capacity);
    try std.testing.expectEqual(@as(usize, 48), workspace.scratch.layer_capacity);
    try std.testing.expectEqual(@as(usize, 3), workspace.scratch.state_capacity);
    try std.testing.expectEqual(@as(usize, 121), workspace.scratch.measurement_capacity);

    workspace.reset();
    try std.testing.expectEqual(@as(u64, 1), workspace.scratch.reset_count);
}
