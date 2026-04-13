## O2A Telemetry

Telemetry is explicit and stage-based. It is product code, not test-only support.

The retained profiling path is:

- [src/o2a/report/json.zig](../src/o2a/report/json.zig)
- [src/o2a/cli/profile.zig](../src/o2a/cli/profile.zig)

## What Gets Measured

Preparation phases:

- input loading
- scene assembly
- optics preparation
- route preparation

Forward phases:

- radiance integration
- radiance postprocess
- irradiance integration
- irradiance postprocess
- reduction

The profile workflow emits `summary.json` and can also emit `generated_spectrum.csv`.

## Design Rules

- telemetry should read like the physics pipeline, not like a framework
- timers and counters stay explicit
- detailed snapshots are opt-in and bounded
- numerics are not wrapped in telemetry-aware scalar types

The retained local command is:

```bash
zig build o2a-forward-profile
```

The plot bundle path layers on top of the same profile workflow:

```bash
zig build o2a-plot-bundle
```
