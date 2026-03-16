# Work Package: Plugins and C ABI

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_plugins_abi_2026-03-14.md

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

- `$workflows`
- `$coding`

## Metadata

- Created: 2026-03-14
- Scope: `src/plugins`, `src/api/c`, `plugins/examples`, `packages`, `schemas`
- Input sources: `docs/specs/original-plan.md`, `docs/specs/architecture.md`
- Constraints: keep native plugins behind the C ABI; distinguish declarative/data plugins from trusted native capability plugins; do not allow plugin callbacks in innermost transport loops

## Background

The original plan treats the plugin system as the main extensibility boundary and explicitly rejects vague “memory-safe native plugin” claims. This package turns that into discrete execution items.

## Overarching Goals

- Establish the two-lane plugin model.
- Stabilize the host/plugin C ABI and capability registry.
- Keep plugin resolution at plan preparation time rather than execution hot loops.

## Non-goals

- Implementing every builtin plugin immediately.
- Designing language-specific bindings beyond the stable C ABI.
- Allowing arbitrary graph surgery as an extension mechanism.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | `zig test src/root.zig`; `jq empty schemas/plugin.schema.json plugins/examples/data_pack/plugin.json plugins/examples/native_surface/plugin.json plugins/examples/native_retrieval/plugin.json` | Run finishing steps (PR remediation + staging release) |
| WP-02 | Done 2026-03-14 | 2026-03-14 | `zig test src/root.zig`; `zig build test` | Run finishing steps (PR remediation + staging release) |
| WP-03 | Done 2026-03-14 | 2026-03-14 | `zig test src/root.zig`; `zig build test-unit`; `zig build test` | Run finishing steps (PR remediation + staging release) |

## Work Package Items

### WP-01 Define Declarative and Native Plugin Lanes [Status: Done 2026-03-14]

