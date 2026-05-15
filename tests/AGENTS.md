# Tests

- Inline `#[cfg(test)] mod tests` blocks under `rust_src/` are not allowed. Tests live under `tests/rust/`, mirroring source paths. The `check-no-inline-src-tests.sh` guard is wired into `prek run --all-files`.
- `tests/` is for first-class unit, integration, golden, and performance suites.
- Do not treat dumped output artifacts as tests without harnesses or assertions.
- Keep fast correctness checks here; longer-running compatibility or benchmark assets belong in `validation/`.
- Keep the harness layered: `cargo test` owns the fast presubmit unit/integration coverage, while heavier compatibility evidence stays under `validation/`.
- Allocation-failure and `std.heap.DebugAllocator` coverage belong in the fast suites when they validate lifecycle or cleanup behavior.
- Performance and compatibility benchmark reports belong under `validation/outputs/` when tracked, or `out/` when disposable.
- A validation regression is a concern when work touched `rust_src/forward_model/radiative_transfer`, `rust_src/forward_model/optical_properties`, `rust_src/input/o2a_reference`, `rust_src/input/reference`, `data/reference_data/cross_sections`, or the O2 A reference CSV.
- New config/control surfaces should get three kinds of coverage when practical: one valid-path test, one invalid or unsupported-input test, and one DISAMAR-reference test against the legacy or alternate path when both are meant to agree.
- Shard and focused-lane tests must assert the intended case set or semantic outcome directly, not merely that some cases ran.
- When a change introduces derived hints, prepared metadata, or delayed config application, add at least one test that omits redundant legacy fields so stale fallback values cannot mask ordering bugs.
- Wavelength-dependent controls need at least two-point coverage when they affect prepared optics or morphology, so reference-only sampling mistakes fail deterministically.
