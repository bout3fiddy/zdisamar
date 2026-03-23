//! Purpose:
//!   Store compact tensor blocks in an array-of-structure-of-arrays layout.
//!
//! Physics:
//!   Maps a flattened logical tensor onto fixed-width SIMD-friendly lanes.
//!
//! Vendor:
//!   `tensor block AoSoA`
//!
//! Design:
//!   The lane width is fixed so index arithmetic remains simple and predictable.
//!
//! Invariants:
//!   The block must have at least one lane and the logical length must fit within the lane storage.
//!
//! Validation:
//!   Tests cover linear index mapping and in-place updates.

const std = @import("std");

pub const Error = error{
    InvalidShape,
    IndexOutOfRange,
};

/// Purpose:
///   Fix the lane width used by the AoSoA tensor block.
pub const lane_width: usize = 4;

/// Purpose:
///   Store a tensor block in AoSoA form.
pub const TensorBlockAoSoA = struct {
    lane_count: usize,
    logical_len: usize,
    lanes: [][lane_width]f64,

    /// Purpose:
    ///   Construct a tensor block after validating shape bounds.
    pub fn init(lanes: [][lane_width]f64, logical_len: usize) Error!TensorBlockAoSoA {
        if (lanes.len == 0) return Error.InvalidShape;
        if (logical_len == 0) return Error.InvalidShape;
        if (logical_len > lanes.len * lane_width) return Error.InvalidShape;

        return .{
            .lane_count = lanes.len,
            .logical_len = logical_len,
            .lanes = lanes,
        };
    }

    /// Purpose:
    ///   Read a flattened element from the tensor block.
    pub fn at(self: TensorBlockAoSoA, linear_index: usize) Error!f64 {
        if (linear_index >= self.logical_len) return Error.IndexOutOfRange;
        const lane_index = linear_index / lane_width;
        const offset = linear_index % lane_width;
        return self.lanes[lane_index][offset];
    }

    /// Purpose:
    ///   Write a flattened element into the tensor block.
    pub fn set(self: TensorBlockAoSoA, linear_index: usize, value: f64) Error!void {
        if (linear_index >= self.logical_len) return Error.IndexOutOfRange;
        const lane_index = linear_index / lane_width;
        const offset = linear_index % lane_width;
        self.lanes[lane_index][offset] = value;
    }
};

test "AoSoA tensor block maps linear index onto lane and offset" {
    var lanes = [_][lane_width]f64{
        .{ 1.0, 2.0, 3.0, 4.0 },
        .{ 5.0, 6.0, 7.0, 8.0 },
    };
    const block = try TensorBlockAoSoA.init(&lanes, 7);

    try std.testing.expectApproxEqRel(@as(f64, 1.0), try block.at(0), 1e-12);
    try std.testing.expectApproxEqRel(@as(f64, 7.0), try block.at(6), 1e-12);

    try block.set(6, 9.5);
    try std.testing.expectApproxEqRel(@as(f64, 9.5), try block.at(6), 1e-12);
}
