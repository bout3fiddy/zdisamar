# 13. Parallelize Traced Setup Phases

Historical checkpoint: `cd03a91^ -> cd03a91`, where the trace harness moved
from `prepare_o2a=0.177154 s` to `prepare_o2a=0.044454 s`.

In short: build independent O2 A setup products in parallel before the repeated
LABOS transport work begins.

Source links:

- DISAMAR
  - No direct Fortran analogue is used here. This is a zdisamar setup-boundary
    optimization around the typed O2 A baseline.
- zdisamar
  - [Wavelength sampling](https://github.com/bout3fiddy/zdisamar/blob/cd03a913b49cf1d65b8f6d6c3fed5074843122b6/src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig): parallelizes instrument support and forward-miss preparation.
  - [Absorber setup](https://github.com/bout3fiddy/zdisamar/blob/cd03a913b49cf1d65b8f6d6c3fed5074843122b6/src/forward_model/optical_properties/state_build/absorbers.zig): prepares fixed absorber state for the O2 A case.
  - [Layer accumulation](https://github.com/bout3fiddy/zdisamar/blob/cd03a913b49cf1d65b8f6d6c3fed5074843122b6/src/forward_model/optical_properties/state_build/layer_accumulation.zig): splits independent layer accumulation work across workers.

The forward calculation needs several setup products before it can enter the
high-resolution LABOS loop:

```python
# Serial shape.
wavelength_plan = build_wavelength_plan(instrument)
absorbers = build_absorbers(spectroscopy, atmosphere)
layers = accumulate_layers(atmosphere, aerosols)
forward = run_labos(wavelength_plan, absorbers, layers)

# Parallel setup shape.
wavelength_plan, absorbers, layers = join(
    spawn(build_wavelength_plan, instrument),
    spawn(build_absorbers, spectroscopy, atmosphere),
    spawn(accumulate_layers, atmosphere, aerosols),
)
forward = run_labos(wavelength_plan, absorbers, layers)
```

The retained detailed trace for that checkpoint reported:

```text
prepare_o2a                 0.177154 s -> 0.044454 s
forward elapsed time        1.799918 s -> 1.538076 s
forward-input CPU           4.055074 s -> 0.876687 s
```

The current branch later moved detailed timeline inspection to ztracy and added
a low-overhead Lauka wrapper for elapsed timing. Those newer artifacts should be
used for current numbers; this note records the mechanism and historical gain.
