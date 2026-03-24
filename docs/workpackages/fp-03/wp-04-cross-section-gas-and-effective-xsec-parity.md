# WP-04 Cross-Section Gas And Effective-Xsec Parity

## Metadata

- Created: 2026-03-18
- Scope: implement vendor-style cross-section gas handling, effective cross sections, and UV/Vis gas-family parity for O3, NO2, SO2, HCHO, BrO, CHOCHO-like species, and related retrieval controls
- Input sources:
  - vendor `propAtmosphere.f90`
  - vendor `readConfigFileModule.f90::{readGeneral,readAbsorbingGas}`
  - vendor `doasModule.f90` and `classic_doasModule.f90`
  - vendor UV/Vis and profile example configs
  - Zig reference, retrieval, and config code
- Dependencies:
  - `WP-01` for config expression parity
  - `WP-02` for forward RT parity
  - `WP-03` for shared spectroscopy/control infrastructure where relevant
- Reference baseline:
  - vendor `propAtmosphere.f90::{getAbsorptionXsecUsingLUT,getAbsorptionXsecFromLUT,createXsecLUT,convoluteXsec,convoluteXsecLUT}`
  - vendor `readConfigFileModule.f90::{readGeneral,readAbsorbingGas}` including `specifications_DOAS_DISMAS` and gas-section `specifyFitting`
  - vendor `doasModule.f90` and `classic_doasModule.f90` for effective cross-section usage patterns

## Background

O2A is only one part of the DISAMAR surface. The vendor code supports a large UV/Vis family based on cross-section tables, effective cross sections, profile and column retrievals, and multi-species fits. Without this WP, Zig may improve line-absorbing gases but still fail major DISAMAR use cases like O3 profiles, NO2 DOMINO, and mixed trace-gas column retrievals.

## Overarching Goals

- Support the vendor cross-section gas family and its config controls.
- Implement effective-cross-section pathways where the vendor uses them.
- Keep line-gas and cross-section-gas representations cleanly separated but interoperable.

## Non-goals

- Full DOAS fitting logic; that belongs in `WP-12`.
- Full DISMAS fitting logic; that belongs in `WP-13`.
- Measured-input operational wiring; that belongs in `WP-07`.

### WP-04 Cross-section gas and effective-xsec parity [Status: Done 2026-03-24]

Issue:
Current Zig work is still biased toward O2A and line-gas scaffolding. The vendor config and example suite show a broader family of cross-section-based gases and effective-xsec behavior that the Zig runtime must support to be a general DISAMAR replacement.

Needs:
- a typed absorption-representation split between line gases and cross-section gases
- cross-section and XsecLUT ingestion/runtime support for UV/Vis families
- effective cross-section controls for OE/DOAS-class workflows
- validation on non-O2 example cases

How:
1. Add a clear abstraction for line-absorption versus cross-section absorption.
2. Implement runtime selection and interpolation of cross-section assets, including temperature/pressure-aware LUT-backed cases.
3. Surface `useEffXsec_OE_*`, polynomial degree, and strong-absorption flags into typed config.
4. Validate on NO2, O3, SO2, and multi-species cases from the vendor corpus.

Why this approach:
The vendor code mixes line-gas and cross-section-gas workflows within one system but does not treat them as the same physics. Zig needs that same distinction if it is going to go beyond O2A.

Recommendation rationale:
This lands after transport and line-gas work because the cross-section path reuses the same forward core, but it now keeps line gases, table cross sections, LUT-backed cross sections, and effective-xsec controls distinct all the way from typed config through bundled-provider dispatch and prepared optics.

Desired outcome:
Zig can express and execute vendor-style cross-section gas cases without pretending they are line-absorption cases, and the config/runtime path for effective cross sections is explicit and testable.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation-cross-section-parity --summary all`

Files by type:
- Absorption/reference targets:
  - `src/model/Absorber.zig`
  - `src/model/ReferenceData.zig`
  - `src/model/reference/cross_sections.zig`
  - `src/model/reference/climatology.zig`
  - `src/model/instrument/cross_section_lut.zig`
- Optics and runtime targets:
  - `src/kernels/optics/prepare.zig`
  - `src/runtime/reference/BundledOptics.zig`
  - `src/plugins/providers/optics.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
  - `src/model/ObservationModel.zig`
- Validation targets:
  - `tests/unit/optics_preparation_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`
  - `tests/validation/oe_parity_test.zig`
  - `tests/validation/doas_parity_test.zig`

## Exact Patch Checklist

