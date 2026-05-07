# 05. Phase-Matrix Construction

Phase-matrix construction costs `1.038334 s`, or `9.041%` of aggregate LABOS CPU. It is not the dominant block, but it is still a visible secondary cost.

What that means: zdisamar already reuses the PLM Fourier basis, so basis generation itself costs only `0.006664 s`. The remaining cost is not "build the angular basis"; it is "combine layer-specific phase coefficients into the two phase matrices `Zplus` and `Zmin`." That happened `1,284,366` times in the retained trace. The coefficient loop scanned `20,479,142` phase coefficient terms, and `20,184,718` of those terms were nonzero.

The phase build is called from [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L369-L380):

```zig
// One phase matrix build for one active layer/Fourier pair.
var z = basis.fillZplusZminFromBasisLimited(
    i_fourier,
    phase_coefs,
    max_phase_index,
    geo,
    plm_basis,
);
```

The repeated matrix fill is in [phase_basis.zig](../../../src/forward_model/radiative_transfer/labos/phase_basis.zig#L218-L243):

```zig
for (i_fourier..bounded_max_phase_index + 1) |l| {
    const alpha1 = phase_coefs[l];
    if (alpha1 == 0.0) continue;

    // PLM values are reused from plm_basis, but this layer's coefficient
    // still has to be applied to every matrix row/column.
    const plus_l = &plm_basis.plus[l];
    const minus_l = &plm_basis.minus[l];
    for (0..n) |i| {
        const scaled_plus_i = alpha1 * plus_l[i];
        const scaled_minus_i = alpha1 * minus_l[i];
        const row = i * n;
        for (0..n) |j| {
            zplus.data[row + j] += scaled_plus_i * plus_l[j];
            zmin.data[row + j] += scaled_minus_i * plus_l[j];
        }
    }
}
```

The [PLM basis is already reused](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md) well enough that it is effectively gone from the wall. The repeated layer-specific matrix fill is the remaining phase cost. This is not currently the final bottleneck, but any future phase-kernel reuse strategy would have to prove that layer phase coefficients are identical or safely reusable across wavelengths without changing the O2 A result.
