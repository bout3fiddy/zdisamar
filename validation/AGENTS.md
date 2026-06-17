# Validation

- Use this tree for tracked output-validation evidence that is intentionally committed: zdisamar versus DISAMAR reference outputs, zdisamar normal versus fast-mode outputs, and Python optimal-estimation retrieval outputs.
- Keep validation-specific maintenance scripts in this directory when they run reference scenes, compare outputs, or rewrite the tracked validation bundle.
- Keep code-level invariants, API behavior checks, and algorithm unit checks under `tests/`, not in validation experiments.
- Keep disposable traces, scratch runs, and exploratory validation output under `out/`.
- Keep spectra validation under `validation/spectra/` and inverse-method validation under `validation/optimal_estimation/`.
- Keep shared validation setup under `validation/o2a/`; reserve
  `validation/common/` for generic validation plumbing.
- Keep validation-owned reference fixtures under `validation/reference_data/`.
- Use Altair for validation plots. Do not add Matplotlib back to validation scripts.
- Keep DISAMAR baseline retrieval configs on `aerosolLayerHeight 0`. `aerosolLayerHeight 1` activates a Fortran DISAMAR shortcut path, and these validation lanes are meant to compare zdisamar against the normal physical inverse problem instead.
- Keep tracked benchmark outputs under `validation/outputs/`; these files are generated evidence and should only be refreshed by the validation scripts.
- Invoke validation scripts directly with `uv run ...`; do not add one-off Python validation or plotting scripts to `zig build`.
- The committed O2A spectra comparison evidence lives under `validation/outputs/spectra/`. Regenerate it with `uv run validation/spectra/validate_spectra.py`; do not hand-edit its generated contents.
- Validation thresholds are sacred contracts, not tuning knobs. Do not loosen a
  threshold to make a failing lane pass. If a threshold fails, fix the
  configuration alignment, reference generation, implementation, or explicitly
  change the validation contract with documented scientific justification.
- You may only change residual/error thresholds after explicit user approval.
  Ask first, explain why the threshold change is needed, and wait for approval.
