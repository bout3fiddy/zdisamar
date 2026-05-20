const std = @import("std");
const internal = @import("internal");

const convolution = internal.forward_model.instrument_grid.spectral_math.convolution;
const apply = convolution.apply;

test "spectral convolution smooths a spike with a symmetric kernel" {
    const signal = [_]f64{ 0.0, 0.0, 10.0, 0.0, 0.0 };
    const kernel = [_]f64{ 1.0, 2.0, 1.0 };
    var output: [5]f64 = undefined;

    try apply(&signal, &kernel, &output);
    try std.testing.expect(output[2] < signal[2]);
    try std.testing.expect(output[1] > 0.0);
}

test "spectral convolution preserves edge normalization with odd and even kernels" {
    const signal = [_]f64{ 1.0, 2.0, 3.0, 4.0, 5.0 };

    const odd_kernel = [_]f64{ 1.0, 2.0, 1.0 };
    var odd_output: [5]f64 = undefined;
    try apply(&signal, &odd_kernel, &odd_output);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0 / 3.0), odd_output[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 2.0), odd_output[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), odd_output[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), odd_output[3], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 14.0 / 3.0), odd_output[4], 1.0e-12);

    const even_kernel = [_]f64{ 1.0, 2.0, 3.0, 4.0 };
    var even_output: [5]f64 = undefined;
    try apply(&signal, &even_kernel, &even_output);
    try std.testing.expectApproxEqAbs(@as(f64, 11.0 / 7.0), even_output[0], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 20.0 / 9.0), even_output[1], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 3.0), even_output[2], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 4.0), even_output[3], 1.0e-12);
    try std.testing.expectApproxEqAbs(@as(f64, 13.0 / 3.0), even_output[4], 1.0e-12);
}
