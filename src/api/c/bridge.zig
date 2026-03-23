//! Purpose:
//!   Bridge the typed engine lifecycle into a stable C-facing ABI surface.
//!
//! Physics:
//!   No new physics is introduced here; the file translates request, plan, and
//!   result metadata across the boundary.
//!
//! Vendor:
//!   `bridge`
//!
//! Design:
//!   Keep the C ABI thin and explicit. The bridge validates descriptor sizes,
//!   converts nullable C strings into typed Zig values, and keeps result-owned
//!   strings isolated from the engine workspace lifetime.
//!
//! Invariants:
//!   ABI descriptors must match `struct_size` and `abi_version`; result strings
//!   captured from the typed result must be cleared before the workspace handle
//!   is destroyed.
//!
//! Validation:
//!   Exercised by the C ABI lifecycle tests at the bottom of this file.
const std = @import("std");
const CoreEngine = @import("../../core/Engine.zig").Engine;
const CoreEngineOptions = @import("../../core/Engine.zig").EngineOptions;
const PlanModule = @import("../../core/Plan.zig");
const PreparedPlan = PlanModule.PreparedPlan;
const Request = @import("../../core/Request.zig").Request;
const Result = @import("../../core/Result.zig").Result;
const Workspace = @import("../../core/Workspace.zig").Workspace;
const errors = @import("../../core/errors.zig");

/// ABI revision exported by this bridge.
pub const abi_version: u32 = 1;
/// DECISION:
///   Keep the exported C entrypoints disabled until the declarative ABI is
///   treated as stable for external consumers.
pub const c_abi_enabled = false;

/// Status codes returned by the C ABI bridge.
pub const StatusCode = enum(u32) {
    ok = 0,
    invalid_argument = 1,
    internal = 2,
};

/// Solver mode requested by the C ABI plan descriptor.
pub const SolverMode = enum(u32) {
    scalar = 0,
    polarized = 1,
};

/// Descriptor for engine-level ABI options.
pub const EngineOptionsDesc = extern struct {
    struct_size: u32,
    abi_version: u32,
    max_prepared_plans: u32,
};

/// Descriptor for the scene portion of a C ABI request.
pub const SceneDesc = extern struct {
    scene_id: ?[*:0]const u8,
    spectral_start_nm: f64,
    spectral_end_nm: f64,
    spectral_samples: u32,
};

/// Descriptor for a full C ABI request.
pub const RequestDesc = extern struct {
    scene: SceneDesc,
    diagnostics_flags: u32 = diagnostics_provenance,
};

/// Descriptor for the plan portion of the C ABI.
pub const PlanDesc = extern struct {
    model_family: [*:0]const u8,
    transport_solver: [*:0]const u8,
    retrieval_algorithm: ?[*:0]const u8 = null,
    solver_mode: SolverMode = .scalar,
};

/// Descriptor for the C ABI result.
pub const ResultDesc = extern struct {
    plan_id: u64,
    scene_id: ?[*:0]const u8 = null,
    solver_route: ?[*:0]const u8 = null,
    status: StatusCode,
    plugin_count: u32,
};

pub const diagnostics_provenance: u32 = 1 << 0;

const BridgeError = error{InvalidArgument};

const CEngine = opaque {};
const CPlan = opaque {};
const CWorkspace = opaque {};

const EngineHandle = struct {
    engine: CoreEngine,
};

