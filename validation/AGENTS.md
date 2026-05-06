# Validation

- Use this tree for tracked O2 A DISAMAR-reference evidence that is intentionally committed.
- Keep validation-specific O2 A maintenance scripts in this directory when they read or rewrite the tracked validation bundle.
- Keep disposable traces, scratch runs, and exploratory validation output under `out/`.
- Keep spectra validation under `validation/spectra/` and inverse-method validation under `validation/optimal_estimation/`.
- The committed O2 A spectra comparison evidence lives under `validation/spectra/plots/` and `validation/spectra/data/`. Regenerate it with `zig build o2a-plot-bundle`; do not hand-edit its generated contents.
