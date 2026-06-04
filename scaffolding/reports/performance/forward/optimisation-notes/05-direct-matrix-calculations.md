# 05. Use Direct 12x10 And 12x12 Matrix Calculations

Historical checkpoint: `97088cf -> 0ae1cad`, where forward elapsed time moved
from `5.911137 s` to `2.460360 s`. This was the largest measured checkpoint win.

In short: replace general matrix loops with direct fixed-shape O2 A matrix
operations.

Source links:

- DISAMAR
  - [General matrix shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L1799-L1803): keeps dimensions general for many model configurations, leaving dynamic shape overhead in the hot path.
- zdisamar
  - [Fixed matrix helper](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L106-L144): specializes the common O2 A 12x10 and 12x12 matrix shapes so the compiler can produce direct arithmetic.

The O2 A route uses 20 streams, represented in LABOS as 10 Gauss directions plus
direct solar and viewing directions. The common shapes are therefore 12x10 and
12x12. A general dynamic matrix route keeps loop bounds and shape checks in the
hot path.

```python
# Broad route: shape decided at runtime.
def multiply(a, b, rows, inner, cols):
    out = zeros(rows, cols)
    for i in range(rows):
        for j in range(cols):
            for k in range(inner):
                out[i, j] += a[i, k] * b[k, j]
    return out

# Narrow route: O2 A common shape is known.
def multiply_12x10(a, b):
    out = zeros(12, 12)
    for i in range(12):
        # Compiler-facing implementation can unroll this fixed shape.
        out[i, 0] = sum(a[i, k] * b[k, 0] for k in range(10))
        out[i, 1] = sum(a[i, k] * b[k, 1] for k in range(10))
    return out
```

One fixed-shape multiply is still small. The win appears because the route calls
these operations millions of times.
