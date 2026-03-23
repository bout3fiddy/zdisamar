//! Purpose:
//!   Run the retrieval half of a prepared plan when an inverse problem is present.
//!
//! Physics:
//!   Converts the request into a retrieval problem, evaluates candidate scenes through the same
//!   optics/transport path as forward execution, and attaches the solver outcome and materialized
//!   retrieval products to the result.
//!
//! Vendor:
//!   `retrieval execution pipeline`
//!
//! Design:
//!   The retrieval provider owns method-specific policy while this module owns typed execution
//!   context, summary/product callbacks, and result attachment.
//!
//! Invariants:
//!   Retrieval is skipped when no inverse problem is present. Summary/product callbacks must
//!   evaluate scenes through the prepared plan's provider set and transport route.
//!
//! Validation:
//!   Retrieval integration and parity tests covering OE, DOAS, and DISMAS execution through the
//!   public engine surface.

const std = @import("std");

const errors = @import("../errors.zig");
const PreparedPlan = @import("../Plan.zig").PreparedPlan;
const Request = @import("../Request.zig").Request;
const Result = @import("../Result.zig").Result;
const Scene = @import("../../model/Scene.zig").Scene;
const MeasurementSpace = @import("../../kernels/transport/measurement.zig");
const MeasurementSpaceProduct = MeasurementSpace.MeasurementSpaceProduct;
const RetrievalContracts = @import("../../retrieval/common/contracts.zig");
const shared = @import("shared.zig");
const RetrievalProducts = @import("retrieval_products.zig");

/// Purpose:
///   Execute the selected retrieval provider and attach owned retrieval outputs to the result.
pub fn execute(
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    request: *const Request,
    result: *Result,
) errors.Error!void {
    if (request.inverse_problem == null) return;

    const retrieval_provider = plan.providers.retrieval orelse return errors.Error.InvalidRequest;
    var summary_workspace: MeasurementSpace.SummaryWorkspace = .{};
    defer summary_workspace.deinit(allocator);
    const retrieval_problem = RetrievalContracts.RetrievalProblem.fromRequest(request) catch {
        return errors.Error.InvalidRequest;
    };
    const retrieval_context: RetrievalExecutionContext = .{
        .allocator = allocator,
        .plan = plan,
        .summary_workspace = &summary_workspace,
    };
    var retrieval_outcome = retrieval_provider.solve(allocator, retrieval_problem, .{
        .context = @ptrCast(&retrieval_context),
        .evaluateSummary = evaluateRetrievalSceneSummary,
        .evaluateProduct = evaluateRetrievalSceneProduct,
    }) catch |err| switch (err) {
        error.OutOfMemory => return errors.Error.OutOfMemory,
        else => return errors.Error.InvalidRequest,
    };
    errdefer retrieval_outcome.deinit(allocator);
    const retrieval_products = try RetrievalProducts.materialize(
        allocator,
        plan,
        retrieval_problem,
        retrieval_outcome,
    );
    result.attachRetrievalOutcome(retrieval_outcome);
    result.attachRetrievalProducts(retrieval_products);
}

const RetrievalExecutionContext = struct {
    allocator: std.mem.Allocator,
    plan: *const PreparedPlan,
    summary_workspace: *MeasurementSpace.SummaryWorkspace,
};

/// Purpose:
///   Evaluate a candidate retrieval scene into a summary-only measurement-space product.
fn evaluateRetrievalSceneSummary(
    context: *const anyopaque,
    scene: Scene,
) anyerror!MeasurementSpace.MeasurementSpaceSummary {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(typed_context.allocator, &scene);
    defer prepared_optics.deinit(typed_context.allocator);

    return MeasurementSpace.simulateSummaryWithWorkspace(
        typed_context.allocator,
        typed_context.summary_workspace,
        &scene,
        typed_context.plan.transport_route,
        &prepared_optics,
        shared.measurementProviders(typed_context.plan),
    );
}

/// Purpose:
///   Evaluate a candidate retrieval scene into a fully sampled measurement-space product.
fn evaluateRetrievalSceneProduct(
    allocator: std.mem.Allocator,
    context: *const anyopaque,
    scene: Scene,
) anyerror!MeasurementSpaceProduct {
    const typed_context: *const RetrievalExecutionContext = @ptrCast(@alignCast(context));

    var prepared_optics = try typed_context.plan.providers.optics.prepareForScene(allocator, &scene);
    defer prepared_optics.deinit(allocator);

    return MeasurementSpace.simulateProduct(
        allocator,
        &scene,
        typed_context.plan.transport_route,
        &prepared_optics,
        shared.measurementProviders(typed_context.plan),
    );
}
