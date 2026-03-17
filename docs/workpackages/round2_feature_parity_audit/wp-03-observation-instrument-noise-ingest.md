# WP-03 Observation Model, Instrument, Noise, and Ingest Parity

## Metadata

- Created: 2026-03-16
- Scope: resolve observation/instrument/noise semantics once and wire ingested operational inputs all the way into execution
- Input sources: audit sections `Model`, `Spectra, linalg, interpolation, quadrature, polarization`, `Plugins`, `Adapters and I/O`
- Dependencies:
  - `WP-01` for strict binding and sigma semantics
  - `WP-02` for a repaired forward path that can consume the richer observation model
- Reference baseline: vendored operational O2 A-band measured-channel, slit-function, solar-spectrum, and SNR workflows

## Background

The current repo already has strong typed carriers for line shape, reference grids, solar spectra, and operational cross-section LUTs. The audit's complaint is not that these carriers are missing. It is that too much of the observation model is still stringly in core state and too much of the ingested/measured metadata is parsed but not consumed downstream by the forward and noise providers.

## Overarching Goals

- Parse observation/instrument/noise selectors once at the edge and store resolved forms in core state.
- Use ingested measured-channel, ISRF, solar, reference-grid, and SNR inputs all the way through execution.
- Make the surface provider physically meaningful and the noise provider operationally useful.
- Keep the strong typed data-carrier modules as the stable backbone of this area.

## Non-goals

- Reworking transport physics beyond the observation-model interfaces needed by `WP-02`.
- Implementing retrieval numerics beyond the measurement semantics needed by `WP-04` and `WP-05`.
- Adding new mission adapters beyond the current S5P path.

### WP-03 Observation model, instrument, noise, and ingest parity [Status: Done 2026-03-16]

Issue:
Observation-model configuration is still too string-heavy in the core, and several operational/measured inputs are parsed but not actually consumed by the runtime path that needs them.

Needs:
- resolved instrument/sampling/noise/surface config in core state
- end-to-end measured-channel, table-ISRF, solar-spectrum, reference-grid, LUT, and SNR consumption
- physically meaningful Lambertian surface semantics
- one source of truth for sigma semantics

How:
1. Resolve string selectors into enums/tagged config at canonical-config/ingest boundaries.
2. Thread measured-channel and operational support data into `ObservationModel` and provider contracts.
3. Deepen instrument, surface, and noise providers so they consume the resolved state directly.
4. Split oversized ingest modules by concern so the data flow is easier to maintain and validate.

Why this approach:
The repo already has good data carriers. The main missing work is to stop treating them as optional sidecars and instead make them the runtime source of truth.

Recommendation rationale:
This WP landed after the forward baseline was repaired, because the remaining parity gap was no longer “physics first” but “make the operational/measured inputs actually survive into runtime behavior.” The patch set now resolves selectors once, carries measured radiance/irradiance support data through execution, corrects slight irradiance/radiance grid drift with modeled-solar ratios, and makes `s5p_operational` noise depend on reference radiance plus spectral-bin width rather than silently aliasing `snr_from_input`.

Desired outcome:
Measured-channel paths, table-driven ISRF, operational solar/reference-grid replacements, and SNR-from-input all survive parsing and materially affect the executed forward/noise path. Instrument and surface semantics are resolved once and are no longer rebuilt from strings inside hot code.

Non-destructive tests:
- `zig build test-unit`
- `zig build test-integration`
- Add/update focused tests for:
  - parsed observation-model selectors resolving to enums/tagged config
  - measured-channel integration kernels
  - table-driven ISRF application
  - operational solar/reference-grid replacement
  - ingested SNR reaching the noise provider

Files by type:
- Model:
  - `src/model/Instrument.zig`
  - `src/model/ObservationModel.zig`
  - `src/model/Surface.zig`
  - `src/model/instrument/line_shape.zig`
  - `src/model/instrument/reference_grid.zig`
  - `src/model/instrument/solar_spectrum.zig`
  - `src/model/instrument/cross_section_lut.zig`
- Providers and spectra:
  - `src/plugins/providers/instrument.zig`
  - `src/plugins/providers/surface.zig`
  - `src/plugins/providers/noise.zig`
  - `src/kernels/spectra/calibration.zig`
  - `src/kernels/spectra/convolution.zig`
  - `src/kernels/spectra/grid.zig`
  - `src/kernels/spectra/noise.zig`
