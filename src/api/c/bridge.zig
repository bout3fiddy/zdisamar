const std = @import("std");
const CoreEngine = @import("../../core/Engine.zig").Engine;
const CoreEngineOptions = @import("../../core/Engine.zig").EngineOptions;
const PlanModule = @import("../../core/Plan.zig");
const Request = @import("../../core/Request.zig").Request;
const Result = @import("../../core/Result.zig").Result;
const Workspace = @import("../../core/Workspace.zig").Workspace;
const errors = @import("../../core/errors.zig");

pub const abi_version: u32 = 1;
pub const plugin_abi_version: u32 = 1;
pub const plugin_entry_symbol: [:0]const u8 = "zdisamar_plugin_entry_v1";

pub const StatusCode = enum(u32) {
    ok = 0,
    invalid_argument = 1,
    internal = 2,
};

pub const SolverMode = enum(u32) {
    scalar = 0,
    polarized = 1,
    derivative_enabled = 2,
};

pub const DerivativeMode = enum(u32) {
    none = 0,
    semi_analytical = 1,
    analytical_plugin = 2,
    numerical = 3,
};

pub const PluginPolicy = enum(u32) {
    declarative_only = 0,
    allow_trusted_native = 1,
};

pub const PluginLane = enum(u32) {
    declarative = 0,
    native = 1,
};

pub const EngineOptionsDesc = extern struct {
    struct_size: u32,
    abi_version: u32,
    plugin_policy: PluginPolicy,
    max_prepared_plans: u32,
};

pub const SceneDesc = extern struct {
    scene_id: ?[*:0]const u8,
    spectral_start_nm: f64,
    spectral_end_nm: f64,
    spectral_samples: u32,
};

pub const RequestDesc = extern struct {
    scene: SceneDesc,
    diagnostics_flags: u32 = diagnostics_provenance,
    expected_derivative_mode: DerivativeMode = .none,
};

pub const PlanDesc = extern struct {
    model_family: [*:0]const u8,
    transport_solver: [*:0]const u8,
    retrieval_algorithm: ?[*:0]const u8 = null,
    solver_mode: SolverMode = .scalar,
    expected_plugin_abi_version: u32 = plugin_abi_version,
};

pub const ResultDesc = extern struct {
    plan_id: u64,
    scene_id: ?[*:0]const u8 = null,
    solver_route: ?[*:0]const u8 = null,
    status: StatusCode,
    plugin_count: u32,
};

pub const diagnostics_provenance: u32 = 1 << 0;
pub const diagnostics_jacobians: u32 = 1 << 1;

const BridgeError = error{InvalidArgument};

const CEngine = opaque {};
const CPlan = opaque {};
const CWorkspace = opaque {};

const EngineHandle = struct {
    engine: CoreEngine,
};

const PlanHandle = struct {
    plan: PlanModule.Plan,
};

const WorkspaceHandle = struct {
    workspace: Workspace,
    last_scene_id: ?[:0]u8 = null,
    last_solver_route: ?[:0]u8 = null,

    fn deinit(self: *WorkspaceHandle) void {
        self.clearResultStrings();
        self.* = undefined;
    }

    fn clearResultStrings(self: *WorkspaceHandle) void {
        if (self.last_scene_id) |value| std.heap.c_allocator.free(value);
        if (self.last_solver_route) |value| std.heap.c_allocator.free(value);
        self.last_scene_id = null;
        self.last_solver_route = null;
    }

    fn captureResultStrings(self: *WorkspaceHandle, result: Result) !void {
        const scene_id = if (result.scene_id.len > 0)
            try std.heap.c_allocator.dupeZ(u8, result.scene_id)
        else
            null;
        errdefer if (scene_id) |value| std.heap.c_allocator.free(value);

        const solver_route = if (result.provenance.solver_route.len > 0)
            try std.heap.c_allocator.dupeZ(u8, result.provenance.solver_route)
        else
            null;
        errdefer if (solver_route) |value| std.heap.c_allocator.free(value);

        self.clearResultStrings();
        self.last_scene_id = scene_id;
        self.last_solver_route = solver_route;
    }
};

pub fn defaultEngineOptions(plugin_policy: PluginPolicy, max_prepared_plans: u32) EngineOptionsDesc {
    return .{
        .struct_size = @sizeOf(EngineOptionsDesc),
        .abi_version = abi_version,
        .plugin_policy = plugin_policy,
        .max_prepared_plans = max_prepared_plans,
    };
}

pub fn toSolverMode(mode: PlanModule.SolverMode) SolverMode {
    return switch (mode) {
        .scalar => .scalar,
        .polarized => .polarized,
        .derivative_enabled => .derivative_enabled,
    };
}

pub fn describeResult(result: Result) ResultDesc {
    return describeResultWithPointers(result, null, null);
}

fn describeResultWithPointers(
    result: Result,
    scene_id: ?[*:0]const u8,
    solver_route: ?[*:0]const u8,
) ResultDesc {
    return .{
        .plan_id = result.plan_id,
        .scene_id = scene_id,
        .solver_route = solver_route,
        .status = switch (result.status) {
            .success => .ok,
            .invalid_request => .invalid_argument,
            .internal_error => .internal,
        },
        .plugin_count = @as(u32, @intCast(result.provenance.pluginVersionCount())),
    };
}

