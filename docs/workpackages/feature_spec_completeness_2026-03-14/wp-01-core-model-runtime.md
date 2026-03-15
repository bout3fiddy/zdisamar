# Work Package Detail: Core, Model, and Runtime Completeness

## Metadata

- Package: `docs/workpackages/feature_spec_completeness_2026-03-14/`
- Scope: `src/core`, `src/model`, `src/runtime`, `src/api/zig`
- Input sources:
  - `docs/specs/architecture.md`
  - `docs/specs/fortran-mapping.md`
  - `docs/specs/original-plan.md`
- Constraints:
  - preserve one canonical scene model
  - keep `build.zig` and root files as composition boundaries
  - avoid new global mutable state

## Background

The current scaffold established the top-level runtime contract, but the internal structure still falls short of the spec. The model remains concentrated in `Scene.zig`, several spec-called core files do not exist, and the runtime tree lacks the dataset and scheduling types described in the original plan.

## Overarching Goals

- Align the core/model/runtime tree with the spec-defined module boundaries.
- Keep ownership and allocator flow explicit under Zig production style.
- Remove placeholder concentration points that will otherwise turn into god files.

## Non-goals

- Implementing full transport physics in this document.
- Filling mission-specific adapters.
- Adding compatibility wrappers over the existing monolithic files.

### WP-01 Split the Canonical Domain Model into Spec-Aligned Modules [Status: Done 2026-03-15]

- Issue: the original plan calls for distinct `Atmosphere`, `Geometry`, `Spectrum`, `Surface`, `Cloud`, `Aerosol`, `Instrument`, `Measurement`, `StateVector`, and `InverseProblem` modules, but the current scaffold still concentrates most of this surface in `src/model/Scene.zig` and leaves the observation-model and forward-operator boundary implicit instead of explicit.
- Needs: file-level decomposition that preserves one canonical scene model while making ownership, validation, and testing local to each domain type, and a clear typed seam between scene state, measurement/instrument modeling, and inverse-problem setup.
- How: split `src/model/Scene.zig` into typed submodules, leave `Scene.zig` as a composition boundary, define explicit observation-facing composition around `Instrument` and `Measurement`, and move layout-facing views or helpers into focused files rather than widening a single monolith.
- Why this approach: the current “one file owns almost everything” structure will become unmaintainable as real transport, instrument, and retrieval logic arrives.
- Recommendation rationale: completed by pushing the domain split behind `Scene.zig` as a composition boundary so the rest of the tree could keep importing `model/Scene.zig` while the underlying types moved into dedicated modules.
- Desired outcome: `src/model/` mirrors the spec-defined domain decomposition, the scene/measurement/inverse layers are explicit, and each type owns its own invariants.
- Non-destructive tests:
  - `zig build test`
  - targeted `zig test` runs for each extracted model module
  - compile checks for `src/root.zig` and `src/api/zig/root.zig`
- Files by type:
  - model files: `src/model/*.zig`
  - composition exports: `src/root.zig`, `src/api/zig/root.zig`
  - tests: colocated module tests plus `tests/unit/`
- Implementation status (2026-03-15): split the monolithic model surface into `Atmosphere.zig`, `Geometry.zig`, `Spectrum.zig`, `Surface.zig`, `Cloud.zig`, `Aerosol.zig`, `Instrument.zig`, `ObservationModel.zig`, `StateVector.zig`, `Measurement.zig`, `InverseProblem.zig`, and `LayoutRequirements.zig`; rewrote `Scene.zig` to compose and re-export those types; expanded library exports in `src/root.zig` and `src/api/zig/root.zig`.
- Why this works: the canonical scene remains singular, but ownership and validation now live with the domain type that owns the invariant instead of accumulating in one file.
- Proof / validation: `zig build test` passed on 2026-03-15 after the model split and mission/export/runtime integrations were merged.
- How to test: run `zig build test`; inspect `src/model/Scene.zig` to confirm it is now a composition/re-export file and verify the dedicated domain files exist under `src/model/`.

### WP-02 Add Missing Core Diagnostics, Units, and Wrapper Surfaces [Status: Done 2026-03-15]

