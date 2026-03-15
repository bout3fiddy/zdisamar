# Work Package: Vendored DISAMAR Parity Closure

## Canonical References

- [Architecture scratch copy](../../specs/architecture.md)
- [Fortran mapping scratch copy](../../specs/fortran-mapping.md)
- [Original migration plan](../../specs/original-plan.md)
- [Previous vendor follow-up package](../feature_vendor_parity_followup_2026-03-15/overview.md)
- [Root AGENTS router](../../../AGENTS.md)
- `vendor/disamar-fortran/src/`

## Execution Directive (Standard)

```text
REQUIRED
- Work package directory: docs/workpackages/feature_vendor_parity_closure_2026-03-15/
- Read overview.md first, then continue from the first non-done WP item across the folder.
- Treat the predecessor package as completed context; do not reopen already-closed items unless a regression is found.

EXECUTION RULES
- Keep changes non-destructive.
- Repository mode: library-first Zig project with typed package/module boundaries.
- Primary verification: zig build test, zig build, parity harnesses, focused adapter/kernel tests, and CLI smoke runs when adapter-facing behavior changes.
- Use the vendored DISAMAR Fortran tree as a capability reference, not as an architectural template.
- Do not claim parity from green tests alone; each WP must cite the concrete vendor gap it closes.

WHEN YOU COMPLETE A WP ITEM
- Update the detailed WP section with:
  - Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- Mark the WP title status line as [Status: Done YYYY-MM-DD].
- Update this overview rollup row in the same change with status, date, proof pointer, and next action.

CHECKPOINTS
- Commit and push after each coherent vendor-gap reduction that leaves the repo green.

FINISHING
- Only move on to public-facing docs after the remaining difference against vendor/disamar-fortran/src is reduced to intentional architecture drift instead of missing capability.
```

## Metadata

- Created: 2026-03-15
- Scope: remaining vendor-parity work after the first follow-up package introduced bounded HITRAN-style ingest and wavelength-dependent optical preparation
- Input sources:
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `docs/workpackages/feature_vendor_parity_followup_2026-03-15/`
- Constraints:
  - preserve the typed `Engine -> Plan -> Workspace -> Request -> Result` surface
  - keep file I/O and mission-specific parsing out of `src/core` and `src/kernels`
  - keep native plugin and adapter boundaries behind the existing ABI/package surfaces
  - do not collapse back into vendor-style global mutable state

## Background

The previous vendor follow-up package materially reduced the gap:

- real container exporters exist
- typed ingest paths exist for baseline assets and mission fixtures
- the engine produces measurement-space summaries
- retrieval solvers are no longer placeholders
- spectroscopy ingest now accepts bounded fixed-width HITRAN-style line lists
- aerosol/cloud optical depth now varies with wavelength through typed controls

The remaining audit is narrower but still real. The largest missing surfaces are:

- real reference imports and sidecars beyond bounded demo line lists
- sublayer optical-property materialization comparable to `propAtmosphere.f90`
- HG/Mie phase-function and scattering coefficient preparation
- broader bounded numeric parity cases beyond the current OE-focused anchor
- public scientific docs after the above are honestly closed

## Overarching Goals

- Close the remaining capability delta without undoing the architecture migration.
- Replace bounded demo-style reference preparation with typed vendor-subset import pipelines.
- Materialize sublayer optical properties and scattering coefficients in pure kernels instead of hiding them behind coarse aggregate controls.
- Expand parity evidence so “finished” means bounded scientific agreement, not just internal consistency.

## Non-goals

- Recreating the full DISAMAR global-state application structure.
- Importing the entire upstream reference database into git.
- Claiming full scientific equivalence where only bounded representative subsets are implemented.

## Folder Contents

- `overview.md` — execution entry point and remaining-gap rollup.
- `wp-01-reference-spectroscopy-imports.md` — reference imports, sidecars, and spectroscopy evaluator depth.
- `wp-02-optical-property-sublayers.md` — sublayer gas/aerosol/cloud optical-property preparation.
- `wp-03-parity-docs-closure.md` — compatibility expansion and public docs closure gate.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done | 2026-03-15 | `wp-01-reference-spectroscopy-imports.md`: tracked O2 A-band HITRAN, LISA SDF, and RMF subset assets are now in `data/cross_sections/` with verified hashes and vendor import provenance | Continue into typed RTM sublayer preparation in WP-03 |
| WP-02 | Done | 2026-03-15 | `wp-01-reference-spectroscopy-imports.md`: `SpectroscopyLineList` now partitions weak/strong lines and drives first-order mixing from typed relaxation sidecars | Continue into typed RTM sublayer preparation in WP-03 |
| WP-03 | Done | 2026-03-15 | `wp-02-optical-property-sublayers.md`: `PreparedOpticalState` now carries typed gas sublayers with parent aggregation and `dXsec/dT`-style optical-depth summaries | Continue into bounded Mie interpolation and coefficient combination in WP-05 |
| WP-04 | Done | 2026-03-15 | `wp-02-optical-property-sublayers.md`: aerosol/cloud optical depth is now distributed across sublayers with bounded HG phase-coefficient materialization | Continue into bounded Mie interpolation and coefficient combination in WP-05 |
| WP-05 | Done | 2026-03-15 | `wp-02-optical-property-sublayers.md`: tracked Mie subset ingestion, interpolation, and combined phase-coefficient preparation now run through `src/model/ReferenceData.zig`, `src/adapters/ingest/reference_assets.zig`, and `src/kernels/optics/prepare.zig` with focused unit coverage | Use the new runtime/output package for the remaining non-optics vendor gaps |
| WP-06 | Done | 2026-03-15 | `wp-03-parity-docs-closure.md`: compatibility coverage now includes O2 A-band optics, Mie-influenced measurement space, and bundle-backed runtime execution with `zig build test-validation`, `zig build test`, and the CLI smoke run passing | Continue into runtime/output and mission/scientific parity gaps before public docs |
| WP-07 | In Progress | 2026-03-15 | `wp-03-parity-docs-closure.md`: the later runtime-activation package closed the remaining operational parity blockers, and the public docs pass is now active in `feature_vendor_runtime_activation_2026-03-15/wp-03-public-docs.md` | Continue the public docs pass in `docs/` without reopening the closed parity items |
