# 08. Keep Program Setup Out Of The Forward Timer

This is a measurement and architecture boundary rather than one checkpoint win.
The forward timer should measure a prepared O2 A forward call, not full program
startup, config parsing, or asset loading.

In short: measure prepared forward calls separately from full executable setup.

Source links:

- DISAMAR
  - [Executable entry](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/main_DISAMAR.f90#L101-L119): includes full program startup and run orchestration in the executable lane.
  - [Module setup](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/DISAMARModule.f90#L2100-L2115): performs broad configuration and reference-data preparation before the forward calculation.
- zdisamar
  - [Fixed asset cache](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/input/o2a_reference/fixed_asset_cache.zig#L83-L103): keeps immutable reference assets out of repeated forward timing.
  - [Profile-state cache](https://github.com/bout3fiddy/zdisamar/blob/36598b67287c918b410ae25ca54319cbe63ade4b/src/forward_model/optical_properties/state_build/profile_state_cache.zig#L24-L60): prepares reusable profile state before the timed forward call.

DISAMAR executable timings include broad program work. zdisamar reports a
prepare/forward split so repeated spectra can reuse fixed assets and prepared
profile state.

```python
# Full executable timing.
def run_program(config_path):
    config = parse_config(config_path)
    assets = load_reference_assets(config)
    prepared = prepare_o2a(config, assets)
    return forward_model(prepared)

# Prepared forward timing.
assets = load_reference_assets_once()
prepared = prepare_o2a(case, assets)
timer.start()
spectrum = forward_model(prepared)
timer.stop()
```

This distinction matters when comparing timings: a full executable simulation
and an in-process prepared forward call are not the same measurement.
