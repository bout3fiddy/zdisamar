# 06. Skip Layers And Terms That Cannot Contribute

Historical checkpoint: `0ae1cad -> f42445d`, where forward elapsed time moved
from `2.460360 s` to `2.266849 s`.

In short: test cheap no-contribution cases before building layer scattering
work.

Source links:

- DISAMAR
  - [Layer loop shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L1832-L1870): enters the general layer-building loop before the path can avoid all no-contribution work.
- zdisamar
  - [Layer checks](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L321-L344): proves cheap no-contribution cases before building phase matrices or doubled layers.
  - [Orders activity use](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/orders.zig#L432-L441): carries the same inactive-layer decision into later scattering-order work.

Many layer/Fourier combinations cannot contribute because the Fourier term is
outside the layer's phase range, the optical depth is effectively zero, or there
is no scattering.

```python
# Broad route: enter expensive setup before proving contribution.
for layer in layers:
    zplus, zmin = build_phase_matrices(layer, fourier)
    rt[layer] = build_rt_layer(layer, zplus, zmin)

# Narrow route: cheap contribution tests first.
for layer in layers:
    if fourier > layer.max_phase_index:
        rt[layer] = zero_rt()
        continue
    if layer.optical_depth == 0 or layer.scattering_optical_depth == 0:
        rt[layer] = zero_rt()
        continue
    rt[layer] = build_active_rt_layer(layer, fourier)
```

The current trace still visits millions of layer/Fourier combinations, but many
of them are now cheap skips.
