//! Purpose:
//!   Store state vectors in a structure-of-arrays layout.
//!
//! Physics:
//!   Keeps parameter names and values aligned for typed retrieval state handling.
//!
//! Vendor:
//!   `state vector SoA`
//!
//! Design:
//!   The layout exposes indexed reads and in-place scaling without hiding the parameter axis.
//!
//! Invariants:
//!   Parameter names and values must match the declared axis length.
//!
//! Validation:
//!   Tests cover indexed access and in-place scaling.

const std = @import("std");
const Axes = @import("Axes.zig");

pub const Error = error{
    ShapeMismatch,
    IndexOutOfRange,
} || Axes.Error;

/// Purpose:
///   Store a typed state vector in SoA form.
pub const StateVectorSoA = struct {
    axis: Axes.StateAxis,
    parameter_names: []const []const u8,
    values: []f64,

    /// Purpose:
    ///   Construct a state-vector SoA after validating shape alignment.
    pub fn init(
        axis: Axes.StateAxis,
        parameter_names: []const []const u8,
        values: []f64,
    ) Error!StateVectorSoA {
        try axis.validate();
        const expected = axis.parameter_count;
        if (parameter_names.len != expected) return Error.ShapeMismatch;
        if (values.len != expected) return Error.ShapeMismatch;

        return .{
            .axis = axis,
            .parameter_names = parameter_names,
            .values = values,
        };
    }

    /// Purpose:
    ///   Read a state-vector value by axis index.
    pub fn value(self: StateVectorSoA, index: u32) Error!f64 {
        if (index >= self.axis.parameter_count) return Error.IndexOutOfRange;
        return self.values[index];
    }

    /// Purpose:
    ///   Scale all state-vector values in place.
    pub fn scale(self: StateVectorSoA, factor: f64) void {
        for (self.values) |*entry| {
            entry.* *= factor;
        }
    }
};

test "state vector SoA exposes indexed access and in-place scaling" {
    const parameter_names = [_][]const u8{ "albedo", "ozone_scale", "surface_pressure" };
    var values = [_]f64{ 0.08, 1.1, 1008.0 };

    var state = try StateVectorSoA.init(
        .{ .parameter_count = 3 },
        &parameter_names,
        &values,
    );

    try std.testing.expectApproxEqRel(@as(f64, 1.1), try state.value(1), 1e-12);
    state.scale(2.0);
    try std.testing.expectApproxEqRel(@as(f64, 2016.0), try state.value(2), 1e-12);
}
