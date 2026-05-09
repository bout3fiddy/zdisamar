# 02. Prepare Line Spectroscopy Once

Historical checkpoint: `163db7e -> 5ef6c71`, where forward elapsed time moved
from `35.364130 s` to `8.432518 s`.

In short: move pressure/temperature line preparation out of the per-wavelength
loop.

Source links:

- DISAMAR
  - [HITRAN preparation](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/HITRANModule.f90#L161-L212): broad line-list preparation is tied to the executable setup path, so the timing comparison includes more general spectroscopy work.
- zdisamar
  - [Absorber preparation](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/absorbers.zig#L154-L171): creates prepared absorber state before wavelength evaluation.
  - [State spectroscopy](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/state_spectroscopy.zig#L60-L87): stores pressure/temperature line state so it is not rebuilt per sample.
  - [Line-list operations](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/input/reference/spectroscopy/line_list_ops.zig#L126-L147): evaluates the remaining wavelength-dependent line shape from prepared state.

Line strength and pressure/temperature state are scene dependent. The expensive
part should be prepared once, then the forward pass should evaluate the
wavelength-dependent line shape.

```python
# Broad route: mix scene preparation with wavelength evaluation.
for wavelength in high_resolution_samples:
    total = 0.0
    for line in lines:
        state = prepare_line_for_temperature_pressure(line, atmosphere)
        total += evaluate_line_shape(state, wavelength)

# Narrow route: prepare line state once.
prepared_lines = [
    prepare_line_for_temperature_pressure(line, atmosphere)
    for line in lines
]

for wavelength in high_resolution_samples:
    total = sum(evaluate_line_shape(line, wavelength) for line in prepared_lines)
```

The remaining spectroscopy cost is still real, but the repeated
pressure/temperature setup is no longer paid for every wavelength.
