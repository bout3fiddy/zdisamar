# WP-03 Line-Absorbing Spectroscopy And Strong-Line Sampling Parity

## Metadata

- Created: 2026-03-18
- Scope: implement vendor-faithful line-absorbing gas controls, line mixing, isotope selection, line thresholds, cutoffs, and adaptive strong-line sampling for O2, H2O, CO2, CH4, CO, and NH3
- Input sources:
  - vendor `HITRANModule.f90`
  - vendor `propAtmosphere.f90`
  - vendor `readConfigFileModule.f90::readAbsorbingGas`
  - vendor line-gas example configs
  - Zig absorber/reference/optics/instrument code
- Dependencies:
  - `WP-01` for config expression parity
  - `WP-02` for a real transport core that can consume the prepared spectroscopy
- Reference baseline:
  - vendor `HITRANModule.f90::{getAbsorptionXsecLineAbs,getLinePositions,fillMolecularParameters,CalculatAbsXsec,CalculateLineMixingXsec,readLineParameters}`
  - vendor `propAtmosphere.f90::{getAbsorptionXsec,getAbsorptionXsecUsingLUT,convoluteXsec}`
  - vendor `DISAMARModule.f90::setupHRWavelengthGrid`

## Background

The current findings already point to O2 spectroscopy controls and adaptive strong-line sampling as major remaining mismatch sources. The vendor config does not merely point at a HITRAN file; it carries per-gas controls like `factorLM*`, isotope lists, line-strength thresholds, and cutoffs, plus adaptive line-absorption sampling controls through the RTM section. This WP makes the Zig spectroscopy path honor those semantics for the full line-gas family, not just O2A.

## Overarching Goals

- Match vendor line-absorbing gas controls and their runtime consequences.
- Support adaptive strong-line sampling rather than a single fixed HR step.
- Reuse the same infrastructure for O2, H2O, CO2, CH4, CO, and NH3.

## Non-goals

- UV/Vis cross-section gas parity; that belongs in `WP-04`.
- Measured-input replacement workflows; those belong later.
- Papering over missing spectroscopy with measurement-space shape corrections.

### WP-03 Line-absorbing spectroscopy and strong-line sampling parity [Status: Todo]

Issue:
The current Zig line-gas handling still flattens important vendor controls. O2A already shows the consequence: the forward spectrum does not yet show the vendor line structure and depth correctly.

Needs:
- gas-family-specific line-absorption controls
- real line-mixing support for O2 where the vendor supports it
- isotope selection and threshold/cutoff handling
- adaptive HR sampling around strong lines

How:
1. Carry vendor gas controls into typed absorber/reference structs.
2. Implement adaptive strong-line grid generation around line centers instead of one fixed HR step.
3. Feed the resulting cross sections into the now-real transport kernel.
4. Validate on O2A first, then extend to the broader line-gas corpus.

Why this approach:
The vendor config and source make clear that line absorption is not one monolithic mode. Different gases and bands need different cutoffs, isotopes, and sampling behavior.

Recommendation rationale:
This follows transport parity because line-absorption accuracy matters only once the forward solver can use it correctly, and it must land before any full-gas-family parity claim.

Desired outcome:
O2A no longer relies on synthetic shaping to mimic narrow-line behavior, and the same infrastructure supports the broader vendor line-gas family without special-casing O2A forever.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/optics_preparation_test.zig`
- `zig test tests/validation/o2a_forward_shape_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Gas/control carriers:
  - `src/model/Absorber.zig`
  - `src/model/ReferenceData.zig`
  - `src/model/reference/cross_sections.zig`
  - `src/model/reference/cia.zig`
  - `src/model/hitran_partition_tables.zig`
- Optics/spectroscopy execution:
  - `src/kernels/optics/prepare.zig`
  - `src/runtime/reference/BundledOptics.zig`
  - `src/model/instrument/reference_grid.zig`
- Config/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
- Validation targets:
  - `tests/unit/optics_preparation_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/model/Absorber.zig` and `src/model/ReferenceData.zig`: add typed fields for vendor line-gas controls.
  - Vendor anchors: `readConfigFileModule.f90::readAbsorbingGas` and its `HITRAN` subsection keys `factorLMSim/Retr`, `ISOsim/Retr`, `thresholdLineSim/Retr`, `cutoffSim/Retr`.
  - Keep sim and retr controls separate.
  - Example direction:
    ```zig
    const LineGasControls = struct {
        factor_lm_sim: f64,
        factor_lm_retr: f64,
        isotopes_sim: []const u8,
        isotopes_retr: []const u8,
        threshold_line_sim: f64,
        threshold_line_retr: f64,
        cutoff_sim: f64,
        cutoff_retr: f64,
    };
    ```

