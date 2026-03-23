//! Purpose:
//!   Track reusable scratch-capacity reservations for one workspace or thread context.
//!
//! Physics:
//!   This module stores capacity hints only. It does not own numerical buffers, but it preserves
//!   the largest spectral/layer/state/measurement requirements seen so repeated evaluations can
//!   reuse the same scratch strategy.
//!
//! Vendor:
//!   `scratch-capacity reservation`
//!
//! Design:
//!   Keep scratch reuse lightweight by storing only counts derived from prepared layouts rather
//!   than allocating typed buffers here.
//!
//! Invariants:
//!   Reserved capacities are monotonic maxima until the workspace/thread is destroyed. `reset`
//!   records lifecycle transitions but does not shrink capacities.
//!
//! Validation:
//!   Scratch-arena tests in this file and workspace/batch-runner tests that reuse prepared
//!   layouts across repeated execution.

const std = @import("std");
const PreparedLayout = @import("../cache/PreparedLayout.zig").PreparedLayout;

/// Purpose:
///   Store reusable capacity hints derived from prepared layouts.
pub const ScratchArena = struct {
    spectral_capacity: usize = 0,
    layer_capacity: usize = 0,
    state_capacity: usize = 0,
    measurement_capacity: usize = 0,
    reserve_count: u64 = 0,
    reset_count: u64 = 0,

    /// Purpose:
    ///   Expand the stored capacity hints to cover the given prepared layout.
    pub fn reserveFromLayout(self: *ScratchArena, prepared_layout: *const PreparedLayout) void {
        self.spectral_capacity = @max(self.spectral_capacity, prepared_layout.layout_requirements.spectral_sample_count);
        self.layer_capacity = @max(self.layer_capacity, prepared_layout.layout_requirements.layer_count);
        self.state_capacity = @max(self.state_capacity, prepared_layout.layout_requirements.state_parameter_count);
        self.measurement_capacity = @max(self.measurement_capacity, prepared_layout.measurement_capacity);
        self.reserve_count += 1;
    }

    /// Purpose:
    ///   Record a scratch reset without discarding the already reserved capacity maxima.
    pub fn reset(self: *ScratchArena) void {
        self.reset_count += 1;
    }
};

test "scratch arena keeps the largest reserved capacities across resets" {
    var scratch: ScratchArena = .{};
    const small: PreparedLayout = .{
        .layout_requirements = .{
            .spectral_start_nm = 400.0,
            .spectral_end_nm = 410.0,
            .spectral_sample_count = 16,
            .layer_count = 24,
            .state_parameter_count = 2,
            .measurement_count = 16,
        },
        .measurement_capacity = 16,
    };
    const large: PreparedLayout = .{
        .layout_requirements = .{
            .spectral_start_nm = 400.0,
            .spectral_end_nm = 410.0,
            .spectral_sample_count = 64,
            .layer_count = 48,
            .state_parameter_count = 4,
            .measurement_count = 64,
        },
        .measurement_capacity = 64,
    };

    scratch.reserveFromLayout(&small);
    scratch.reset();
    scratch.reserveFromLayout(&large);
    scratch.reset();
    scratch.reserveFromLayout(&small);

    try std.testing.expectEqual(@as(usize, 64), scratch.spectral_capacity);
    try std.testing.expectEqual(@as(usize, 48), scratch.layer_capacity);
    try std.testing.expectEqual(@as(usize, 4), scratch.state_capacity);
    try std.testing.expectEqual(@as(usize, 64), scratch.measurement_capacity);
    try std.testing.expectEqual(@as(u64, 3), scratch.reserve_count);
    try std.testing.expectEqual(@as(u64, 2), scratch.reset_count);
}

test "scheduler package includes thread context and batch runner implementations" {
    _ = @import("ThreadContext.zig");
    _ = @import("BatchRunner.zig");
}