- Issue: the directory layout in the original plan explicitly names `logging.zig`, `diagnostics.zig`, `units.zig`, and Zig-side wrappers, but the current core surface still folds those concerns into ad hoc structs or omits them entirely.
- Needs: typed units, reusable diagnostics materialization, explicit diagnostics-spec handling, structured logging boundaries, and Zig wrappers that sit above the stable C ABI without reintroducing string-keyed behavior.
- How: add focused files under `src/core/` and `src/api/zig/`, keep root files as composition only, and move diagnostics/provenance formatting out of request/result scaffolding into explicit helper modules that can support a future `DiagnosticsSpec`-style contract.
- Why this approach: diagnostics, units, and wrappers are boundary code. Leaving them implicit will spread formatting and conversion logic across unrelated files.
- Recommendation rationale: completed by moving diagnostics and units into named core modules and by adding a Zig wrapper layer that projects typed helper views onto the C ABI descriptors instead of duplicating core behavior.
- Desired outcome: core logging/diagnostics/units policy lives in named modules and the Zig-facing API is a thin typed facade over the stable ABI.
- Non-destructive tests:
  - `zig build test`
  - API-specific unit tests under `tests/unit/`
  - ABI drift checks for wrapper surfaces
- Files by type:
  - core boundary files: `src/core/logging.zig`, `src/core/diagnostics.zig`, `src/core/units.zig`
  - Zig wrappers: `src/api/zig/wrappers.zig`, `src/api/zig/root.zig`
  - tests: `tests/unit/`, `tests/golden/`
- Implementation status (2026-03-15): added `src/core/logging.zig`, `src/core/diagnostics.zig`, and `src/core/units.zig`; moved `DiagnosticsSpec`/result diagnostics use sites onto the new module; added `src/api/zig/wrappers.zig` plus unit coverage for diagnostics flags and typed C-descriptor conversion; expanded library exports for logging, diagnostics, and units.
- Why this works: diagnostics and unit semantics now have one home in `src/core`, while the Zig API exposes typed helpers without reintroducing string-keyed mutation or a second implementation path.
- Proof / validation: `zig build test` passed on 2026-03-15 with the new wrapper unit test in `tests/unit/api_wrappers_test.zig`.
- How to test: run `zig build test` and verify `tests/unit/api_wrappers_test.zig` plus the inline tests in `src/core/diagnostics.zig`, `src/core/logging.zig`, and `src/core/units.zig`.

### WP-03 Implement the Missing Runtime Cache and Scheduler Types [Status: Done 2026-03-15]

- Issue: the original plan calls for `DatasetCache`, `LUTCache`, `PlanCache`, `BatchRunner`, and `ThreadContext`, but the current runtime tree only contains prepared-plan cache hints and a scratch arena.
- Needs: explicit long-lived caches for scientific data, reusable plan cache state, and scheduler/runtime types for batch execution and per-thread contexts.
- How: add the missing runtime/cache and runtime/scheduler modules with explicit ownership and `init`/`deinit` protocols, then wire them through `Engine` without introducing hidden globals.
- Why this approach: prepared-plan reuse is only half the runtime architecture. Without dataset/LUT caches and scheduler context, every future feature will improvise its own cache and execution model.
- Recommendation rationale: completed by adding explicit runtime ownership types and then wiring them into `Engine` so caches and batch execution live behind explicit lifecycle methods instead of ad hoc helpers.
- Desired outcome: runtime/cache and runtime/scheduler match the spec-defined shape and own the right lifetimes explicitly.
- Non-destructive tests:
  - `zig build test`
  - cache invalidation and reuse tests
  - batch execution smoke tests under `tests/perf/`
- Files by type:
  - runtime/cache: `src/runtime/cache/*.zig`
  - runtime/scheduler: `src/runtime/scheduler/*.zig`
  - integration points: `src/core/Engine.zig`, `src/core/Plan.zig`, `src/core/Workspace.zig`
- Implementation status (2026-03-15): added `DatasetCache.zig`, `LUTCache.zig`, `PlanCache.zig`, `ThreadContext.zig`, `BatchRunner.zig`, `src/runtime/root.zig`, and runtime package roots; integrated dataset/LUT/plan caches plus batch-runner and thread-context creation into `src/core/Engine.zig`; exported runtime types through `src/root.zig` and `src/api/zig/root.zig`; added unit coverage in `tests/unit/runtime_cache_scheduler_test.zig`.
- Why this works: long-lived dataset/LUT/plan state is now explicit and reusable, and batch execution runs through typed engine-owned runtime state instead of hidden process state.
- Proof / validation: `zig build test` passed on 2026-03-15 after runtime cache and scheduler integration; the runtime worker also validated `zig build test-unit` and `zig test src/root.zig` during implementation.
- How to test: run `zig build test`; inspect `tests/unit/runtime_cache_scheduler_test.zig`; verify `Engine.registerDatasetArtifact`, `Engine.registerLUTArtifact`, `Engine.createThreadContext`, and `Engine.runBatch` are present in `src/core/Engine.zig`.