const PlanHandle = struct {
    plan: PreparedPlan,
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
        // GOTCHA:
        //   Copy the strings before clearing the previous result cache; the
        //   workspace result teardown is independent from the typed result.
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

/// Purpose:
///   Build the default bridge-level engine options descriptor.
///
/// Physics:
///   None.
///
/// Vendor:
///   `bridge::defaultEngineOptions`
///
/// Inputs:
///   `max_prepared_plans` is the plan-cache capacity exported to C callers.
///
/// Outputs:
///   Returns the ABI descriptor with the current version and struct size.
///
/// Units:
///   Prepared-plan count.
///
/// Assumptions:
///   The ABI version constant in this file is authoritative.
///
/// Decisions:
///   Mirror the typed engine options through one helper so the C ABI stays
///   consistent.
///
/// Validation:
///   Covered by the default engine options test in this file.
pub fn defaultEngineOptions(max_prepared_plans: u32) EngineOptionsDesc {
    return .{
        .struct_size = @sizeOf(EngineOptionsDesc),
        .abi_version = abi_version,
        .max_prepared_plans = max_prepared_plans,
    };
}

/// Purpose:
///   Convert the typed solver mode into the C ABI enum.
///
/// Physics:
///   None.
///
/// Vendor:
///   `bridge::toSolverMode`
///
/// Inputs:
///   `mode` is the typed solver mode from the plan template.
///
/// Outputs:
///   Returns the ABI enum variant.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The typed solver mode enum stays in lockstep with the ABI enum.
///
/// Decisions:
///   Use a direct switch so any future solver mode expansion fails loudly.
///
/// Validation:
///   Covered implicitly by plan preparation tests.
pub fn toSolverMode(mode: PlanModule.SolverMode) SolverMode {
    return switch (mode) {
        .scalar => .scalar,
        .polarized => .polarized,
    };
}

/// Purpose:
///   Convert a typed result into the default C ABI result descriptor.
///
/// Physics:
///   No new physics; this is the default pointer-free result summary.
///
/// Vendor:
///   `bridge::describeResult`
///
/// Inputs:
///   `result` is the typed engine result.
///
/// Outputs:
///   Returns a descriptor without copied provenance pointers.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The caller only needs the raw status and provenance count.
///
/// Decisions:
///   Delegate to the pointer-aware helper with null provenance pointers so the
///   default path stays centralized.
///
/// Validation:
///   Covered by the result-description test in this file.
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
    // INVARIANT:
    //   ABI callers must pass the exact descriptor size and revision expected
    //   by this bridge.
    if (value.struct_size != @sizeOf(EngineOptionsDesc) or value.abi_version != abi_version) {
        return error.InvalidArgument;
    }

    return .{
        .abi_version = value.abi_version,
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
        },
    };
}

