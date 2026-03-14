# Work Package: Validation, Parity, and Release Evidence

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_validation_parity_2026-03-14.md

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
- Scope: `tests`, `validation`, `src/core/provenance.zig`, `packages`, `vendor/disamar-fortran` comparisons
- Input sources: `docs/specs/original-plan.md`, `docs/specs/fortran-mapping.md`, `.agents/repo-context/index.md`
- Constraints: use `zig build test` as the verification baseline; treat vendor Fortran as read-only comparison material; capture parity and provenance evidence without rebuilding legacy architecture

## Background

The original plan explicitly calls out the lack of real tests, the need for parity evidence, and the requirement that every result carry provenance. This package covers the validation system that proves the migration is not just structurally clean but scientifically defensible.

## Overarching Goals

- Replace sample-output style testing with real verification suites.
- Define parity evidence against the upstream Fortran reference where it matters.
- Make provenance and completion evidence part of the release gate.

## Non-goals

- Building new features that have no validation story.
- Treating the vendored reference as the target runtime architecture.
- Marking migration work complete without captured proof.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | `tests/README.md`, `build.zig`, `zig build test-suites` | Run finishing steps (PR remediation + staging release) |
| WP-02 | Done 2026-03-14 | 2026-03-14 | `validation/compatibility/parity_matrix.json`, `tests/validation/parity_assets_test.zig`, `zig build test-validation` | Run finishing steps (PR remediation + staging release) |
| WP-03 | Done 2026-03-14 | 2026-03-14 | `validation/release/release_readiness.json`, `tests/golden/provenance_golden_test.zig`, `zig build test` | Run finishing steps (PR remediation + staging release) |

## Work Package Items

### WP-01 Build First-Class Verification Suites [Status: Done 2026-03-14]

