# 05. Phase-Matrix Construction

Phase-matrix construction remains visible but is no longer the dominant wall:

```text
phase matrix CPU              1.038334 s    9.041% of LABOS CPU
phase matrix builds           1,284,366
phase coefficient scans      20,479,142
nonzero coefficient terms    20,184,718
PLM basis CPU                 0.006664 s    0.058% of LABOS CPU
```

The [PLM basis is already reused](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md) well enough that it is effectively gone from the wall. The remaining phase cost is combining active layer-specific phase coefficients into `Zplus` and `Zmin` for each active wavelength/layer/Fourier combination.

The important distinction is:

```text
basis generation              tiny
layer-specific matrix fill    still repeated
```

This is not currently the final bottleneck, but it is a meaningful secondary cost. A new phase-kernel reuse strategy would have to prove that layer phase coefficients are identical or close enough across wavelengths without changing the O2 A result.
