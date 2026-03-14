# Work Package: Core Runtime and Model Migration

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_core_runtime_model_2026-03-14.md

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
- Scope: `src/core`, `src/model`, `src/runtime`, `src/root.zig`, `src/api/zig`
- Input sources: `docs/specs/original-plan.md`, `docs/specs/architecture.md`, `docs/specs/fortran-mapping.md`
- Constraints: no global mutable state; no file I/O or text parsing in `src/core`; keep the public surface typed around `Engine -> Plan -> Workspace -> Request -> Result`; do not reintroduce string-keyed mutation APIs

## Background

The original plan makes the runtime object model and canonical scene model the first structural cutover. This folder turns that into resumable slices tied to the current scaffold.

## Overarching Goals

- Lock the runtime around `Engine`, `Plan`, `Workspace`, `Request`, `Result`, and `Catalog`.
- Replace split simulation/retrieval trees with one canonical scene and observation model.
- Make ownership and layering explicit across `src/core`, `src/model`, and `src/runtime`.

## Non-goals

- Implementing transport kernels or retrieval algorithms.
- Building legacy config import or exporter adapters.
- Preserving string-keyed compatibility shims.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | WP-01 Proof / validation (2026-03-14) | Continue finishing steps when requested |
| WP-02 | Done 2026-03-14 | 2026-03-14 | WP-02 Proof / validation (2026-03-14) | Continue finishing steps when requested |
| WP-03 | Done 2026-03-14 | 2026-03-14 | WP-03 Proof / validation (2026-03-14) | Continue finishing steps when requested |

## Work Package Items

### WP-01 Define Runtime Lifecycle Contracts [Status: Done 2026-03-14]

