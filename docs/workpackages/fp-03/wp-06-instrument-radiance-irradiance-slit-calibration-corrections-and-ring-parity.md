# WP-06 Instrument, Radiance/Irradiance, Slit, Calibration, Corrections, And Ring Parity

## Metadata

- Created: 2026-03-18
- Scope: match vendor instrument semantics including separate radiance/irradiance slit handling, wavelength shifts, calibration errors, noise, Raman/Ring additions, offsets, stray light, smear, and reflectance normalization/order of operations
- Input sources:
  - vendor `readConfigFileModule.f90::{readInstrument,readMulOffset,readStrayLight,readRRS_Ring,readReferenceData}`
  - vendor `radianceIrradianceModule.f90`
  - vendor `calibrateIrradianceModule.f90`
  - vendor `ramanspecsModule_v2.f90`
  - vendor measured-spectra and instrument example configs
  - Zig instrument, spectra, measurement-space, and provider files
- Dependencies:
  - `WP-01` for config surface parity
  - `WP-02` through `WP-05` for forward-atmosphere correctness
- Reference baseline:
  - vendor `radianceIrradianceModule.f90::{integrateSlitFunctionIrr,integrateSlitFunctionRad,convoluteSlitFunction,specifyNoise,calcSNR_S5,calcLAB_SNR,fillReferenceSpectrum,addSpecFeaturesIrr,addSpecFeaturesRad,addSimpleOffsets,addSmear,addMulOffset,addStraylight,ignorePolarizationScrambler,addRingSpec,fillReflectanceSim,fillReflectanceRetr,fillReflCalibrationError}`
  - vendor `calibrateIrradianceModule.f90::{readIrrRadFromFile,setupHRWavelengthGridIrr}`
  - vendor `ramanspecsModule_v2.f90::{ConvoluteSpecRaman,ConvoluteSpecRamanMS}`

## Background

Even after the forward core improves, parity will still miss if instrument and correction semantics are wrong. The vendor config distinguishes radiance and irradiance slit functions, wavelength shifts, calibration errors, SNR models, ring terms, simple offsets, multiplicative offsets, stray light, and smear. This WP makes that entire post-RT chain explicit and order-correct.

## Overarching Goals

- Match the vendor order of operations from HR spectra to instrument-grid outputs.
- Support radiance/irradiance-specific slit and calibration controls.
- Make noise and correction terms physically and numerically explicit rather than hidden heuristics.

## Non-goals

- Retrieval-family-specific fit logic.
- S5P measured-input replacement; that is `WP-07`.
- Treating reflectance normalization as a cosmetic exporter transformation.

### WP-06 Instrument, radiance/irradiance, slit, calibration, corrections, and Ring parity [Status: Todo]

Issue:
The current Zig measurement-space path still mixes physical and synthetic shaping and does not yet match the vendor order of operations for instrument convolution, calibration, offsets, stray light, ring terms, and reflectance formation.

Needs:
- separate sim/retr and radiance/irradiance instrument controls
- explicit ordering for slit integration, corrections, calibration, noise, and normalization
- typed correction families instead of ad hoc flags
- reflectance normalization that is physically trustworthy

How:
1. Extract a strict spectral processing pipeline from the vendor modules.
2. Encode each stage as a typed measurement-space/instrument step in Zig.
3. Keep the sequence explicit: HR source -> slit/instrument integration -> corrections/calibration -> noise -> reflectance/derived fields.
4. Validate with O2A and at least one measured-spectra or Ring-sensitive case.

Why this approach:
The vendor code performs many post-RT transformations that materially affect observables. Matching only the RT core without matching this order will still produce the wrong instrument-level spectra.

Recommendation rationale:
This follows the atmosphere-facing WPs because the instrument pipeline consumes their outputs, but it must land before measured-input and retrieval parity.

Desired outcome:
A developer can point to one clear Zig measurement-space pipeline and show where each vendor instrument/correction control enters, in the same broad order the vendor code uses.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration --summary all`
- `zig build test-validation --summary all`
- `zig test tests/integration/forward_model_integration_test.zig`
- `zig test tests/validation/o2a_forward_shape_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Instrument/model targets:
  - `src/model/Instrument.zig`
  - `src/model/ObservationModel.zig`
  - `src/model/instrument/line_shape.zig`
  - `src/model/instrument/solar_spectrum.zig`
  - `src/model/instrument/reference_grid.zig`
- Measurement-space/spectra targets:
  - `src/kernels/transport/measurement_space.zig`
  - `src/kernels/spectra/convolution.zig`
  - `src/kernels/spectra/calibration.zig`
  - `src/kernels/spectra/noise.zig`
