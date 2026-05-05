# Validation

- Use this tree for tracked O2 A DISAMAR-reference evidence that is intentionally committed.
- Keep validation-specific O2 A maintenance scripts in this directory when they read or rewrite the tracked validation bundle.
- Keep disposable traces, scratch runs, and exploratory validation output under `out/`.
- The committed O2 A comparison evidence lives under `validation/plots/` and `validation/data/`. Regenerate it with `zig build o2a-plot-bundle`; do not hand-edit its generated contents.
