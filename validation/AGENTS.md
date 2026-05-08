# Validation

- Use this tree for tracked O2 A DISAMAR-reference evidence that is intentionally committed.
- Keep validation-specific O2 A maintenance scripts in this directory when they read or rewrite the tracked validation bundle.
- Keep disposable traces, scratch runs, and exploratory validation output under `out/`.
- Keep spectra validation under `validation/spectra/` and inverse-method validation under `validation/optimal_estimation/`.
- Keep reference fixtures under `*/data/reference/`.
- Keep DISAMAR baseline retrieval configs on `aerosolLayerHeight 0`. `aerosolLayerHeight 1` activates a Fortran DISAMAR shortcut path, and these validation lanes are meant to compare zdisamar against the normal physical inverse problem instead.
- Keep tracked benchmark outputs under `validation/outputs/`; these files are generated evidence and should only be refreshed by the validation scripts.
- The committed O2 A spectra comparison evidence lives under `validation/outputs/spectra/`. Regenerate it with `zig build o2a-plot-bundle`; do not hand-edit its generated contents.
- Validation thresholds are sacred contracts, not tuning knobs. Do not loosen a
  threshold to make a failing lane pass. If a threshold fails, fix the
  configuration alignment, reference generation, implementation, or explicitly
  change the validation contract with documented scientific justification.
