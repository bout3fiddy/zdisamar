//! Purpose:
//!   Compute solver convergence and fit-quality diagnostics for retrieval
//!   outputs.
//!
//! Physics:
//!   These metrics summarize the cost, reduced chi-square, step size, and
//!   degrees of freedom used to judge whether a retrieval has converged.
//!
//! Vendor:
//!   Rodgers-style and method-specific fit assessment stages.
//!
//! Design:
//!   Keep the common convergence test separate from method-specific
//!   diagnostic payloads so OE, DOAS, and DISMAS can share the same core
//!   summary.
//!
//! Invariants:
//!   Fit statistics must stay numerically stable even when the previous cost
//!   is missing.
//!
//! Validation:
//!   Retrieval diagnostics tests cover the common and method-specific summary
//!   paths.

const std = @import("std");
const Convergence = @import("../../model/InverseProblem.zig").Convergence;
const vector_ops = @import("../../kernels/linalg/vector_ops.zig");

pub const Summary = struct {
    measurement_cost: f64,
    prior_cost: f64,
    total_cost: f64,
    reduced_chi_square: f64,
    step_norm: f64,
    state_relative: f64,
    cost_relative: f64,
    dfs: f64,
    converged: bool,
};

pub const DifferentialSummary = struct {
    common: Summary,
    polynomial_order: u32,
    effective_air_mass_factor: f64,
    weighted_residual_rms: f64,
    fit_window_start_nm: f64,
    fit_window_end_nm: f64,
    effective_cross_section_rms: ?f64 = null,
};

pub const DirectIntensitySummary = struct {
    common: Summary,
    polynomial_order: u32,
    effective_air_mass_factor: f64,
    weighted_residual_rms: f64,
    fit_window_start_nm: f64,
    fit_window_end_nm: f64,
    selected_rtm_sample_count: u32,
    selection_zero_crossing_count: u32,
};

/// Purpose:
///   Compute the method-agnostic convergence summary.
pub fn assess(
    previous_total_cost: ?f64,
    measurement_cost: f64,
    prior_cost: f64,
    step: []const f64,
    state: []const f64,
    convergence: Convergence,
    measurement_count: u32,
    dfs: f64,
) Summary {
    const total_cost = measurement_cost + prior_cost;
    const step_norm = vector_ops.normL2(step);
    const state_relative = vector_ops.relativeNorm(step, state) catch 0.0;
    const cost_relative = if (previous_total_cost) |previous|
        @abs(previous - total_cost) / @max(@abs(previous), 1.0)
    else
        std.math.inf(f64);
    const reduced_chi_square = measurement_cost / @max(@as(f64, @floatFromInt(measurement_count)), 1.0);

    // DECISION:
    //   Fall back to conservative default thresholds when the inverse problem
    //   does not specify explicit convergence limits.
    const cost_threshold = if (convergence.cost_relative > 0.0) convergence.cost_relative else 1.0e-4;
    const state_threshold = if (convergence.state_relative > 0.0) convergence.state_relative else 1.0e-4;

    return .{
        .measurement_cost = measurement_cost,
        .prior_cost = prior_cost,
        .total_cost = total_cost,
        .reduced_chi_square = reduced_chi_square,
        .step_norm = step_norm,
        .state_relative = state_relative,
        .cost_relative = cost_relative,
        .dfs = dfs,
        .converged = cost_relative <= cost_threshold and state_relative <= state_threshold,
    };
}

