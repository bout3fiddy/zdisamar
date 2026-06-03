# 12. Combine The D Update In Doubling

Historical checkpoint: `4791c22 -> baf0b4f`, where forward elapsed time moved
from `1.915826 s` to `1.889351 s`.

In short: compute `T + Q*E + Q*T` in one destination pass.

Source links:

- DISAMAR
  - [D update shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L2196-L2202): expresses `T + Q*E + Q*T` as separate matrix terms in the general recurrence.
- zdisamar
  - [D update call](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L245-L250): routes the common D update through the fused helper.
  - [Fused helper](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L279-L352): combines scaled diagonal and product contributions in one output pass.

The D update has a common shape:

```text
D = T + Q * diag(E) + Q * T
```

The optimization is to combine the scaled diagonal contribution and the product
contribution in one pass.

```python
# Broad route: separate temporaries and passes.
qe = q * diag(e)
qt = q @ t
d = t + qe + qt

# Narrow route: one destination pass.
for i, j in matrix_indices:
    scaled = q[i, j] * e[j]
    product = dot(q[i, :], t[:, j])
    d[i, j] = t[i, j] + scaled + product
```

This is a smaller win than the earlier fixed-shape matrix work, but it sits in
the repeated layer-doubling recurrence and therefore still matters.
