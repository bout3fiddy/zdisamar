# 08. Assembly Notes

Assembly-level inspection is useful only after the trace has named a primitive worth inspecting. The current trace points to four candidate code shapes: `smul12x10Into`, `qseriesKnownNonzeroProduct` / `qseriesFromProduct`, `smulAddSemul3_12`, and `dotGaussPair`.

The reason to start from those names is simple: they are the primitive classes with both high call volume and a clear microbench or counter. But the ReleaseFast build inlines much of this code, so symbol-level inspection alone is not enough. A missing symbol does not mean the code is absent; it often means the compiler inlined it into the caller.

The direct matrix product candidate is [matrix.zig](../../../src/forward_model/radiative_transfer/labos/matrix.zig#L106-L144):

```zig
inline fn smul12x10Into(noalias result: *Mat, a: *const Mat, b: *const Mat) void {
    // In ReleaseFast this fixed-size loop is expected to inline/unroll.
    // Assembly inspection is useful only if we want to check register use,
    // vectorization, or unexpected spills in the emitted multiply-add chain.
    inline for (0..12) |i| {
        const a0 = a.data[row];
        const a1 = a.data[row + 1];
        const a9 = a.data[row + 9];
        inline for (0..12) |j| {
            var s = a0 * b0[j];
            s += a1 * b1[j];
            s += a9 * b9[j];
            result.data[row + j] = s;
        }
    }
}
```

The q-series candidate is [matrix.zig](../../../src/forward_model/radiative_transfer/labos/matrix.zig#L402-L430):

```zig
inline fn qseriesFromProduct(n: usize, n_gauss: usize, noalias ab: *const Mat) Mat {
    // Fast exit when repeated reflection is below threshold.
    if (@abs(trab) < threshold_q) return ab.*;

    // Otherwise build I - AB on the Gauss block and solve the small system.
    for (0..n_gauss) |i| {
        for (0..n_gauss) |j| {
            one_minus_ab_gg[i * n_gauss + j] = delta - ab.data[i * n + j];
        }
    }
}
```

The paired dot-product candidate is [orders.zig](../../../src/forward_model/radiative_transfer/labos/orders.zig#L186-L218):

```zig
fn dotGaussPair(
    mat: *const basis.Mat,
    row: usize,
    vec_col0: *const basis.Vec,
    vec_col1: *const basis.Vec,
    n_gauss: usize,
) DotPair {
    // One call computes two 10-term dot products. The trace counted
    // 295,581,240 calls, so even tiny codegen differences can matter.
    var s0 = data[0] * vec0[0];
    var s1 = data[0] * vec1[0];
    // ... repeated through Gauss term 9 ...
    return .{ .col0 = s0, .col1 = s1 };
}
```

The practical inspection path is:

1. use the trace counters to pick a primitive;
2. use `zig build bench` to isolate it;
3. use a debug or noinline research build only when the assembly for that primitive needs to be read directly;
4. confirm any assembly-level change against the full trace, because the full wall is dominated by repetition counts.

The commands are:

```sh
zig build bench
zig build -Dtrace-optimize=Debug labos-bottleneck-trace-bin
xcrun llvm-objdump -d --demangle zig-out/bin/labos-bottleneck-trace
```

The current evidence does not justify an assembly-first rewrite. The larger question is still whether the exact O2 A route can reduce the number of wavelength, Fourier, layer, doubling, or order iterations without changing the result.
