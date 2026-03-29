# Tests

- `tests/` is for first-class unit, integration, golden, and performance suites.
- Do not treat dumped output artifacts as tests without harnesses or assertions.
- Keep fast correctness checks here; longer-running compatibility or benchmark assets belong in `validation/`.
- Keep the harness layered: `test-fast` owns the fast presubmit unit/integration coverage, while heavier compatibility evidence stays under `validation/`.
- Allocation-failure and `std.heap.DebugAllocator` coverage belong in the fast suites when they validate lifecycle or cleanup behavior.
- `tests/perf/` is for bounded smoke coverage and benchmark harness code that feeds `zig build bench`; disposable reports belong under `out/ci/`.
- `tests/validation/o2a_vendor_reflectance_assessment_test.zig` is an opt-in assessment lane, not a default correctness gate.
- `tests/validation/o2a_compare_test.zig` is the lightweight O2A compare lane. It runs one Zig forward spectrum, times the run, compares it against the cached vendor CSV, and emits a JSON report.
- Run it with `zig build test-validation-o2a-compare -Doptimize=ReleaseFast` when you want a runtime-oriented O2A check without invoking the vendored executable.
- Run the stricter vendor assessment lane with `zig build test-validation-o2a-vendor` when you need to compare zdisamar's O2 A forward reflectance against the stored vendor reference for `Config_O2_with_CIA.in`.
- The lane emits JSON on every run and only fails when the tracked metrics regress beyond the stored baseline tolerances. Treat the emitted JSON as the real output: compare `current` against `baseline`, look at `trend`, and decide whether `improved`, `flat`, or `regressed` matches the files that changed.
- A `flat` result is acceptable when the change did not touch forward physics or O2 A reference assets. A `regressed` result is a concern when work touched `src/kernels/transport`, `src/kernels/optics`, `src/runtime/reference`, `src/model/reference`, `data/cross_sections`, or the O2 A reference CSV. A zero-difference pass is exceptional and should be called out explicitly.
- New config/control surfaces should get three kinds of coverage when practical: one valid-path test, one invalid or unsupported-input test, and one parity test against the legacy or alternate path when both are meant to agree.
- Shard and focused-lane tests must assert the intended case set or semantic outcome directly, not merely that some cases ran.
- When a change introduces derived hints, prepared metadata, or delayed config application, add at least one test that omits redundant legacy fields so stale fallback values cannot mask ordering bugs.
- Wavelength-dependent controls need at least two-point coverage when they affect prepared optics or morphology, so reference-only sampling mistakes fail deterministically.
