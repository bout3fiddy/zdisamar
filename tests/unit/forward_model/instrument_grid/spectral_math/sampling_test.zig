const std = @import("std");
const internal = @import("internal");

const sampling = internal.forward_model.instrument_grid.spectral_math.sampling;
const sampleLinearClamped = sampling.sampleLinearClamped;

test "sampling clamps linearly on sparse wavelength nodes" {
    const wavelengths = [_]f64{ 760.0, 760.2, 760.4 };
    const values = [_]f64{ 1.0, 3.0, 5.0 };

    try std.testing.expectApproxEqRel(
        @as(f64, 2.0),
        try sampleLinearClamped(&wavelengths, &values, 760.1),
        1.0e-12,
    );
    try std.testing.expectEqual(@as(f64, 1.0), try sampleLinearClamped(&wavelengths, &values, 759.9));
    try std.testing.expectEqual(@as(f64, 5.0), try sampleLinearClamped(&wavelengths, &values, 760.5));
}
