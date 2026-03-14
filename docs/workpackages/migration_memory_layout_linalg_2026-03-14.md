# Work Package: Memory Layout, Prepared Plans, and Linalg

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_memory_layout_linalg_2026-03-14.md

RESUME
- Read this file from top to bottom.
- Continue from the first `WP-*` item whose status is not done.
- If every `WP-*` item is done and staging release is already complete, report final state and stop.
- If every `WP-*` item is done but staging release is not complete, continue with the finishing steps below.

EXECUTION RULES
- Keep changes non-destructive.
- Repository mode: library-first Zig project; no browser app is expected.
- Primary verification: `zig build test`, `zig build`, and targeted checks relevant to the change.
- Use Playwright/browser tooling only if the work introduces or changes a runtime UI surface.

WHEN YOU COMPLETE A `WP-*`
- Update that `WP-*` section with:
  - updated Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- Mark the WP title status line as `[Status: Done YYYY-MM-DD]`.
- Update the rollup row in this file with status, last-updated date, proof pointer, and next action.

CHECKPOINTS
- Commit and push periodically as coherent checkpoints.

FINISHING
- When all `WP-*` items are done, run the PR review remediation loop until all required checks pass and no new actionable review comments remain.
- Create a staging release.
- Only after staging release, update Linear issue LINEAR_ISSUE_REQUIRED_BEFORE_EXECUTION with shipped outcomes and move it to In Review.

REPEATS
- This command may be repeated.
- If staging release already exists for this work package, treat repeats as reminder signals and continue only unfinished steps.

ARCHITECTURE RULE
- Default to hard cutovers.
- Do not add fallback branches or shims unless explicitly approved with owner, removal date, and tracking issue.
```

## Mandatory Invocable Skills

- `[$workflows](/Users/swadhinnanda/.agents/skills/workflows/SKILL.md)`
- `[$coding](/Users/swadhinnanda/.agents/skills/coding/SKILL.md)`

## Metadata

- Created: 2026-03-14
- Scope: `src/model/layout`, `src/runtime/cache`, `src/core`, `src/kernels/interpolation`, `src/kernels/quadrature`, `src/kernels/linalg`, `tests`, `validation`
- Input sources: `docs/specs/original-plan.md`, `docs/specs/architecture.md`
- Constraints: keep hot numeric data separate from cold metadata; use prepared plans plus scratch workspaces as the allocation model; avoid monolithic math utility modules

## Background

The original plan treats memory layout and reusable preparation work as a first-order architectural concern, not a later optimization pass. This package isolates that work before transport and retrieval implementation begins.

## Overarching Goals

- Establish SoA/AoSoA layout choices where they matter.
- Move repeated setup into prepared plans and reusable scratch arenas.
- Keep interpolation, quadrature, and linalg packages narrow and independently testable.

## Non-goals

- Implementing plugin contracts or exporter flows.
- Reaching full numerical optimization for every kernel in one pass.
- Hiding layout decisions behind oversized abstraction layers.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | WP-01 Proof / validation | Continue finishing steps when requested |
| WP-02 | Done 2026-03-14 | 2026-03-14 | WP-02 Proof / validation (2026-03-14) | Continue finishing steps when requested |
| WP-03 | Done 2026-03-14 | 2026-03-14 | WP-03 Proof / validation | Continue finishing steps when requested |

## Work Package Items

### WP-01 Introduce Domain and Kernel Data Layouts [Status: Done 2026-03-14]

- Issue: the plan requires SoA for domain structures and AoSoA for the hottest tensor blocks, but the scaffold does not yet encode that split.
- Needs: explicit layout types for atmospheric layers, spectral grids, state vectors, and hot transport blocks.
- How: build typed layout helpers in `src/model/layout/` and expose only the minimum views that kernels need.
- Why this approach: layout contracts are easier to verify and benchmark when they are declared once and reused.
- Recommendation rationale: choose layout ownership before kernels and caches start depending on ad hoc arrays.
- Desired outcome: callers and kernels share stable layout types instead of custom per-module storage.
- Non-destructive tests: `zig build test`; focused tests for layout views and shape invariants; perf smoke tests when available.
- Files by type: storage/view helpers in `src/model/layout/`; consumers in `src/core/` and `src/kernels/`; validation notes in `validation/perf/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] Hot numeric and cold metadata ownership remained separate.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added typed layout modules under `src/model/layout/`:
    - `Axes.zig` (`SpectralAxis`, `LayerAxis`, `StateAxis`) with deterministic index/step validation.
    - `AtmosphereSoA.zig` with explicit hot numeric columns separated from cold metadata and layer views.
    - `StateVectorSoA.zig` with explicit state-axis shape checks and in-place scaling.
    - `TensorBlockAoSoA.zig` for lane-based hot tensor storage and index mapping.
    - `root.zig` exports for layout package composition.
  - Why this works: domain layout ownership is now explicit and typed, with SoA for domain columns and AoSoA for hot tensor blocks. Kernels can consume only validated axis/view surfaces instead of ad hoc raw arrays.
  - Proof / validation:
    - `zig test -Mroot=src/model/layout/root.zig` (pass).
    - `zig build test` (pass).
    - `zig build` (pass).
  - How to test:
    - Run `zig test -Mroot=src/model/layout/root.zig`.
    - Run `zig build test`.
    - Run `zig build`.

