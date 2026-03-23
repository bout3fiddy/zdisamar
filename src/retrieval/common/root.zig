//! Purpose:
//!   Re-export the canonical retrieval helper vocabulary used by OE, DOAS,
//!   and DISMAS solver paths.
//!
//! Physics:
//!   This namespace does not implement science itself. It collects the
//!   contracts, transforms, covariance helpers, and forward-model selectors
//!   that shape retrieval behavior.
//!
//! Vendor:
//!   Retrieval common helper surface and solver-shared stage names.
//!
//! Design:
//!   Keep the solver-specific files focused on policy and iteration control
//!   while this module provides a stable namespace for shared retrieval
//!   plumbing.
//!
//! Invariants:
//!   The re-export set must stay limited to retrieval-common helpers; no
//!   adapter or engine wiring belongs here.
//!
//! Validation:
//!   Compilation of the solver packages and retrieval unit tests exercises
//!   this package root.

const std = @import("std");

pub const contracts = @import("contracts.zig");
pub const priors = @import("priors.zig");
pub const covariance = @import("covariance.zig");
pub const forward_model = @import("forward_model.zig");
pub const jacobian_chain = @import("jacobian_chain.zig");
pub const state_access = @import("state_access.zig");
pub const spectral_fit = @import("spectral_fit.zig");
pub const surrogate_forward = @import("surrogate_forward.zig");
pub const transforms = @import("transforms.zig");
pub const diagnostics = @import("diagnostics.zig");

test "retrieval common exports surrogate forward naming" {
    try std.testing.expect(@hasDecl(@This(), "surrogate_forward"));
    try std.testing.expect(!@hasDecl(@This(), "synthetic_forward"));
    try std.testing.expectEqual(
        surrogate_forward.UsageClass.test_only,
        surrogate_forward.usage_class,
    );
}

test {
    _ = @import("contracts.zig");
    _ = @import("priors.zig");
    _ = @import("covariance.zig");
    _ = @import("forward_model.zig");
    _ = @import("jacobian_chain.zig");
    _ = @import("state_access.zig");
    _ = @import("spectral_fit.zig");
    _ = @import("surrogate_forward.zig");
    _ = @import("transforms.zig");
    _ = @import("diagnostics.zig");
}
