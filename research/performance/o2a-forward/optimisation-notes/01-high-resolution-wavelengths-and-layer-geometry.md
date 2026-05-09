# 01. Reuse Wavelength Work And Layer Geometry

Historical checkpoint: `511061b -> e23035b`, where forward elapsed time moved
from `79.767901 s` to `11.890893 s`. This checkpoint combines two reuse
boundaries: unique high-resolution wavelength evaluation and shared layer
geometry.

In short: calculate each unique radiance sample once and reuse scene-stable
geometry across those samples.

Source links:

- DISAMAR
  - [Wavelength setup](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/DISAMARModule.f90#L2716-L2732): prepares broad wavelength tables for the general executable, so the O2 A path does not start from the smallest unique radiance list.
  - [Layer setup](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/DISAMARModule.f90#L2734-L2744): builds vertical layer state in the broad setup flow rather than exposing a narrow scene-stable geometry cache.
  - [LABOS layer use](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/LabosModule.f90#L472-L483): consumes the general layer structures inside repeated transport work.
- zdisamar
  - [Sampling entry](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/simulate.zig#L51-L75): makes wavelength sampling an explicit first step before transport.
  - [Unique list](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig#L109-L135): collapses repeated high-resolution radiance samples to exact unique work.
  - [Shared geometry](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/shared_geometry.zig#L127-L150): prepares scene-stable vertical geometry once.
  - [Forward input](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/instrument_grid/grid_calculation/forward_input.zig#L21-L53): combines cached geometry with wavelength-dependent optical values.

The useful O2 A boundary is the full set of work that is stable for the scene.
The output grid needs repeated high-resolution radiance samples, and each sample
uses the same vertical geometry with wavelength-dependent optical values.

```python
# Broad route: rediscover wavelength support and rebuild geometry repeatedly.
for output_wavelength in output_grid:
    samples = instrument_support(output_wavelength)
    values = []
    for sample in samples:
        geometry = build_layer_geometry(scene)
        optical = build_wavelength_optics(scene, sample, geometry)
        values.append(labos(optical, geometry))
    spectrum[output_wavelength] = integrate(values)

# Narrow route: prepare stable scene data and evaluate unique samples once.
geometry = build_layer_geometry(scene)
needed = []
for output_wavelength in output_grid:
    needed.extend(instrument_support(output_wavelength))

cache = {}
for sample in sorted(set(needed)):
    optical = build_wavelength_optics(scene, sample, geometry)
    cache[sample] = labos(optical, geometry)

for output_wavelength in output_grid:
    spectrum[output_wavelength] = integrate_from_cache(output_wavelength, cache)
```

The science is unchanged. The change is that scene-invariant geometry and exact
duplicate high-resolution radiance samples are no longer recomputed.
