const zdisamar = @import("zdisamar");
const std = @import("std");

pub const common = struct {
    pub const contracts = zdisamar.retrieval_modules.common.contracts;
    pub const covariance = zdisamar.retrieval_modules.common.covariance;
    pub const diagnostics = zdisamar.retrieval_modules.common.diagnostics;
    pub const forward_model = zdisamar.retrieval_modules.common.forward_model;
    pub const priors = zdisamar.retrieval_modules.common.priors;
    pub const synthetic_forward = zdisamar.retrieval_modules.common.synthetic_forward;
};

pub const oe = zdisamar.retrieval_modules.oe;
pub const doas = zdisamar.retrieval_modules.doas;
pub const dismas = zdisamar.retrieval_modules.dismas;

test {
    std.testing.refAllDecls(@This());
}
