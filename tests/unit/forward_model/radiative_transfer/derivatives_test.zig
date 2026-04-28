const std = @import("std");
const internal = @import("internal");

const derivatives = internal.forward_model.radiative_transfer.derivatives;
const dTransmittanceDOpticalDepth = derivatives.dTransmittanceDOpticalDepth;
const proxyOpticalDepthSensitivity = derivatives.proxyOpticalDepthSensitivity;
const proxyJacobianColumn = derivatives.proxyJacobianColumn;

test "transport derivative helpers expose analytical transmittance gradients" {
    try std.testing.expectApproxEqRel(@as(f64, -std.math.exp(-0.5)), dTransmittanceDOpticalDepth(0.5), 1e-12);
    try std.testing.expectApproxEqRel(
        @as(f64, -1.1),
        proxyOpticalDepthSensitivity(1.0, 0.1, 1.0, 1.0),
        1e-12,
    );
    try std.testing.expect(proxyJacobianColumn(1.0, 0.5, 0.1) < 0.0);
}