- [ ] `src/kernels/optics/prepare.zig`: make line-absorption preparation aware of gas family, line mixing, isotope selection, and strong-line filtering.
  - Vendor anchors: `HITRANModule.f90::{fillMolecularParameters,CalculatAbsXsec,CalculateLineMixingXsec,readLineParameters}`.
  - O2 line mixing must be controlled explicitly, because the vendor warns that line mixing is implemented only for O2.
  - Do not treat `factorLM` as a generic no-op scalar for all gases.

- [ ] `src/model/instrument/reference_grid.zig` plus `src/kernels/optics/prepare.zig`: implement adaptive strong-line sampling rather than a fixed HR step.
  - Vendor anchors: `DISAMARModule.f90::setupHRWavelengthGrid`; `readRadiativeTransfer` subsections `numDivPointsWavel` and `numDivPointsWavelLineAbs`.
  - Support vendor-like controls such as points per FWHM and min/max division controls for strong lines.
  - The grid builder should be able to say: “for this band and gas, use baseline spacing here and refined spacing near detected strong-line centers.”
  - Example direction:
    ```zig
    const AdaptiveGridSpec = struct {
        base_step_nm: f64,
        strong_line_min_div: u16,
        strong_line_max_div: u16,
        strong_line_half_span_nm: f64,
    };
    ```

- [ ] `src/runtime/reference/BundledOptics.zig` and `src/model/reference/cia.zig`: keep O2-O2 CIA and related reference assets aligned with the line-gas path.
  - Vendor anchors: `Config_O2_with_CIA.in`, `Config_O2_no_CIA.in`, and reference assets such as `O2A_LISA_baseJPL.dat`, `O2A_LISA_CIAF.dat`, `O2O2T_BIRA.dat`.
  - The line-gas path should not bypass CIA or collision-complex handling when the vendor config includes it.

- [ ] `src/adapters/canonical_config/Document.zig` and `document_fields.zig`: expose the vendor `HITRAN` subsection in canonical YAML exactly enough to express all line-gas controls.
  - Vendor anchors: `readConfigFileModule.f90::readAbsorbingGas` and the line-gas example configs `Config_O2_with_CIA.in`, `Config_O2A_XsecLUT.in`, `Config_H2O_NH3.in`, `Config_ESA_project_CO2+H2O.in`, `Config_ESA_project_O2+CO2+H2O_3bands.in`.
  - Do not collapse isotope lists or sim/retr split fields into a generic opaque blob.

- [ ] `tests/unit/optics_preparation_test.zig`, `tests/validation/o2a_forward_shape_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add line-gas family validation.
  - O2A: verify trough depth, line density, and CIA toggle sensitivity.
  - Non-O2 line-gas cases: add at least one H2O/NH3 case and one CO2/H2O or O2+CO2+H2O pressure case from the vendor corpus.
  - Add tests that changing isotope selection or threshold/cutoff changes the prepared spectroscopy and downstream spectrum.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] O2 line-mixing and isotope controls are represented explicitly
- [ ] Adaptive strong-line sampling exists and is used in execution
- [ ] At least one non-O2 line-gas family case passes the validation harness

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

Vendor line-gas parity is not just “read HITRAN.” It is the combination of gas controls, line selection, adaptive grid refinement, and the way those feed transport. Capturing those pieces explicitly lets O2A improve for real reasons and prevents the architecture from ossifying around one forcing case.

## Proof / Validation

- Planned: `zig test tests/validation/o2a_forward_shape_test.zig` -> O2A line structure and trough depth move toward vendor behavior
- Planned: `zig test tests/unit/optics_preparation_test.zig` -> line controls change prepared cross sections and grids as expected
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> line-gas example configs are classified and executed with the correct gas controls

## How To Test

1. Run the O2-with-CIA and O2-without-CIA vendor cases and compare the radiance and reflectance overlays.
2. Toggle line-mixing factor and isotope selection in a controlled test config and confirm the spectrum changes.
3. Run one H2O/NH3 or CO2/H2O vendor-like case and confirm the same line-gas path is used without O2-specific assumptions.
4. Inspect the generated HR grid and verify strong-line refinement happens near the strongest lines only.
