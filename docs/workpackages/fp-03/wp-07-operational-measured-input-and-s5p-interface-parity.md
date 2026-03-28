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

### WP-07 Operational measured-input and S5P interface parity [Status: Done 2026-03-28]

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
This landed immediately after instrument parity because it depends on the corrected measurement-grid and correction semantics from `WP-06`, and it needed to land before any broader operational or mission-parity claims could be made honestly.

Desired outcome:
A mission-style or operational caller can provide measured radiance/irradiance and replacement assets through typed APIs, and the Zig runtime can execute them without abusing the static-scene path.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-transport --summary all`
- `zig build test-validation --summary all`
- `zig build test-fast --summary all`
- `zig build check --summary all`

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
  - `build.zig`
  - `tests/integration/mission_s5p_integration_test.zig`
  - `tests/unit/adapter_ingest_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`

## Exact Patch Checklist

- [x] `src/adapters/ingest/spectral_ascii.zig`, `spectral_ascii_metadata.zig`, `spectral_ascii_runtime.zig`: represent measured radiance/irradiance inputs as typed runtime artifacts.
  - Vendor anchors: `readIrrRadFromFileModule.f90::{readIrrRadFromFile,readIrrRadPostProcess}`.
  - Parse measured-grid metadata, SNR-like information, and band-specific instrument descriptors into a struct that the runtime can consume directly.
  - Do not reduce measured inputs to “external spectrum file path + maybe noise.”

- [x] `src/core/Request.zig`, `src/core/Plan.zig`, `src/core/Engine.zig`: add a distinct operational/measured-input execution mode.
  - Vendor anchors: `S5PInterfaceModule.f90::{setInputGeneric,setInputBand,prepare,retrieve}` and `S5POperationalModule.f90::replaceDynamicData`.
  - The prepared plan should know whether it is executing a synthetic scene or an operational measured-input case.
  - Use typed handles or owned views for measured spectra instead of raw pointers with ambiguous lifetime.

- [x] `src/model/Instrument.zig`, `src/model/ObservationModel.zig`, `src/plugins/providers/instrument.zig`: support band-level replacement of ISRF, HR wavelength data, and reference assets.
  - Vendor anchors: `S5POperationalModule.f90::{replaceXSecLUTData,replaceHRWavelengthData,replaceISRFData}`.
  - Keep replacement operations explicit and band-scoped; do not let one late replacement silently rewrite unrelated bands.

- [x] `src/adapters/missions/s5p/root.zig`: turn the current mission adapter into a real operational bridge instead of just preset metadata.
  - Vendor anchors: `S5PInterfaceModule.f90::initialize` and `S5POperationalModule.f90` workflow.
  - Add typed mission presets for input band setup, dynamic replacement, and expected outputs, but keep them layered on top of the generic engine.

- [x] `tests/unit/adapter_ingest_test.zig`, `tests/integration/mission_s5p_integration_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`: validate operational flows.
  - Add at least one measured-radiance/irradiance ingestion test and one S5P-style replacement test.
  - Confirm that runtime replacement actually changes the executed plan and that provenance records the replaced assets.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Measured radiance/irradiance are first-class typed inputs
- [x] Band-level operational replacement of ISRF/HR/LUT data is explicit and testable
- [x] At least one S5P-style integration flow runs end-to-end

## Implementation Status (2026-03-28)

Implemented. Measured radiance/irradiance ingestion now materializes typed `MeasuredInput` and per-band `OperationalBandSupport` artifacts, the core request/plan/result path now carries an explicit `operational_measured_input` execution mode, S5P mission wiring now builds a real measured-input request instead of only preset metadata, focused validation covers typed ingest, end-to-end operational execution, and compatibility-harness classification, and the final post-review hardening both rejects malformed inactive HR-grid controls and removes duplicated legacy-carrier clones so operational measured-input requests keep band support as the single source of truth.

## Why This Works

Operational parity is not a thin wrapper around the static forward model. The implemented path keeps measured spectra and band-scoped replacement assets as typed owned values from ingest through execution, so the runtime can reject unsupported or inconsistent operational inputs instead of silently falling back to the synthetic-scene path. The explicit execution mode and provenance annotations make the operational path visible in request planning, mission adapters, and validation output without recreating the vendor's global mutable state.

## Proof / Validation

- `zig build test-unit --summary all` -> passed (`161/161`); includes the measured-input ingest/runtime ownership coverage plus the new request-drift regression in `tests/unit/adapter_ingest_test.zig`
- `zig build test-transport --summary all` -> passed (`180/180`); covers the focused transport/O2A aggregate and now includes the operational measured-input compatibility shard
- `zig build test-validation --summary all` -> passed (`48/48`); proves the full validation aggregate, including the new operational measured-input classification shard wired into `build.zig`
- `zig build test-fast --summary all` -> passed (`196/196`)
- `zig build check --summary all` -> passed (`161/161`)

Note:
The original planning note used raw `zig test tests/...` commands, but this repo wires test modules through `build.zig`. The completed proof uses the equivalent `zig build` suite steps so the required module imports and the new operational-classification harness step are reproducible.

Final review follow-up:
The latest PR-review hardening commits tightened `Instrument.OperationalBandSupport.validate()` so negative or one-sided high-resolution grid controls fail even when no other operational replacement is enabled (`add6c3a`), then removed redundant top-level operational carrier clones from the measured-input builders so `operational_band_support` is the single runtime source of truth on that path (`d002448`). Both follow-ups reran `zig build test-fast --summary all` (`196/196`) and `zig build check --summary all` (`161/161`) on the updated heads.

## How To Test

1. Run `zig build test-unit --summary all` and confirm the typed ingest suite passes, especially the measured-input artifact, allocation-failure cleanup, and request-drift checks in `tests/unit/adapter_ingest_test.zig`.
2. Run `zig build test-transport --summary all` and confirm the focused transport/O2A aggregate passes, including the operational measured-input compatibility classification shard.
3. Run `zig build test-validation --summary all` and confirm the full validation aggregate passes with the operational measured-input shard included in the current `build.zig` wiring.
4. Run `zig build test-fast --summary all` and `zig build check --summary all` to confirm the presubmit and baseline repo lanes still pass on the same tree.
5. Run `zig build check --summary all` as the final repo baseline.
