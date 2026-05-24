const std = @import("std");
const internal = @import("internal");

const Telemetry = internal.forward_model.calculation_telemetry;

test "calculation telemetry defaults to disabled no-op instrumentation" {
    // instrumentation: calculation telemetry test
    // captures: disabled product-build facade behavior
    // why: prove telemetry hooks can stay in model code without changing default builds.
    try std.testing.expect(!Telemetry.requested);
    try std.testing.expect(!Telemetry.enabled);

    Telemetry.wavelengthSamplingPlan(3, 2, 2, 7, 7, 4, 5);
    Telemetry.forwardMissPlan(3, 7, 5);
    Telemetry.reflectanceAssembly(3, 0, 1.0, 0.5);
    Telemetry.jacobianColumn(1, 2.0, 0.5, 1.25);
    Telemetry.labosLayerDecision(1, 2, 6, 0.4, 0.8, 0.2, 0.064, 1.0e-6, 0.1, 2, true);
    Telemetry.labosDoublingStep(1, 2, 6, 0, 0.1, 0.2, 1.0e-12, false);
    Telemetry.labosDoublingDownstreamGates(
        1,
        2,
        6,
        0,
        false,
        0.1,
        0.2,
        0.2,
        0.01,
        1.0e-12,
        true,
        true,
        true,
    );
    Telemetry.ordersConvergence(3, 12, 1.0e-8, 1.0e-6, false, false);
    Telemetry.fourierContribution(2, 0.25, 0.1, 0.025, 1.0e-8, false);
    Telemetry.labosResult(0.4, 0.4, 0.01);
}
