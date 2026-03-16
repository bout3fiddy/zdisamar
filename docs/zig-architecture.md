# Architecture and Execution Model

## Design Objective

`zdisamar` separates scientific state, numerical kernels, operational adapters, runtime preparation, and extension contracts so that each part of the DISAMAR model family can be inspected and validated without hidden mutation. The architecture is therefore not organized around file formats or mission scripts. It is organized around the life cycle of a scientific run.

## Top-Level Structure

The main repository layers are these.

- `src/core/`
  - engine life cycle, plan preparation, workspaces, typed requests and results, diagnostics, and provenance
- `src/model/`
  - canonical atmospheric, spectroscopic, surface, cloud, aerosol, and observation-domain types
- `src/kernels/`
  - numerical kernels for optics preparation, transport, interpolation, quadrature, and linear algebra
- `src/retrieval/`
  - inverse-method layers such as OE, DOAS, and DISMAS built on the shared scene and measurement-space contracts
- `src/runtime/`
  - execution support such as bundle-backed reference-data preparation and caches
- `src/adapters/`
  - mission wiring, measured-input parsing, exporter backends, and historical configuration import
- `src/plugins/`
  - manifests, capability registration, runtime resolution, and native ABI boundaries
- `src/api/`
  - stable C-facing host surface and Zig wrappers

That separation exists for scientific reasons as much as software reasons. Transport code is easier to test when it does not parse text. Retrieval code is easier to compare when it consumes one canonical observation-side product. Provenance is easier to trust when plan preparation and execution are explicit phases.

## Execution Life Cycle

The public execution contract is:

`Engine -> Plan -> Workspace -> Request -> Result`

Each step has a distinct role.

### Engine

`Engine` owns long-lived host state: catalogs, capability registries, allocator policy, and the plan-preparation entry point. It is the place where a model family and transport route are selected and where plan-time invariants are checked.

### Plan

`Plan` freezes everything that should not change mid-run:

- model family,
- transport route and solver mode,
- prepared caches,
- capability snapshot and plugin provenance.

This is the key boundary for reproducibility. A plan should answer the question "what scientific and runtime path has been selected?" before a scene is executed.

### Workspace

`Workspace` owns per-run mutable execution state. It is where scratch memory, request-local preparation, and temporary numerical state belong. That keeps repeated runs on the same engine from sharing mutable atmospheric or retrieval state accidentally.

### Request

`Request` carries the typed scientific problem:

- a `Scene`,
- optional retrieval or inversion intent,
- any operational observation-model replacements that belong to that scene only.

### Result

`Result` owns:

- provenance,
- diagnostics,
- measurement-space summaries,
- measurement-space arrays when materialized.

The result is therefore more than a status flag. It is the scientific artifact produced by execution.

## Canonical Scientific State

The current implementation uses one canonical scene model rather than separate forward-model and retrieval-model object trees.

That choice matters because atmospheric, spectroscopic, and instrument state should not change meaning as execution crosses from transport to inversion. A single `Scene` definition reduces field drift, keeps dimensions consistent, and makes it possible to share prepared optics and measurement-space products across retrieval methods.

In practical terms:

- geometry, surface, aerosol, cloud, and spectral sampling belong to the same scene;
- reference data is prepared against that scene once;
- transport and retrieval methods work from the same physical description.

## Reference Data and Operational Inputs

The architecture distinguishes two kinds of scientific input.

### Reference data

Reference data consists of slowly changing scientific assets such as climatologies, spectroscopy tables, collision-induced absorption, and optical-property tables. These are prepared by `src/runtime/reference/` from tracked bundle manifests and typed asset parsers.

### Operational replacements

Operational inputs are scene-specific overrides such as:

- measured channel grids,
- explicit slit-function tables,
- external solar spectra,
- O2 and O2-O2 coefficient cubes,
- mission-specific geometry or auxiliary fields.

These enter through adapters and are stored as typed observation-model state. They are not loaded implicitly inside transport or retrieval kernels.

## Measurement Space As A First-Class Interface

The architecture treats the forward-model result as a stable scientific interface.

`src/kernels/transport/measurement_space.zig` materializes radiance, irradiance, reflectance, and associated physical summaries as owned result data. Retrieval methods, exporters, and validation harnesses all consume that product instead of reconstructing it independently.

That decision keeps the code aligned with the DISAMAR literature, where forward modelling and retrieval are coupled but not collapsed into a single scalar output.

## Retrieval Layer

The retrieval layer is intentionally separate from the transport kernels.

- transport computes the observation-side response for a scene;
- retrieval methods decide how that response is used in an inverse problem;
- shared contracts hold priors, covariance structures, derivative requirements, and diagnostics.

This makes it possible to host OE, DOAS, and DISMAS on the same physical scene description and the same measurement-space outputs while keeping method-specific policy readable.

## Plugin Boundary

The plugin system is part of the architecture, but it does not redefine the execution contract.

Capabilities are frozen into a plan and surfaced in provenance. Native extensions stay behind the C ABI. Declarative capability packs can advertise reference-data or format surfaces without leaking parsing or mutation into kernels. The full plugin story is described in [Plugins and Extension Boundaries](./plugins-and-extension-boundaries.md), but the architectural point is simple: extension is allowed only when it preserves typed execution, provenance, and deterministic preparation.

## Why The Architecture Looks This Way

Earlier DISAMAR implementations combined scientific logic, operational I/O, and application flow in a single program. The current implementation keeps the same model family but makes several boundaries explicit:

- kernels do not read files,
- mission adapters do not define transport numerics,
- plugin resolution happens before execution,
- provenance is attached to the result rather than reconstructed later.

Those choices are not cosmetic. They are what make the codebase reviewable as a scientific system rather than only as a procedural application.

## Reading Order In Code

For a compact architecture walk-through:

1. read `src/core/Engine.zig`,
2. read `src/core/Plan.zig`,
3. read `src/model/Scene.zig`,
4. read `src/runtime/reference/BundledOptics.zig`,
5. read `src/kernels/optics/prepare.zig`,
6. read `src/kernels/transport/measurement_space.zig`,
7. read `src/plugins/registry/CapabilityRegistry.zig`.
