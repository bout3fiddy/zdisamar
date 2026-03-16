# Work Package: Vendored DISAMAR Parity Follow-up

## Canonical References

- [Architecture scratch copy](../../specs/architecture.md)
- [Fortran mapping scratch copy](../../specs/fortran-mapping.md)
- [Original migration plan](../../specs/original-plan.md)
- [Root AGENTS router](../../../AGENTS.md)
- `vendor/disamar-fortran/src/`

## Execution Directive (Standard)

```text
REQUIRED
- Work package directory: docs/workpackages/feature_vendor_parity_followup_2026-03-15/
- Read overview.md first, then continue from the first non-done WP item across the folder.
- Do not leave any <...> placeholder unresolved.

EXECUTION RULES
- Keep changes non-destructive.
- Repository mode: library-first Zig project; no browser app is expected.
- Primary verification: zig build test, zig build, targeted parity harnesses, and focused artifact checks relevant to each WP.
- Use the vendored DISAMAR Fortran tree as the reference for missing capability surface, not as a structure to reproduce verbatim.
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
- Commit and push periodically as coherent checkpoints when the vendor-parity delta is materially reduced.

FINISHING
- When all WP items are done, re-run the vendor audit against vendor/disamar-fortran/src and document why the remaining difference is intentional architecture drift rather than missing capability.
- Only then treat the repo as functionally complete relative to the vendor reference and move on to extensive public-facing docs.
```

## Metadata

- Created: 2026-03-15
- Scope: remaining feature-completeness work after the contract-level scaffold package was completed
- Input sources:
  - `vendor/disamar-fortran/src/`
  - `docs/workpackages/feature_spec_completeness_2026-03-14/`
  - `docs/specs/original-plan.md`
- Constraints:
  - preserve the typed `Engine -> Plan -> Workspace -> Request -> Result` surface
  - keep file I/O and mission-specific logic out of `src/core` and `src/kernels`
  - keep native plugin contracts behind the stable C ABI
  - do not pretend contract-level parity equals scientific/output parity

## Background

The first feature-completeness package is now done at the contract level: the directory layout exists, plugin/runtime boundaries are typed, exporter and data scaffolds are executable, and parity/perf harnesses run. A direct comparison against `vendor/disamar-fortran/src/` shows that this is still not the same thing as being complete relative to the vendored DISAMAR implementation.

Concrete examples from the vendor audit:

- `vendor/disamar-fortran/src/netcdfModule.f90` is a real NetCDF writer layered on the Fortran NetCDF API, while `src/adapters/exporters/netcdf_cf.zig` currently writes a CF/CDL-style text artifact.
- `vendor/disamar-fortran/src/propAtmosphere.f90`, `vendor/disamar-fortran/src/HITRANModule.f90`, and `vendor/disamar-fortran/src/radianceIrradianceModule.f90` are large numerical/physics modules, while the current Zig transport/retrieval stack still uses deterministic simplified kernels.
- `vendor/disamar-fortran/src/optimalEstimationModule.f90`, `vendor/disamar-fortran/src/doasModule.f90`, and `vendor/disamar-fortran/src/dismasModule.f90` contain substantial retrieval machinery, while the current Zig solver files are compact contract-proving implementations.
- `vendor/disamar-fortran/src/S5POperationalModule.f90` and `vendor/disamar-fortran/src/S5PInterfaceModule.f90` implement operational ingestion/replacement flows that do not yet exist in the Zig adapter tree.

This package captures that remaining delta explicitly so future work is not hidden behind the completed status of the earlier scaffold package.

## Overarching Goals

- Separate “architecturally migrated” from “capability-complete against the vendor reference”.
- Turn the current contract-level implementations into real scientific/output implementations where the vendor reference still materially exceeds the Zig tree.
- Keep the new work aligned with the target architecture rather than rebuilding the Fortran global-state application shape.

## Non-goals

- Reintroducing global mutable state, implicit file units, or string-keyed mutation APIs.
- Translating the vendor tree file-for-file.
- Claiming scientific parity before numerical reference comparisons actually pass.

## Folder Contents

- `overview.md` — vendor-parity status rollup and execution entry point.
- `wp-01-output-and-data-parity.md` — result containers, data import, and reference asset parity.
- `wp-02-physics-and-retrieval-parity.md` — atmosphere, spectroscopy, forward model, and retrieval gaps.
- `wp-03-mission-and-validation-parity.md` — operational mission ingestion, compatibility, and completion criteria.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done | 2026-03-15 | `wp-01-output-and-data-parity.md`: real NetCDF classic/Zarr v2 container emitters and typed adapter-level data ingestion are now implemented and covered by `zig build test`, `zig test src/exporters_wp12_test_entry.zig`, and the CLI smoke run | Move to WP-02 optical-property and spectroscopy preparation |
| WP-02 | Todo | 2026-03-15 | `wp-02-physics-and-retrieval-parity.md`: typed optical preparation now includes fixed-width HITRAN-style line-list ingestion, bounded line-mixing and temperature-derivative evaluation, wavelength-dependent aerosol/cloud optical-depth scaling, and band-averaged spectroscopy summaries, all covered by `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test`, `zig build`, `zig test src/exporters_wp12_test_entry.zig`, and the CLI smoke run; full vendor database ingestion and sublayer optical-property depth are still open | Move from bounded HITRAN-style ingest to real vendor reference imports and richer sublayer optical-property derivation |
| WP-03 | Done | 2026-03-15 | `wp-02-physics-and-retrieval-parity.md`: `src/kernels/transport/measurement_space.zig` now composes typed optical preparation, transport routing, calibration, convolution, noise, and derivative summaries; `src/core/Engine.zig` materializes the summary in results and `zig build test-integration` exercises the path | Move to retrieval algorithm depth and broader numeric anchors |
| WP-04 | Done | 2026-03-15 | `wp-02-physics-and-retrieval-parity.md`: OE/DOAS/DISMAS solvers now run iterative forward-model-driven fits through `src/retrieval/common/synthetic_forward.zig` and are covered by `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, and `zig build test` | Broaden scientific fidelity and numeric anchors after spectroscopy depth lands |
| WP-05 | Done | 2026-03-15 | `wp-03-mission-and-validation-parity.md`: S5P adapter now has a file-backed operational ingestion path, typed measurement summaries, and integration coverage through `zig build test-integration` and `zig build test` | Move to WP-06 numeric validation against bounded vendor cases |
| WP-06 | Done | 2026-03-15 | `wp-03-mission-and-validation-parity.md`: `tests/validation/disamar_compatibility_harness_test.zig` now compares OE retrieval iterations, convergence, chi2, and DFS against the bounded vendor `test/disamar.asciiHDF` anchor with explicit tolerances in `validation/compatibility/parity_matrix.json` | Public docs stay blocked until the remaining spectroscopy/physics gap is closed or intentionally bounded |
