# 05. Phase-Matrix Construction

Phase-matrix construction costs `1.020827 s`, or `10.802%` of aggregate LABOS CPU. It is not the dominant block, but it is still a visible secondary cost.

What that means: zdisamar already reuses the PLM Fourier basis, so basis generation itself costs only `0.008842 s`. The remaining cost is not "build the angular basis"; it is "combine layer-specific phase coefficients into the two phase matrices `Zplus` and `Zmin`." That happened `1,284,366` times in the retained trace. The coefficient loop scanned `20,479,142` phase coefficient terms, and `20,184,718` of those terms were nonzero.

The phase build is called from [layers.zig](../../../src/forward_model/radiative_transfer/labos/layers.zig#L374-L380):

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

The repeated fixed-12 matrix fill is in [phase_basis.zig](../../../src/forward_model/radiative_transfer/labos/phase_basis.zig#L386-L414):

```zig
var scaled_plus_col: [12]f64 = undefined;
inline for (0..12) |j| {
    scaled_plus_col[j] = alpha1 * plus_l[j];
}

inline for (0..12) |i| {
    const plus_i = plus_l[i];
    const minus_i = minus_l[i];
    const row = i * 12;
    inline for (0..12) |j| {
        zplus.data[row + j] += plus_i * scaled_plus_col[j];
        zmin.data[row + j] += minus_i * scaled_plus_col[j];
    }
}
```

The [PLM basis is already reused](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md) well enough that it is effectively gone from the wall. The fixed-12 fill now applies `alpha * plus[j]` once per column and reuses it for both `Zplus` and `Zmin`; that is a small math-ordering win, not a change in the phase recurrence. The repeated layer-specific matrix fill is still the remaining phase cost. Any future phase-kernel reuse strategy would have to prove that layer phase coefficients are identical or safely reusable across wavelengths without changing the O2 A result.

## Simple Python Shape

The cached basis removes one cost, but each active layer still fills its own matrices:

```python
plm_basis = basis_cache[fourier]  # reused across wavelengths

zplus = zeros((12, 12))
zmin = zeros((12, 12))

for l, alpha in layer.phase_coefficients[fourier:]:
    if alpha == 0:
        continue

    plus = plm_basis.plus[l]
    minus = plm_basis.minus[l]
    scaled_plus_col = alpha * plus
    for i in range(12):
        for j in range(12):
            zplus[i, j] += plus[i] * scaled_plus_col[j]
            zmin[i, j] += minus[i] * scaled_plus_col[j]
```

The example is small, but the trace counted `1,284,366` phase matrix builds.
