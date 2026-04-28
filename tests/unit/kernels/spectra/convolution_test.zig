const std = @import("std");
const internal = @import("internal");

const convolution = internal.kernels.spectra.convolution;
const apply = convolution.apply;

test "spectral convolution smooths a spike with a symmetric kernel" {
    const signal = [_]f64{ 0.0, 0.0, 10.0, 0.0, 0.0 };
    const kernel = [_]f64{ 1.0, 2.0, 1.0 };
    var output: [5]f64 = undefined;

    try apply(&signal, &kernel, &output);
    try std.testing.expect(output[2] < signal[2]);
    try std.testing.expect(output[1] > 0.0);
}
