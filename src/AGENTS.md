# Source Tree

- `src/input/` owns typed atmosphere, geometry, surface, spectroscopy, instrument, and reference-data input structures.
- `src/forward_model/` owns optical-property preparation, radiative transfer, instrument-grid calculation, and implementation bindings.
- `src/output/` owns diagnostic reports and spectrum serialization.
- `src/common/` is shared support code only.
- `src/validation/disamar_reference/` owns the DISAMAR reference comparison helpers and CLI support.

## Rules

- Inline `test` blocks under `src/` are not allowed. Add tests under `tests/unit/`, mirroring the source path.
- Tests that need non-public symbols should use `src/internal.zig`; keep that access surface named after the current tree.
- Prefer the public flow input -> forward model -> output. Do not move product wiring into `src/common/`.
- Comments explain why, not what. Keep comments near non-obvious DISAMAR semantics, unit conversions, sign conventions, ordering, and intentional divergences.
- File I/O and text parsing belong in input, output, validation, CLI, or scripts, not in forward-model routines.
- Every new input/config field must be consumed, rejected with a typed error, or explicitly documented as inert with focused test coverage.
