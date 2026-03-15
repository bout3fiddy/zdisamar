# Work Package: Vendor Runtime Activation and Scientific Output Closure

## Canonical References

- [Architecture scratch copy](../../specs/architecture.md)
- [Fortran mapping scratch copy](../../specs/fortran-mapping.md)
- [Previous vendor closure package](../feature_vendor_parity_closure_2026-03-15/overview.md)
- [Root AGENTS router](../../../AGENTS.md)
- `vendor/disamar-fortran/src/HITRANModule.f90`
- `vendor/disamar-fortran/src/propAtmosphere.f90`
- `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
- `vendor/disamar-fortran/src/S5POperationalModule.f90`

## Execution Directive (Standard)

```text
REQUIRED
- Work package directory: docs/workpackages/feature_vendor_runtime_activation_2026-03-15/
- Read overview.md first, then continue from the first non-done WP item across the folder.
- Treat the predecessor package as completed context; do not reopen already-closed items unless a regression is found.

EXECUTION RULES
- Keep changes non-destructive.
- Repository mode: library-first Zig project with typed package/module boundaries.
- Primary verification: zig build test-unit, zig build test-validation, zig build test-integration, zig build test-perf, zig build test, zig build, zig test src/exporters_wp12_test_entry.zig, and CLI smoke runs when adapter/runtime behavior changes.
- Use the vendored DISAMAR Fortran tree as a capability reference, not as an architectural template.
- Do not claim “feature parity” while runtime execution still bypasses tracked bundle assets, measurement/export paths still emit summaries instead of scientific arrays, or mission/scientific operators remain bounded approximations.

WHEN YOU COMPLETE A WP ITEM
- Update the detailed WP section with:
  - Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- Mark the WP title status line as [Status: Done YYYY-MM-DD].
- Update this overview rollup row in the same change with status, date, proof pointer, and next action.

FINISHING
- Only move on to public-facing docs after the remaining vendor delta is reduced to intentional architecture drift instead of missing runtime or scientific capability.
```

## Metadata

- Created: 2026-03-15
- Scope: remaining runtime, scientific-output, operational-mission, and spectroscopy depth gaps after the bounded parity closure package
- Input sources:
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `vendor/disamar-fortran/src/S5POperationalModule.f90`
  - `docs/workpackages/feature_vendor_parity_closure_2026-03-15/`
- Constraints:
  - preserve the typed `Engine -> Plan -> Workspace -> Request -> Result` surface
  - keep file parsing out of `src/core` and `src/kernels`
  - keep runtime state allocator-owned and explicit
  - separate bounded representative parity from full vendor feature parity

## Background

The closure package finished the bounded optics-preparation and compatibility-expansion work, but the vendor audit still found material capability gaps:

- runtime execution paths were still using demo-only reference builders instead of the tracked bundle assets
- measurement-space and exporter outputs still center on summaries/metadata rather than scientific arrays
- the S5P operational adapter still falls far short of the vendor operational replacement flow
- spectroscopy remains hybrid-contract level rather than full HITRAN/LISA physical parity

This package closes the runtime/output side first, then tackles the deeper scientific gaps before public documentation is allowed.

## Folder Contents

- `overview.md` — execution entry point and remaining-gap rollup.
- `wp-01-runtime-and-output.md` — bundle-backed runtime activation and scientific output payloads.
- `wp-02-mission-and-spectroscopy.md` — S5P operational parity and spectroscopy depth closure.
- `wp-03-public-docs.md` — public docs gate after true parity closure.

## Overview Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| WP-01 | Done | 2026-03-15 | `wp-01-runtime-and-output.md`: runtime execution now prepares optics from tracked bundle assets through `src/runtime/reference/BundledOptics.zig`, and both `Engine.execute` and retrieval synthetic forward use that path | Continue into result/export scientific arrays and exporter payloads |
| WP-02 | Done | 2026-03-15 | `wp-01-runtime-and-output.md`: `Result` now owns typed measurement-space vectors and physical fields, and NetCDF/Zarr emit wavelength/radiance/irradiance/reflectance/noise/jacobian payloads plus physical scalars | Continue into S5P operational replacement parity |
| WP-03 | Done | 2026-03-15 | `wp-02-mission-and-spectroscopy.md`: operational metadata now drives explicit high-resolution grid sampling plus wavelength-indexed typed ISRF nominal rows, and measurement-space execution selects the nearest nominal slit row per instrument sample | Continue into the remaining spectroscopy-science delta |
| WP-04 | Done | 2026-03-15 | `wp-02-mission-and-spectroscopy.md`: the operational S5P path now carries weighted refspec wavelengths, external high-resolution solar spectra, and O2 / O2-O2 `lnT/lnp` LUT coefficient cubes as typed observation-model state, and the optics plus measurement-space kernels consume those inputs directly | Continue the public docs pass and document the operational replacement architecture clearly |
| WP-05 | In Progress | 2026-03-15 | `wp-03-public-docs.md`: implementation blockers are cleared and the docs pass may start | Continue the docs pass in `docs/` with architecture and DISAMAR scientific context |
