# Work Package: Spec Completeness Against Architecture and Fortran Mapping

## Canonical References

- [Architecture spec](../../specs/architecture.md)
- [Fortran mapping spec](../../specs/fortran-mapping.md)
- [Root AGENTS router](../../../AGENTS.md)
- [Original migration plan](../../specs/original-plan.md)

## Execution Directive (Standard)

```text
REQUIRED
- Work package directory: docs/workpackages/feature_spec_completeness_2026-03-14/
- Read overview.md first, then continue from the first non-done WP item across the folder.
- Do not leave any <...> placeholder unresolved.

EXECUTION RULES
- Keep changes non-destructive.
- Repository mode: library-first Zig project; no browser app is expected.
- Primary verification: zig build test, zig build, and targeted parity/asset checks relevant to each item.
- Use Playwright/browser tooling only if a future item introduces an actual runtime UI surface.
- Default to hard cutovers; do not add fallback branches or compatibility shims unless explicitly approved with owner, removal date, and tracking issue.

WHEN YOU COMPLETE A WP ITEM
- Update the detailed WP section with:
  - updated Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- Mark the WP title status line as [Status: Done YYYY-MM-DD].
- Update this overview rollup row in the same change with status, last-updated date, proof pointer, and next action.

CHECKPOINTS
- Commit and push periodically as coherent checkpoints.

FINISHING
- When all WP items are done, run the PR review remediation loop until all required checks pass and no new actionable review comments remain.
- Create a staging release.
- Only after staging release, update the linked Linear issue for this package with shipped outcomes and move it to In Review.

REPEATS
- This command may be repeated.
- If staging release already exists for this work package, treat repeats as reminder signals and continue only unfinished steps.
```

## Metadata

- Created: 2026-03-14
- Scope: everything still missing relative to the tracked architecture scaffold, tracked Fortran mapping, and local original migration plan
- Input sources:
  - `docs/specs/architecture.md`
  - `docs/specs/fortran-mapping.md`
  - `docs/specs/original-plan.md`
  - `vendor/disamar-fortran/src/`
- Constraints:
  - keep the public surface typed around `Engine -> Plan -> Workspace -> Request -> Result`
  - no file I/O or text parsing in `src/core` or `src/kernels`
  - no new global mutable state
  - native plugin contracts stay behind the C ABI
  - work packages must describe hard cutovers rather than compatibility shims

## Background

The current migration work packages closed the first scaffold pass, but they did not complete the full surface described in the architecture notes or the original migration plan. The current tree still contains major placeholder areas: mission adapters are empty, builtin plugin families beyond exporters are empty, data bundles are mostly absent, transport and retrieval implementations are still scaffold-depth, and the native plugin path stops at manifests plus ABI declarations rather than real resolution and execution. The canonical scene is still too concentrated, the observation/forward-operator boundary is still implicit instead of explicit, and diagnostics/units/runtime cache support remain incomplete.

This package captures the remaining spec-defined backlog in one place so execution can proceed from the architecture contract instead of from ad hoc observations.

## Overarching Goals

- Close the gap between the current scaffold and the intended directory layout in `docs/specs/original-plan.md`.
- Convert placeholder subsystems into real runtime, kernel, plugin, adapter, and validation implementations.
- Make parity work against the local DISAMAR reference explicit instead of implicit.
- Separate “migration scaffolding is in place” from “feature-complete against the spec.”

## Non-goals

- Reverting the current Zig scaffold back toward the legacy Fortran application shape.
- Preserving ASCII-HDF or file-driven execution as a core runtime pattern.
- Defining release dates or ownership for external collaborators in this document.

## Folder Contents

- `overview.md` — canonical status rollup and execution entry point.
- `wp-01-core-model-runtime.md` — missing core/model/runtime structure.
- `wp-02-kernels-physics.md` — missing physics, numerical kernels, and retrieval math depth.
- `wp-03-plugins-sdk.md` — missing plugin runtime, builtin plugin families, and hot-swap semantics.
- `wp-04-adapters-data-io.md` — missing adapters, data bundles, and concrete exporters.
- `wp-05-validation-parity-api.md` — missing parity harness, validation depth, and API hardening.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done | 2026-03-15 | `zig build test` after model split and root export update | Closed; monitor for downstream import regressions |
| WP-02 | Done | 2026-03-15 | `zig build test` with diagnostics/units/wrapper coverage | Closed; use new core boundary modules for future API work |
| WP-03 | Done | 2026-03-15 | `zig build test` with runtime cache/scheduler and engine integration | Closed; extend runtime state for parity/data ingestion work |
| WP-04 | Done | 2026-03-15 | `zig build test` after quadrature/doubling/derivative transport integration | Closed; deepen physical fidelity in future parity iterations |
| WP-05 | Done | 2026-03-15 | `zig build test` after interpolation/spectra/polarization module expansion | Closed; consume these kernels from exporters and mission flows |
| WP-06 | Done | 2026-03-15 | `zig build test` after retrieval/common and linalg rewrites | Closed; use parity harnesses to tune solver behavior next |
| WP-07 | Done | 2026-03-15 | `zig build test` after loader/runtime resolution, ABI validation, and plan-time plugin freeze | Closed; use `Plan.deinit()` and runtime resolution hooks for future shared-library plugins |
| WP-08 | Done | 2026-03-15 | `zig build test` after builtin transport/retrieval/surface/instrument families and package metadata updates | Closed; deepen builtin data/model payloads without changing package topology |
| WP-09 | Done | 2026-03-15 | `zig build test` after plan-boundary runtime resolution plus provenance/schema/golden updates | Closed; keep future plugin additions on plan-boundary invalidation semantics |
| WP-10 | Done | 2026-03-15 | `zig build test` with split legacy-config importer/schema mapper | Closed; add broader legacy fixture coverage when new cases arrive |
| WP-11 | Done | 2026-03-15 | `zig build test` with S5P integration coverage | Closed; extend mission family coverage beyond the first S5P path |
| WP-12 | Done | 2026-03-15 | `zig build test` plus `zig test src/exporters_wp12_test_entry.zig` after concrete writer backends landed | Closed; deepen payload richness later without reintroducing metadata-only exporters |
| WP-13 | Done | 2026-03-15 | `zig build test` with bundle-manifest digest checks and vendor import registry coverage | Closed; replace baseline fixtures with richer imported science bundles when available |
| WP-14 | Done | 2026-03-15 | `zig build test` with executable compatibility/perf harnesses and vendor anchors | Closed; tighten tolerances only when scientific-output parity work starts |
| WP-15 | Done | 2026-03-15 | `zig build test`, `zig build`, and CLI smoke through the C/Zig typed boundary work | Closed; maintain ABI/layout tests as the public surface grows |
