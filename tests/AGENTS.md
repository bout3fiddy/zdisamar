# Tests

- `tests/` is for first-class unit, integration, golden, and performance suites.
- Do not treat dumped output artifacts as tests without harnesses or assertions.
- Keep fast correctness checks here; longer-running compatibility or benchmark assets belong in `validation/`.
- Keep the harness layered: `test-fast` owns the fast presubmit unit/integration coverage, while heavier compatibility evidence stays under `validation/`.
- Allocation-failure and `std.heap.DebugAllocator` coverage belong in the fast suites when they validate lifecycle or cleanup behavior.
- `tests/perf/` is for bounded smoke coverage and benchmark harness code that feeds `zig build bench`; disposable reports belong under `out/ci/`.
- `tests/validation/o2a_compare_test.zig` backs the existing `zig build test-validation-o2a-vendor` lane.
- The lane runs one Zig O2A forward spectrum, times the run, compares it against the cached vendor CSV, and emits a JSON report.
- Run it with `zig build test-validation-o2a-vendor -Doptimize=ReleaseFast` when you want the runtime-oriented O2A compare without invoking the vendored executable.
- New config/control surfaces should get three kinds of coverage when practical: one valid-path test, one invalid or unsupported-input test, and one parity test against the legacy or alternate path when both are meant to agree.
- Shard and focused-lane tests must assert the intended case set or semantic outcome directly, not merely that some cases ran.
- When a change introduces derived hints, prepared metadata, or delayed config application, add at least one test that omits redundant legacy fields so stale fallback values cannot mask ordering bugs.
- Wavelength-dependent controls need at least two-point coverage when they affect prepared optics or morphology, so reference-only sampling mistakes fail deterministically.
