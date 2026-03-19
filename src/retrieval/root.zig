const std = @import("std");

pub const common = struct {
    pub const contracts = @import("common/contracts.zig");
    pub const covariance = @import("common/covariance.zig");
    pub const diagnostics = @import("common/diagnostics.zig");
    pub const forward_model = @import("common/forward_model.zig");
    pub const priors = @import("common/priors.zig");
    pub const spectral_fit = @import("common/spectral_fit.zig");
    pub const state_access = @import("common/state_access.zig");
    pub const surrogate_forward = @import("common/surrogate_forward.zig");
};

pub const oe = @import("oe/root.zig");
pub const doas = @import("doas/root.zig");
pub const dismas = @import("dismas/root.zig");

test "retrieval root surfaces surrogate forward naming" {
    try std.testing.expect(@hasDecl(common, "surrogate_forward"));
    try std.testing.expect(!@hasDecl(common, "synthetic_forward"));
}

test {
    std.testing.refAllDecls(@This());
}
