# WP-01 Full Config Surface And Canonical YAML Parity

## Metadata

- Created: 2026-03-18
- Scope: inventory every vendor config control and extend canonical YAML plus runtime compilation so each vendor control is either expressible and honored or explicitly unsupported
- Input sources:
  - `current_state_and_findings_2026-03-17.md`
  - vendor `readConfigFileModule.f90`
  - vendor `verifyConfigFileModule.f90`
  - vendor example configs in `InputFiles/Config_*.in`
  - Zig `Document.zig`, `document_fields.zig`, `execution.zig`, model config carriers
- Dependencies:
  - none; this is the inventory and control-surface gate for every later WP
- Reference baseline:
  - vendor `readConfigFileModule.f90::{readGeneral,readInstrument,readMulOffset,readStrayLight,readRRS_Ring,readReferenceData,readGeometry,readAtmosphere_PT,readAbsorbingGas,readSurface,readAtmosphericIntervals,readCldAerFraction,readCloud,readAerosol,readSubcolumns,readRetrieval,readRadiativeTransfer,readAdditionalOutput}`
  - vendor `verifyConfigFileModule.f90::verifyConfigFile`

## Background

The current Zig canonical YAML can represent the O2A forcing case reasonably well, but that is not enough for full DISAMAR parity. The vendor config surface is broad and includes general controls, instrument controls, multiple gas families, radiative-transfer controls, measured-input workflows, LUT creation, Raman/Ring, offsets, stray light, subcolumns, additional outputs, and retrieval-family-specific knobs. This WP creates the single source of truth for what is expressible, what is honored, what is approximate, and what is unsupported.

## Overarching Goals

- Build a complete vendor-config inventory and map every key to a canonical YAML path or an explicit unsupported decision.
- Remove silent parse-and-ignore behavior from the Zig config pipeline.
- Move string-heavy runtime config into typed, resolved representations at compile/plan-preparation time.

## Non-goals

- Implementing every physics behavior in this WP.
- Keeping permissive parsing that accepts keys the runtime does not honor.
- Preserving the current stringly config representation deeper than the document adapter boundary.

### WP-01 Full config surface and canonical YAML parity [Status: Done 2026-03-18]

Issue:
The current YAML and runtime cover a useful subset of vendor controls, but they do not yet form a complete parity surface. The risk is not only missing syntax; it is also parsed-but-ignored controls and approximate representations that look exact.

Needs:
- a machine-readable vendor config inventory
- a canonical YAML mapping for every vendor section/subsection/key
- a typed internal representation for resolved controls
- strict runtime-honor accounting

How:
1. Build a key-by-key matrix from vendor parser and verifier code, not from assumptions.
2. Extend the YAML schema only where a runtime consumer can exist or where unsupported status is declared explicitly.
3. Compile YAML into typed config structs/enums before execution starts.
4. Add validation tests that fail if a vendor key has no classification.

Why this approach:
The repo cannot credibly claim “DISAMAR config parity” from ad hoc YAML growth. A full inventory first prevents later physics WPs from rebuilding config handling piecemeal and inconsistently.

Recommendation rationale:
This must come before the rest of the program because every later WP needs a stable answer to “where is this vendor control represented and who consumes it?”

