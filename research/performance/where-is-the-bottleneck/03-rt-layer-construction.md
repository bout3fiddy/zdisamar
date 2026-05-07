# 03. RT-Layer Construction

RT-layer construction is the largest LABOS block:

```text
RT-layer build                8.026027 s   69.888% of LABOS CPU
layer visits                  5,417,550
phase matrix builds           1,284,366
doubled layers                1,075,939
doubling steps                8,389,666
```

Most layer visits do not build a phase matrix:

```text
skipped by Fourier range      4,133,184
phase matrix builds           1,284,366
```

This is already one of the optimizations from the earlier performance work: [layers and Fourier terms that cannot contribute are skipped](../why-zdisamar-is-faster/07-skip-empty-layer-work.md), and [tiny Fourier tails stop early](../why-zdisamar-is-faster/08-fourier-tail-and-basis-reuse.md). The remaining cost is the subset that still has active phase coefficients and scattering optical depth.

The traced split inside active RT-layer work is:

```text
phase matrix                  1.038334 s    9.041% of LABOS CPU
effective scattering scan     0.043808 s    0.381% of LABOS CPU
initial exponentials          0.074818 s    0.651% of LABOS CPU
single scatter setup          0.201130 s    1.751% of LABOS CPU
phase renormalization         0.055815 s    0.486% of LABOS CPU
layer doubling                6.036863 s   52.567% of LABOS CPU
```

The conclusion is direct: RT-layer construction dominates because it contains the doubling loop, and the doubling loop is repeated 8.39 million times for this spectrum.
