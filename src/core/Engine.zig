const std = @import("std");

const Catalog = @import("Catalog.zig").Catalog;
const PlanModule = @import("Plan.zig");
const PreparedPlan = PlanModule.PreparedPlan;
const Request = @import("Request.zig").Request;
const Result = @import("Result.zig").Result;
const Workspace = @import("Workspace.zig").Workspace;
const errors = @import("errors.zig");
const PluginManifest = @import("../plugins/loader/manifest.zig").PluginManifest;
const CapabilityRegistry = @import("../plugins/registry/CapabilityRegistry.zig").CapabilityRegistry;
const DatasetCache = @import("../runtime/cache/DatasetCache.zig").DatasetCache;
const LUTCache = @import("../runtime/cache/LUTCache.zig").LUTCache;
const PlanCache = @import("../runtime/cache/PlanCache.zig").PlanCache;
const BatchRunnerModule = @import("../runtime/scheduler/BatchRunner.zig");
const BatchRunner = BatchRunnerModule.BatchRunner;
const ThreadContext = @import("../runtime/scheduler/ThreadContext.zig").ThreadContext;
const Logging = @import("logging.zig");
const Preparation = @import("engine/prepare.zig");
const ForwardExecution = @import("engine/forward.zig");
const RetrievalExecution = @import("engine/retrieval.zig");

pub const EngineOptions = struct {
    abi_version: u32 = 1,
    allow_native_plugins: bool = false,
    // Cache capacity for prepared-plan reuse. This is not a lifetime-total cap.
    max_prepared_plans: usize = 64,
    log_policy: Logging.Policy = .{},
};

pub const Engine = struct {
    allocator: std.mem.Allocator,
    options: EngineOptions,
    catalog: Catalog = .{},
    registry: CapabilityRegistry = .{},
    dataset_cache: DatasetCache,
    lut_cache: LUTCache,
    plan_cache: PlanCache,
    next_plan_id: u64 = 1,

    pub fn init(allocator: std.mem.Allocator, options: EngineOptions) Engine {
        return .{
            .allocator = allocator,
            .options = options,
            .dataset_cache = DatasetCache.init(allocator),
            .lut_cache = LUTCache.init(allocator),
            .plan_cache = PlanCache.init(allocator, .{ .max_entries = options.max_prepared_plans }),
        };
    }

    pub fn deinit(self: *Engine) void {
        self.plan_cache.deinit();
        self.lut_cache.deinit();
        self.dataset_cache.deinit();
        self.registry.deinit(self.allocator);
        self.catalog.deinit(self.allocator);
    }

    pub fn bootstrapBuiltinCatalog(self: *Engine) !void {
        try self.catalog.bootstrapBuiltin(self.allocator);
        try self.registry.bootstrapBuiltin(self.allocator, self.options.allow_native_plugins);
        try self.dataset_cache.upsert("builtin.cross_sections", "sha256:builtin-cross-sections-demo");
    }

    pub fn registerPluginManifest(self: *Engine, manifest: PluginManifest) !void {
        try self.registry.registerManifest(self.allocator, manifest, self.options.allow_native_plugins);
        for (manifest.provenance.dataset_hashes, 0..) |dataset_hash, index| {
            var key_buffer: [128]u8 = undefined;
            const cache_id = try std.fmt.bufPrint(&key_buffer, "{s}#{d}", .{ manifest.id, index });
            try self.dataset_cache.upsert(cache_id, dataset_hash);
        }
    }

    pub fn registerDatasetArtifact(self: *Engine, id: []const u8, dataset_hash: []const u8) !void {
        try self.dataset_cache.upsert(id, dataset_hash);
    }

    pub fn registerLUTArtifact(self: *Engine, dataset_id: []const u8, lut_id: []const u8, shape: LUTCache.Shape) !void {
        try self.lut_cache.upsert(dataset_id, lut_id, shape);
    }

    pub fn preparePlan(self: *Engine, template: PlanModule.Template) errors.PreparationError!PreparedPlan {
        var context = Preparation.Context{
            .allocator = self.allocator,
            .allow_native_plugins = self.options.allow_native_plugins,
            .catalog = &self.catalog,
            .registry = &self.registry,
            .dataset_cache = &self.dataset_cache,
            .plan_cache = &self.plan_cache,
            .next_plan_id = &self.next_plan_id,
        };
        return Preparation.preparePlan(&context, template);
    }

    pub fn createWorkspace(self: *Engine, label: []const u8) Workspace {
        _ = self;
        return Workspace.init(label);
    }

    pub fn createThreadContext(self: *Engine, label: []const u8) ThreadContext {
        _ = self;
        return ThreadContext.init(label);
    }

    pub fn createBatchRunner(self: *Engine) BatchRunner {
        return BatchRunner.init(self.allocator);
    }

    pub fn runBatch(
        self: *Engine,
        runner: *BatchRunner,
        thread: *ThreadContext,
        exec_ctx: ?*anyopaque,
        execute_fn: BatchRunnerModule.ExecuteFn,
    ) !void {
        try runner.run(thread, &self.plan_cache, exec_ctx, execute_fn);
    }

    pub fn execute(self: *Engine, plan: *const PreparedPlan, workspace: *Workspace, request: *const Request) errors.Error!Result {
        try request.validateForPlan(plan);
        try ForwardExecution.beginExecution(&self.plan_cache, plan, workspace, request);

        var result: Result = undefined;
        try ForwardExecution.initializeResult(self.allocator, plan, workspace, request, &result);
        errdefer result.deinit(self.allocator);

        try ForwardExecution.executeForwardProducts(self.allocator, plan, request, &result);
        try RetrievalExecution.execute(self.allocator, plan, request, &result);
        result.diagnostics = plan.providers.diagnostics.materialize(
            request.diagnostics,
            "Plugin-selected forward and retrieval providers executed with typed scene preparation and owned provenance.",
        );
        return result;
    }
};
