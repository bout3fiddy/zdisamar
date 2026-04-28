const std = @import("std");
const internal = @import("internal");

const airmass_phase = internal.reference.airmass_phase;
const spectralProfileFromOpticalDepth = airmass_phase.spectralProfileFromOpticalDepth;

test "spectral amf profile preserves the requested mean factor" {
    const wavelengths = [_]f64{ 759.0, 760.0, 761.0, 762.0 };
    const proxy = [_]f64{ 0.5, 1.0, 1.5, 1.0 };
    const profile = try spectralProfileFromOpticalDepth(std.testing.allocator, &wavelengths, 2.0, &proxy);
    defer std.testing.allocator.free(profile);

    var mean: f64 = 0.0;
    for (profile) |value| mean += value;
    mean /= @as(f64, @floatFromInt(profile.len));
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), mean, 1.0e-9);
    try std.testing.expect(profile[2] > profile[0]);
}