- Issue: the scaffold has the right file names, but the lifetime and ownership rules for `Engine`, `Plan`, `Workspace`, `Request`, `Result`, and `Catalog` still need explicit execution criteria.
- Needs: typed constructors, execution flow contracts, and error boundaries that match the target public API.
- How: tighten `src/core/*`, `src/root.zig`, and `src/api/zig/root.zig` around the target lifecycle, then refresh the local architecture notes in `docs/specs/` if the contract surface changes.
- Why this approach: locking lifecycle contracts first prevents later adapters and plugins from rebuilding stringly or stateful seams.
- Recommendation rationale: enforce lifecycle guardrails directly in `Engine`/`Plan`/`Request`/`Workspace` so invalid plans, model families, derivative expectations, and workspace reuse are rejected at typed boundaries rather than leaking into adapters or kernels.
- Desired outcome: a caller can prepare a plan and execute a request without global state or string-keyed mutation.
- Non-destructive tests: `zig build test`; `zig build`; targeted compile checks for the public Zig surface.
- Files by type: core contracts in `src/core/`; exported bindings in `src/api/zig/` and `src/root.zig`; local architecture notes in `docs/specs/` when useful for execution context.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No string-keyed mutation API or fallback shim was introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Added typed lifecycle validation across `src/core` (`template.validate`, model-family support checks, prepared-plan limit checks, request/scene validation, workspace plan binding, derivative-mode matching) and exposed canonical model contract types (`DerivativeMode`, `InverseProblem`, `StateVector`, `MeasurementVector`) through `src/root.zig` and `src/api/zig/root.zig`.
  - Why this works: execution now requires explicit, validated contracts at each lifecycle boundary (`Engine.preparePlan` and `Engine.execute`) so invalid state is rejected before kernel wiring; workspace ownership is explicit (single-plan binding until reset), and scene/request contracts are typed rather than inferred from runtime strings.
  - Proof / validation:
    - `zig test src/root.zig` -> passed (8/8 tests), including new lifecycle-contract and scene-validation tests.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig test src/root.zig` to verify lifecycle contract behavior and scene validation.
    - Run `zig build test` and `zig build` to confirm the lifecycle contracts hold under the repo-wide build and suite graph.

### WP-02 Canonicalize Scene and Observation Types [Status: Done 2026-03-14]

- Issue: the original plan rejects parallel sim/retr trees in favor of one canonical `Scene`, `ObservationModel`, and `InverseProblem`.
- Needs: a single domain model that retrieval code can layer onto without duplicating geometry, atmosphere, spectrum, or measurement structures.
- How: expand `src/model/` and `src/retrieval/common/` around canonical scene, measurement, and inverse-problem types while keeping retrieval policy out of the core runtime.
- Why this approach: one domain model reduces migration churn and removes the incentive to recreate legacy twin trees.
- Recommendation rationale: the scene model must stabilize before transport, retrieval, and adapter work can share a consistent contract.
- Desired outcome: downstream code depends on one typed domain model rather than simulation/retrieval forks.
- Non-destructive tests: `zig build test`; targeted model construction tests under `tests/unit/`; API compile checks for any exported scene/request types.
- Files by type: model definitions in `src/model/`; inverse layering in `src/retrieval/common/`; local contract notes in `docs/specs/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No parallel sim/retr object tree was introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Expanded the canonical model in `src/model/Scene.zig` with `ObservationModel`, `ObservationRegime`, `DerivativeMode`, `StateVector`, `MeasurementVector`, `InverseProblem`, and `Blueprint` layout hints; extended `src/core/Request.zig` to carry `inverse_problem` and `expected_derivative_mode`; layered retrieval contracts on the canonical request/scene types in `src/retrieval/common/contracts.zig`; and re-exported the shared scene surface through `src/root.zig` and `src/api/zig/root.zig`. Also wired retrieval coverage into the standard suite graph via `build.zig`, `tests/unit/main.zig`, and `tests/integration/main.zig`.
  - Why this works: transport and retrieval now consume one typed scene/observation model instead of rebuilding separate simulation and retrieval trees. Canonical observation regime, derivative mode, inverse-problem structure, and layout requirements all originate from `src/model/` and are reused by retrieval contracts and plan preparation.
  - Proof / validation:
    - `zig build test-unit` -> passed.
    - `zig build test-integration` -> passed.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig build test-unit` and `zig build test-integration` to verify the retrieval suite is part of the normal graph.
    - Run `zig test --dep zdisamar -Mroot=src/retrieval/root.zig -Mzdisamar=src/root.zig` to exercise the retrieval-common and solver modules directly.
    - Run `zig build test` and `zig build` to confirm the canonical model composes through the full repository build.

### WP-03 Enforce Core, Model, and Runtime Boundaries [Status: Done 2026-03-14]

- Issue: the migration only works if `src/core`, `src/model`, and `src/runtime` keep clear ownership lines and stay free of file-driven orchestration.
- Needs: documented and enforced directory boundaries, especially around plan preparation, scratch allocation, and dataset cache ownership.
- How: update module boundaries, entry-point wiring, and local architecture notes so `Plan` owns prepared configuration, `Workspace` owns scratch only, and `runtime/cache` stays read-only to callers.
- Why this approach: boundary enforcement stops new work from leaking adapter or mission concerns back into the core tree.
- Recommendation rationale: directory ownership is a precondition for scalable package-by-package execution.
- Desired outcome: agents can change one area without guessing where state, allocation, or orchestration belongs.
- Non-destructive tests: `zig build test`; boundary-focused regression checks; static searches for forbidden file I/O or parser imports under `src/core`.
- Files by type: ownership and lifetime code in `src/core/` and `src/runtime/`; boundary notes in `docs/specs/architecture.md`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No file I/O, text parsing, or mission-specific logic leaked into `src/core` or `src/runtime`.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Finalized plan/runtime ownership so `src/core/Plan.zig` owns the prepared transport route, prepared-plan cache, and frozen plugin snapshot; `src/core/Workspace.zig` owns scratch lifecycle only; `src/runtime/cache/PreparedPlanCache.zig` and `src/runtime/scheduler/ScratchArena.zig` stay as reusable runtime support modules; and `src/core/Engine.zig` performs plan preparation, typed route resolution, and scratch reservation without leaking adapter concerns into the core tree.
  - Why this works: ownership boundaries are explicit and enforceable. `Plan` carries prepared state, `Workspace` carries resettable execution scratch, and runtime support stays behind typed calls. That keeps `src/core` and `src/runtime` free of file-driven orchestration while still allowing prepared-plan reuse and typed provenance.
  - Proof / validation:
    - `rg -n "std\\.fs|readFile|openFile|parseFromSlice|parseFromTokenSource|std\\.json|tokenize|legacy_config|mission" src/core src/runtime` -> no matches.
    - `zig test src/root.zig` -> passed (25/25 tests), including transport-route, cache, scratch, and boundary regression tests.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run the `rg` search above to confirm `src/core` and `src/runtime` remain free of file I/O, parser, and mission wiring.
    - Run `zig test src/root.zig` for focused boundary and ownership regression coverage.
    - Run `zig build test` and `zig build` for full verification.
