# Tests

- `tests/` is for first-class unit, integration, golden, and performance suites.
- Do not treat dumped output artifacts as tests without harnesses or assertions.
- Keep fast correctness checks here; longer-running compatibility or benchmark assets belong in `validation/`.
- Keep the harness layered: `test-fast` owns the fast presubmit unit/integration coverage, while heavier compatibility evidence stays under `validation/`.
- Allocation-failure and `std.heap.DebugAllocator` coverage belong in the fast suites when they validate lifecycle or cleanup behavior.
- `tests/perf/` is for bounded smoke coverage and benchmark harness code that feeds `zig build bench`; disposable reports belong under `out/ci/`.
- `tests/validation/o2a_vendor_reflectance_assessment_test.zig` is an opt-in assessment lane, not a default correctness gate.
- Run it with `zig build test-validation-o2a-vendor` when you need to compare zdisamar's O2 A forward reflectance against the stored vendor reference for `Config_O2_with_CIA.in`.
- `tests/validation/o2a_vendor_line_list_smoke_test.zig` is a separate opt-in smoke lane for the vendor O2A line-list anchor/weak-line helper behavior. Run it with `zig build test-validation-o2a-vendor-line-list` when you need that coverage.
- The lane emits JSON on every run and only fails when the tracked metrics regress beyond the stored baseline tolerances. Treat the emitted JSON as the real output: compare `current` against `baseline`, look at `trend`, and decide whether `improved`, `flat`, or `regressed` matches the files that changed.
- A `flat` result is acceptable when the change did not touch forward physics or O2 A reference assets. A `regressed` result is a concern when work touched `src/kernels/transport`, `src/kernels/optics`, `src/o2a/data`, `src/model/reference`, `data/cross_sections`, or the O2 A reference CSV. A zero-difference pass is exceptional and should be called out explicitly.
- New config/control surfaces should get three kinds of coverage when practical: one valid-path test, one invalid or unsupported-input test, and one parity test against the legacy or alternate path when both are meant to agree.
- Shard and focused-lane tests must assert the intended case set or semantic outcome directly, not merely that some cases ran.
- When a change introduces derived hints, prepared metadata, or delayed config application, add at least one test that omits redundant legacy fields so stale fallback values cannot mask ordering bugs.
- Wavelength-dependent controls need at least two-point coverage when they affect prepared optics or morphology, so reference-only sampling mistakes fail deterministically.
