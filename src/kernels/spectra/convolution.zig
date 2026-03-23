//! Purpose:
//!   Apply normalized spectral convolution kernels to sampled radiance or irradiance vectors.
//!
//! Physics:
//!   Produces a locally weighted spectral smoothing over the supplied line-spread function.
//!
//! Vendor:
//!   `spectral convolution`
//!
//! Design:
//!   The kernel is normalized on the fly so edge truncation does not silently change total weight.
//!
//! Invariants:
//!   Output length must match the input signal length and the kernel must be non-empty.
//!
//! Validation:
//!   Unit tests cover symmetric-kernel smoothing behavior.

pub const Error = error{
    KernelShapeMismatch,
};

/// Purpose:
///   Convolve a sampled signal with a finite kernel while renormalizing at the boundaries.
///
/// Physics:
///   Implements a discrete line-spread convolution on the wavelength grid.
///
/// Vendor:
///   `spectral convolution`
pub fn apply(signal: []const f64, kernel: []const f64, output: []f64) Error!void {
    if (signal.len != output.len or kernel.len == 0) return Error.KernelShapeMismatch;

    const half_width = kernel.len / 2;
    for (output, 0..) |*slot, index| {
        var acc: f64 = 0.0;
        var norm: f64 = 0.0;

        for (kernel, 0..) |weight, kernel_index| {
            const signal_index_signed: isize = @as(isize, @intCast(index)) + @as(isize, @intCast(kernel_index)) - @as(isize, @intCast(half_width));
            if (signal_index_signed < 0 or signal_index_signed >= signal.len) continue;
            const signal_index: usize = @intCast(signal_index_signed);
            acc += signal[signal_index] * weight;
            norm += weight;
        }

        slot.* = if (norm == 0.0) 0.0 else acc / norm;
    }
}

test "spectral convolution smooths a spike with a symmetric kernel" {
    const signal = [_]f64{ 0.0, 0.0, 10.0, 0.0, 0.0 };
    const kernel = [_]f64{ 1.0, 2.0, 1.0 };
    var output: [5]f64 = undefined;

    try apply(&signal, &kernel, &output);
    try std.testing.expect(output[2] < signal[2]);
    try std.testing.expect(output[1] > 0.0);
}

const std = @import("std");
