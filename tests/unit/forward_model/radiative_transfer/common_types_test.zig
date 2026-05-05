const std = @import("std");
const internal = @import("internal");

const common = internal.forward_model.radiative_transfer;

test "accuracy target leaves exact tolerances unchanged by default" {
    const controls = common.RadiativeTransferControls{
        .threshold_doubl = 1.0e-6,
        .threshold_mul = 1.0e-8,
    };
    const tolerances = controls.accuracyTolerances();

    try std.testing.expectEqual(@as(f64, 3.0e-14), tolerances.fourier_tail_reflectance_epsilon);
    try std.testing.expectEqual(controls.threshold_doubl, tolerances.threshold_doubl);
    try std.testing.expectEqual(controls.threshold_mul, tolerances.threshold_mul);
    try std.testing.expectEqual(@as(f64, 1.0e-3), tolerances.qseries_trace_threshold);
    try std.testing.expectEqual(@as(f64, 0.0), tolerances.weak_scattering_tau_floor);
}

test "accuracy target relaxes only reflectance-scale Fourier tolerance above exact mode" {
    const controls = common.RadiativeTransferControls{
        .threshold_doubl = 1.0e-6,
        .threshold_mul = 1.0e-8,
        .accuracy_target = 1.0e-11,
    };
    const tolerances = controls.accuracyTolerances();

    try std.testing.expectApproxEqAbs(@as(f64, 1.0e-13), tolerances.fourier_tail_reflectance_epsilon, 1.0e-25);
    try std.testing.expectEqual(controls.threshold_doubl, tolerances.threshold_doubl);
    try std.testing.expectEqual(controls.threshold_mul, tolerances.threshold_mul);
    try std.testing.expectEqual(@as(f64, 1.0e-3), tolerances.qseries_trace_threshold);
    try std.testing.expectEqual(@as(f64, 0.0), tolerances.weak_scattering_tau_floor);
}
