pub const Error = error{
    KernelShapeMismatch,
};

// convolution.zig -------------------------------------------------------------------------------------------------------|
// One-dimensional slit convolution for measurement-space arrays. Radiance, irradiance, and active Jacobian               |
// columns all use this helper when the instrument response was not already integrated during sampling.                   |
//                                                                                                                        |
// main paths                                                                                                             |
//   apply               -> whole signal, including boundary and interior samples                                         |
//   applyBoundarySample -> clipped edge normalization                                                                    |
//   applyFullKernelSample -> fixed-window interior dot product                                                           |
//                                                                                                                        |
// convention                                                                                                             |
//   Boundaries normalize by the valid part of the kernel only. Interior samples reuse the full kernel norm.              |
// -----------------------------------------------------------------------------------------------------------------------|

pub fn apply(signal: []const f64, kernel: []const f64, output: []f64) Error!void {
    // apply -------------------------------------------------------------------------------------------------------------|
    // Slit convolution for radiance, irradiance, and active Jacobian columns.                                            |
    //                                                                                                                    |
    // Steps:                                                                                                             |
    //   1. use edge-normalized samples near the signal boundaries                                                        |
    //   2. use the full kernel norm through the dense interior                                                           |
    //   3. write one output sample per input sample                                                                      |
    //                                                                                                                    |
    // interior math                                                                                                      |
    //               sum_j signal[i + j - half_width] * kernel_j                                                          |
    //   output_i = ---------------------------------------------                                                         |
    //                              sum_j kernel_j                                                                        |
    //                                                                                                                    |
    // boundary math                                                                                                      |
    //   Use the same formula, but keep only j where signal[i + j - half_width] is inside the signal. The                 |
    //   denominator uses that clipped kernel subset, so constant input stays constant at the edges.                      |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // applyBoundarySample -----------------------------------------------------------------------------------------------|
    // Edge sample with partial-kernel normalization. Only valid signal samples contribute to the numerator               |
    // and denominator.                                                                                                   |
    //                                                                                                                    |
    // index mapping                                                                                                      |
    //   signal_index = output_index + kernel_index - half_width                                                          |
    //   kernel_start/kernel_end clip kernel_index so signal_index stays in bounds.                                       |
    //                                                                                                                    |
    // why                                                                                                                |
    //   The clipped norm avoids darkening or brightening the spectrum at the first and last samples.                     |
    // -------------------------------------------------------------------------------------------------------------------|

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
    // applyFullKernelSample ---------------------------------------------------------------------------------------------|
    // Full-kernel interior convolution sample. Boundary samples are handled by applyBoundarySample.                      |
    //                                                                                                                    |
    // Two-lane vector path                                                                                               |
    //   vector_sum accumulates two signal*kernel products at a time with @mulAdd.                                        |
    //   @reduce(.Add, vector_sum) collapses the lanes before the scalar tail and normalization.                          |
    //                                                                                                                    |
    // math                                                                                                               |
    //   The vector and scalar paths compute the same dot product: sum_j signal_window[j] * kernel[j].                    |
    //   The final divide by norm applies the kernel normalization once.                                                  |
    // -------------------------------------------------------------------------------------------------------------------|

    if (norm == 0.0) return 0.0;
    const Vec2 = @Vector(2, f64);
    var vector_sum: Vec2 = @splat(0.0);
    var kernel_index: usize = 0;

    // Vector lanes accumulate dot(signal_window, kernel) before scalar normalization by norm.
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
    // kernelSum ---------------------------------------------------------------------------------------------------------|
    // Sum kernel weights once so interior samples can reuse the same normalization.                                      |
    // -------------------------------------------------------------------------------------------------------------------|

    var sum: f64 = 0.0;
    for (kernel) |weight| sum += weight;
    return sum;
}

inline fn loadPair(values: []const f64, index: usize) @Vector(2, f64) {
    // loadPair (two adjacent f64 values as one vector) ------------------------------------------------------------------|
    // Read values[index] and values[index + 1] as one two-lane vector. The convolution interior uses this for            |
    // two signal*kernel products at a time.                                                                              |
    //                                                                                                                    |
    // align(1) is deliberate: slices are contiguous, but this helper does not require vector-aligned storage.            |
    // -------------------------------------------------------------------------------------------------------------------|

    const pair: *align(1) const @Vector(2, f64) = @ptrCast(&values[index]);
    return pair.*;
}
