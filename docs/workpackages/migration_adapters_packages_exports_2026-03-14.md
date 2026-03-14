# Work Package: Adapters, Packages, and Exports

## Execution Directive (Standard)

```text
REQUIRED
- Replace every <VARIABLE> placeholder before running this directive.
- Do not leave any <...> token unresolved.

TARGET
- Work package file: docs/workpackages/migration_adapters_packages_exports_2026-03-14.md

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
- Scope: `src/adapters`, `packages`, `plugins/examples`, `schemas`, `data`
- Input sources: `docs/specs/original-plan.md`, `docs/specs/architecture.md`, `docs/specs/fortran-mapping.md`
- Constraints: keep the core in-memory first; move legacy config parsing and mission wiring into adapters; ship official exporters as adapters/plugins rather than kernel behavior

## Background

The original plan explicitly moves config parsing, CLI behavior, mission packaging, and exporters out of the core runtime. This folder breaks that into execution slices that match the existing scaffold.

## Overarching Goals

- Build adapters over the typed public API rather than a second execution path.
- Align package, schema, and example assets with the standard DISAMAR model-family framing.
- Make NetCDF/CF and Zarr the official export direction.

## Non-goals

- Reintroducing file-driven control flow into `src/core` or `src/kernels`.
- Treating DISAMAR as the whole engine instead of one bundled model family.
- Shipping mission-specific logic inside the core runtime tree.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done 2026-03-14 | 2026-03-14 | WP-01 Proof / validation | Run finishing steps (PR remediation + staging release) |
| WP-02 | Done 2026-03-14 | 2026-03-14 | WP-02 Proof / validation | Run finishing steps (PR remediation + staging release) |
| WP-03 | Done 2026-03-14 | 2026-03-14 | WP-03 Proof / validation | Run finishing steps (PR remediation + staging release) |

## Work Package Items

### WP-01 Build CLI and Legacy Config Adapters [Status: Done 2026-03-14]

- Issue: the architecture requires `Config.in` parsing and command-line execution to become thin adapters over the same library API.
- Needs: adapter-only parsing, schema mapping, and orchestration that does not leak into the runtime core.
- How: populate `src/adapters/cli/` and `src/adapters/legacy_config/` around the typed request/plan/result surface, then keep legacy parsing code out of `src/core` and `src/kernels`.
- Why this approach: adapter boundaries preserve embeddability and stop file-driven orchestration from becoming the default runtime model again.
- Recommendation rationale: adapter cutovers unlock migration of legacy workflows without compromising core architecture.
- Desired outcome: CLI and legacy config import both call the same typed runtime API.
- Non-destructive tests: `zig build test`; adapter integration tests; legacy-config translation smoke tests with fixture inputs.
- Files by type: implementation in `src/adapters/cli/` and `src/adapters/legacy_config/`; request/result implications in `src/core/`; fixtures in `data/examples/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No file parsing or orchestration leaked into `src/core` or `src/kernels`.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added a real adapter layer in `src/adapters/cli/App.zig` and `src/adapters/legacy_config/Adapter.zig`, rewired `src/adapters/cli/main.zig` to run through that adapter flow, and added `data/examples/legacy_config.in` as a fixture-backed legacy-import smoke input. The CLI now reads either direct flags or a legacy config file, translates those inputs into `PlanTemplate`, `Scene`, and `Request`, and executes through the typed `Engine -> Plan -> Workspace -> Request -> Result` API.
  - Why this works: Parsing, file access, and command-line concerns stay confined to `src/adapters`, while the adapter output is a typed `PreparedRun` that materializes only plan, scene, diagnostics, and requested products before execution. That keeps legacy orchestration out of `src/core` and lets both CLI and `Config.in`-style import call the exact same runtime surface.
  - Proof / validation: `zig build`; `zig build test`; `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` -> `zdisamar adapter run: workspace=import-smoke scene=s5p-no2 model=disamar_standard plan_id=1 status=success route=transport.dispatcher`.
  - How to test: 1. Run `zig build`. 2. Run `zig build test`. 3. Run `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`. 4. Confirm the command succeeds and reports the typed adapter execution path with `workspace=import-smoke`, `scene=s5p-no2`, and `route=transport.dispatcher`.

### WP-02 Establish Official Exporters and Export Packaging [Status: Done 2026-03-14]