- Adapters:
  - `src/adapters/ingest/spectral_ascii.zig`
  - `src/adapters/ingest/reference_assets.zig`
  - `src/adapters/ingest/reference_assets_formats.zig`
  - `src/adapters/missions/s5p/root.zig`
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/document_fields.zig`
- Tests:
  - `tests/unit/adapter_ingest_test.zig`
  - `tests/unit/optics_preparation_test.zig`
  - `tests/integration/mission_s5p_integration_test.zig`
  - `tests/integration/canonical_config_execution_integration_test.zig`

## Exact Patch Checklist

- [x] `src/model/Instrument.zig`: replace string selectors such as `sampling` and `noise_model` with resolved enums/tagged config; keep operational line shape, reference-grid, solar-spectrum, and LUT carriers as typed payloads rather than stringly lookups.
- [x] `src/model/ObservationModel.zig`: store the resolved instrument/sampling/noise config once; stop reconstructing instrument specs or repeatedly comparing strings at runtime.
- [x] `src/model/Surface.zig`: replace stringly surface-kind routing with a typed surface enum and parameter set; keep Lambertian inputs explicit enough for a real surface provider.
- [x] `src/model/instrument/line_shape.zig`: extend table-driven ISRF handling so measured-channel and operational slit-function paths work end-to-end without ad hoc provider logic.
- [x] `src/model/instrument/reference_grid.zig`: preserve the current strong validation model; add only the missing fields or helper APIs needed by weighted operational reference-grid workflows.
- [x] `src/model/instrument/solar_spectrum.zig`: preserve the current strong validation/interpolation model and make it the runtime source of truth for solar input wherever an external or operational spectrum is present.
- [x] `src/model/instrument/cross_section_lut.zig`: ensure operational O2 and O2-O2 coefficient cubes are consumed through the resolved observation model rather than as optional side data.
- [x] `src/plugins/providers/instrument.zig`: build integration kernels from the resolved observation model; support native grids, measured channels, Gaussian ISRF, and table-driven ISRF without repeated string parsing.
- [x] `src/plugins/providers/surface.zig`: implement actual Lambertian response semantics or rename the provider surface clearly if it remains a surrogate gain model in the interim.
- [x] `src/plugins/providers/noise.zig`: unify `shot_noise`, `s5p_operational`, and `snr_from_input` under the same sigma semantics and runtime error model.
- [x] `src/kernels/spectra/calibration.zig`: align wavelength shift, multiplicative offset, and stray-light handling with the resolved instrument config and repaired measurement-space ordering.
- [x] `src/kernels/spectra/convolution.zig`: verify and, if needed, extend convolution semantics so Gaussian and table-driven ISRF behave consistently over measured-channel and native-grid paths.
- [x] `src/kernels/spectra/grid.zig`: support the grid semantics needed by measured-channel, oversampled HR, and weighted reference-grid workflows without ad hoc special cases in providers.
- [x] `src/kernels/spectra/noise.zig`: become the single source of truth for sigma generation, sigma validation, and any whitening helpers reused by forward and retrieval code.
- [x] `src/adapters/ingest/spectral_ascii.zig`: split parser responsibilities by metadata class and ensure measured channels, ISRF tables, solar spectra, weighted reference grids, operational LUTs, and SNR fields all survive into typed runtime structures.
- [x] `src/adapters/ingest/reference_assets.zig`: keep orchestration only; move format-specific parsing down into dedicated helpers so the file stops growing into another monolith.
- [x] `src/adapters/ingest/reference_assets_formats.zig`: continue the format split and keep all format-specific parsing delegated here rather than regrowing `reference_assets.zig`.
- [x] `src/adapters/missions/s5p/root.zig`: use ingested measured radiance/irradiance, slit, solar, grid, and noise inputs to populate the resolved observation model and provider-facing structures.
- [x] `src/adapters/canonical_config/Document.zig`: resolve observation-model selectors to typed internal forms during parsing/resolution rather than leaving strings for runtime comparison.
- [x] `src/adapters/canonical_config/document_fields.zig`: parse only the execution/sampling/noise modes that are actually supported, and map them directly to the resolved types used by the model.
- [x] `tests/unit/adapter_ingest_test.zig`: add coverage for measured channels, ISRF tables, operational solar/reference-grid inputs, and SNR propagation.
- [x] `tests/unit/optics_preparation_test.zig`: verify that resolved operational observation inputs affect prepared optics and support-data wiring as expected.
- [x] `tests/integration/mission_s5p_integration_test.zig`: prove that the S5P adapter materially changes execution when measured/operational inputs are present.
- [x] `tests/integration/canonical_config_execution_integration_test.zig`: add canonical-config cases covering resolved enums/tagged observation config and measured-input execution.

## Completion Checklist

- [x] Implementation matches the described approach
- [x] Non-destructive tests pass
- [x] Proof / validation section filled with exact commands and outcomes
- [x] How to test section is reproducible
- [x] `overview.md` rollup row updated
- [x] Observation/instrument/noise selectors are resolved once and not re-parsed in hot paths
- [x] Measured-channel, ISRF-table, solar, reference-grid, and SNR ingests all survive into execution
- [x] Lambertian surface semantics are physically meaningful or explicitly renamed as surrogate

Implementation status (2026-03-16):
- Split `spectral_ascii` into orchestration, metadata parsing, and runtime bridging so measured channels, operational ISRF tables, solar spectra, reference grids, LUTs, and SNR-derived sigma stop disappearing behind one ingest file.
- Hardened the core observation model around typed sampling/noise/surface state, explicit measured wavelengths, reference radiance, ingested sigma, table-driven ISRF carriers, operational solar spectra, and weighted reference-grid carriers.
- Routed ingest-backed measurement binding all the way through canonical-config execution and the S5P mission adapter, including direct radiance observation products for retrievals.
- Added vendor-style radiance/irradiance wavelength reconciliation: small grid drift is corrected using the modeled solar ratio, while larger drift is rejected as invalid operational input.
- Reworked `s5p_operational` noise from “copy the ingest sigma” into reference-radiance scaling with spectral-bin correction, while keeping `snr_from_input` as the strict raw-sigma path.
- Renamed the surface provider contract to `brdfFactor` and kept Lambertian behavior explicit as a unit directional factor with albedo still entering through transport.

Why this works:
- Canonical config and mission adapters now resolve selectors once at the edge, so hot paths stop rebuilding sampling/noise/surface behavior from strings.
- Operational support data is no longer passive metadata: measured wavelengths, ISRF tables, solar spectra, weighted reference grids, and operational LUTs are threaded into providers, optics preparation, measurement binding, and mission execution.
- The new irradiance reconciliation closes the vendor-style observed-data gap where irradiance and radiance wavelengths differ slightly but should still bind into one observed spectrum.
- `s5p_operational` noise now preserves the important vendor semantics: sigma is tied to a reference radiance spectrum and scales with both radiance level and spectral-bin width, rather than silently collapsing to raw input sigma.
- The extra integration cases prove the new paths through real engine execution instead of only unit-level helper coverage.

Proof / validation:
- `zig build test-unit --summary all`
  Outcome: passed, `24/24` tests.
- `zig build test-integration --summary all`
  Outcome: passed, `21/21` tests.
- `zig build test-validation --summary all`
  Outcome: passed, `12/12` tests.
- Added or updated focused coverage for:
  - reference-radiance propagation and sigma threading from spectral ingest
  - canonical-config measured support-data execution and ingest-backed retrieval binding
  - S5P observed-spectrum irradiance/radiance grid correction and over-threshold rejection
  - `s5p_operational` noise scaling through executed products, including a non-unity reference-bin correction case
  - operational reference-grid spacing affecting runtime noise semantics
- Independent code-review acceptance:
  - strict implementation review: accepted
  - vendor-guided parity review: accepted after the observed-grid and noise-scaling parity fixes
  - checklist/test review: accepted after the end-to-end non-unity bin-width assertion landed

How to test:
1. Run `zig build test-unit --summary all`.
2. Run `zig build test-integration --summary all`.
3. Run `zig build test-validation --summary all`.
4. Inspect the S5P integration cases for:
   - shifted irradiance/radiance grids being corrected rather than silently interpolated away
   - over-threshold grid drift being rejected as invalid operational input
   - `s5p_operational` noise sigma matching `ref_sigma * sqrt(radiance / ref_radiance) * sqrt(reference_spacing / current_spacing)` on the executed product.
