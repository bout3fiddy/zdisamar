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
| WP-01 | Todo | 2026-03-15 | `wp-01-reference-spectroscopy-imports.md`: the repo now has bounded `hitran_160` ingest, but not real vendor-subset reference imports or sidecar relaxation inputs | Import tracked vendor-shaped subsets and typed sidecars into bundle form |
| WP-02 | Todo | 2026-03-15 | `wp-01-reference-spectroscopy-imports.md`: line evaluation now includes bounded line mixing and temperature derivatives, but not strong/weak-line partitioning or sidecar-driven first-order mixing | Extend spectroscopy evaluation beyond single-lane bounded proxies |
| WP-03 | Todo | 2026-03-15 | `wp-02-optical-property-sublayers.md`: optical preparation is wavelength aware, but still aggregates by coarse scene layers instead of RTM-style sublayers | Introduce typed sublayer grids and gas optical-property materialization |
| WP-04 | Todo | 2026-03-15 | `wp-02-optical-property-sublayers.md`: aerosol/cloud wavelength scaling exists, but HG interval optical properties and coefficient synthesis are still missing | Implement HG aerosol/cloud optical-property lanes |
| WP-05 | Todo | 2026-03-15 | `wp-02-optical-property-sublayers.md`: there is no bounded Mie interpolation or combined phase-function coefficient path yet | Add tracked Mie subset ingestion and coefficient preparation |
| WP-06 | Todo | 2026-03-15 | `wp-03-parity-docs-closure.md`: compatibility coverage is still centered on one bounded OE case | Broaden parity cases to O2A, aerosol/cloud, and measurement-space reference outputs |
| WP-07 | Todo | 2026-03-15 | `wp-03-parity-docs-closure.md`: public docs are intentionally blocked until the remaining scientific gap is closed or explicitly bounded | Start docs only after the vendor audit says the remaining delta is intentional |
