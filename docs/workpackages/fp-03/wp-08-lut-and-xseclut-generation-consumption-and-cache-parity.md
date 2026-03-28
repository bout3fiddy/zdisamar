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

### WP-08 LUT and XsecLUT generation, consumption, and cache parity [Status: Done 2026-03-28]

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
This follows the core physics, cross-section, and operational measured-input WPs because the LUT workflows only become meaningful once the forward physics, instrument sampling, and typed mission/runtime carriers are already honest.

Desired outcome:
A caller can choose direct or LUT-backed execution through typed config, the engine can generate or consume the appropriate asset, and validation can compare both modes on the same scientific case.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation-lut-assets --summary all`
- `zig build test-validation-compatibility-lut-parity --summary all`
- `zig build test-fast --summary all`
- `zig build check --summary all`

Files by type:
- Runtime/cache targets:
  - `src/runtime/cache/LUTCache.zig`
  - `src/runtime/cache/PreparedLayout.zig`
  - `src/runtime/reference/BundledOptics.zig`
  - `src/core/Request.zig`
  - `src/core/engine/forward.zig`
  - `src/core/provenance.zig`
- Spectroscopy/LUT targets:
  - `src/core/lut_controls.zig`
  - `src/model/instrument/cross_section_lut.zig`
  - `src/kernels/optics/preparation/state.zig`
  - `src/kernels/optics/preparation/builder.zig`
  - `src/kernels/quadrature/gauss_legendre.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/model/Scene.zig`
  - `src/core/Engine.zig`
  - `src/root.zig`
- Validation targets:
  - `build.zig`
  - `tests/unit/bundled_optics_test.zig`
  - `tests/unit/canonical_config_test.zig`
  - `tests/unit/runtime_cache_scheduler_test.zig`
  - `tests/validation/parity_assets_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`
  - `tests/validation/main.zig`

## Exact Patch Checklist

- [x] `src/adapters/canonical_config/Document.zig` and `document_fields.zig`: expose vendor create/use LUT controls exactly enough to distinguish generation and consumption modes.
  - Vendor anchors: `readConfigFileModule.f90::readGeneral` subsections `createLUT` and `createXsecLUT`; `readReferenceData`.
  - Carry parameters like pressure/temperature ranges, polynomial order controls, and toggles for reflectance vs correction LUTs.

- [x] `src/model/instrument/cross_section_lut.zig`, `src/kernels/optics/prepare.zig`, `src/plugins/providers/optics.zig`: implement XsecLUT generation and use as explicit execution paths.
  - Vendor anchors: `propAtmosphere.f90::{createXsecLUT,getAbsorptionXsecUsingLUT,getAbsorptionXsecFromLUT,convoluteXsecLUT}`.
  - Keep direct spectroscopy and LUT-backed spectroscopy as separate code paths with common interfaces.
  - Record which path was used in provenance and test output.

- [x] `src/runtime/cache/LUTCache.zig`, `src/runtime/cache/PreparedLayout.zig`, `src/core/Plan.zig`, `src/core/Engine.zig`: make prepared plans and caches aware of LUT identity and compatibility.
  - Vendor anchors: `DISAMARModule.f90::fillWavelPressureGeometryLUT` and `createLUTModule.f90`.
  - A prepared plan should not accidentally reuse a LUT generated for incompatible geometry, spectral window, or instrument settings.
  - Include hashable keys based on the scientific inputs that define a LUT.

- [x] `src/runtime/reference/BundledOptics.zig`: add or standardize typed storage for generated LUT assets.
  - Vendor anchors: reflectance/polarization/RRS correction LUT generation in `createLUTModule.f90`.
  - Avoid storing opaque “some LUT” blobs. Use typed asset wrappers with dimensions, grid specs, provenance, and intended use.

- [x] `tests/unit/runtime_cache_scheduler_test.zig`, `tests/validation/parity_assets_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add direct-vs-LUT comparisons.
  - Required cases: `Config_O2A_XsecLUT.in` and one non-O2 LUT-relevant case.
  - Assert that direct and LUT-backed runs stay within agreed thresholds and that the harness can report which mode was used.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Create/use LUT controls are explicit in config and prepared plans
- [x] Provenance records whether execution used direct or LUT-backed paths
- [x] At least one XsecLUT case runs end-to-end through the validation harness

## Implementation Status (2026-03-28)

Implemented. The runtime now carries typed reflectance/correction and XsecLUT controls through `Scene`, canonical-config staging, prepared-plan compatibility keys, and cache registration; `BundledOptics` can generate or consume typed reflectance/correction/XsecLUT assets with explicit provenance labels; generated LUT assets are registered into the typed `LUTCache` with geometry/spectral/instrument compatibility keys; request validation rejects plan/request LUT mismatches; and focused validation now covers cache compatibility, generated-versus-consumed asset metadata, O2A generated-XsecLUT bounded parity, and a non-O2 NO2 LUT path.

## Why This Works

The vendor code uses LUTs as a real execution mode, not as an incidental memoization layer, and the landed Zig path now does the same. `LutControls` and `CompatibilityKey` make the create/use choice explicit on the typed scene/plan boundary, generated assets are recorded as typed reflectance/correction/Xsec entries instead of opaque blobs, and request execution rejects incompatible plan reuse before a stale LUT can leak across geometry, spectral-window, or instrument-response changes. On the spectroscopy side, the XsecLUT carrier keeps direct and LUT-backed paths separate while sharing the same runtime interfaces, so provenance and validation can prove which route actually ran.

For the O2A validation case, the current runtime stays morphologically consistent and bounded at a mean absolute reflectance delta below the explicit `1.5e-3` acceptance threshold, while the non-O2 NO2 LUT case remains effectively exact under its tighter tolerance. That gives the harness an honest bounded-parity contract instead of a silent direct-path fallback.

## Proof / Validation

- `zig build test-unit --summary all` -> passed (`165/165`); covers the new LUT compatibility-key comparisons, cache mismatch rejection, generated cross-section LUT extrapolation regression, and the bundled-optics generated-table replacement regression
- `zig build test-validation-lut-assets --summary all` -> passed (`2/2`); proves generated reflectance/correction/Xsec assets register typed cache metadata and that consume mode records provenance without creating cache entries
- `zig build test-validation-compatibility-lut-parity --summary all` -> passed (`2/2`); proves `Config_O2A_XsecLUT` direct versus generated runs stay within the explicit bounded O2A threshold and that the non-O2 NO2 LUT case remains within its tighter parity tolerance
- `zig build test-fast --summary all` -> passed (`200/200`)
- `zig build check --summary all` -> passed (`165/165`)

Note:
The planning draft referenced raw `zig test tests/...` commands, but this repo wires the relevant suites through `build.zig`. The completed proof uses the corresponding `zig build` entrypoints so the same aggregates the repo expects before push are the ones recorded here.

## How To Test

1. Run `zig build test-validation-lut-assets --summary all` and confirm the generated reflectance/correction/Xsec asset metadata and consume-mode provenance checks pass.
2. Run `zig build test-validation-compatibility-lut-parity --summary all` and confirm the O2A generated-XsecLUT case stays within the explicit bounded parity threshold while the non-O2 NO2 case still passes its tighter tolerance.
3. Run `zig build test-unit --summary all` and confirm the LUT compatibility-key, request/plan mismatch, bundled-optics generation, and cross-section-LUT regression coverage stays green.
4. Run `zig build test-fast --summary all` and `zig build check --summary all` as the presubmit and repo-baseline confirmation on the same tree.
