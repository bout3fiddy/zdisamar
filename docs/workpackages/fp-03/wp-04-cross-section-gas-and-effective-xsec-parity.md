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

### WP-04 Cross-section gas and effective-xsec parity [Status: Todo]

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
This comes after transport and line-gas work because the cross-section path shares the same forward core, but it must land before broad retrieval parity claims.

Desired outcome:
Zig can express and execute vendor-style cross-section gas cases without pretending they are line-absorption cases, and the config/runtime path for effective cross sections is explicit and testable.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/optics_preparation_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`
- `zig test tests/validation/oe_parity_test.zig`
- `zig test tests/validation/doas_parity_test.zig`

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

- [ ] `src/model/Absorber.zig`, `src/model/ReferenceData.zig`, `src/model/reference/cross_sections.zig`: add a typed separation between line absorption, table cross sections, and LUT-backed cross sections.
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

- [ ] `src/model/instrument/cross_section_lut.zig`, `src/kernels/optics/prepare.zig`, `src/runtime/reference/BundledOptics.zig`: support vendor-style XsecLUT usage for cross-section gases.
  - Vendor anchors: `propAtmosphere.f90::{createXsecLUT,convoluteXsecLUT}` and `readConfigFileModule.f90::readGeneral` subsection `createXsecLUT`.
  - Keep LUT-backed and direct-table paths distinct so validation can compare them.

- [ ] `src/adapters/canonical_config/Document.zig`, `document_fields.zig`, `src/model/ObservationModel.zig`: expose and compile effective-cross-section controls.
  - Vendor anchors: `readConfigFileModule.f90::readGeneral` subsection `method` (`useEffXsec_OE_sim`, `useEffXsec_OE_retr`) and subsection `specifications_DOAS_DISMAS` (e.g. `XsecStrongAbs*`, polynomial degree controls).
  - These controls must reach runtime as typed booleans/enums/integers, not raw string maps.

- [ ] `src/plugins/providers/optics.zig`: keep absorption-representation dispatch centralized.
  - Vendor anchors: vendor uses the same high-level forward engine with multiple absorption sources; Zig should centralize the absorption source choice rather than scattering `if gas.kind == ...` logic through transport and retrieval.
  - The provider should decide whether to prepare line absorption, cross-section tables, or LUT-backed data for each gas/band.

- [ ] `tests/unit/optics_preparation_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`, `tests/validation/oe_parity_test.zig`, `tests/validation/doas_parity_test.zig`: add multi-gas UV/Vis validation cases.
  - Required case families: one NO2 case (`Config_NO2_DOMINO.in` or `Config_NO2_O2-O2.in`), one O3 profile case, one mixed-gas case (`Config_columns_O3_HCHO_BrO_NO2.in`), and one SO2-containing case.
  - The harness should prove that these cases no longer go through an O2A-specific path.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Cross-section gases have a first-class typed representation distinct from line gases
- [ ] Effective-xsec controls are represented and consumed explicitly
- [ ] At least one O3 and one NO2-family case are validated end-to-end

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

DISAMAR is not “an O2A code with extras.” It supports multiple spectroscopy families. A clean absorption-representation split lets Zig support that breadth without overloading one path with incompatible assumptions.

## Proof / Validation

- Planned: `zig test tests/unit/optics_preparation_test.zig` -> cross-section and LUT-backed preparation paths build correct typed optics inputs
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> UV/Vis example configs map to cross-section or effective-xsec execution paths
- Planned: `zig test tests/validation/oe_parity_test.zig` and `doas_parity_test.zig` -> retrieval families see correct absorption representations

## How To Test

1. Run one NO2-family, one O3-profile, and one mixed UV/Vis vendor case through the compatibility harness.
2. Inspect the prepared absorption representation for each gas and confirm it is not incorrectly routed through line-gas logic.
3. Compare direct-table and LUT-backed cross-section paths where the vendor offers both.
4. Confirm `useEffXsec_OE_*` changes the runtime path rather than being a parse-only ornament.
