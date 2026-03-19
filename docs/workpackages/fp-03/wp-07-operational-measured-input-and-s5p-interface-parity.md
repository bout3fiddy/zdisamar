# WP-07 Operational Measured-Input And S5P Interface Parity

## Metadata

- Created: 2026-03-18
- Scope: support vendor-style measured radiance/irradiance ingestion, dynamic replacement of operational data products, and S5P interface workflows
- Input sources:
  - vendor `S5POperationalModule.f90`
  - vendor `S5PInterfaceModule.f90`
  - vendor `readIrrRadFromFileModule.f90`
  - vendor measured-input and operational example configs
  - Zig ingest, mission, instrument, and request/result code
- Dependencies:
  - `WP-01` and `WP-06`
- Reference baseline:
  - vendor `S5POperationalModule.f90::{readIrrRadFromMemory,replaceXSecLUTData,replaceHRWavelengthData,replaceISRFData,replaceDynamicData}`
  - vendor `S5PInterfaceModule.f90::{initialize,setInputGeneric,setInputBand,prepare,retrieve,getOutput}`
  - vendor `readIrrRadFromFileModule.f90::{readIrrRadFromFile,readIrrRadPostProcess,setupHRWavelengthGridIrr,setMRWavelengthGrid}`

## Background

The vendor system is not only a forward simulator from static configs. It also supports operational ingestion and dynamic replacement of measured spectra, cross-section LUT data, ISRF data, and other band-specific state. If Zig is going to be a full replacement, it must support those workflows rather than only synthetic scenes.

## Overarching Goals

- Support measured radiance/irradiance ingestion as first-class input.
- Support dynamic operational replacement of band-specific data products.
- Expose a typed interface for mission-style workflows without hard-wiring global state.

## Non-goals

- Recreating the Fortran global mutable operational state.
- Hiding measured-input semantics behind the same API as purely synthetic scenes.
- Implementing mission-specific retrieval families in this WP.

### WP-07 Operational measured-input and S5P interface parity [Status: Todo]

Issue:
Current Zig workflows are still heavily synthetic-scene oriented. The vendor code supports operational use cases where measured spectra and dynamic support data replace static inputs late in the pipeline.

Needs:
- explicit measured-input carriers for radiance, irradiance, ISRF, and dynamic support data
- mission-style request/plan plumbing
- runtime replacement hooks for per-band assets
- validation on at least one operational-style example path

How:
1. Model measured input as distinct typed artifacts, not as optional strings stuffed into scene config.
2. Add mission/operational replacement hooks that mutate prepared plan inputs safely and explicitly.
3. Keep per-band replacement and band setup visible in the request/plan/result APIs.
4. Validate with S5P-style flows and ingested spectra.

Why this approach:
The vendor operational path treats measured inputs and replacement data as a distinct execution mode. Zig should do the same instead of pretending everything is just another static YAML scene.

Recommendation rationale:
This follows instrument parity because it depends on correct instrument-grid semantics, but it should land before broad operational case claims or full mission adapters.

Desired outcome:
A mission-style or operational caller can provide measured radiance/irradiance and replacement assets through typed APIs, and the Zig runtime can execute them without abusing the static-scene path.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration --summary all`
- `zig test tests/integration/mission_s5p_integration_test.zig`
- `zig test tests/unit/adapter_ingest_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Ingest/mission targets:
  - `src/adapters/ingest/spectral_ascii.zig`
  - `src/adapters/ingest/spectral_ascii_metadata.zig`
  - `src/adapters/ingest/spectral_ascii_runtime.zig`
  - `src/adapters/missions/s5p/root.zig`
- Model/request/result targets:
  - `src/model/Instrument.zig`
  - `src/model/ObservationModel.zig`
  - `src/core/Request.zig`
  - `src/core/Result.zig`
  - `src/core/Plan.zig`
  - `src/core/Engine.zig`
- Provider/runtime targets:
  - `src/plugins/providers/instrument.zig`
  - `src/plugins/providers/noise.zig`
  - `src/runtime/reference/BundledOptics.zig`
- Validation targets:
  - `tests/integration/mission_s5p_integration_test.zig`
  - `tests/unit/adapter_ingest_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [ ] `src/adapters/ingest/spectral_ascii.zig`, `spectral_ascii_metadata.zig`, `spectral_ascii_runtime.zig`: represent measured radiance/irradiance inputs as typed runtime artifacts.
  - Vendor anchors: `readIrrRadFromFileModule.f90::{readIrrRadFromFile,readIrrRadPostProcess}`.
  - Parse measured-grid metadata, SNR-like information, and band-specific instrument descriptors into a struct that the runtime can consume directly.
  - Do not reduce measured inputs to “external spectrum file path + maybe noise.”

- [ ] `src/core/Request.zig`, `src/core/Plan.zig`, `src/core/Engine.zig`: add a distinct operational/measured-input execution mode.
  - Vendor anchors: `S5PInterfaceModule.f90::{setInputGeneric,setInputBand,prepare,retrieve}` and `S5POperationalModule.f90::replaceDynamicData`.
  - The prepared plan should know whether it is executing a synthetic scene or an operational measured-input case.
  - Use typed handles or owned views for measured spectra instead of raw pointers with ambiguous lifetime.

- [ ] `src/model/Instrument.zig`, `src/model/ObservationModel.zig`, `src/plugins/providers/instrument.zig`: support band-level replacement of ISRF, HR wavelength data, and reference assets.
  - Vendor anchors: `S5POperationalModule.f90::{replaceXSecLUTData,replaceHRWavelengthData,replaceISRFData}`.
  - Keep replacement operations explicit and band-scoped; do not let one late replacement silently rewrite unrelated bands.

- [ ] `src/adapters/missions/s5p/root.zig`: turn the current mission adapter into a real operational bridge instead of just preset metadata.
  - Vendor anchors: `S5PInterfaceModule.f90::initialize` and `S5POperationalModule.f90` workflow.
  - Add typed mission presets for input band setup, dynamic replacement, and expected outputs, but keep them layered on top of the generic engine.

- [ ] `tests/unit/adapter_ingest_test.zig`, `tests/integration/mission_s5p_integration_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: validate operational flows.
  - Add at least one measured-radiance/irradiance ingestion test and one S5P-style replacement test.
  - Confirm that runtime replacement actually changes the executed plan and that provenance records the replaced assets.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Measured radiance/irradiance are first-class typed inputs
- [ ] Band-level operational replacement of ISRF/HR/LUT data is explicit and testable
- [ ] At least one S5P-style integration flow runs end-to-end

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

Operational parity is not a thin wrapper around the static forward model. The vendor code clearly separates measured-input setup, per-band replacement, and retrieval execution. This WP gives Zig the same capability without inheriting the Fortran global-state design.

## Proof / Validation

- Planned: `zig test tests/unit/adapter_ingest_test.zig` -> measured-input artifacts parse into typed runtime structures
- Planned: `zig test tests/integration/mission_s5p_integration_test.zig` -> band-level operational replacement and execution succeed end-to-end
- Planned: `zig test tests/validation/disamar_compatibility_harness_test.zig` -> operational example configs are classified and mapped correctly

## How To Test

1. Ingest a measured radiance/irradiance file and inspect the typed runtime artifact.
2. Run an S5P-style case with replacement ISRF or HR grid data and confirm the plan provenance changes.
3. Compare outputs with and without a replacement asset to ensure the new data is actually used.
4. Confirm lifetime/ownership of measured inputs survives the full execution path.