fn toEngineOptions(desc: ?*const EngineOptionsDesc) BridgeError!CoreEngineOptions {
    if (desc == null) return .{};
    const value = desc.?;
    if (value.struct_size != @sizeOf(EngineOptionsDesc) or value.abi_version != abi_version) {
        return error.InvalidArgument;
    }

    return .{
        .abi_version = value.abi_version,
        .allow_native_plugins = value.plugin_policy == .allow_trusted_native,
        .max_prepared_plans = value.max_prepared_plans,
    };
}

fn toPlanTemplate(desc: *const PlanDesc) BridgeError!PlanModule.Template {
    if (std.mem.len(desc.model_family) == 0 or std.mem.len(desc.transport_solver) == 0) {
        return error.InvalidArgument;
    }

    return .{
        .model_family = std.mem.span(desc.model_family),
        .providers = .{
            .transport_solver = std.mem.span(desc.transport_solver),
            .retrieval_algorithm = if (desc.retrieval_algorithm) |value| std.mem.span(value) else null,
        },
        .solver_mode = switch (desc.solver_mode) {
            .scalar => .scalar,
            .polarized => .polarized,
            .derivative_enabled => .derivative_enabled,
        },
    };
}

fn toRequest(desc: *const RequestDesc) BridgeError!Request {
    const scene_id = desc.scene.scene_id orelse return error.InvalidArgument;
    if (std.mem.len(scene_id) == 0 or desc.scene.spectral_samples == 0) {
        return error.InvalidArgument;
    }

    var request = Request.init(.{
        .id = std.mem.span(scene_id),
        .spectral_grid = .{
            .start_nm = desc.scene.spectral_start_nm,
            .end_nm = desc.scene.spectral_end_nm,
            .sample_count = desc.scene.spectral_samples,
        },
    });
    request.diagnostics = .{
        .provenance = (desc.diagnostics_flags & diagnostics_provenance) != 0,
        .jacobians = (desc.diagnostics_flags & diagnostics_jacobians) != 0,
    };
    request.expected_derivative_mode = switch (desc.expected_derivative_mode) {
        .none => .none,
        .semi_analytical => .semi_analytical,
        .analytical_plugin => .analytical_plugin,
        .numerical => .numerical,
    };
    return request;
}

fn mapError(err: anyerror) StatusCode {
    return switch (err) {
        error.InvalidArgument,
        errors.Error.InvalidRequest,
        errors.Error.MissingScene,
        errors.Error.MissingModelFamily,
        errors.Error.MissingTransportRoute,
        errors.Error.MissingObservationInstrument,
        errors.Error.UnsupportedModelFamily,
        errors.Error.PreparedPlanLimitExceeded,
        errors.Error.WorkspacePlanMismatch,
        errors.Error.DerivativeModeMismatch,
        errors.Error.UnsupportedDerivativeMode,
        errors.Error.UnsupportedExecutionMode,
        errors.Error.UnsupportedCapability,
        errors.Error.PluginPrepareFailed,
        errors.Error.PluginExecutionFailed,
        => .invalid_argument,
        else => .internal,
    };
}

fn castEngine(ptr: *CEngine) *EngineHandle {
    return @ptrCast(@alignCast(ptr));
}

fn castPlan(ptr: *CPlan) *PlanHandle {
    return @ptrCast(@alignCast(ptr));
}

fn castWorkspace(ptr: *CWorkspace) *WorkspaceHandle {
    return @ptrCast(@alignCast(ptr));
}

export fn zdisamar_engine_create(out_engine: *?*CEngine) StatusCode {
    return zdisamar_engine_create_with_options(null, out_engine);
}

export fn zdisamar_engine_create_with_options(
    options: ?*const EngineOptionsDesc,
    out_engine: *?*CEngine,
) StatusCode {
    out_engine.* = null;
    const engine_options = toEngineOptions(options) catch |err| return mapError(err);
    const handle = std.heap.c_allocator.create(EngineHandle) catch return .internal;
    handle.* = .{
        .engine = CoreEngine.init(std.heap.c_allocator, engine_options),
    };
    handle.engine.bootstrapBuiltinCatalog() catch |err| {
        std.heap.c_allocator.destroy(handle);
        return mapError(err);
    };
    out_engine.* = @ptrCast(handle);
    return .ok;
}

export fn zdisamar_engine_destroy(engine: ?*CEngine) void {
    const ptr = engine orelse return;
    const handle = castEngine(ptr);
    handle.engine.deinit();
    std.heap.c_allocator.destroy(handle);
}

