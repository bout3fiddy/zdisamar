//! Purpose:
//!   Apply state transforms to Jacobians and assemble normal-equation terms
//!   for retrieval solvers.
//!
//! Physics:
//!   The helpers here scale Jacobian columns by transform derivatives and
//!   accumulate the weighted normal matrix and gradient used in nonlinear
//!   least-squares retrievals.
//!
//! Vendor:
//!   Jacobian chaining and normal-equation accumulation stages.
//!
//! Design:
//!   Keep these routines low-level and explicit so solver modules can choose
//!   between diagonal and dense inverse measurement covariance paths.
//!
//! Invariants:
//!   Row/column dimensions must agree exactly and every dense output must be
//!   fully initialized before use.
//!
//! Validation:
//!   Retrieval Jacobian-chain tests exercise the transform scaling and
//!   weighted accumulation helpers.

const std = @import("std");
const dense = @import("../../kernels/linalg/small_dense.zig");

pub const Error = error{
    ShapeMismatch,
};

pub fn applyColumnScales(
    jacobian: []const f64,
    row_count: usize,
    column_count: usize,
    column_scales: []const f64,
    output: []f64,
) Error!void {
    if (jacobian.len != row_count * column_count or
        output.len != jacobian.len or
        column_scales.len != column_count)
    {
        return Error.ShapeMismatch;
    }

    for (0..row_count) |row| {
        for (0..column_count) |column| {
            output[dense.index(row, column, column_count)] =
                jacobian[dense.index(row, column, column_count)] * column_scales[column];
        }
    }
}

pub fn accumulateNormalMatrix(
    jacobian: []const f64,
    row_count: usize,
    column_count: usize,
    inverse_measurement_variance: []const f64,
    output: []f64,
) Error!void {
    if (jacobian.len != row_count * column_count or
        inverse_measurement_variance.len != row_count or
        output.len != column_count * column_count)
    {
        return Error.ShapeMismatch;
    }

    @memset(output, 0.0);
    for (0..column_count) |lhs_column| {
        for (lhs_column..column_count) |rhs_column| {
            var total: f64 = 0.0;
            for (0..row_count) |row| {
                total += jacobian[dense.index(row, lhs_column, column_count)] *
                    inverse_measurement_variance[row] *
                    jacobian[dense.index(row, rhs_column, column_count)];
            }
            output[dense.index(lhs_column, rhs_column, column_count)] = total;
            output[dense.index(rhs_column, lhs_column, column_count)] = total;
        }
    }
}

pub fn accumulateNormalMatrixWithInverseCovariance(
    jacobian: []const f64,
    row_count: usize,
    column_count: usize,
    inverse_measurement_covariance: []const f64,
    output: []f64,
) Error!void {
    if (jacobian.len != row_count * column_count or
        inverse_measurement_covariance.len != row_count * row_count or
        output.len != column_count * column_count)
    {
        return Error.ShapeMismatch;
    }

    @memset(output, 0.0);
    for (0..column_count) |lhs_column| {
        for (lhs_column..column_count) |rhs_column| {
            var total: f64 = 0.0;
            for (0..row_count) |lhs_row| {
                const lhs_value = jacobian[dense.index(lhs_row, lhs_column, column_count)];
                for (0..row_count) |rhs_row| {
                    total += lhs_value *
                        inverse_measurement_covariance[dense.index(lhs_row, rhs_row, row_count)] *
                        jacobian[dense.index(rhs_row, rhs_column, column_count)];
                }
            }
            output[dense.index(lhs_column, rhs_column, column_count)] = total;
            output[dense.index(rhs_column, lhs_column, column_count)] = total;
        }
    }
}

pub fn accumulateWeightedResidual(
    jacobian: []const f64,
    row_count: usize,
    column_count: usize,
    inverse_measurement_variance: []const f64,
    residual: []const f64,
    output: []f64,
) Error!void {
    if (jacobian.len != row_count * column_count or
        inverse_measurement_variance.len != row_count or
        residual.len != row_count or
        output.len != column_count)
    {
        return Error.ShapeMismatch;
    }

    @memset(output, 0.0);
    for (0..column_count) |column| {
        var total: f64 = 0.0;
        for (0..row_count) |row| {
            total += jacobian[dense.index(row, column, column_count)] *
                inverse_measurement_variance[row] *
                residual[row];
        }
        output[column] = total;
    }
}

pub fn accumulateWeightedResidualWithInverseCovariance(
    jacobian: []const f64,
    row_count: usize,
    column_count: usize,
    inverse_measurement_covariance: []const f64,
    residual: []const f64,
    output: []f64,
) Error!void {
    if (jacobian.len != row_count * column_count or
        inverse_measurement_covariance.len != row_count * row_count or
        residual.len != row_count or
        output.len != column_count)
    {
        return Error.ShapeMismatch;
    }

    @memset(output, 0.0);
    for (0..column_count) |column| {
        var total: f64 = 0.0;
        for (0..row_count) |lhs_row| {
            const lhs_value = jacobian[dense.index(lhs_row, column, column_count)];
            for (0..row_count) |rhs_row| {
                total += lhs_value *
                    inverse_measurement_covariance[dense.index(lhs_row, rhs_row, row_count)] *
                    residual[rhs_row];
            }
        }
        output[column] = total;
    }
}

test "jacobian chain applies transform scaling and weighted accumulation" {
    const row_count = 2;
    const column_count = 2;
    const jacobian = [_]f64{
        1.0, 2.0,
        3.0, 4.0,
    };
    const scales = [_]f64{ 2.0, 0.5 };
    var scaled: [4]f64 = undefined;
    try applyColumnScales(&jacobian, row_count, column_count, &scales, &scaled);
    try std.testing.expectEqual(@as(f64, 2.0), scaled[0]);
    try std.testing.expectEqual(@as(f64, 1.0), scaled[1]);

    const inv_variance = [_]f64{ 4.0, 1.0 };
    var normal: [4]f64 = undefined;
    try accumulateNormalMatrix(&scaled, row_count, column_count, &inv_variance, &normal);
    try std.testing.expect(normal[dense.index(0, 0, column_count)] > 0.0);
    try std.testing.expectEqual(
        normal[dense.index(0, 1, column_count)],
        normal[dense.index(1, 0, column_count)],
    );
}

test "jacobian chain supports explicit inverse covariance matrices" {
    const row_count = 2;
    const column_count = 2;
    const jacobian = [_]f64{
        2.0, 1.0,
        6.0, 2.0,
    };
    const inverse_covariance = [_]f64{
        4.0, 0.0,
        0.0, 1.0,
    };
    var normal: [4]f64 = undefined;
    try accumulateNormalMatrixWithInverseCovariance(&jacobian, row_count, column_count, &inverse_covariance, &normal);
    try std.testing.expectApproxEqRel(@as(f64, 52.0), normal[dense.index(0, 0, column_count)], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 20.0), normal[dense.index(0, 1, column_count)], 1.0e-12);

    const residual = [_]f64{ 0.5, -0.25 };
    var weighted: [2]f64 = undefined;
    try accumulateWeightedResidualWithInverseCovariance(&jacobian, row_count, column_count, &inverse_covariance, &residual, &weighted);
    try std.testing.expectApproxEqRel(@as(f64, 2.5), weighted[0], 1.0e-12);
    try std.testing.expectApproxEqRel(@as(f64, 1.5), weighted[1], 1.0e-12);
}
