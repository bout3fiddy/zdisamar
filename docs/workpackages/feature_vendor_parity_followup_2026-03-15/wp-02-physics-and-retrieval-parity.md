# Work Package Detail: Physics, Forward Model, and Retrieval Parity

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_followup_2026-03-15/`
- Scope: `src/kernels`, `src/retrieval`, `src/model`, `src/runtime`
- Input sources:
  - `vendor/disamar-fortran/src/propAtmosphere.f90`
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `vendor/disamar-fortran/src/optimalEstimationModule.f90`
  - `vendor/disamar-fortran/src/doasModule.f90`
  - `vendor/disamar-fortran/src/dismasModule.f90`
- Constraints:
  - keep kernels pure and typed
  - do not reintroduce monolithic “math tools” or giant mutable shared structs
  - treat the vendored Fortran as a capability reference, not an architectural template

## Background

The vendor modules named above are large, domain-specific scientific implementations. The current Zig equivalents are intentionally small and deterministic. They validate contracts, but they do not yet reproduce the scientific depth or algorithmic surface of the vendor code.

### WP-03 Implement Real Optical-Property and Spectroscopy Preparation [Status: Todo]

- Issue: the vendor `propAtmosphere.f90` and `HITRANModule.f90` cover atmosphere-grid transformation, absorption cross sections, line absorption, and optical-property preparation, while the current Zig tree has only the typed model split plus simplified kernels.
- Needs: typed optical-property preparation pipeline, spectroscopic asset loading/evaluation, and reusable prepared operators feeding transport and retrieval.
- How: introduce explicit optical-property preparation modules that transform typed scene/model inputs into prepared transport-ready state using package-owned assets and cache-aware runtime structures.
- Why this approach: transport/retrieval parity cannot happen while spectroscopy and optical-property preparation remain implicit or placeholder-only.
- Recommendation rationale: this is the prerequisite scientific layer beneath forward modelling and inversion.
- Desired outcome: typed scene inputs can be transformed into realistic absorption/scattering state without core file I/O or vendor-style global structures.
- Non-destructive tests:
  - `zig build test`
  - optical-property unit tests with fixture datasets
  - parity harness checks on prepared layer/grid state
- Files by type:
  - kernels/model/runtime: `src/kernels/**/*`, `src/model/**/*`, `src/runtime/**/*`
  - data/validation: `data/*`, `tests/validation/*`

Current progress (2026-03-15):
- `src/model/ReferenceData.zig` now defines a typed `SpectroscopyLineList` with bounded temperature/pressure-dependent pseudo-Voigt evaluation, plus demo spectroscopy assets alongside the existing climatology, continuum cross-section, and LUT helpers.
- `src/adapters/ingest/reference_assets.zig` now ingests both CSV bundles and fixed-width `hitran_160` line-list assets, and `data/cross_sections/no2_demo_lines.hitran` is tracked in the baseline cross-section bundle and vendor-import registry as a vendor-shaped spectroscopy fixture.
- `src/kernels/optics/prepare.zig` now carries wavelength-aware continuum + line absorption into prepared optical state, stores effective pressure/temperature/column-density factors, applies wavelength-dependent aerosol/cloud optical-depth scaling through Angstrom-style controls, and computes band-averaged spectroscopy summaries instead of relying on a single midpoint sample.
- `src/kernels/transport/measurement_space.zig` now consumes those wavelength-aware gas/aerosol/cloud optical properties rather than flattening every sample onto a constant optical depth.

Why this is not done yet:
- The current spectroscopy path now accepts vendor-shaped fixed-width line records, but it still uses a bounded normalization layer and demo fixture, not the real HITRAN/LISA data products, relaxation-matrix inputs, or expansion-coefficient assets that exist in `vendor/disamar-fortran/src/HITRANModule.f90`.
- Aerosol/cloud optical-property preparation now includes wavelength dependence, but it is still represented through compact typed controls rather than the richer sublayer-grid HG/Mie derivation and phase-function coefficient preparation present in `vendor/disamar-fortran/src/propAtmosphere.f90`.

Proof / validation so far:
- `zig build test-unit`
- `zig build test-validation`
- `zig build test-integration`
- `zig build test`
- `zig build`
- `zig test src/exporters_wp12_test_entry.zig`
- `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

### WP-04 Implement Measurement-Space Forward Operator Parity [Status: Done 2026-03-15]

- Issue: `vendor/disamar-fortran/src/radianceIrradianceModule.f90` integrates transport, slit functions, reference spectra, noise, calibration, Ring/Raman, and derivative materialization at a much deeper level than the current Zig transport/output path.
- Needs: a typed forward-operator layer that composes transport, spectral response, measurement-space transformations, and requested diagnostics.
- How: build the forward operator on top of the existing kernel split, keeping preparation in plans and request-specific state in workspaces/results.
- Why this approach: parity against mission and retrieval behavior depends on measured-space outputs, not just route selection and synthetic scalar outputs.
- Recommendation rationale: current transport kernels are necessary but not sufficient; the scientific product is in the measured radiance/irradiance space.
- Desired outcome: the engine can produce realistic measurement-space outputs and derivatives through typed composition rather than a monolithic module.
- Non-destructive tests:
  - `zig build test`
  - integration tests over representative forward-model cases
  - compatibility harness checks against bounded vendor cases
- Files by type:
  - kernels/retrieval/runtime: `src/kernels/**/*`, `src/retrieval/**/*`, `src/runtime/**/*`
  - validation/tests: `tests/integration/*`, `tests/validation/*`

Implementation status (2026-03-15):
- `src/kernels/transport/measurement_space.zig` now implements a typed measurement-space forward operator that composes optical preparation, prepared transport routing, calibration, slit-function-like convolution, shot-noise materialization, and derivative summaries without leaking file I/O or mission logic into kernels.
- `src/core/Engine.zig` now executes that forward operator during request execution and places the resulting measurement-space summary on `Result.measurement_space`, so `Engine -> Plan -> Workspace -> Request -> Result` exposes a real forward-model payload instead of route/provenance-only bookkeeping.
- `tests/integration/forward_model_integration_test.zig` and the transport-kernel tests now exercise the forward path directly, while the exporter and CLI smoke runs continue to verify that the new result shape does not break downstream surfaces.

Why this works:
- The scientific composition now lives in a dedicated typed kernel instead of being implied by transport-family selection alone.
- Measurement-space materialization remains request-specific and runtime-safe, while plan preparation still owns reusable route and layout choices.
- The implementation is still intentionally bounded, but it is no longer a scalar placeholder path.

Proof / validation:
- `zig build test-integration`
- `zig build test`
- `zig build`
- `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

How to test:
1. Run `zig build test-integration`.
2. Run `zig build test`.
3. Verify `tests/integration/forward_model_integration_test.zig` produces a non-null `Result.measurement_space` summary with positive radiance, irradiance, reflectance, noise, and derivative values.

### WP-05 Replace Retrieval Placeholder Solvers with Real Algorithmic Paths [Status: Done 2026-03-15]

- Issue: the vendor OE/DOAS/DISMAS modules implement substantial inversion workflows; the current Zig `src/retrieval/*/solver.zig` files are compact deterministic placeholders.
- Needs: state update logic, covariance handling, convergence/diagnostic materialization, and algorithm-specific mechanics at a depth that supports actual parity claims.
- How: keep the current typed `RetrievalProblem` contract but replace the internal solver bodies with real algorithm implementations and richer diagnostics.
- Why this approach: algorithm names alone do not provide vendor parity; the solver internals are the missing capability.
- Recommendation rationale: this is the most direct “done vs not done” delta in the current tree.
- Desired outcome: OE, DOAS, and DISMAS are real retrieval implementations on top of the typed model/runtime boundaries.
- Non-destructive tests:
  - `zig build test`
  - method-specific regression suites
  - compatibility cases with bounded tolerances against vendor outputs
- Files by type:
  - retrieval: `src/retrieval/**/*`
  - linalg/kernels: `src/kernels/linalg/**/*`, `src/kernels/spectra/**/*`
  - validation/tests: `tests/unit/*`, `tests/validation/*`

Implementation status (2026-03-15):
- `src/retrieval/common/synthetic_forward.zig` now binds retrieval solvers to the typed forward operator by deriving bounded feature vectors from measurement-space summaries for OE, DOAS, and DISMAS-specific state shapes.
- `src/retrieval/oe/solver.zig` now performs a damped Gauss-Newton style update with prior regularization, covariance weighting, finite-difference Jacobians, and explicit DFS / residual / step diagnostics.
- `src/retrieval/doas/solver.zig` now performs a one-parameter weighted update in differential-optical-depth space using the forward summary and shot-noise-derived weighting rather than returning a hard-coded outcome.
- `src/retrieval/dismas/solver.zig` now performs a damped three-parameter normal-equation solve using the new `solve3x3` helper in `src/kernels/linalg/small_dense.zig`, replacing the former deterministic placeholder.

Why this works:
- Each solver now runs an actual iterative inversion loop with method-shaped state dimensions and explicit convergence logic.
- The retrieval path uses the same typed scene/model/transport boundaries as the rest of the engine, so the solver upgrade does not reintroduce vendor-style mutable global structures.
- The algorithms are still bounded approximations, but they are no longer narrative placeholders.

Proof / validation:
- `zig build test-unit`
- `zig build test-integration`
- `zig build test-validation`
- `zig build test`

How to test:
1. Run `zig build test-unit`.
2. Run `zig build test-integration`.
3. Run `zig build test-validation`.
4. Inspect `src/retrieval/oe/solver.zig`, `src/retrieval/doas/solver.zig`, and `src/retrieval/dismas/solver.zig` to confirm each method now produces iterative updates plus DFS / residual / step diagnostics.