- Issue: the architecture depends on a default declarative/data plugin path plus a smaller trusted native capability path.
- Needs: package structure, schema expectations, and examples that make the two plugin lanes unmistakable.
- How: define lane-specific rules across `src/plugins/loader/`, `packages/`, `plugins/examples/`, and `schemas/plugin.schema.json`.
- Why this approach: collaborators need a safe default extension route before native capability plugins are introduced.
- Recommendation rationale: lane separation is foundational because it shapes package layout, documentation, and security posture, so this cutover enforced lane-specific manifest contracts and examples in one pass.
- Desired outcome: data packs, schemas, and examples clearly distinguish declarative assets from native code plugins.
- Non-destructive tests: `zig build test`; schema validation tests; example-plugin loading smoke tests.
- Files by type: manifests and loader rules in `src/plugins/loader/`; schemas in `schemas/`; example packages in `plugins/examples/` and `packages/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] Declarative and native plugin lanes remained distinct in contracts and docs.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Updated `src/plugins/loader/manifest.zig` with lane-aware validation and native contract requirements, updated `src/plugins/registry/CapabilityRegistry.zig` to register manifests with explicit lane enforcement, expanded `schemas/plugin.schema.json` with lane-conditional native contract rules, added native plugin examples under `plugins/examples/native_surface/plugin.json` and `plugins/examples/native_retrieval/plugin.json`, and added lane policy metadata in package manifests (`packages/*/package.json`).
  - Why this works: declarative manifests now validate without native fields, while native manifests require explicit ABI + entry symbol metadata and opt-in at registration time, so the default path remains declarative/data and trusted native plugins are an explicit second lane.
  - Proof / validation: `zig test src/root.zig` (pass; includes plugin manifest and registry tests), `jq empty schemas/plugin.schema.json plugins/examples/data_pack/plugin.json plugins/examples/native_surface/plugin.json plugins/examples/native_retrieval/plugin.json packages/disamar_standard/package.json packages/builtin_exporters/package.json packages/mission_s5p/package.json` (pass).
  - How to test: run `zig test src/root.zig` and confirm the plugin tests `register manifest enforces native lane opt-in` and `bootstrap registers declarative and native lanes` pass; run `jq empty` against the schema + plugin/package JSON files to confirm valid JSON payloads.

### WP-02 Lock the Host/Plugin C ABI Contract [Status: Done 2026-03-14]

- Issue: native plugin contracts must stay behind `src/api/c` and `src/plugins/abi`, with only C-compatible POD views crossing the boundary.
- Needs: stable entry symbol expectations, capability tables, host service tables, and ABI version checks.
- How: define the ABI surfaces in `src/plugins/abi/plugin.h`, `src/api/c/disamar.h`, and matching Zig bridge types without passing Zig allocators or slices.
- Why this approach: a small ABI surface is easier to keep stable across languages and plugin versions.
- Recommendation rationale: ABI stability is the precondition for any external plugin ecosystem, so this pass locked symbol/version fields and POD host/plugin descriptors at the C boundary and mirrored them in Zig bridge types.
- Desired outcome: trusted native plugins can integrate through one versioned entry point and explicit capability tables.
- Non-destructive tests: `zig build test`; ABI shape tests; native-plugin loading smoke tests for example plugins.
- Files by type: C headers in `src/api/c/` and `src/plugins/abi/`; registry and bridge code in `src/plugins/registry/` and `src/api/c/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No Zig-owned allocator, slice, or hidden ownership crossed the ABI boundary.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Rewrote `src/plugins/abi/plugin.h` to include fixed ABI constants, entry symbol contract, host API/versioned struct metadata, and explicit plugin lane typing; rewrote `src/api/c/disamar.h` with versioned engine options and plugin policy fields; rewrote `src/api/c/bridge.zig` to mirror C ABI-facing enums/extern structs and added ABI-focused Zig tests.
  - Why this works: the host/plugin surface is now explicit and versioned at compile time in both C headers and Zig bridge declarations, with no Zig allocators, slices, or hidden ownership crossing ABI boundaries.
  - Proof / validation: `zig test src/root.zig` (pass; bridge and plugin contract tests pass), `zig build test` (pass).
  - How to test: run `zig test src/root.zig` to exercise the bridge and plugin contract tests; run `zig build test` to confirm the repo-wide suite still passes with the ABI and plugin-lane changes in place.

### WP-03 Enforce Plan-Boundary Hot-Swap Rules [Status: Done 2026-03-14]

- Issue: plugin hot-swap is allowed only at the plan boundary, and innermost kernels must stay free of plugin callbacks.
- Needs: resolver semantics, plan invalidation rules, and execution-time guarantees that resolved tables are fixed for the life of a plan.
- How: tie plugin resolution into plan preparation, record plugin provenance in results, and guard hot paths against dynamic callback re-entry.
- Why this approach: boundary-based hot-swap preserves extensibility without sacrificing performance predictability.
- Recommendation rationale: lifecycle semantics must be fixed before builtin and third-party plugins can be trusted.
- Desired outcome: existing plans keep their resolved function tables while future plans see updated plugin inventory.
- Non-destructive tests: `zig build test`; plugin reload and invalidation tests; perf smoke tests showing no inner-loop callback injection.
- Files by type: resolver code in `src/plugins/loader/` and `src/plugins/registry/`; plan integration in `src/core/Plan.zig`; provenance in `src/core/provenance.zig`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No plugin callback entered innermost transport loops.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added plan-boundary plugin snapshots by extending `src/plugins/registry/CapabilityRegistry.zig` with registry generations, frozen `PluginSnapshot` copies, version labels, and dataset-hash capture; wired `src/core/Plan.zig` to own the frozen snapshot; added `Engine.registerPluginManifest` plus snapshotting during `Engine.preparePlan`; and changed `src/core/provenance.zig` / `src/core/Result.zig` so execution results report the plan’s frozen plugin versions, dataset hashes, and inventory generation.
  - Why this works: Plugin resolution now happens only during plan preparation, producing a bounded copy of the registry state that lives on the `Plan`. Later registry mutations can affect new plans, but existing plans execute against their already-resolved snapshot and simply emit that snapshot into provenance, so no execution-time callback or inventory lookup is needed in hot paths.
  - Proof / validation: `zig test src/root.zig` (pass, including snapshot-generation and plan-freeze tests); `zig build test-unit` (pass); `zig build test` (pass).
  - How to test: 1. Run `zig test src/root.zig` and confirm the plugin snapshot tests pass. 2. Run `zig build test-unit` to exercise `tests/unit/plan_plugin_snapshot_test.zig`. 3. Run `zig build test` to confirm the full suite still passes with plan-boundary plugin freezing enabled.
