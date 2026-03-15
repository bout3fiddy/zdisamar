const SceneModel = @import("../model/Scene.zig");
const Plan = @import("Plan.zig").Plan;
const DiagnosticsSpec = @import("diagnostics.zig").DiagnosticsSpec;
const errors = @import("errors.zig");

pub const Request = struct {
    scene: SceneModel.Scene,
    inverse_problem: ?SceneModel.InverseProblem = null,
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
    }

    pub fn validateForPlan(self: Request, plan: *const Plan) errors.Error!void {
        try self.validate();

        if (self.expected_derivative_mode) |mode| {
            if (mode != plan.template.scene_blueprint.derivative_mode) {
                return errors.Error.DerivativeModeMismatch;
            }
        }
    }
};
