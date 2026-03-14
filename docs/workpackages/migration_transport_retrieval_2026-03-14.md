# Work Package: Transport and Retrieval Migration

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_transport_retrieval_2026-03-14.md

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
- Scope: `src/kernels/transport`, `src/kernels/polarization`, `src/kernels/spectra`, `src/retrieval`, `src/model`, `validation`
- Input sources: `docs/specs/original-plan.md`, `docs/specs/architecture.md`, `docs/specs/fortran-mapping.md`
- Constraints: preserve adding and LABOS as first-class builtins; expose derivative modes explicitly; keep retrieval layered on the canonical scene model

## Background

The original plan calls out transport routing and derivative handling as core physics boundaries. Retrieval code then layers on the same canonical scene model rather than creating a second system.

## Overarching Goals

- Preserve the transport families as explicit, typed plan-time choices.
- Make derivative mode a first-class forward-operator contract.
- Keep OE, DOAS, and DISMAS built on shared model and kernel infrastructure.

## Non-goals

- Designing plugin ABI details.
- Recreating legacy Fortran module structure in Zig.
- Mixing mission wiring or file export logic into transport or retrieval code.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | WP-01 Proof / validation (2026-03-14) | Continue finishing steps when requested |
| WP-02 | Done 2026-03-14 | 2026-03-14 | WP-02 Proof / validation (2026-03-14) | Continue finishing steps when requested |
| WP-03 | Done 2026-03-14 | 2026-03-14 | WP-03 Proof / validation (2026-03-14) | Continue finishing steps when requested |

## Work Package Items

### WP-01 Implement Plan-Time Transport Dispatch [Status: Done 2026-03-14]

- Issue: the target architecture depends on a `SolverDispatcher` that chooses transport strategy by regime and derivative needs.
- Needs: typed transport mode selection plus clear boundaries between common transport helpers and specific solvers.
- How: populate `src/kernels/transport/` with `common`, `adding`, `labos`, `dispatcher`, and mode-specific entry points resolved during plan preparation.
- Why this approach: plan-time dispatch keeps hot loops free of policy branches and plugin callbacks.
- Recommendation rationale: dispatch policy must stabilize before transport features spread into adapters or retrieval code.
- Desired outcome: each prepared plan resolves its transport route once and exposes that decision through typed diagnostics and provenance.
- Non-destructive tests: `zig build test`; transport dispatch unit tests; parity smoke tests against selected upstream cases when available.
- Files by type: solver code in `src/kernels/transport/`; plan integration in `src/core/Plan.zig`; evidence in `validation/golden/` and `validation/perf/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No runtime string dispatch or inner-loop policy branching was introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Populated `src/kernels/transport/common.zig`, `adding.zig`, `labos.zig`, and `dispatcher.zig` with typed dispatch and lane execution; extended `src/model/Scene.zig` with canonical `ObservationRegime`; and updated `src/core/Engine.zig` plus `src/core/Plan.zig` so `preparePlan` resolves and stores a typed `transport_route` exactly once from observation regime, solver mode, and derivative mode. Provenance now reports both the dispatcher route string and the selected transport family via `src/core/provenance.zig`, with matching golden/schema/example updates in `validation/golden/result_provenance_golden.json`, `schemas/result.schema.json`, and `data/examples/export_result_netcdf.json`.
  - Why this works: transport policy is now a preparation-time decision. The dispatcher chooses the concrete lane once, `Plan` owns that typed route, and execution/provenance consume prepared state instead of recomputing or string-dispatching transport policy inside hot paths.
  - Proof / validation:
    - `zig test src/root.zig` -> passed (25/25 tests), including `kernels.transport.*` tests and `core.Engine` plan-time route coverage.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig test src/root.zig` and confirm the `kernels.transport.common`, `kernels.transport.dispatcher`, `kernels.transport.adding`, and `kernels.transport.labos` tests pass.
    - Run `zig build test` and `zig build` to verify the prepared transport route composes through the full repo build.

### WP-02 Add Explicit Derivative-Mode Contracts [Status: Done 2026-03-14]

