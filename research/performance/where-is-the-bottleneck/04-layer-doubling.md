# 04. Layer Doubling

Layer doubling is the largest single measured LABOS sub-block. It costs `4.536551 s`, or `48.005%` of aggregate LABOS CPU. The trace counted `1,075,939` layers that needed doubling. Those layers required `8,389,666` doubling steps, which means each doubled layer ran about `7.8` doubling steps on average.

What that means: LABOS first builds a thin starting layer that is safe for the configured scattering threshold. It then repeatedly doubles that layer until it represents the original optical thickness. Every doubling step updates the layer reflection matrix `R`, the layer transmission matrix `T`, and the attenuation vector `E`.

The doubling loop is in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L230-L313):

```zig
for (0..ndouble) |_| {
    // One trace "doubling step". This happened 8,389,666 times.
    const trace_r = gaussTrace(n, n_gauss, R);
    const trace_t = gaussTrace(n, n_gauss, T);
    const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

    // Q represents repeated reflection between the two half-layers.
    // If R*R is below threshold, D is just T and q-series is skipped.
    const D = if (q_is_zero) blk: {
        break :blk T.*;
    } else blk: {
        const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
        break :blk basis.smulAddSemul3KnownRightTrace(n, n_gauss, threshold_mul, &Q, E, T, trace_t);
    };

    const trace_d = if (q_is_zero) trace_t else gaussTrace(n, n_gauss, &D);

    // The remaining matrix products update reflection and transmission
    // for the doubled layer. Their threshold decisions reuse known traces,
    // and skipped products take the matching two-term update.
    var rd: basis.Mat = undefined;
    const rd_nonzero = basis.smulIntoKnownTracesIfNonzero(&rd, n, n_gauss, threshold_mul, trace_r, trace_d, R, &D);
    const U = if (rd_nonzero) basis.semulAdd(n, R, E, &rd) else basis.semul(n, R, E);
    const trace_u = gaussTrace(n, n_gauss, &U);

    var tu: basis.Mat = undefined;
    const tu_nonzero = basis.smulIntoKnownTracesIfNonzero(&tu, n, n_gauss, threshold_mul, trace_t, trace_u, T, &U);
    const R_new = if (tu_nonzero) basis.matAddEsmul3(n, R, E, &U, &tu) else basis.matAddEsmul(n, R, E, &U);

    var td: basis.Mat = undefined;
    const td_nonzero = basis.smulIntoKnownTracesIfNonzero(&td, n, n_gauss, threshold_mul, trace_t, trace_d, T, &D);
    const T_new = if (td_nonzero) basis.esmulSemulAdd(n, E, &D, T, &td) else basis.esmulSemul(n, E, &D, T);

    // The next layer thickness is doubled, so exp(-2*b/mu) is E*E.
    squareAttenuation(n, E);
}
```

This loop explains the primitive counts. `qseriesKnownNonzeroProduct` was needed `3,408,299` times; the q-series path was skipped `4,981,367` times; and the three matrix products `R*D`, `T*U`, and `T*D` are each attempted once per doubling step. The retained trace counted `10,931,496` nonzero products across those `25,168,998` product slots; the remaining slots take the zero-aware elementwise updates.

This is why doubling is the final frontier. The code has already [specialized the common 12x10 and 12x12 matrix shapes](../why-zdisamar-is-faster/06-direct-12x10-12x12-matrix-calculations.md), [fused layer-doubling updates](../why-zdisamar-is-faster/05-fuse-layer-doubling-matrix-updates.md), [skipped empty q-series work](../why-zdisamar-is-faster/11-skip-empty-qseries-work.md), [combined the D update](../why-zdisamar-is-faster/13-combine-d-update-in-doubling.md), reused Gauss traces across the post-D products, and avoids materializing threshold-skipped product matrices. The exact calculation still has to run the same scientific recurrence millions of times.

A small assembly improvement can reduce a primitive. It does not remove the outer product: `3,874` wavelengths times active Fourier terms times active layers times repeated doubling steps. The next large speedup would need to reduce one of those counts or introduce a new scientifically valid reuse boundary.

## Assembly-Level Reading

The research-only codegen harness in [primitive-codegen/bench_primitives.zig](primitive-codegen/bench_primitives.zig) isolates the same fixed 12x10 operation shapes with deterministic mock matrices. Its retained summary is [codegen-summary.md](primitive-codegen/outputs/codegen-summary.md), and the extracted disassembly files sit beside it.

For layer doubling, the important retained numbers are:

- `smul_12x10` takes about `169.672 ns` per isolated call after the retained two-lane vector shape. The regenerated `codegen_smul12x10` disassembly has `2,195` instructions, including `1,368` floating-point arithmetic instructions and no floating-point divides.
- `smul_add_semul3_known_right_trace_12` takes about `188.876 ns` per isolated call. Its extracted wrapper plus callee have `2,842` instructions, including `1,729` floating-point arithmetic instructions and no floating-point divides.
- `qseries_nonzero_12x10` takes about `519.070 ns` per isolated call after reciprocal reuse in the 10x10 solve and the two-lane product shape. Its regenerated disassembly has `4,450` instructions, including `2,054` floating-point arithmetic instructions and `1` floating-point divide.

That makes the assembly-level story more specific. The ordinary 12x10 products are not spending time in file I/O, allocation, dynamic dispatch, or text parsing; the retained disassembly is dominated by floating-point multiply/add work over the fixed matrix shape. The q-series path is different: it contains the product plus the 10x10 pivoted solve. The solve now computes one reciprocal per pivot and reuses it, which removes the repeated divide instructions from elimination and back-substitution while preserving the same pivoted factorization.

## Simple Python Shape

One doubled layer runs the same recurrence several times:

```python
def double_layer(r, t, e, steps):
    for _ in range(steps):
        if repeated_reflection_is_tiny(r):
            d = t
        else:
            q = qseries(matmul(r, r))
            d = t + q * e + matmul(q, t)

        rd = matmul(r, d)
        u = r * e + rd

        tu = matmul(t, u)
        r_next = r + e * u + tu

        td = matmul(t, d)
        t_next = e * d + t * e + td

        r, t = r_next, t_next
        e = update_attenuation(e)
    return r, t
```

The individual matrix operations are small. The cost appears because this recurrence runs `8,389,666` times in one retained spectrum.