fn toRequest(desc: *const RequestDesc) BridgeError!Request {
    const scene_id = desc.scene.scene_id orelse return error.InvalidArgument;
    // INVARIANT:
    //   The C ABI request must carry a scene identifier and at least one
    //   spectral sample before it can reach the typed engine.
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

pub fn zdisamar_engine_create(out_engine: *?*CEngine) StatusCode {
    return zdisamar_engine_create_with_options(null, out_engine);
}

/// Purpose:
///   Allocate and bootstrap a typed engine behind the C ABI.
///
/// Physics:
///   None; this is lifecycle plumbing for the exported host entrypoint.
///
/// Vendor:
///   `bridge::zdisamar_engine_create_with_options`
///
/// Inputs:
///   `options` may be null; `out_engine` receives the opaque handle.
///
/// Outputs:
///   Returns `ok` when the engine is initialized and bootstrapped.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   `out_engine` is writable.
///
/// Decisions:
///   The bridge rejects mismatched descriptor sizes instead of guessing at
///   layout compatibility.
///
/// Validation:
///   Covered by the ABI lifecycle test in this file.
pub fn zdisamar_engine_create_with_options(
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

pub fn zdisamar_engine_destroy(engine: ?*CEngine) void {
    const ptr = engine orelse return;
    const handle = castEngine(ptr);
    handle.engine.deinit();
    std.heap.c_allocator.destroy(handle);
}

/// Purpose:
///   Prepare a typed plan from a C ABI plan descriptor.
///
/// Physics:
///   No direct physics; this converts solver and model-family labels into the
///   typed planning surface.
///
/// Vendor:
///   `bridge::zdisamar_plan_prepare`
///
/// Inputs:
///   `plan_desc` carries the model family, transport solver, and solver mode.
///
/// Outputs:
///   Returns an opaque prepared-plan handle on success.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   The plan descriptor uses non-empty C strings.
///
/// Decisions:
///   The plan is prepared through the typed engine first so validation stays in
///   one place.
///
/// Validation:
///   Covered by the ABI lifecycle test in this file.
pub fn zdisamar_plan_prepare(
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

pub fn zdisamar_plan_destroy(plan: ?*CPlan) void {
    const ptr = plan orelse return;
    const handle = castPlan(ptr);
    handle.plan.deinit();
    std.heap.c_allocator.destroy(handle);
}

/// Purpose:
///   Create a workspace bound to the typed engine for later execution.
///
/// Physics:
///   No direct physics; this allocates the per-request execution container.
///
/// Vendor:
///   `bridge::zdisamar_workspace_create`
///
/// Inputs:
///   `out_workspace` receives the opaque workspace handle.
///
/// Outputs:
///   Returns `ok` when the workspace is created.
///
/// Units:
///   N/A.
///
/// Assumptions:
///   `engine` is a valid opaque handle.
///
/// Decisions:
///   The workspace label is fixed here so the ABI side does not invent a new
///   public naming scheme.
///
/// Validation:
///   Covered by the ABI lifecycle test in this file.
pub fn zdisamar_workspace_create(
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

pub fn zdisamar_workspace_destroy(workspace: ?*CWorkspace) void {
    const ptr = workspace orelse return;
    const handle = castWorkspace(ptr);
    handle.deinit();
    std.heap.c_allocator.destroy(handle);
}

/// Purpose:
///   Execute a prepared plan against a C ABI request and write a result.
///
/// Physics:
///   The typed engine performs the actual retrieval and forward-model work;
///   this function only translates descriptors and returned provenance.
///
/// Vendor:
///   `bridge::zdisamar_execute`
///
/// Inputs:
///   `plan`, `workspace`, and `request_desc` must all be valid handles.
///
/// Outputs:
///   Writes a translated result descriptor and returns a bridge status code.
///
/// Units:
///   Spectral values use nanometers via the C descriptor.
///
/// Assumptions:
///   The workspace outlives the call and can own copied provenance strings.
///
/// Decisions:
///   The bridge copies result strings so the C caller can inspect them after
///   the typed result is deinitialized.
///
/// Validation:
///   Covered by the ABI lifecycle test in this file.
pub fn zdisamar_execute(
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

comptime {
    if (c_abi_enabled) {
        @export(&zdisamar_engine_create, .{ .name = "zdisamar_engine_create" });
        @export(&zdisamar_engine_create_with_options, .{ .name = "zdisamar_engine_create_with_options" });
        @export(&zdisamar_engine_destroy, .{ .name = "zdisamar_engine_destroy" });
        @export(&zdisamar_plan_prepare, .{ .name = "zdisamar_plan_prepare" });
        @export(&zdisamar_plan_destroy, .{ .name = "zdisamar_plan_destroy" });
        @export(&zdisamar_workspace_create, .{ .name = "zdisamar_workspace_create" });
        @export(&zdisamar_workspace_destroy, .{ .name = "zdisamar_workspace_destroy" });
        @export(&zdisamar_execute, .{ .name = "zdisamar_execute" });
    }
}

test "default engine options lock C ABI fields" {
    const options = defaultEngineOptions(64);
    try std.testing.expectEqual(@as(u32, @sizeOf(EngineOptionsDesc)), options.struct_size);
    try std.testing.expectEqual(abi_version, options.abi_version);
    try std.testing.expectEqual(@as(u32, 64), options.max_prepared_plans);
}

test "c abi exports stay disabled until the declarative surface is declared stable" {
    try std.testing.expect(!c_abi_enabled);
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
        },
        &result,
    ));

    try std.testing.expectEqual(@as(u64, 1), result.plan_id);
    try std.testing.expectEqual(StatusCode.ok, result.status);
    try std.testing.expectEqualStrings("scene-c-api", std.mem.span(result.scene_id.?));
    try std.testing.expectEqualStrings("builtin.dispatcher", std.mem.span(result.solver_route.?));
}
