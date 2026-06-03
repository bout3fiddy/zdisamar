# Forward-Model Instrumentation

- This directory holds the production-facing instrumentation facades:
  `trace.zig`, `telemetry.zig`, and `sensitivity.zig`.
- Normal forward-model code imports these facades only. Capture storage,
  Parquet writers, trace CLIs, perturbation sweep drivers, and analysis code
  live under `scaffolding/instrumentation/`.
- Keep this directory free of file I/O, CLI wiring, text parsing, allocation
  surprises, and hidden global state beyond the explicit sink state needed by
  an enabled research harness.
- Disabled product and test builds must compile these APIs to no-ops or
  baseline-preserving pass-throughs.

## How It Works

- `build.zig` chooses either a no-op stub sink or a scaffolding research sink.
- `build_options` carries the requested flag:
  `enable_ztracy`, `enable_calculation_telemetry`, or
  `enable_perturbation_sensitivity`.
- A facade is active only when both the build option requests it and the
  selected sink reports `available`.
- Stubs preserve the public API while doing no work. They should stay small and
  obvious.

## Insertion Points

- `trace.zig` wraps timeline zones, counters, thread names, messages, and frame
  markers. Call sites sit around input preparation, product simulation, LABOS,
  optimal estimation, worker chunks, and trace CLIs.
- `telemetry.zig` records structured calculation rows. Call sites sit around
  wavelength sampling, cache misses, reflectance assembly, Jacobian columns,
  LABOS layer/order/Fourier decisions, and optimal-estimation context.
- `sensitivity.zig` exposes perturbation hooks for ablation sweeps. Call sites
  sit inside LABOS Fourier contribution/tail decisions, layer-doubling gates,
  scattering-order convergence, and aerosol Jacobian contributions.

## Editing Rules

- Add instrumentation at the measured work site, with names that describe the
  model phase or quantity being measured.
- Do not let instrumentation change physics, cache behavior, or public results
  when disabled.
- Keep file headers as concise maps of what the facade records and where hooks
  are inserted. Do not add function docstrings for pass-through facade methods.
- Run `zig fmt` and
  `uv run scripts/linting/check-zig-styleguide.py src/forward_model/instrumentation`
  after changing this directory.
