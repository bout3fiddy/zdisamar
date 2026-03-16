const zdisamar = @import("zdisamar");
const std = @import("std");

pub const common = struct {
    pub const contracts = zdisamar.RetrievalContracts;
    pub const covariance = zdisamar.RetrievalCovariance;
    pub const diagnostics = zdisamar.RetrievalDiagnostics;
    pub const forward_model = zdisamar.RetrievalForwardModel;
    pub const priors = zdisamar.RetrievalPriors;
    pub const synthetic_forward = zdisamar.RetrievalSyntheticForward;
};

pub const oe = zdisamar.RetrievalOE;
pub const doas = zdisamar.RetrievalDOAS;
pub const dismas = zdisamar.RetrievalDISMAS;

test {
    std.testing.refAllDecls(@This());
}