/// Purpose:
///   Compute the differential-optical-depth diagnostic payload.
pub fn assessDifferential(
    previous_total_cost: ?f64,
    measurement_cost: f64,
    prior_cost: f64,
    step: []const f64,
    state: []const f64,
    convergence: Convergence,
    measurement_count: u32,
    dfs: f64,
    polynomial_order: u32,
    effective_air_mass_factor: f64,
    fit_window_start_nm: f64,
    fit_window_end_nm: f64,
    effective_cross_section_rms: ?f64,
) DifferentialSummary {
    const common_summary = assess(
        previous_total_cost,
        measurement_cost,
        prior_cost,
        step,
        state,
        convergence,
        measurement_count,
        dfs,
    );
    return .{
        .common = common_summary,
        .polynomial_order = polynomial_order,
        .effective_air_mass_factor = effective_air_mass_factor,
        .weighted_residual_rms = std.math.sqrt(
            measurement_cost / @max(@as(f64, @floatFromInt(measurement_count)), 1.0),
        ),
        .fit_window_start_nm = fit_window_start_nm,
        .fit_window_end_nm = fit_window_end_nm,
        .effective_cross_section_rms = effective_cross_section_rms,
    };
}

/// Purpose:
///   Compute the direct-intensity diagnostic payload.
pub fn assessDirectIntensity(
    previous_total_cost: ?f64,
    measurement_cost: f64,
    prior_cost: f64,
    step: []const f64,
    state: []const f64,
    convergence: Convergence,
    measurement_count: u32,
    dfs: f64,
    polynomial_order: u32,
    effective_air_mass_factor: f64,
    fit_window_start_nm: f64,
    fit_window_end_nm: f64,
    selected_rtm_sample_count: u32,
    selection_zero_crossing_count: u32,
) DirectIntensitySummary {
    const common_summary = assess(
        previous_total_cost,
        measurement_cost,
        prior_cost,
        step,
        state,
        convergence,
        measurement_count,
        dfs,
    );
    return .{
        .common = common_summary,
        .polynomial_order = polynomial_order,
        .effective_air_mass_factor = effective_air_mass_factor,
        .weighted_residual_rms = std.math.sqrt(
            measurement_cost / @max(@as(f64, @floatFromInt(measurement_count)), 1.0),
        ),
        .fit_window_start_nm = fit_window_start_nm,
        .fit_window_end_nm = fit_window_end_nm,
        .selected_rtm_sample_count = selected_rtm_sample_count,
        .selection_zero_crossing_count = selection_zero_crossing_count,
    };
}

test "retrieval diagnostics compute Rodgers-style convergence metrics" {
    const summary = assess(
        10.0,
        2.0,
        0.5,
        &.{ 0.01, 0.02 },
        &.{ 1.0, 2.0 },
        .{ .cost_relative = 0.9, .state_relative = 0.1 },
        8,
        1.3,
    );
    try std.testing.expect(summary.converged);
    try std.testing.expectApproxEqRel(@as(f64, 0.25), summary.reduced_chi_square, 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.3), summary.dfs, 1e-12);
}

test "differential diagnostics report method-specific fit metadata" {
    const summary = assessDifferential(
        8.0,
        2.0,
        0.5,
        &.{ 0.01, -0.02 },
        &.{ 1.0, 1.5 },
        .{ .cost_relative = 0.9, .state_relative = 0.1 },
        10,
        1.1,
        3,
        2.4,
        759.0,
        767.0,
        0.7,
    );
    try std.testing.expect(summary.common.converged);
    try std.testing.expectEqual(@as(u32, 3), summary.polynomial_order);
    try std.testing.expectApproxEqRel(@as(f64, 2.4), summary.effective_air_mass_factor, 1.0e-12);
    try std.testing.expect(summary.weighted_residual_rms > 0.0);
    try std.testing.expect(summary.effective_cross_section_rms != null);
}

test "direct-intensity diagnostics track RTM selection metadata" {
    const summary = assessDirectIntensity(
        8.0,
        3.0,
        0.5,
        &.{ 0.01, -0.02 },
        &.{ 1.0, 1.5 },
        .{ .cost_relative = 0.9, .state_relative = 0.1 },
        12,
        1.5,
        1,
        1.9,
        405.0,
        465.0,
        64,
        17,
    );
    try std.testing.expect(summary.common.converged);
    try std.testing.expectEqual(@as(u32, 64), summary.selected_rtm_sample_count);
    try std.testing.expectEqual(@as(u32, 17), summary.selection_zero_crossing_count);
    try std.testing.expect(summary.weighted_residual_rms > 0.0);
}
