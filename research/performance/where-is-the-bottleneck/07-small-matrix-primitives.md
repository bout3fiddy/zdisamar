# 07. Small Matrix Primitives

The primitive estimate combines real trace counts with the retained `zig build bench` microbench:

```text
qseries_nonzero_12x10       519.493 ns/call
smul_12x10                  155.266 ns/call
smulAddSemul3_12            168.916 ns/call
matAddEsmul3_12              90.744 ns/call
semulAdd_12                  66.846 ns/call
esmulSemulAdd_12             93.381 ns/call
```

Derived estimates:

```text
qseries package              1.770587 s CPU
R*D, T*U, T*D products       3.907890 s CPU
D update                     0.575716 s CPU
U update                     0.560816 s CPU
R_next update                0.761312 s CPU
T_next update                0.783435 s CPU
```

The estimate sums to `8.359756 s` of primitive CPU. That is larger than the directly timed `6.036863 s` doubling block because the microbench seed is not the exact same data distribution as every in-run matrix and because tracing/timing boundaries are not identical to standalone kernel loops. The value is still useful for ranking: repeated 12x10 matrix products and q-series are the heavy primitive classes.

The exact retained table is:

```text
validation/outputs/performance/labos-bottleneck/primitive_estimates.csv
```

The primitive conclusion matches the higher-level trace: there is no single slow call. The final wall is millions of already-small fixed-shape operations.
