const std = @import("std");
const Transform = @import("../../model/StateVector.zig").Transform;

pub const Error = error{
    InvalidStateValue,
};

pub fn toSolverSpace(transform: Transform, physical_value: f64) Error!f64 {
    return switch (transform) {
        .none => physical_value,
        .log => {
            if (physical_value <= 0.0) return Error.InvalidStateValue;
            return std.math.log(f64, std.math.e, physical_value);
        },
        .logit => {
            if (physical_value <= 0.0 or physical_value >= 1.0) return Error.InvalidStateValue;
            return std.math.log(f64, std.math.e, physical_value / (1.0 - physical_value));
        },
    };
}

pub fn toPhysicalSpace(transform: Transform, solver_value: f64) f64 {
    return switch (transform) {
        .none => solver_value,
        .log => std.math.exp(solver_value),
        .logit => {
            const exp_value = std.math.exp(solver_value);
            return exp_value / (1.0 + exp_value);
        },
    };
}

pub fn dPhysicalDsolver(transform: Transform, solver_value: f64) f64 {
    return switch (transform) {
        .none => 1.0,
        .log => std.math.exp(solver_value),
        .logit => {
            const physical_value = toPhysicalSpace(.logit, solver_value);
            return physical_value * (1.0 - physical_value);
        },
    };
}

test "state transforms round-trip positive and bounded values" {
    const log_solver = try toSolverSpace(.log, 3.0);
    try std.testing.expectApproxEqRel(@as(f64, 3.0), toPhysicalSpace(.log, log_solver), 1e-12);

    const logit_solver = try toSolverSpace(.logit, 0.25);
    try std.testing.expectApproxEqRel(@as(f64, 0.25), toPhysicalSpace(.logit, logit_solver), 1e-12);
    try std.testing.expect(dPhysicalDsolver(.logit, logit_solver) > 0.0);
}
