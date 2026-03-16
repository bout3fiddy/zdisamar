pub const contracts = @import("contracts.zig");
pub const priors = @import("priors.zig");
pub const covariance = @import("covariance.zig");
pub const forward_model = @import("forward_model.zig");
pub const jacobian_chain = @import("jacobian_chain.zig");
pub const synthetic_forward = @import("synthetic_forward.zig");
pub const surrogate_forward = synthetic_forward;
pub const transforms = @import("transforms.zig");
pub const diagnostics = @import("diagnostics.zig");

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
