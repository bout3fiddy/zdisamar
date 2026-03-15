const Diagnostics = @import("diagnostics.zig").Diagnostics;
const Provenance = @import("provenance.zig").Provenance;
const std = @import("std");
const MeasurementSpaceSummary = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceSummary;
const MeasurementSpaceProduct = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceProduct;
const RetrievalOutcome = @import("../retrieval/common/contracts.zig").SolverOutcome;

const Allocator = std.mem.Allocator;

pub const Result = struct {
    pub const Status = enum {
        success,
        invalid_request,
        internal_error,
    };

    status: Status = .success,
    plan_id: u64,
    workspace_label: []const u8,
    scene_id: []const u8,
    provenance: Provenance = .{},
    diagnostics: Diagnostics = .{},
    measurement_space: ?MeasurementSpaceSummary = null,
    measurement_space_product: ?MeasurementSpaceProduct = null,
    retrieval: ?RetrievalOutcome = null,

    pub fn init(
        plan_id: u64,
        workspace_label: []const u8,
        scene_id: []const u8,
        provenance: Provenance,
    ) Result {
        return .{
            .plan_id = plan_id,
            .workspace_label = workspace_label,
            .scene_id = scene_id,
            .provenance = provenance,
            .diagnostics = Diagnostics.fromSpec(.{ .provenance = true }, "Prepared transport routing and provenance are wired; full transport and retrieval numerics remain scaffold-only."),
        };
    }

    pub fn attachMeasurementSpaceProduct(self: *Result, product: MeasurementSpaceProduct) void {
        self.measurement_space = product.summary;
        self.measurement_space_product = product;
    }

    pub fn attachRetrievalOutcome(self: *Result, outcome: RetrievalOutcome) void {
        self.retrieval = outcome;
    }

    pub fn deinit(self: *Result, allocator: Allocator) void {
        if (self.measurement_space_product) |*product| {
            product.deinit(allocator);
            self.measurement_space_product = null;
        }
        self.provenance.deinit(allocator);
    }
};