- Provider/config targets:
  - `src/plugins/providers/instrument.zig`
  - `src/plugins/providers/noise.zig`
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
- Validation targets:
  - `tests/integration/forward_model_integration_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/model/Instrument.zig`, `src/model/ObservationModel.zig`, `src/adapters/canonical_config/Document.zig`: represent vendor instrument controls explicitly and separately for radiance and irradiance.
  - Vendor anchors: `readInstrument` subsections `wavelength_range`, `slit_index`, `slit_parameters`, `wavelShift`, `addGaussianNoise`, `SNR_irradiance`, `SNR_radiance`, `polScrambler`, `calibrationErrorRefl`, `sinusoidal_features`, `smear`, plus `readReferenceData`.
  - Do not collapse `slit_index_irradiance_*` and `slit_index_radiance_*` or the separate FWHM/amplitude/scale/phase parameters into one generic “instrument response.”

- [ ] `src/kernels/transport/measurement_space.zig`, `src/kernels/spectra/convolution.zig`, `src/plugins/providers/instrument.zig`: implement a strict order-of-operations pipeline.
  - Vendor anchors: `radianceIrradianceModule.f90::{integrateSlitFunctionIrr,integrateSlitFunctionRad,convoluteSlitFunction,fillReferenceSpectrum}`.
  - Keep the stages explicit. A useful sequence is:
    ```text
    prepare HR solar/radiance -> instrument-grid integration (irr/rad separately)
    -> apply calibration/wavelength-shift semantics
    -> apply Ring / multiplicative offset / stray-light / smear terms
    -> apply noise / derive reflectance and related products
    ```
  - Reflectance should be derived from physically consistent radiance and irradiance, not from a surrogate convenience ratio.

- [ ] `src/kernels/spectra/noise.zig` and `src/plugins/providers/noise.zig`: align noise semantics with vendor SNR models.
  - Vendor anchors: `radianceIrradianceModule.f90::{specifyNoise,calcSNR_S5,calcLAB_SNR}`.
  - Add explicit branches for vendor-like S5 and LAB SNR modes; avoid magic constants hidden in providers.
  - Honor per-band and per-channel inputs if present.

- [ ] `src/kernels/spectra/calibration.zig`, `src/kernels/transport/measurement_space.zig`: implement Ring, simple offsets, multiplicative offsets, stray light, smear, and calibration-error semantics as first-class steps.
  - Vendor anchors: `radianceIrradianceModule.f90::{addSpecFeaturesIrr,addSpecFeaturesRad,addSimpleOffsets,addSmear,fillRadianceAtMulOffsetNodes,fillRadianceAtStrayLightNodes,addMulOffset,addStraylight,ignorePolarizationScrambler,addRingSpec,fillReflCalibrationError}`.
  - Keep each effect toggleable and traceable in diagnostics. Do not bury them in one giant “measurement correction” helper.

- [ ] `src/model/instrument/line_shape.zig`, `src/model/instrument/solar_spectrum.zig`, `src/kernels/spectra/convolution.zig`: match vendor slit and irradiance-grid preparation assumptions.
  - Vendor anchors: `calibrateIrradianceModule.f90::setupHRWavelengthGridIrr`; `readIrrRadFromFileModule.f90::{setupHRWavelengthGridIrr,setMRWavelengthGrid}`.
  - This is where wavelength-node and slit-grid parity must be tightened, not later in exporters.

- [ ] `tests/integration/forward_model_integration_test.zig`, `tests/validation/o2a_forward_shape_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: add order-sensitive validation.
  - Confirm radiance-vs-irradiance slit differences affect outputs when configured.
  - Confirm Ring, stray-light, and multiplicative offset controls change the correct output products.
  - Add at least one case where turning a correction off restores the expected baseline.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Radiance and irradiance instrument controls are represented separately
- [ ] Reflectance normalization is physically consistent and no longer exceeds expected bounds for the wrong reason
- [ ] Ring/offset/stray-light/smear terms are explicit, typed, and testable

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

The vendor instrument chain is not just convolution. It is a sequence of distinct, configurable effects that can move the final spectrum noticeably. Making that sequence explicit in Zig turns hidden shaping into auditable instrument semantics.

## Proof / Validation

- Planned: `zig test tests/integration/forward_model_integration_test.zig` -> instrument-grid outputs respond correctly to slit, shift, and correction controls
- Planned: `zig test tests/validation/o2a_forward_shape_test.zig` -> reflectance and radiance are normalized consistently without spurious >1 behavior from bad bookkeeping
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> vendor instrument/correction sections map to typed runtime controls

## How To Test

1. Run the O2A case with vendor-like slit parameters and compare radiance, irradiance, and reflectance outputs.
2. Toggle Ring, stray-light, and multiplicative offset terms one at a time and confirm the correct stage changes.
3. Run one case with different radiance-vs-irradiance slit definitions and confirm the separation is honored.
4. Inspect provenance/diagnostics to ensure every enabled correction term is listed explicitly.
