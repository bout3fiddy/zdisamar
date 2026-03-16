const std = @import("std");

pub const contracts = @import("contracts.zig");
pub const priors = @import("priors.zig");
pub const covariance = @import("covariance.zig");
pub const forward_model = @import("forward_model.zig");
pub const jacobian_chain = @import("jacobian_chain.zig");
pub const surrogate_forward = @import("synthetic_forward.zig");
pub const transforms = @import("transforms.zig");
pub const diagnostics = @import("diagnostics.zig");

test "retrieval common exports surrogate forward naming" {
    try std.testing.expect(@hasDecl(@This(), "surrogate_forward"));
    try std.testing.expect(!@hasDecl(@This(), "synthetic_forward"));
}

test {
    _ = @import("contracts.zig");
    _ = @import("priors.zig");
    _ = @import("covariance.zig");
    _ = @import("forward_model.zig");
    _ = @import("jacobian_chain.zig");
    _ = @import("synthetic_forward.zig");
    _ = @import("transforms.zig");
    _ = @import("diagnostics.zig");
}