### WP-02 Add Prepared-Plan Caches and Scratch Reuse [Status: Done 2026-03-14]

- Issue: repeated work should live in prepared plans and resettable scratch workspaces instead of being rebuilt per request.
- Needs: dataset caches, precomputed operator caches, and workspace reset rules that match the runtime object model.
- How: define prepared artifacts under `src/runtime/cache/` and scratch ownership under `src/core/Workspace.zig` and `src/runtime/scheduler/`.
- Why this approach: stable preparation boundaries improve both latency and correctness because allocation ownership is explicit.
- Recommendation rationale: moving setup out of hot execution is the main performance architecture change in the original plan.
- Desired outcome: large repeated allocations and preparation work happen once per plan or cache lifetime, not once per request loop.
- Non-destructive tests: `zig build test`; cache reuse tests; workspace reset tests; targeted benchmarks where available.
- Files by type: caches in `src/runtime/cache/`; scratch orchestration in `src/core/` and `src/runtime/scheduler/`; regression checks in `tests/` and `validation/perf/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] Scratch ownership stayed in `Workspace` and not in hidden globals.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Added `src/runtime/cache/PreparedPlanCache.zig` to derive reusable spectral/layer/state/measurement layout hints from `Scene.Blueprint`; added `src/runtime/scheduler/ScratchArena.zig` to retain the largest reserved capacities across resets; and wired ownership through `src/core/Plan.zig`, `src/core/Workspace.zig`, and `src/core/Engine.zig` so plan preparation owns cache construction while workspace execution owns scratch reservation and reset.
  - Why this works: repeated setup now happens at the correct lifetime. The prepared plan carries stable cache hints, the workspace reuses scratch capacity instead of reallocating per request, and reset semantics are explicit rather than hidden behind globals or ad hoc allocator behavior.
  - Proof / validation:
    - `zig test src/root.zig` -> passed (25/25 tests), including prepared-cache, scratch-arena, and engine cache/scratch ownership tests.
    - `zig build test-perf` -> passed.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig test src/root.zig` to verify prepared-cache and scratch reuse invariants.
    - Run `zig build test-perf` for the repeated prepared-plan smoke check.
    - Run `zig build test` and `zig build` to confirm the cache/scratch model holds in the full graph.

### WP-03 Split Interpolation, Quadrature, and Linalg Packages [Status: Done 2026-03-14]

- Issue: the target design explicitly rejects one monolithic math-tools module.
- Needs: small, testable packages for quadrature, interpolation, and small-dense linear algebra paths.
- How: populate `src/kernels/quadrature/`, `src/kernels/interpolation/`, and `src/kernels/linalg/` with narrow responsibilities and explicit callers.
- Why this approach: small packages keep numerical code easier to audit and benchmark than one large toolbox.
- Recommendation rationale: package splits should happen before transport and retrieval implementations accumulate hidden coupling.
- Desired outcome: independent kernels with direct tests and clear callers.
- Non-destructive tests: `zig build test`; focused unit tests per kernel package; optional perf checks for hot kernels.
- Files by type: implementation in `src/kernels/*`; callers in `src/core/`, `src/runtime/`, and later transport/retrieval packages; evidence in `validation/perf/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No catch-all math module or compatibility wrapper was introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Split focused kernel packages into dedicated modules:
    - `src/kernels/interpolation/linear.zig` + `root.zig` (uniform linear interpolation).
    - `src/kernels/quadrature/composite_trapezoid.zig` + `root.zig` (composite trapezoid integration).
    - `src/kernels/linalg/vector_ops.zig` + `root.zig` (dot, axpy, L2 norm).
    Also updated `validation/perf/perf_matrix.json` with layout/kernel scenarios that match the strict validation schema.
  - Why this works: interpolation, quadrature, and linear algebra now live in separate narrow packages with direct tests and no compatibility wrapper, reducing hidden coupling before transport/retrieval expansion.
  - Proof / validation:
    - `zig test --dep model_layout -Mroot=src/kernels/interpolation/root.zig -Mmodel_layout=src/model/layout/root.zig` (pass).
    - `zig test --dep model_layout -Mroot=src/kernels/quadrature/root.zig -Mmodel_layout=src/model/layout/root.zig` (pass).
    - `zig test -Mroot=src/kernels/linalg/root.zig` (pass).
    - `zig build test` (pass).
    - `zig build` (pass).
  - How to test:
    - Run `zig test --dep model_layout -Mroot=src/kernels/interpolation/root.zig -Mmodel_layout=src/model/layout/root.zig`.
    - Run `zig test --dep model_layout -Mroot=src/kernels/quadrature/root.zig -Mmodel_layout=src/model/layout/root.zig`.
    - Run `zig test -Mroot=src/kernels/linalg/root.zig`.
    - Run `zig build test`.