- Issue: the original plan rejects a repo where “tests” are mostly sample outputs instead of executable validation suites.
- Needs: clear unit, integration, golden, perf, and plugin-test ownership across `tests/` and `validation/`.
- How: define suite boundaries, fixture sources, and baseline commands so every migration slice has a home for evidence.
- Why this approach: stable test taxonomy makes it obvious where new assertions belong and prevents ad hoc validation drift.
- Recommendation rationale: executable suite ownership and build entry points were added first so future migration slices land with enforceable test destinations and command-level evidence.
- Desired outcome: each subsystem lands with executable tests and matching validation evidence directories.
- Non-destructive tests: `zig build test`; targeted suite commands as they are added; fixture integrity checks.
- Files by type: executable tests in `tests/`; evidence and parity assets in `validation/`; supporting fixtures in `data/examples/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] New tests landed in the correct suite rather than as ad hoc samples.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added executable suite roots and suite-specific tests under `tests/unit`, `tests/integration`, `tests/golden`, `tests/perf`, and `tests/validation`; added suite ownership docs in `tests/README.md`; updated `build.zig` with dedicated `test-unit`, `test-integration`, `test-golden`, `test-perf`, `test-validation`, and aggregate `test-suites` steps while preserving CLI `legacy_config` module import wiring.
  - Why this works: the repository now has explicit, runnable suite boundaries with concrete assertions and first-class build targets instead of placeholder directories and sample-only artifacts.
  - Proof / validation:
    - `zig build test-unit` (pass)
    - `zig build test-integration` (pass)
    - `zig build test-golden` (pass)
    - `zig build test-perf` (pass)
    - `zig build test-validation` (pass)
    - `zig build test-suites` (pass)
    - `zig build test` (pass)
  - How to test:
    - Run `zig build test` for baseline verification.
    - Run `zig build test-suites` for all suite-owned checks.
    - Run any targeted suite command (`test-unit`, `test-integration`, `test-golden`, `test-perf`, `test-validation`) to verify ownership and isolation.

### WP-02 Define Fortran Parity Harness and Evidence Capture [Status: Done 2026-03-14]

- Issue: the vendored Fortran tree is useful only as comparison input, but parity still needs a repeatable evidence story.
- Needs: bounded parity targets, selected upstream cases, and documentation of acceptable differences where architecture changed.
- How: build compatibility fixtures and parity checks under `validation/compatibility/` and `validation/golden/` without copying the Fortran runtime model.
- Why this approach: parity is credible only when it is reproducible, selective, and explicit about what is compared.
- Recommendation rationale: a structured parity matrix plus executable validation-asset checks establishes reproducible evidence contracts before wiring full numerical comparators.
- Desired outcome: the team can point to named upstream comparisons for each major subsystem without coupling to legacy globals or file workflows.
- Non-destructive tests: `zig build test`; parity comparison scripts or checks; documented upstream fixture provenance.
- Files by type: parity assets in `validation/compatibility/` and `validation/golden/`; references in `vendor/disamar-fortran/`; local mapping notes in `docs/specs/fortran-mapping.md`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No new feature was justified solely by copying legacy global-state behavior.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added bounded parity targets and tolerances in `validation/compatibility/parity_matrix.json`; added golden provenance fixture in `validation/golden/result_provenance_golden.json`; added perf and plugin validation matrices in `validation/perf/perf_matrix.json` and `validation/plugin_tests/plugin_validation_matrix.json`; added executable asset checks in `tests/validation/parity_assets_test.zig` and validation ownership docs in `validation/README.md`.
  - Why this works: parity evidence is now explicit, versioned, and machine-checked, with named upstream comparison placeholders and guardrails for tolerances, lane coverage, and fixture completeness.
  - Proof / validation:
    - `zig build test-validation` (pass)
    - `zig build test-golden` (pass)
    - `zig build test-suites` (pass)
    - `zig build test` (pass)
  - How to test:
    - Run `zig build test-validation` to verify matrix and fixture integrity.
    - Run `zig build test-golden` to verify provenance golden defaults.
    - Inspect `validation/compatibility/parity_matrix.json` for parity-case IDs, metrics, and tolerances used by the validation tests.

### WP-03 Add Provenance and Release-Readiness Gates [Status: Done 2026-03-14]

- Issue: the original plan requires results to carry provenance, and the workflow requires concrete proof before a work package is considered done.
- Needs: provenance capture, evidence pointers, and release-readiness checks that connect implementation to validation and package versions.
- How: populate provenance surfaces in `src/core/provenance.zig` and require validation artifacts plus package/plugin version evidence before release transitions.
- Why this approach: provenance makes later debugging, parity review, and collaboration defensible.
- Recommendation rationale: result provenance is a platform capability, not optional reporting.
- Desired outcome: every significant result can report plugin versions, dataset hashes, solver route, and numerical mode, and release gates require that evidence.
- Non-destructive tests: `zig build test`; provenance serialization or rendering tests; release checklist dry runs.
- Files by type: provenance code in `src/core/`; package metadata in `packages/`; release evidence in `validation/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] Proof, provenance, and release evidence were captured together.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Extended `src/core/provenance.zig` so results carry plugin inventory generation plus frozen plugin-version and dataset-hash evidence from the prepared plan; updated `validation/golden/result_provenance_golden.json` and `tests/golden/provenance_golden_test.zig` to enforce those provenance defaults; added `validation/release/release_readiness.json` as a release gate tying commands, package versions, plugin versions, and required evidence artifacts together; and extended `tests/validation/parity_assets_test.zig` and `validation/README.md` to validate and document the release-readiness asset.
  - Why this works: Provenance is now part of the executable contract instead of an informal note: golden tests verify the result contains plugin/version/hash evidence, and the release-readiness matrix gives the repo one machine-checked place to declare which commands, package versions, plugin versions, and evidence artifacts must exist before release transitions.
  - Proof / validation: `zig build test-golden` (pass); `zig build test-validation` (pass); `zig build test` (pass); `zig build` (pass).
  - How to test: 1. Run `zig build test-golden` to verify the provenance golden fixture. 2. Run `zig build test-validation` to verify the release-readiness matrix and asset references. 3. Run `zig build test` and `zig build` to confirm the repo-wide gate remains green.
