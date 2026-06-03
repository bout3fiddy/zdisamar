# 09. Carry Layer Activity Into Scattering Orders

Historical checkpoint: `c423f4a -> f295ace`, where forward elapsed time moved
from `2.025331 s` to `1.980342 s`.

In short: carry inactive-layer decisions from RT-layer construction into
scattering orders.

Source links:

- DISAMAR
  - [Orders loop shape](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L2360-L2396): propagates scattering orders through the general layer set, so inactive-layer knowledge is not the central data contract.
- zdisamar
  - [Active-layer marking](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/layers.zig#L335-L344): records whether a layer can contribute while RT layers are built.
  - [Orders skip](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/orders.zig#L432-L490): skips later dot products for layers already proven inactive.

If RT-layer construction proves a layer has zero reflection/transmission for a
Fourier term, the later scattering-order dot products through that layer will
also return zero. That activity decision should be carried forward.

```python
# Broad route: orders loop still visits every layer as active.
rt_layers = build_rt_layers(layers, fourier)
for order in scattering_orders:
    for layer in layers:
        local_down[layer] = dot(rt_layers[layer].R, up) + dot(rt_layers[layer].T, down)

# Narrow route: reuse the activity mask from RT-layer construction.
rt_layers, active = build_rt_layers_with_activity(layers, fourier)
for order in scattering_orders:
    for layer in layers:
        if not active[layer]:
            local_down[layer] = 0.0
            continue
        local_down[layer] = dot(rt_layers[layer].R, up) + dot(rt_layers[layer].T, down)
```

The current trace still has many active dot products, but inactive layers no
longer pay the full orders recurrence.
