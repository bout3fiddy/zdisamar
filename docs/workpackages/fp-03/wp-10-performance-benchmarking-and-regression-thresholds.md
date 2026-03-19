# WP-10 Performance Benchmarking And Regression Thresholds

## Metadata

- Created: 2026-03-18
- Scope: add performance baselines and regression thresholds for the scientifically correct direct and LUT-backed execution paths
- Input sources:
  - vendor runtime structure in `DISAMARModule.f90`
  - vendor heavy-path modules such as `radianceIrradianceModule.f90`, `LabosModule.f90`, `addingToolsModule.f90`, `propAtmosphere.f90`
  - Zig perf tests and runtime/cache code
- Dependencies:
  - `WP-02` through `WP-09`
- Reference baseline:
  - vendor `DISAMARModule.f90::{setupHRWavelengthGrid,prepareSimulation,retrieve}`
  - Zig `tests/perf/parity_perf_harness_test.zig`

## Background

Scientific correctness comes first, but the final system also needs predictable cost. DISAMAR-style line-by-line, multi-stream, cloud/aerosol, and retrieval cases can become expensive fast. This WP adds baselines after the scientific harness exists so performance work is driven by real case families instead of synthetic microbenchmarks alone.

## Overarching Goals

- Measure the cost of the major execution stages on representative parity cases.
- Catch performance regressions without encouraging premature optimization.
- Distinguish direct, LUT-backed, and measured-input execution costs.

## Non-goals

- Trading away scientific correctness for benchmark wins.
- Introducing unsafe caching or hidden approximations just to pass thresholds.
- Rewriting architecture around benchmark harnesses.

### WP-10 Performance benchmarking and regression thresholds [Status: Todo]

Issue:
The repo has some perf scaffolding, but there is not yet a parity-aware performance program tied to the scientific acceptance matrix.

Needs:
- case-family benchmarks
- stage-level timing breakdowns
- regression thresholds linked to validated modes
- clear separation of direct vs LUT-backed vs measured-input costs

How:
1. Use the validation case matrix as the source of benchmark scenarios.
2. Time HR grid setup, optics preparation, transport, instrument convolution, retrieval, and export separately.
3. Record direct and LUT-backed performance separately.
4. Add regression thresholds that are strict enough to catch breakage but loose enough for CI variability.

Why this approach:
Performance only matters in context. Benchmarking the same validated cases that support scientific parity prevents the team from optimizing irrelevant micro-paths while missing real bottlenecks.

Recommendation rationale:
This follows the validation harness because you need stable scientifically correct cases before performance numbers are meaningful.

Desired outcome:
For each major case family, the repo can answer: how long did setup take, how long did the forward pass take, how long did retrieval take, and did a change cause a regression beyond the accepted threshold?

Non-destructive tests:
- `zig build test-perf --summary all`
- `zig test tests/perf/parity_perf_harness_test.zig`
- `zig test tests/perf/dispatch_smoke_test.zig`

Files by type:
- Perf harness targets:
  - `tests/perf/parity_perf_harness_test.zig`
  - `tests/perf/dispatch_smoke_test.zig`
  - `tests/perf/main.zig`
- Runtime/engine targets:
  - `src/core/Engine.zig`
  - `src/runtime/cache/LUTCache.zig`
  - `src/runtime/cache/PlanCache.zig`
  - `src/runtime/scheduler/BatchRunner.zig`
  - `src/kernels/transport/measurement_space.zig`
  - `src/kernels/optics/prepare.zig`
- Validation/case assets:
  - `tests/validation/assets/vendor_cases/`
  - `tests/perf/assets/perf_case_catalog.json` (new)

## Exact Patch Checklist

- [ ] `tests/perf/parity_perf_harness_test.zig` and `tests/perf/assets/perf_case_catalog.json` (new): benchmark representative case families instead of synthetic placeholders.
  - Required families: O2A direct, O2A LUT-backed, NO2/O3 UV/Vis, cloud/cirrus, and one operational measured-input case.
  - Record stage timings for grid setup, optics prep, transport, convolution, retrieval, and export.

- [ ] `src/core/Engine.zig`: expose stable timing hooks around major execution stages.
  - Keep instrumentation low overhead and build-flag-controlled.
  - Do not add pervasive logging side effects; capture timings in a structured benchmark result.

- [ ] `src/runtime/cache/LUTCache.zig`, `src/runtime/cache/PlanCache.zig`, `src/runtime/scheduler/BatchRunner.zig`: benchmark cache-hit and cache-miss behavior explicitly.
  - Distinguish first-run cost from steady-state cost.
  - Include plan reuse and LUT reuse scenarios, but do not let caches hide scientific mismatches.

- [ ] `src/kernels/optics/prepare.zig` and `src/kernels/transport/measurement_space.zig`: add optional internal timing scopes for hotspot decomposition.
  - The benchmark output should show whether time is dominated by spectroscopy, transport, convolution, or retrieval.
  - Use these timings to guide optimization only after correctness and acceptance tests pass.

- [ ] `tests/perf/dispatch_smoke_test.zig`: add mode-sensitive smoke benchmarks.
  - Confirm that direct, LUT-backed, and measured-input execution all run through the expected route and emit timings.
  - This catches accidental route collapse or cache misuse.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Benchmarks cover direct, LUT-backed, and measured-input modes
- [ ] Stage-level timing breakdowns are available for major case families
- [ ] Regression thresholds are documented and enforced in perf tests

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

Because the benchmarks are tied to real validated cases, performance regressions are caught where users actually care about them, and performance work stays subordinate to scientific correctness instead of replacing it.

## Proof / Validation

- Planned: `zig test tests/perf/parity_perf_harness_test.zig` -> case-family benchmarks run and store timing summaries
- Planned: `zig test tests/perf/dispatch_smoke_test.zig` -> route-sensitive smoke timings distinguish direct/LUT/measured modes
- Planned: benchmark summaries checked into local artifact folders during validation passes

## How To Test

1. Run the perf harness on the curated case catalog.
2. Compare first-run and cache-hit timings.
3. Confirm the reported hotspots match the expected stage breakdown.
4. Change one hotspot intentionally and verify the regression threshold catches it.
