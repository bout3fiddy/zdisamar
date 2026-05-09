# 11. Write Matrix Results Into Separate Outputs

Historical checkpoint: `63df87e -> 4791c22`, where forward elapsed time moved
from `2.136820 s` to `1.915826 s`.

In short: write repeated matrix products directly into their final destination.

Source links:

- DISAMAR
  - [Matrix update shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L3528-L3569): returns matrix results through a general helper style.
  - [Assignment shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L2199-L2202): shows the extra destination assignment that becomes costly when repeated.
- zdisamar
  - [Matrix storage](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/matrix.zig#L68-L98): exposes helpers that can write into caller-owned outputs.
  - [Doubling destination use](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L252-L265): passes final destinations into repeated product calls.

Returning a matrix and then assigning it into the real destination creates extra
traffic in a repeated path. Passing the destination into the helper lets the
helper write the final output directly.

```python
# Broad route: helper returns temporary, caller copies it.
tmp = matrix_product(a, b)
rd[:, :] = tmp

# Narrow route: helper writes into the destination.
matrix_product_into(rd, a, b)
```

This is a data-movement optimization. It is valuable because the same matrix
products are attempted once per doubling step.
