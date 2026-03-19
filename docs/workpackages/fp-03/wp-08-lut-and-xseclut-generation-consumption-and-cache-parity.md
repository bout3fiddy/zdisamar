# WP-08 LUT And XsecLUT Generation, Consumption, And Cache Parity

## Metadata

- Created: 2026-03-18
- Scope: support vendor-style reflectance/correction LUT creation and XsecLUT generation and runtime consumption, with cache semantics that remain compatible with the typed Zig engine
- Input sources:
  - vendor `createLUTModule.f90`
  - vendor `propAtmosphere.f90`
  - vendor `DISAMARModule.f90::fillWavelPressureGeometryLUT`
  - vendor `readConfigFileModule.f90::{readGeneral,readReferenceData}`
  - Zig LUT/cache/reference code
- Dependencies:
  - `WP-01`, `WP-02`, `WP-03`, `WP-04`, and `WP-06`
- Reference baseline:
  - vendor `createLUTModule.f90::{createReflectanceLUT,createPolcorrectionLUT,createPolRRScorrectionLUT}`
  - vendor `propAtmosphere.f90::{createXsecLUT,getAbsorptionXsecUsingLUT,getAbsorptionXsecFromLUT,convoluteXsecLUT}`
  - vendor `DISAMARModule.f90::fillWavelPressureGeometryLUT`

## Background

The vendor code supports precomputed LUT workflows for both reflectance/correction paths and cross-section polynomials. Those paths are not optional polish; they are part of how DISAMAR supports operational and performance-sensitive use cases. The current Zig repo has cache and LUT scaffolding, but it is not yet a complete vendor-style LUT workflow.

## Overarching Goals

- Support creation and consumption of reflectance/correction LUTs.
- Support creation and consumption of XsecLUT assets for spectroscopy.
- Keep LUT use explicit and provenance-visible.

## Non-goals

- Hiding LUT use behind silent magic caches.
- Over-optimizing before validation and acceptance criteria exist.
- Replacing direct simulation paths entirely.

### WP-08 LUT and XsecLUT generation, consumption, and cache parity [Status: Todo]

Issue:
The vendor config and source support LUT workflows as first-class capabilities. Zig has early cache structures and a strong `cross_section_lut` carrier, but not yet the full workflow or the config/runtime semantics around it.

Needs:
- typed create/use LUT controls
- runtime asset generation and serialization hooks
- prepared-plan cache semantics that distinguish direct vs LUT-backed execution
- validation across both direct and LUT-backed cases

How:
1. Expose create/use LUT semantics in config and prepared plans.
2. Add explicit generation paths for reflectance/correction LUTs and XsecLUTs.
3. Store generated assets in typed caches with provenance.
4. Compare direct and LUT-backed runs in the validation harness.

Why this approach:
LUT workflows affect both scientific behavior and performance. They must be explicit enough that the validation harness can prove whether a case used direct computation or a LUT.

Recommendation rationale:
This follows the core physics and instrument WPs because the LUTs are only meaningful once their source computations are correct.

Desired outcome:
A caller can choose direct or LUT-backed execution through typed config, the engine can generate or consume the appropriate asset, and validation can compare both modes on the same scientific case.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/runtime_cache_scheduler_test.zig`
- `zig test tests/validation/parity_assets_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Runtime/cache targets:
  - `src/runtime/cache/LUTCache.zig`
  - `src/runtime/cache/PreparedLayout.zig`
  - `src/runtime/reference/BundledOptics.zig`
- Spectroscopy/LUT targets:
  - `src/model/instrument/cross_section_lut.zig`
  - `src/kernels/optics/prepare.zig`
  - `src/plugins/providers/optics.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
  - `src/core/Plan.zig`
  - `src/core/Engine.zig`
- Validation targets:
  - `tests/unit/runtime_cache_scheduler_test.zig`
  - `tests/validation/parity_assets_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/adapters/canonical_config/Document.zig` and `document_fields.zig`: expose vendor create/use LUT controls exactly enough to distinguish generation and consumption modes.
  - Vendor anchors: `readConfigFileModule.f90::readGeneral` subsections `createLUT` and `createXsecLUT`; `readReferenceData`.
  - Carry parameters like pressure/temperature ranges, polynomial order controls, and toggles for reflectance vs correction LUTs.

- [ ] `src/model/instrument/cross_section_lut.zig`, `src/kernels/optics/prepare.zig`, `src/plugins/providers/optics.zig`: implement XsecLUT generation and use as explicit execution paths.
  - Vendor anchors: `propAtmosphere.f90::{createXsecLUT,getAbsorptionXsecUsingLUT,getAbsorptionXsecFromLUT,convoluteXsecLUT}`.
  - Keep direct spectroscopy and LUT-backed spectroscopy as separate code paths with common interfaces.
  - Record which path was used in provenance and test output.

- [ ] `src/runtime/cache/LUTCache.zig`, `src/runtime/cache/PreparedLayout.zig`, `src/core/Plan.zig`, `src/core/Engine.zig`: make prepared plans and caches aware of LUT identity and compatibility.
  - Vendor anchors: `DISAMARModule.f90::fillWavelPressureGeometryLUT` and `createLUTModule.f90`.
  - A prepared plan should not accidentally reuse a LUT generated for incompatible geometry, spectral window, or instrument settings.
  - Include hashable keys based on the scientific inputs that define a LUT.

- [ ] `src/runtime/reference/BundledOptics.zig`: add or standardize typed storage for generated LUT assets.
  - Vendor anchors: reflectance/polarization/RRS correction LUT generation in `createLUTModule.f90`.
  - Avoid storing opaque “some LUT” blobs. Use typed asset wrappers with dimensions, grid specs, provenance, and intended use.

- [ ] `tests/unit/runtime_cache_scheduler_test.zig`, `tests/validation/parity_assets_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add direct-vs-LUT comparisons.
  - Required cases: `Config_O2A_XsecLUT.in` and one non-O2 LUT-relevant case.
  - Assert that direct and LUT-backed runs stay within agreed thresholds and that the harness can report which mode was used.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Create/use LUT controls are explicit in config and prepared plans
- [ ] Provenance records whether execution used direct or LUT-backed paths
- [ ] At least one XsecLUT case runs end-to-end through the validation harness

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

The vendor code uses LUTs as a real execution mode, not just a cache side effect. Modeling them explicitly in config, planning, and provenance preserves scientific auditability while still enabling performance-oriented workflows.

## Proof / Validation

- Planned: `zig test tests/unit/runtime_cache_scheduler_test.zig` -> LUT identity and cache compatibility are enforced correctly
- Planned: `zig test tests/validation/parity_assets_test.zig` -> generated/consumed LUT assets are typed and complete
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> vendor LUT cases map to the correct Zig execution mode

## How To Test

1. Run a direct O2A case and an XsecLUT-backed O2A case.
2. Confirm the prepared plan and provenance record which path was taken.
3. Compare scientific outputs and ensure differences stay within the acceptance criteria.
4. Invalidate one defining input (for example spectral window or geometry) and confirm the runtime refuses to reuse an incompatible LUT.
