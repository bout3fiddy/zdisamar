# Validation

- Use this tree for compatibility, golden, plugin, and performance validation assets that are broader or heavier than normal tests.
- Validation data should support parity and regression analysis against the tracked specs and the local Fortran reference clone.
- `validation/compatibility/o2a_plots/` is committed O2A comparison evidence. Regenerate it by command with `zig build o2a-plot-bundle`; do not hand-edit its contents.