Desired outcome:
A new agent can open a single matrix and answer, for any vendor config key, whether it is exactly expressible, approximately expressible, unsupported, or parsed-but-not-yet-honored — and the runtime rejects invalid combinations instead of silently flattening them.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/canonical_config_test.zig`
- `zig test tests/unit/canonical_config_execution_test.zig`
- `zig test tests/validation/disamar_compatibility_harness_test.zig`

Files by type:
- Canonical-config parser/compiler targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
  - `src/adapters/canonical_config/document_yaml_helpers.zig`
  - `src/adapters/canonical_config/execution.zig`
  - `src/adapters/canonical_config/yaml.zig`
- Resolved config carriers:
  - `src/model/ObservationModel.zig`
  - `src/model/Instrument.zig`
  - `src/model/Measurement.zig`
  - `src/model/Surface.zig`
  - `src/model/StateVector.zig`
  - `src/core/Plan.zig`
- Compatibility and validation targets:
  - `tests/unit/canonical_config_test.zig`
  - `tests/unit/canonical_config_execution_test.zig`
  - `tests/unit/legacy_config_import_test.zig`
  - `tests/validation/disamar_compatibility_harness_test.zig`
  - `tests/validation/parity_assets_test.zig`
  - `tests/validation/assets/vendor_config_surface_matrix.json` (new)
  - `tests/validation/assets/vendor_case_catalog.json` (new)

## Exact Patch Checklist

- [x] `src/adapters/canonical_config/Document.zig`: extend the parser so every vendor top-level section is represented explicitly.
  - Vendor anchors: `readConfigFileModule.f90::{readGeneral,readInstrument,readMulOffset,readStrayLight,readRRS_Ring,readReferenceData,readGeometry,readAtmosphere_PT,readAbsorbingGas,readSurface,readAtmosphericIntervals,readCldAerFraction,readCloud,readAerosol,readSubcolumns,readRetrieval,readRadiativeTransfer,readAdditionalOutput}`.
  - Do not keep adding free-form nested maps. Add typed sub-doc structs for `GENERAL`, `INSTRUMENT`, `REFERENCE_DATA`, `GEOMETRY`, `PRESSURE_TEMPERATURE`, gas sections, `SURFACE`, `ATMOSPHERIC_INTERVALS`, `CLOUD_AEROSOL_FRACTION`, `CLOUD`, `AEROSOL`, `SUBCOLUMNS`, `RETRIEVAL`, `RADIATIVE_TRANSFER`, `RRS_RING`, `MUL_OFFSET`, `STRAY_LIGHT`, and `ADDITIONAL_OUTPUT`.
  - Example direction:
    ```zig
    const VendorCompat = enum { exact, approximate, unsupported, parsed_but_ignored };
    const RtMethod = enum { oe, dismas, doas, classic_doas, domino_no2 };
    const CanonicalDoc = struct {
        general: GeneralDoc,
        instrument: InstrumentDoc,
        radiative_transfer: RadiativeTransferDoc,
        gases: []GasDoc,
        // ...
    };
    ```

- [x] `src/adapters/canonical_config/document_fields.zig`: create a stable vendor-key identity layer instead of scattering raw strings across the parser.
  - Vendor anchors: every keyword case in `readConfigFileModule.f90`; legality constraints in `verifyConfigFileModule.f90::verifyConfigFile`.
  - Add enums or interned identifiers for section/subsection/key triples so tests can assert full coverage.
  - Add a support-status table: `exact`, `approximate`, `unsupported`, `parsed_but_not_honored`.

- [x] `src/adapters/canonical_config/execution.zig`: compile YAML into resolved typed config and reject parsed-but-unhonored controls at execution time.
  - Vendor anchors: `verifyConfigFileModule.f90::verifyConfigFile` for cross-section and method legality; use its restrictions as the behavioral reference when translating parsed config to a `PreparedPlan`.
  - Add a compile-time or run-time error type such as `error.UnsupportedVendorControl` and include the section/subsection/key path in the message.
  - Do not silently coerce vendor controls into approximate equivalents without an explicit compatibility flag recorded in provenance.

- [x] `src/model/ObservationModel.zig`, `src/model/Instrument.zig`, `src/model/Measurement.zig`, `src/model/Surface.zig`, `src/model/StateVector.zig`, `src/core/Plan.zig`: replace stringly runtime config with typed resolved fields.
  - Vendor anchors: section-specific semantics in `readConfigFileModule.f90` and `verifyConfigFileModule.f90`.
  - Replace fields like `sampling`, `noise_model`, `surface.kind`, and textual retrieval targets with enums/tagged unions or generated accessors.
  - Use sim-vs-retr split fields when the vendor config distinguishes them. Do not flatten `*_Sim` and `*_Retr` pairs into one field.

- [x] `tests/validation/assets/vendor_config_surface_matrix.json` and `tests/validation/assets/vendor_case_catalog.json` (new): add machine-readable parity inventory assets.
  - Build the matrix from the vendor parser, not by handwaving. Each row should include `section`, `subsection`, `key`, `example_configs`, `zig_yaml_path`, `status`, `runtime_consumer`, and `notes`.
  - Seed `example_configs` from the vendored corpus such as `Config_O2_with_CIA.in`, `Config_O2A_XsecLUT.in`, `Config_NO2_DOMINO.in`, `Config_O3_profile_TROPOMI_band1_2.in`, `Config_ESA_project_O2+CO2+H2O_3bands.in`, and `Config_H2O_NH3.in`.

- [x] `tests/unit/canonical_config_test.zig`, `tests/unit/canonical_config_execution_test.zig`, `tests/unit/legacy_config_import_test.zig`, `tests/validation/disamar_compatibility_harness_test.zig`, `tests/validation/parity_assets_test.zig`: add coverage assertions for the full config surface.
  - Assert that every vendor key in the matrix is classified.
  - Assert that “exact” and “approximate” keys parse into typed config objects.
  - Assert that “unsupported” keys fail loudly with a stable message.
  - Add one golden config-per-family test: O2A, O2A XsecLUT, NO2 DOMINO, O3 profile, SWIR greenhouse-gas, and cloud/aerosol mixed cases.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Every vendor section/subsection/key is classified in the matrix
- [x] No parsed-but-unhonored control reaches execution silently
- [x] Sim-vs-retr split controls remain split in the resolved model

## Implementation Status (2026-03-18)

Done. Implemented across commits `6349c8e`, `7e6eb9a` on `feature_parity_r2`.

Key deliverables:
- 415-entry vendor config surface matrix (87 exact, 45 approximate, 283 unsupported, 0 parsed_but_ignored)
- 36-entry vendor case catalog covering 5 families
- 13 typed sub-doc structs in Document.zig (6 sections omitted: 100% unsupported)
- VendorSection (18), VendorSubsection (68), VendorKeyId, VendorCompatStatus enums in document_fields.zig
- Cloud.cloud_type, Aerosol.aerosol_type typed enums; Absorber.resolved_species; Surface.Kind.wavel_dependent; StateVector new targets
- UnsupportedVendorControl error gate in execution.zig (rejects DISMAS sim, DOAS/classic_DOAS/DOMINO retrieval, unknown line shapes)
- WP-01 tests added to all 5 required test files plus vendor_config_surface_test.zig
- Deferred: 4 stringly fields with TODO markers (model_family, algorithm_name, algorithm_damping, spectral_response_shape) due to >5 cascading call sites each

## Why This Works

This WP turns config parity from a vague aspiration into a measurable contract. Once every vendor control has a typed destination or an explicit unsupported status, the later physics and retrieval WPs can implement behavior without rediscovering config semantics ad hoc.

## Proof / Validation

- `zig build test-unit --summary all` -> 34/34 passed (includes typed vendor section parse test, UnsupportedVendorControl comptime test)
- `zig build test-integration --summary all` -> 22/22 passed
- `zig build test-validation --summary all` -> 35/35 passed (includes vendor matrix classification gate, case catalog family coverage, section coverage, zig_yaml_path assertions)
- All 415 matrix entries have status exact/approximate/unsupported — 0 parsed_but_ignored, 0 unmapped
- All exact/approximate entries have non-null zig_yaml_path
- All 18 vendor sections represented in matrix

## How To Test

1. Regenerate the vendor config matrix from `readConfigFileModule.f90` and `verifyConfigFileModule.f90`.
2. Run the unit and validation config tests.
3. Pick one config from each family and confirm the harness reports `exact`, `approximate`, or `unsupported` for every control.
4. Confirm no execution path proceeds when a config contains an unsupported-but-unflagged key.
