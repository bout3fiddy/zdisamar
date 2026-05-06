# Validation

- Use this tree for tracked O2 A DISAMAR-reference evidence that is intentionally committed.
- Keep validation-specific O2 A maintenance scripts in this directory when they read or rewrite the tracked validation bundle.
- Keep disposable traces, scratch runs, and exploratory validation output under `out/`.
- Keep spectra validation under `validation/spectra/` and inverse-method validation under `validation/optimal_estimation/`.
- Keep reference fixtures under `*/data/reference/`.
- Keep tracked benchmark outputs under `validation/outputs/`; these files are generated evidence and should only be refreshed by the validation scripts.
- The committed O2 A spectra comparison evidence lives under `validation/outputs/spectra/`. Regenerate it with `zig build o2a-plot-bundle`; do not hand-edit its generated contents.
