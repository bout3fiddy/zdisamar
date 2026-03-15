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

### WP-03 Introduce Typed RTM Sublayer Gas Optical Properties [Status: Todo]

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

### WP-04 Implement HG Aerosol/Cloud Interval Optical Properties [Status: Todo]

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

### WP-05 Add Bounded Mie Interpolation and Combined Phase-Function Coefficients [Status: Todo]

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
