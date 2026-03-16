const SceneModel = @import("../model/Scene.zig");
const Plan = @import("Plan.zig").Plan;
const DiagnosticsSpec = @import("diagnostics.zig").DiagnosticsSpec;
const errors = @import("errors.zig");
const MeasurementSpaceProduct = @import("../kernels/transport/measurement_space.zig").MeasurementSpaceProduct;
const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Request = struct {
    pub const MeasurementBinding = struct {
        source_name: []const u8 = "",
        observable: []const u8 = "",
        product: *const MeasurementSpaceProduct,

        pub fn validate(self: MeasurementBinding) errors.Error!void {
            if (self.source_name.len == 0) return errors.Error.InvalidRequest;
            if (self.product.summary.sample_count == 0) return errors.Error.InvalidRequest;
        }
    };

    scene: SceneModel.Scene,
    inverse_problem: ?SceneModel.InverseProblem = null,
    measurement_binding: ?MeasurementBinding = null,
    requested_products: []const []const u8 = &[_][]const u8{},
    expected_derivative_mode: ?SceneModel.DerivativeMode = null,
    diagnostics: DiagnosticsSpec = .{},

    pub fn init(scene: SceneModel.Scene) Request {
        return .{ .scene = scene };
    }

    pub fn validate(self: Request) errors.Error!void {
        try self.scene.validate();
        if (self.inverse_problem) |inverse_problem| {
            try inverse_problem.validate();
        }
        if (self.measurement_binding) |binding| {
            try binding.validate();
        }
    }

    pub fn validateForPlan(self: Request, plan: *const Plan) errors.Error!void {
        try self.validate();

        if (self.inverse_problem) |inverse_problem| {
            switch (inverse_problem.measurements.source.kind) {
                .stage_product, .external_observation => {
                    const binding = self.measurement_binding orelse return errors.Error.InvalidRequest;
                    if (inverse_problem.measurements.source.name.len != 0 and
                        !std.mem.eql(u8, inverse_problem.measurements.source.name, binding.source_name))
                    {
                        return errors.Error.InvalidRequest;
                    }
                    if (binding.observable.len != 0 and
                        inverse_problem.measurements.observable.len != 0 and
                        !std.mem.eql(u8, inverse_problem.measurements.observable, binding.observable))
                    {
                        return errors.Error.InvalidRequest;
                    }
                    if (binding.product.summary.sample_count != inverse_problem.measurements.sample_count) {
                        return errors.Error.InvalidRequest;
                    }
                },
                else => {},
            }
        }

        if (self.expected_derivative_mode) |mode| {
            if (mode != plan.transport_route.derivative_mode) {
                return errors.Error.DerivativeModeMismatch;
            }
        }
    }

    pub fn deinitOwned(self: *Request, allocator: Allocator) void {
        self.scene.deinitOwned(allocator);
        if (self.inverse_problem) |*inverse_problem| {
            inverse_problem.deinitOwned(allocator);
        }
        self.* = undefined;
    }
};
