pub const Error = error{
    KernelShapeMismatch,
};

// hot path:
//   when: radiance, irradiance, or active Jacobian columns use slit convolution
//   work: applies edge-normalized samples plus a SIMD full-kernel interior
//   data: signal array, kernel weights, output array
//   math: output_i = sum_j signal_{i+j-half_width} * kernel_j / sum_j kernel_j, with boundary j clipped to valid signal samples
//   follow: simulate radiance/irradiance convolution and processJacobianSamples
pub fn apply(signal: []const f64, kernel: []const f64, output: []f64) Error!void {
    if (signal.len != output.len or kernel.len == 0) return Error.KernelShapeMismatch;

    const half_width = kernel.len / 2;
    const right_width = kernel.len - half_width - 1;
    const interior_begin = @min(half_width, signal.len);
    const interior_end = if (signal.len > right_width) signal.len - right_width else 0;
    const full_norm = kernelSum(kernel);

    // Boundary samples keep the legacy partial-kernel normalization. The dense
    // interior can stream a fixed window and reuse the full kernel norm.
    var index: usize = 0;
    while (index < interior_begin) : (index += 1) {
        output[index] = applyBoundarySample(signal, kernel, half_width, index);
    }
    if (interior_end > interior_begin) {
        while (index < interior_end) : (index += 1) {
            output[index] = applyFullKernelSample(signal[index - half_width ..], kernel, full_norm);
        }
    }
    while (index < output.len) : (index += 1) {
        output[index] = applyBoundarySample(signal, kernel, half_width, index);
    }
}

fn applyBoundarySample(signal: []const f64, kernel: []const f64, half_width: usize, index: usize) f64 {
    const kernel_start = if (index < half_width) half_width - index else 0;
    const kernel_end = @min(kernel.len, signal.len + half_width - index);
    var acc: f64 = 0.0;
    var norm: f64 = 0.0;
    for (kernel_start..kernel_end) |kernel_index| {
        const signal_index = index + kernel_index - half_width;
        const weight = kernel[kernel_index];
        acc += signal[signal_index] * weight;
        norm += weight;
    }
    return if (norm == 0.0) 0.0 else acc / norm;
}

fn applyFullKernelSample(signal_window: []const f64, kernel: []const f64, norm: f64) f64 {
    if (norm == 0.0) return 0.0;
    const Vec2 = @Vector(2, f64);
    var vector_sum: Vec2 = @splat(0.0);
    var kernel_index: usize = 0;
    // math: vector lanes accumulate dot(signal_window, kernel) before scalar normalization by norm.
    while (kernel_index + 2 <= kernel.len) : (kernel_index += 2) {
        vector_sum = @mulAdd(
            Vec2,
            loadPair(signal_window, kernel_index),
            loadPair(kernel, kernel_index),
            vector_sum,
        );
    }
    var acc: f64 = @reduce(.Add, vector_sum);
    while (kernel_index < kernel.len) : (kernel_index += 1) {
        acc += signal_window[kernel_index] * kernel[kernel_index];
    }
    return acc / norm;
}

fn kernelSum(kernel: []const f64) f64 {
    var sum: f64 = 0.0;
    for (kernel) |weight| sum += weight;
    return sum;
}

inline fn loadPair(values: []const f64, index: usize) @Vector(2, f64) {
    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&values[index]);
    return pair.*;
}