- Issue: the plan retires the ASCII-HDF to Python conversion path in favor of first-class NetCDF/CF and Zarr exporters.
- Needs: exporter boundaries, plugin or adapter packaging, and migration of legacy output behavior away from kernels.
- How: implement exporter ownership in `src/adapters/exporters/` and `src/plugins/builtin/exporters/`, then keep output metadata in plugins/packages instead of core structs.
- Why this approach: exporter isolation keeps scientific output policy separate from forward and retrieval kernels.
- Recommendation rationale: export format change is both a user-facing feature and an architectural cleanup.
- Desired outcome: official export paths are versioned, testable, and disconnected from kernel control flow.
- Non-destructive tests: `zig build test`; exporter integration tests; schema and fixture validation for NetCDF/CF and Zarr outputs.
- Files by type: exporters in `src/adapters/exporters/` and `src/plugins/builtin/exporters/`; package docs in `packages/builtin_exporters/`; schemas in `schemas/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] No exporter file creation path was introduced into `src/core` or `src/kernels`.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Added explicit exporter adapter contracts in `src/adapters/exporters/format.zig` and `src/adapters/exporters/spec.zig`, plus builtin exporter catalog and manifests in `src/plugins/builtin/exporters/catalog.zig`, `src/plugins/builtin/exporters/netcdf_cf.plugin.json`, and `src/plugins/builtin/exporters/zarr.plugin.json`. Updated exporter package metadata in `packages/builtin_exporters/package.json` so official NetCDF/CF and Zarr manifests are first-class assets.
  - Why this works: Exporter routing metadata now lives entirely in adapter/plugin/package lanes, with stable format/media/plugin mapping and manifested builtin exporters, so export behavior is versioned and testable without introducing file-format policy into `src/core` or `src/kernels`.
  - Proof / validation: `zig test src/adapters/exporters/format.zig` (pass); `zig test src/adapters/exporters/spec.zig` (pass); `zig test src/plugins/builtin/exporters/catalog.zig` (pass); `jq empty` over package/schema/plugin/data JSON files (pass); `zig build test` (pass).
  - How to test: 1. Run `zig test src/adapters/exporters/format.zig`. 2. Run `zig test src/adapters/exporters/spec.zig`. 3. Run `zig test src/plugins/builtin/exporters/catalog.zig`. 4. Run `jq empty` on `src/plugins/builtin/exporters/*.plugin.json` and `packages/builtin_exporters/package.json`. 5. Run `zig build test` for repo-wide status.

### WP-03 Align Packages, Schemas, Examples, and Data Assets [Status: Done 2026-03-14]

- Issue: the top-level package layout in the plan treats DISAMAR as one model pack and keeps examples/data/plugin assets coherent with that framing.
- Needs: package metadata, example assets, and schema ownership that match `disamar_standard`, mission packages, and builtin exporters.
- How: update `packages/`, `plugins/examples/`, `schemas/`, and `data/` so assets are traceable to one package or plugin lane and not hidden in core defaults.
- Why this approach: package clarity reduces future migration ambiguity and makes plugin/adaptor work easier to distribute.
- Recommendation rationale: supporting assets should reflect the same architectural cutovers as code directories.
- Desired outcome: packages and examples clearly advertise which model family, mission, exporter, or plugin lane they belong to.
- Non-destructive tests: `zig build test`; schema validation; fixture loading tests for data packs and example packages.
- Files by type: package metadata in `packages/`; example assets in `plugins/examples/`; schemas in `schemas/`; sample data in `data/`.
- Completion checklist:
  - [x] `workflows` skill invoked for this execution.
  - [x] `coding` skill invoked for this execution.
  - [x] Relevant `AGENTS.md` files were re-read before edits.
  - [x] DISAMAR remained one bundled model family rather than the whole engine shape.
  - [x] Validation commands were run and captured below.
  - [x] The rollup row in this work-package file was updated in the same change.
- Completion record (fill before marking done):
  - Implementation status (2026-03-14): Updated package metadata in `packages/disamar_standard/package.json`, `packages/mission_s5p/package.json`, and `packages/builtin_exporters/package.json` to align model-family and exporter ownership; added exporter example and builtin plugin manifests under `plugins/examples/native_exporter/plugin.json` and `src/plugins/builtin/exporters/*.plugin.json`; extended request/result schemas with explicit export intent/artifact fields in `schemas/request.schema.json` and `schemas/result.schema.json`; added fixture assets in `data/examples/export_request_netcdf.json`, `data/examples/export_request_zarr.json`, and `data/examples/export_result_netcdf.json`.
  - Why this works: Packages, schemas, and examples now consistently identify exporter lanes and official formats while keeping DISAMAR scoped to the `disamar_standard` model family package. The new fixtures provide traceable inputs/outputs for exporter-aware adapter flows.
  - Proof / validation: `jq empty` for updated package/schema/plugin/data JSON files (pass); focused exporter Zig tests (pass); `zig build test` (pass).
  - How to test: 1. Run `jq empty` on `packages/*.json`, `schemas/request.schema.json`, `schemas/result.schema.json`, `plugins/examples/native_exporter/plugin.json`, and `data/examples/export_*.json`. 2. Run the focused exporter tests listed under WP-02. 3. Run `zig build test` to confirm repo-wide status.