export fn zdisamar_plan_prepare(
    engine: ?*CEngine,
    plan_desc: ?*const PlanDesc,
    out_plan: *?*CPlan,
) StatusCode {
    const engine_ptr = engine orelse return .invalid_argument;
    const desc = plan_desc orelse return .invalid_argument;
    out_plan.* = null;
    const template = toPlanTemplate(desc) catch |err| return mapError(err);
    const handle = std.heap.c_allocator.create(PlanHandle) catch return .internal;
    handle.* = .{
        .plan = castEngine(engine_ptr).engine.preparePlan(template) catch |err| {
            std.heap.c_allocator.destroy(handle);
            return mapError(err);
        },
    };
    out_plan.* = @ptrCast(handle);
    return .ok;
}

export fn zdisamar_plan_destroy(plan: ?*CPlan) void {
    const ptr = plan orelse return;
    const handle = castPlan(ptr);
    handle.plan.deinit();
    std.heap.c_allocator.destroy(handle);
}

export fn zdisamar_workspace_create(
    engine: ?*CEngine,
    out_workspace: *?*CWorkspace,
) StatusCode {
    const engine_ptr = engine orelse return .invalid_argument;
    out_workspace.* = null;
    const handle = std.heap.c_allocator.create(WorkspaceHandle) catch return .internal;
    handle.* = .{
        .workspace = castEngine(engine_ptr).engine.createWorkspace("c-api"),
    };
    out_workspace.* = @ptrCast(handle);
    return .ok;
}

export fn zdisamar_workspace_destroy(workspace: ?*CWorkspace) void {
    const ptr = workspace orelse return;
    const handle = castWorkspace(ptr);
    handle.deinit();
    std.heap.c_allocator.destroy(handle);
}

export fn zdisamar_execute(
    engine: ?*CEngine,
    plan: ?*const CPlan,
    workspace: ?*CWorkspace,
    request_desc: ?*const RequestDesc,
    out_result: *ResultDesc,
) StatusCode {
    const engine_ptr = engine orelse return .invalid_argument;
    const plan_ptr = plan orelse return .invalid_argument;
    const workspace_ptr = workspace orelse return .invalid_argument;
    const desc = request_desc orelse return .invalid_argument;
    const workspace_handle = castWorkspace(workspace_ptr);
    const request = toRequest(desc) catch |err| return mapError(err);
    var result = castEngine(engine_ptr).engine.execute(
        &castPlan(@constCast(plan_ptr)).plan,
        &workspace_handle.workspace,
        &request,
    ) catch |err| return mapError(err);
    defer result.deinit(std.heap.c_allocator);
    workspace_handle.captureResultStrings(result) catch |err| return mapError(err);
    out_result.* = describeResultWithPointers(
        result,
        if (workspace_handle.last_scene_id) |value| value.ptr else null,
        if (workspace_handle.last_solver_route) |value| value.ptr else null,
    );
    return .ok;
}

test "default engine options lock C ABI fields" {
    const options = defaultEngineOptions(.declarative_only, 64);
    try std.testing.expectEqual(@as(u32, @sizeOf(EngineOptionsDesc)), options.struct_size);
    try std.testing.expectEqual(abi_version, options.abi_version);
    try std.testing.expectEqual(PluginPolicy.declarative_only, options.plugin_policy);
    try std.testing.expectEqual(@as(u32, 64), options.max_prepared_plans);
}

test "result description counts plugin provenance entries" {
    var result = try Result.init(std.testing.allocator, 7, "workspace-a", "scene-a", .{
        .plan_id = 7,
        .workspace_label = "workspace-a",
        .scene_id = "scene-a",
    });
    defer result.deinit(std.testing.allocator);
    const described = describeResult(result);
    try std.testing.expectEqual(@as(u64, 7), described.plan_id);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), described.scene_id);
    try std.testing.expectEqual(@as(?[*:0]const u8, null), described.solver_route);
    try std.testing.expectEqual(@as(u32, 0), described.plugin_count);
}

test "c abi lifecycle prepares and executes a typed request" {
    var engine: ?*CEngine = null;
    try std.testing.expectEqual(StatusCode.ok, zdisamar_engine_create(&engine));
    defer zdisamar_engine_destroy(engine);

    var plan: ?*CPlan = null;
    try std.testing.expectEqual(StatusCode.ok, zdisamar_plan_prepare(engine, &.{
        .model_family = "disamar_standard",
        .transport_solver = "builtin.dispatcher",
        .solver_mode = .scalar,
    }, &plan));
    defer zdisamar_plan_destroy(plan);

    var workspace: ?*CWorkspace = null;
    try std.testing.expectEqual(StatusCode.ok, zdisamar_workspace_create(engine, &workspace));
    defer zdisamar_workspace_destroy(workspace);

    var result: ResultDesc = undefined;
    try std.testing.expectEqual(StatusCode.ok, zdisamar_execute(
        engine,
        plan,
        workspace,
        &.{
            .scene = .{
                .scene_id = "scene-c-api",
                .spectral_start_nm = 405.0,
                .spectral_end_nm = 465.0,
                .spectral_samples = 16,
            },
            .diagnostics_flags = diagnostics_provenance,
            .expected_derivative_mode = .none,
        },
        &result,
    ));

    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("scene-c-api", std.mem.span(result.scene_id.?));
    try std.testing.expectEqualStrings("builtin.dispatcher", std.mem.span(result.solver_route.?));
}
