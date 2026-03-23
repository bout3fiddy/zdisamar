//! Purpose:
//!   Run the forward execution half of a prepared plan.
//!
//! Physics:
//!   Bridges plan-time provider selection into runtime optics preparation, transport simulation,
//!   and provenance/result initialization for the requested scene.
//!
//! Vendor:
//!   `forward execution pipeline`
//!
//! Design:
//!   Split execution into request/workspace setup, result initialization, and forward-product
//!   materialization so each stage can fail with typed ownership boundaries.
//!
//! Invariants:
//!   Plugin execute hooks run before workspace binding. Result provenance is initialized before
//!   forward products are attached.
//!
//! Validation:
//!   Engine execution tests and forward-product integration tests that exercise measurement-space
//!   simulation through the public engine API.

const std = @import("std");

const errors = @import("../errors.zig");
const PreparedPlan = @import("../Plan.zig").PreparedPlan;
const Request = @import("../Request.zig").Request;
const Result = @import("../Result.zig").Result;
const Workspace = @import("../Workspace.zig").Workspace;
const Provenance = @import("../provenance.zig").Provenance;
const PlanCache = @import("../../runtime/cache/PlanCache.zig").PlanCache;
const PluginRuntime = @import("../../plugins/loader/runtime.zig");
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const shared = @import("shared.zig");

/// Purpose:
///   Execute plan/runtime hooks, bind the workspace, and reserve scratch for the request.
pub fn beginExecution(
    plan_cache: *PlanCache,
    plan: *const PreparedPlan,
    workspace: *Workspace,
    request: *const Request,
) errors.Error!void {
    plan.plugin_runtime.executeForRequest(.{
        .plan_id = plan.id,
        .scene_id = request.scene.id,
        .workspace_label = workspace.label,
        .requested_product_count = @intCast(request.requested_products.len),
    }) catch |err| return mapPluginExecutionError(err);
    try workspace.beginExecution(plan.id);
    workspace.prepareScratch(&plan.prepared_layout);
    _ = plan_cache.markRun(plan.id);
}

/// Purpose:
///   Initialize the owned result and provenance for a forward/retrieval execution.
pub fn initializeResult(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    workspace: *Workspace,
    request: *const Request,
    result: *Result,
) errors.Error!void {
    var provenance: Provenance = undefined;
    Provenance.fromPlanOwned(
        &provenance,
        allocator,
        plan,
        workspace.label,
        request.scene.id,
        @tagName(plan.template.solver_mode),
    ) catch |err| return err;
    errdefer provenance.deinit(allocator);

    try result.initOwned(
        allocator,
        plan.id,
        workspace.label,
        request.scene.id,
        provenance,
    );
}

/// Purpose:
///   Prepare optics and attach the forward measurement-space product to the result.
pub fn executeForwardProducts(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    request: *const Request,
    result: *Result,
) errors.Error!void {
    var prepared_optics = plan.providers.optics.prepareForScene(allocator, &request.scene) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.Error.InvalidRequest,
    };
    defer prepared_optics.deinit(allocator);

    const measurement_space_product = MeasurementSpace.simulateProduct(
        allocator,
        &request.scene,
        plan.transport_route,
        &prepared_optics,
        shared.measurementProviders(plan),
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return errors.Error.InvalidRequest,
    };
    result.attachMeasurementSpaceProduct(measurement_space_product);
}

/// Purpose:
///   Translate native-plugin execute failures into public engine execution errors.
fn mapPluginExecutionError(err: PluginRuntime.Error) errors.Error {
    return switch (err) {
        error.MissingExecuteHook => errors.Error.MissingExecuteHook,
        error.PluginEntryIncompatibleAbi => errors.Error.PluginEntryIncompatibleAbi,
        else => errors.Error.PluginExecutionFailed,
    };
}