- Issue: derivatives are part of the core forward-operator contract, not optional glue.
- Needs: typed derivative modes for none, semi-analytical, plugin-provided analytical, and numerical fallback.
- How: define derivative mode surfaces in the forward operator and retrieval common code, then route transport kernels through those explicit modes.
- Why this approach: explicit contracts prevent silent feature regressions and make Jacobian costs visible in the plan.
- Recommendation rationale: derivative handling must be visible at the API and plan layer before solver implementations are considered complete.
- Desired outcome: any request states its derivative expectations directly and receives matching diagnostics/provenance.
- Non-destructive tests: `zig build test`; derivative contract tests; targeted solver-path comparisons where applicable.
- Files by type: derivative surfaces in `src/kernels/transport/` and `src/retrieval/common/`; request/result implications in `src/core/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No hidden derivative side paths or implicit numerical fallback were introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Unified transport derivative routing onto the canonical `Scene.DerivativeMode` in `src/kernels/transport/common.zig`; kept explicit request-side expectations in `src/core/Request.zig`; added plan-time rejection of unsupported derivative-mode/transport combinations in `src/core/Engine.zig` and `src/core/errors.zig`; preserved method-specific derivative requirements in `src/retrieval/common/contracts.zig`; and exposed the selected derivative mode in result provenance through `src/core/provenance.zig` plus the golden/schema/example result fixtures.
  - Why this works: derivative handling is now explicit at the request, plan, transport, retrieval, and provenance layers. Requests declare derivative expectations, plan preparation validates the forward-operator route against them, retrieval-common enforces per-method Jacobian policy, and result provenance records the actual derivative mode instead of leaving it implicit.
  - Proof / validation:
    - `zig build test-unit` -> passed.
    - `zig build test-integration` -> passed.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig build test-unit` to exercise retrieval/common derivative-policy checks.
    - Run `zig build test-integration` to verify method-specific solver behavior over shared derivative contracts.
    - Run `zig build test` and `zig build` to confirm derivative-mode provenance and validation compose through the full build.

### WP-03 Layer OE, DOAS, and DISMAS on Shared Models [Status: Done 2026-03-14]

- Issue: retrieval methods belong on top of the canonical scene model, not in separate duplicated trees.
- Needs: shared retrieval-common building blocks plus solver-specific policy in `oe`, `doas`, and `dismas`.
- How: populate `src/retrieval/common/` first, then wire `src/retrieval/oe/`, `src/retrieval/doas/`, and `src/retrieval/dismas/` to those shared contracts.
- Why this approach: shared model and common retrieval utilities prevent each solver family from recreating incompatible state models.
- Recommendation rationale: common retrieval plumbing is the leverage point for both parity work and future plugin-based retrieval extensions.
- Desired outcome: each retrieval family differs by algorithm and policy, not by owning a separate scene definition.
- Non-destructive tests: `zig build test`; retrieval unit tests; integration or parity checks against selected upstream scenarios.
- Files by type: shared contracts in `src/retrieval/common/`; solver policy in `src/retrieval/*`; evidence in `tests/integration/` and `validation/compatibility/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No retrieval-specific duplicate scene tree was introduced.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (YYYY-MM-DD): 2026-03-14. Added shared retrieval contracts in `src/retrieval/common/contracts.zig`; layered `oe`, `doas`, and `dismas` solver policy in `src/retrieval/oe/solver.zig`, `src/retrieval/doas/solver.zig`, and `src/retrieval/dismas/solver.zig`; exported the retrieval package through `src/retrieval/root.zig`; wired retrieval tests into `tests/unit/main.zig`, `tests/integration/main.zig`, and `build.zig`; and expanded `validation/compatibility/parity_matrix.json` with retrieval parity cases.
  - Why this works: all three retrieval families now consume one shared `RetrievalProblem` built from the canonical request/scene/inverse-problem surface. Solver-specific differences stay in per-method policy while shared validation, layout sizing, and derivative requirements live in retrieval-common.
  - Proof / validation:
    - `zig test --dep zdisamar -Mroot=src/retrieval/root.zig -Mzdisamar=src/root.zig` -> passed (10/10 tests).
    - `zig build test-unit` -> passed.
    - `zig build test-integration` -> passed.
    - `zig build test` -> passed.
    - `zig build` -> passed.
  - How to test:
    - Run `zig test --dep zdisamar -Mroot=src/retrieval/root.zig -Mzdisamar=src/root.zig` for focused retrieval module coverage.
    - Run `zig build test-unit` and `zig build test-integration` to verify retrieval coverage in the standard suite graph.
    - Run `zig build test` and `zig build` for full verification.
