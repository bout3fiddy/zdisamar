# 03. Reuse LABOS Storage

Historical checkpoint: `5ef6c71 -> b0a9e0f`, where forward elapsed time moved
from `8.432518 s` to `7.020602 s`.

In short: keep LABOS work arrays alive instead of allocating them inside
repeated transport loops.

Source links:

- DISAMAR
  - [LABOS allocation region](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L268-L304): allocates general LABOS storage around repeated Fourier work.
  - [LABOS cleanup region](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L421-L427): frees that storage after the loop, which is flexible but costly in repeated O2 A calls.
- zdisamar
  - [LABOS workspace](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/radiative_transfer/labos/workspace.zig#L46-L140): owns reusable arrays sized for the O2 A route and resets them across repeated work.

LABOS repeats the same storage shapes across wavelengths and Fourier terms. The
arrays should live in a reusable workspace rather than being allocated and freed
inside the repeated loop.

```python
# Broad route: allocate inside the hot loop.
for wavelength in high_resolution_samples:
    for fourier in fourier_terms:
        rt = allocate_rt_layers()
        orders = allocate_orders_workspace()
        result += labos_step(wavelength, fourier, rt, orders)

# Narrow route: allocate once and clear/reuse.
workspace = LabosWorkspace(max_layers, n_streams)
for wavelength in high_resolution_samples:
    for fourier in fourier_terms:
        workspace.reset_for_step()
        result += labos_step(wavelength, fourier, workspace)
```

The benefit is smaller than the big algorithmic reuse boundaries, but it removes
allocation churn from one of the most repeated paths.
