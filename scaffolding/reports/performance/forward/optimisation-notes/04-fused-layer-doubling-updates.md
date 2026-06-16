# 04. Fuse Layer-Doubling Matrix Updates

Historical checkpoint: `b0a9e0f -> 97088cf`, where forward elapsed time moved
from `7.020602 s` to `5.911137 s`.

In short: fuse repeated matrix update passes inside the layer-doubling
recurrence.

Source links:

- DISAMAR
  - [Doubling recurrence](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L1857-L1895): expresses the exact layer-doubling math in a general matrix-update style with repeated intermediate traffic.
- zdisamar
  - [Doubling loop](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L228-L284): keeps the same recurrence but fuses common update shapes inside the repeated loop.

Layer doubling updates reflection and transmission matrices many times. The
naive shape materializes intermediate arrays and then combines them in later
passes. zdisamar uses fused updates where the arithmetic allows it.

```python
# Broad route: separate arrays and passes.
qe = q * diag(e)
qt = q @ t
d = t + qe + qt

# Narrow route: one output pass.
d = zeros_like(t)
for i, j in matrix_indices:
    d[i, j] = t[i, j] + q[i, j] * e[j] + dot(q[i, :], t[:, j])
```

The recurrence is the same. The speedup comes from less temporary storage and
fewer full matrix passes inside millions of repeated doubling steps.
