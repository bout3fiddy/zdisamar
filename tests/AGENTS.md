# Tests

- Inline `test` blocks under `src/` are not allowed — tests live under `tests/unit/`, mirroring source paths. The `check-no-inline-src-tests.sh` guard (wired into `zig build check`) fails when `^test "` reappears under `src/`. Tests that need access to non-`pub` symbols go through the `internal` module re-exports in `src/internal.zig` and the matching `<dir>/internal.zig` shim files.
- `tests/` is for first-class unit, integration, golden, and performance suites.
- Do not add smoke-style tests as normal correctness coverage. New tests must be
  classified as unit, integration, golden/regression, property, fuzz,
  packaging, or benchmark/performance.
- A test must assert the invariant it claims to protect. A route that only
  checks status, handles, counts, prints, or finite values is incomplete unless
  it is explicitly a packaging/release smoke probe.
- Python tests should be pytest-collected by default. Direct
  `python tests/python/*.py` scripts are allowed only for release or validation
  harnesses with a stated reason.
- Literal `*_smoke*` names are reserved for packaging/install probes under
  `scripts/` or release-only pytest marks. They must not replace source-level
  unit, integration, property, or fuzz tests.
- When verification is needed, run the root `./verify` once for the current
  tree. Do not assemble ad hoc repeated verification command sets.
- Do not treat dumped output artifacts as tests without harnesses or assertions.
- Keep fast correctness checks here; longer-running compatibility or benchmark assets belong in `validation/`.
- Keep the harness layered: `test-fast` owns the fast presubmit unit/integration coverage, while heavier compatibility evidence stays under `validation/`.
- Allocation-failure and `std.heap.DebugAllocator` coverage belong in the fast suites when they validate lifecycle or cleanup behavior.
- Kernel and construction experiments live under `scaffolding/experiments/`; `tests/` contains asserting coverage.
- `tests/validation/o2a_vendor_reflectance_assessment_test.zig` is an opt-in DISAMAR-reference assessment lane, not a default correctness gate.
- Run it with `zig build test-validation-o2a-vendor` when you need to compare zdisamar's forward reflectance against the stored DISAMAR reference for `Config_O2_with_CIA.in`.
- The lane emits JSON on every run and only fails when the tracked metrics regress beyond the stored baseline tolerances. Treat the emitted JSON as the real output: compare `current` against `baseline`, look at `trend`, and decide whether `improved`, `flat`, or `regressed` matches the files that changed.
- A `flat` result is acceptable when the change did not touch forward physics or reference assets. A `regressed` result is a concern when work touched `src/rtm/`, `src/optics/`, `src/spectrum/`, `src/setup/`, `src/input/case.zig`, `data/reference_data/cross_sections`, or the reference CSV. A zero-difference pass is exceptional and should be called out explicitly.
- New config/control surfaces should get three kinds of coverage when practical: one valid-path test, one invalid or unsupported-input test, and one DISAMAR-reference test against the legacy or alternate path when both are meant to agree.
- Shard and focused-lane tests must assert the intended case set or semantic outcome directly, not merely that some cases ran.
- When a change introduces derived hints, prepared metadata, or delayed config application, add at least one test that omits redundant legacy fields so stale fallback values cannot mask ordering bugs.
- Wavelength-dependent controls need at least two-point coverage when they affect prepared optics or morphology, so reference-only sampling mistakes fail deterministically.