- [x] `src/model/Absorber.zig`, `src/model/ReferenceData.zig`, `src/model/reference/cross_sections.zig`: add a typed separation between line absorption, table cross sections, and LUT-backed cross sections.
  - Vendor anchors: `propAtmosphere.f90::{getAbsorptionXsecUsingLUT,getAbsorptionXsecFromLUT}` and gas configs such as `Config_NO2_DOMINO.in`, `Config_column_O3.in`, `Config_columns_O3_HCHO_BrO_NO2.in`, `Config_O3_profile+SO2_column.in`.
  - Example direction:
    ```zig
    const AbsorptionRepresentation = union(enum) {
        line_abs: LineGasControls,
        xsec_table: CrossSectionTable,
        xsec_lut: CrossSectionLutRef,
        effective_xsec: EffectiveXsecControls,
    };
    ```

- [x] `src/model/instrument/cross_section_lut.zig`, `src/kernels/optics/prepare.zig`, `src/runtime/reference/BundledOptics.zig`: support vendor-style XsecLUT usage for cross-section gases.
  - Vendor anchors: `propAtmosphere.f90::{createXsecLUT,convoluteXsecLUT}` and `readConfigFileModule.f90::readGeneral` subsection `createXsecLUT`.
  - Keep LUT-backed and direct-table paths distinct so validation can compare them.

- [x] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/ObservationModel.zig`: expose and compile effective-cross-section controls.
  - Vendor anchors: `readConfigFileModule.f90::readGeneral` subsection `method` (`useEffXsec_OE_sim`, `useEffXsec_OE_retr`) and subsection `specifications_DOAS_DISMAS` (e.g. `XsecStrongAbs*`, polynomial degree controls).
  - These controls must reach runtime as typed booleans/enums/integers, not raw string maps.

- [x] `src/plugins/providers/optics.zig`: keep absorption-representation dispatch centralized.
  - Vendor anchors: vendor uses the same high-level forward engine with multiple absorption sources; Zig should centralize the absorption source choice rather than scattering `if gas.kind == ...` logic through transport and retrieval.
  - The provider should decide whether to prepare line absorption, cross-section tables, or LUT-backed data for each gas/band.

- [x] `tests/unit/optics_preparation_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`, `tests/validation/oe_parity_test.zig`, `tests/validation/doas_parity_test.zig`: add multi-gas UV/Vis validation cases.
  - Required case families: one NO2 case (`Config_NO2_DOMINO.in` or `Config_NO2_O2-O2.in`), one O3 profile case, one mixed-gas case (`Config_columns_O3_HCHO_BrO_NO2.in`), and one SO2-containing case.
  - The harness should prove that these cases no longer go through an O2A-specific path.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Cross-section gases have a first-class typed representation distinct from line gases
- [x] Effective-xsec controls are represented and consumed explicitly
- [x] At least one O3 and one NO2-family case are validated end-to-end

## Implementation Status (2026-03-24)

Implementation is present on branch `codex/wp-04-cross-section-parity`, and the WP is now re-cleared by a fresh independent verifier loop against the current shipping diff. Newton passed the correctness audit against the completion checklist, Carson passed the broader codebase/coverage audit, and Galileo reproduced the exact WP proof commands (`zig build test-unit --summary all` and `zig build test-validation-cross-section-parity --summary all`) on the live branch state. The earlier self-certified tracker state was reset and replaced with these independent pass verdicts.

## Why This Works

DISAMAR is not “an O2A code with extras.” It supports multiple spectroscopy families. The landed split between line absorption, explicit cross-section tables, and LUT-backed cross sections keeps those paths typed, which lets the provider/runtime choose the right reference assets without reintroducing vendor-style global state. The effective-xsec controls now reach prepared optics and retrieval fit policy as explicit booleans and per-band integers instead of parse-only ornaments, so NO2/O3-family retrievals and mixed-gas UV/Vis scenes can exercise the intended path directly.

## Proof / Validation

- `zig build test-unit --summary all` -> `Build Summary: 4/4 steps succeeded; 129/129 tests passed.`
- `zig build test-validation-cross-section-parity --summary all` -> `Build Summary: 8/8 steps succeeded; 3/3 tests passed.`
  - This step runs three focused proofs through supported build entry points:
    - `compatibility harness routes explicit cross-section fixtures away from O2A defaults`
    - `doas validation routes a NO2 cross-section scene through explicit effective-xsec optics`
    - `oe parity executes an O3 cross-section scene through the explicit LUT path`
- These commands are the exact supported verification entry points used for the independent verifier pass/fail loop.

## How To Test

1. Run `zig build test-unit --summary all`.
2. Run `zig build test-validation-cross-section-parity --summary all`.
3. Confirm the cross-section parity step reports all three focused proofs green.
4. For the compatibility-harness route proof, confirm the UV/Vis cross-section fixtures stay on explicit cross-section absorbers and do not materialize bundled visible-line or O2A CIA sidecars.
