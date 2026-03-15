pub const Summary = struct {
    reduced_chi_square: f64,
    step_norm: f64,
    converged: bool,
};

pub fn assess(cost: f64, step_norm: f64, measurement_count: u32) Summary {
    const dof = @max(measurement_count, 1);
    return .{
        .reduced_chi_square = cost / @as(f64, @floatFromInt(dof)),
        .step_norm = step_norm,
        .converged = step_norm < 1.0 and cost < @as(f64, @floatFromInt(dof)),
    };
}

test "retrieval diagnostics compute reduced chi-square and convergence" {
    const summary = assess(2.0, 0.2, 8);
    try std.testing.expect(summary.converged);
    try std.testing.expectApproxEqRel(@as(f64, 0.25), summary.reduced_chi_square, 1e-12);
}

const std = @import("std");
