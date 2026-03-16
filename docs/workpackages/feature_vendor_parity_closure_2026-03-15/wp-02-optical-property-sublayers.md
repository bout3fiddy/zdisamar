# Work Package Detail: Sublayer Optical-Property Preparation

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_closure_2026-03-15/`
- Scope: `src/model/`, `src/kernels/optics/`, `src/kernels/transport/`, `src/runtime/cache/`, `tests/`
- Input sources:
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `vendor/disamar-fortran/expCoefFiles/`
  - `docs/workpackages/feature_vendor_parity_followup_2026-03-15/wp-02-physics-and-retrieval-parity.md`
- Constraints:
  - keep the prepared state pure and allocator-owned
  - avoid file I/O in kernels
  - encode sublayer preparation with explicit typed layouts rather than ad-hoc arrays in `Engine`

## Background

The current optics layer is wavelength aware and typed, but it still compresses a large part of the vendor optical-property preparation into coarse aggregate controls. `propAtmosphere.f90` still materially exceeds the current Zig implementation in three areas:

- RTM-style sublayer gas-property materialization
- HG aerosol/cloud interval optical properties
- Mie-based coefficient interpolation and combined phase-function assembly

### WP-03 Introduce Typed RTM Sublayer Gas Optical Properties [Status: Done 2026-03-15]

- Issue: gas optical properties are currently prepared per coarse scene layer, while `propAtmosphere.f90` materializes sublayer optical quantities and temperature-derivative fields on a denser RTM grid.
- Needs: a typed sublayer grid, gas optical-property arrays, and explicit temperature-derivative storage feeding transport and validation.
- How: add a dedicated optical-preparation layout for sublayers that stays independent from mission or adapter parsing and can be cached per prepared plan.
- Why this approach: sublayer materialization is the natural typed replacement for the vendor’s RTM-grid arrays.
- Recommendation rationale: this closes the biggest remaining gas-side difference without importing vendor-style global mutable storage.
- Desired outcome: transport and validation can consume deterministic sublayer gas optical properties and `dXsec/dT`-style fields through typed prepared state.
- Non-destructive tests:
  - `zig build test-unit`
  - optical-preparation and cache tests
  - validation cases over prepared sublayer summaries
- Files by type:
  - model/kernels/runtime: `src/model/**/*`, `src/kernels/optics/**/*`, `src/runtime/cache/**/*`
  - tests/validation: `tests/unit/**/*`, `tests/validation/**/*`

- Implementation status (2026-03-15): done. `src/model/Atmosphere.zig` now exposes explicit `sublayer_divisions`, and `src/kernels/optics/prepare.zig` now materializes allocator-owned `PreparedSublayer` entries inside `PreparedOpticalState`. Each sublayer carries gas cross-section summaries, `dXsec/dT`-style fields, gas absorption/scattering/extinction optical depths, and parent-layer indexing so the coarse prepared layers can aggregate from a denser RTM-style gas grid.
- Why this works: it closes the gas-side structure gap from `propAtmosphere.f90` without importing the vendor RTM arrays or pressure-grid mutation model. The repo now has a typed replacement for the vendor’s subgrid gas preparation: deterministic gas optical properties are created on a dedicated sublayer grid and then rolled back up into the transport-facing layer summaries.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. Focused proof lives in `tests/unit/optics_preparation_test.zig`, which now verifies sublayer counts, parent aggregation, and non-zero `d_gas_optical_depth_d_temperature`.
- How to test:
  - `zig build test-unit`
  - `zig build test-validation`
  - `zig build test`
  - inspect the `sublayer-grid` unit test in `tests/unit/optics_preparation_test.zig` for the parent/sublayer gas optical-depth invariants

### WP-04 Implement HG Aerosol/Cloud Interval Optical Properties [Status: Done 2026-03-15]

- Issue: aerosol/cloud wavelength scaling exists, but the vendor code also synthesizes interval scattering/absorption properties and HG-style coefficient lanes.
- Needs: interval optical thickness partitioning, SSA/asymmetry preparation by sublayer, and bounded HG phase-function coefficient materialization.
- How: extend the typed aerosol/cloud models and prepared optical state with interval-level scattering outputs that can be consumed without mission-specific branching.
- Why this approach: the repo already has the typed controls; this turns them into real prepared optical products.
- Recommendation rationale: this is the minimum bounded replacement for the vendor HG aerosol/cloud path.
- Desired outcome: aerosol/cloud preparation yields interval scattering properties and bounded HG coefficient arrays rather than only aggregate optical-depth scalars.
- Non-destructive tests:
  - `zig build test-unit`
  - transport/optics integration tests with aerosol/cloud intervals
  - parity harness checks on bounded HG cases
- Files by type:
  - model/kernels: `src/model/**/*`, `src/kernels/optics/**/*`, `src/kernels/transport/**/*`
  - tests/validation: `tests/unit/**/*`, `tests/integration/**/*`, `tests/validation/**/*`

- Implementation status (2026-03-15): done. `src/kernels/optics/prepare.zig` now distributes aerosol and cloud optical depth across the RTM-style sublayer grid, stores per-sublayer aerosol/cloud SSA, and materializes bounded HG-style phase coefficients for aerosol, cloud, and combined scattering lanes. The interval optical depth that used to live only as coarse layer scalars is now explicitly represented on the same sublayer grid as the gas optical properties.
- Why this works: the repo already had typed aerosol and cloud controls; this change turns them into prepared interval products that can be consumed without mission-specific branching. The HG coefficient materialization is bounded and explicit, which is the right architectural replacement for the vendor’s interval HG path before bringing in a fuller Mie lane.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. `tests/unit/optics_preparation_test.zig` now checks that aerosol/cloud optical depth sums are preserved on sublayers and that combined HG-style phase coefficients are materialized deterministically.
- How to test:
  - `zig build test-unit`
  - `zig build test`
  - inspect the `hg-sublayers` unit test in `tests/unit/optics_preparation_test.zig` for aerosol/cloud sum preservation and combined phase-coefficient checks

### WP-05 Add Bounded Mie Interpolation and Combined Phase-Function Coefficients [Status: Done 2026-03-15]

- Issue: `propAtmosphere.f90` includes Mie interpolation and combined phase-function coefficient preparation; the current Zig tree has no equivalent bounded path.
- Needs: tracked Mie subset assets, interpolation helpers, and typed coefficient preparation that can combine gas, aerosol, and cloud scattering lanes.
- How: introduce small tracked Mie reference subsets plus a typed coefficient builder that produces explicit prepared arrays for transport kernels.
- Why this approach: the repo needs bounded scientific depth here, not a full upstream table dump.
- Recommendation rationale: this is the last major missing optical-property surface before the vendor delta can plausibly be called intentional architecture drift.
- Desired outcome: prepared optical state can include bounded Mie/HG coefficient lanes and combined phase-function summaries for validation and transport.
- Non-destructive tests:
  - `zig build test`
  - focused Mie interpolation tests
  - bounded parity checks against representative vendor cases
- Files by type:
  - data/kernels/tests: `data/**/*`, `src/kernels/**/*`, `tests/**/*`, `validation/**/*`

- Implementation status (2026-03-15): done. `data/luts/mie_dust_phase_subset.csv` is now tracked as a bounded vendor-derived phase-function subset with updated digests in `data/luts/bundle_manifest.json` and provenance in `validation/compatibility/vendor_import_registry.json`. `src/model/ReferenceData.zig` now exposes typed `MiePhasePoint` and `MiePhaseTable` interpolation, `src/adapters/ingest/reference_assets.zig` now parses bundle-backed `mie_phase_table` assets, and `src/kernels/optics/prepare.zig` now routes optional aerosol Mie tables into extinction scaling, SSA, and combined phase-coefficient preparation on the sublayer grid.
- Why this works: the missing vendor depth here was not “some scattering metadata”; it was a real coefficient-preparation lane. The repo now turns a tracked vendor-subset Mie table into deterministic prepared aerosol scattering products without pushing table parsing into the kernels or reintroducing vendor-style mutable global arrays.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. Focused proof lives in `tests/unit/adapter_ingest_test.zig`, `tests/unit/optics_preparation_test.zig`, and `src/model/ReferenceData.zig`.
- How to test:
  - `zig build test-unit`
  - `zig build test-validation`
  - `zig build test`
  - inspect the Mie interpolation assertions in `tests/unit/adapter_ingest_test.zig` and the particle-table preparation assertions in `tests/unit/optics_preparation_test.zig`
