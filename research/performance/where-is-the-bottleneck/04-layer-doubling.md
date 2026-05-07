# 04. Layer Doubling

Layer doubling is the largest single measured LABOS sub-block. It costs `6.036863 s`, or `52.567%` of aggregate LABOS CPU. The trace counted `1,075,939` layers that needed doubling. Those layers required `8,389,666` doubling steps, which means each doubled layer ran about `7.8` doubling steps on average.

What that means: LABOS first builds a thin starting layer that is safe for the configured scattering threshold. It then repeatedly doubles that layer until it represents the original optical thickness. Every doubling step updates the layer reflection matrix `R`, the layer transmission matrix `T`, and the attenuation vector `E`.

The doubling loop is in [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L240-L281):

```zig
for (0..ndouble) |_| {
    // One trace "doubling step". This happened 8,389,666 times.
    const trace_r = gaussTrace(n, n_gauss, R);
    const q_is_zero = @abs(trace_r * trace_r) <= threshold_mul;

    // Q represents repeated reflection between the two half-layers.
    // If R*R is below threshold, D is just T and q-series is skipped.
    const D = if (q_is_zero) blk: {
        break :blk T.*;
    } else blk: {
        const Q = basis.qseriesKnownNonzeroProduct(n, n_gauss, R, R);
        break :blk basis.smulAddSemul3(n, n_gauss, threshold_mul, &Q, E, T);
    };

    // The remaining matrix products update reflection and transmission
    // for the doubled layer.
    var rd: basis.Mat = undefined;
    basis.smulInto(&rd, n, n_gauss, threshold_mul, R, &D);
    const U = basis.semulAdd(n, R, E, &rd);

    var tu: basis.Mat = undefined;
    basis.smulInto(&tu, n, n_gauss, threshold_mul, T, &U);
    const R_new = basis.matAddEsmul3(n, R, E, &U, &tu);

    var td: basis.Mat = undefined;
    basis.smulInto(&td, n, n_gauss, threshold_mul, T, &D);
    const T_new = basis.esmulSemulAdd(n, E, &D, T, &td);
}
```

This loop explains the primitive counts. `qseriesKnownNonzeroProduct` was needed `3,408,299` times; the q-series path was skipped `4,981,367` times; and the three matrix products `R*D`, `T*U`, and `T*D` each ran once per doubling step, so each appears `8,389,666` times.

This is why doubling is the final frontier. The code has already [specialized the common 12x10 and 12x12 matrix shapes](../why-zdisamar-is-faster/06-direct-12x10-12x12-matrix-calculations.md), [fused layer-doubling updates](../why-zdisamar-is-faster/05-fuse-layer-doubling-matrix-updates.md), [skipped empty q-series work](../why-zdisamar-is-faster/11-skip-empty-qseries-work.md), and [combined the D update](../why-zdisamar-is-faster/13-combine-d-update-in-doubling.md). The exact calculation still has to run the same scientific recurrence millions of times.

A small assembly improvement can reduce a primitive. It does not remove the outer product: `3,874` wavelengths times active Fourier terms times active layers times repeated doubling steps. The next large speedup would need to reduce one of those counts or introduce a new scientifically valid reuse boundary.

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
