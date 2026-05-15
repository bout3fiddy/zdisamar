# Rust Source Tree

- `input/` owns typed atmosphere, geometry, surface, spectroscopy, instrument, and reference-data input structures.
- `forward_model/` owns optical-property preparation, radiative transfer, instrument-grid calculation, and implementation bindings.
- `output/` owns diagnostic reports and spectrum serialization.
- `common/` is shared support code only.
- `api/` owns the C ABI used by the Python package.

## Rules

- Inline `#[cfg(test)] mod tests` blocks under `rust_src/` are not allowed. Add tests under `tests/rust/`, mirroring the source path.
- Prefer the public flow input -> RTM -> output. Do not move product wiring into `common/`.
- Comments explain why, not what. Keep comments near non-obvious DISAMAR semantics, unit conversions, sign conventions, ordering, and intentional divergences.
- File I/O and text parsing belong in input, output, validation, CLI, or scripts, not in RTM routines.
- Every new input/config field must be consumed, rejected with a typed error, or explicitly documented as inert with focused test coverage.
