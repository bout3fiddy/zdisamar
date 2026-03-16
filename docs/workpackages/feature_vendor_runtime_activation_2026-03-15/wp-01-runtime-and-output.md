# Work Package Detail: Runtime Bundle Activation and Scientific Output Payloads

## Metadata

- Package: `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/`
- Scope: `src/runtime/`, `src/core/`, `src/retrieval/common/`, `src/adapters/exporters/`, `tests/`, `validation/`
- Input sources:
  - `vendor/disamar-fortran/src/radianceIrradianceModule.f90`
  - `docs/workpackages/feature_vendor_parity_closure_2026-03-15/wp-03-parity-docs-closure.md`
- Constraints:
  - keep runtime-owned preparation explicit
  - do not move parsing logic into `src/core` or `src/kernels`
  - keep export writers adapter-scoped

## Background

The bounded parity package proved that the repo can ingest tracked vendor-subset assets, but runtime execution still bypassed them. The vendor comparison made that mismatch explicit: as long as `Engine.execute` and the retrieval forward operator consume demo-only reference builders, the repo cannot honestly claim runtime parity even for bounded cases. After that runtime gap, the next largest remaining false-positive signal is that exporters still mostly emit metadata and summary information rather than scientific arrays.

### WP-01 Activate Bundle-Backed Runtime Optics Preparation [Status: Done 2026-03-15]

- Issue: execution and retrieval-forward paths still used `buildDemo*` optics inputs instead of the tracked bundle assets that validation and parity work now rely on.
- Needs: a runtime-owned bundle-selection path that prepares typed optics from tracked bundles for visible-band NO2 and O2 A-band representative scenes, including optional aerosol Mie support.
- How: add a runtime reference-preparation module that selects the right tracked bundle assets for a scene, materializes typed optics state through adapter parsing plus kernel preparation, and replace the older demo-only execution paths with that module.
- Why this approach: it closes the real runtime gap without reintroducing file parsing into `src/core` or hardcoding vendor arrays inside the kernels.
- Recommendation rationale: until runtime execution uses the same tracked bundle assets as validation, every parity claim remains structurally weaker than it appears.
- Desired outcome: `Engine.execute` and retrieval synthetic forward preparation both consume tracked bundle assets rather than in-memory demos.
- Non-destructive tests:
  - `zig build test-unit`
  - `zig build test-validation`
  - `zig build test-integration`
  - `zig build test-perf`
  - `zig build test`
  - `zig build`
  - `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`
- Files by type:
  - runtime/core/retrieval: `src/runtime/**/*`, `src/core/**/*`, `src/retrieval/common/**/*`
  - tests/validation: `tests/**/*`, `validation/**/*`

- Implementation status (2026-03-15): done. `src/runtime/reference/BundledOptics.zig` now selects tracked bundle assets at runtime for representative visible-band NO2 and O2 A-band scenes, including LISA sidecars and optional aerosol Mie tables. `src/core/Engine.zig` and `src/retrieval/common/synthetic_forward.zig` now use that runtime-owned preparation path instead of the older `buildDemo*` helpers, and `src/runtime/root.zig` now exports the new runtime reference surface.
- Why this works: the tracked vendor-subset assets are no longer confined to tests and parity harnesses. The actual execution paths now materialize optics from the same bounded bundle products that the repo is using as its reproducible parity reference set, which removes a major runtime inconsistency without violating the repo’s architectural boundaries.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. Focused proof lives in `src/runtime/reference/BundledOptics.zig`, plus the validation matrix cases that now execute through the bundle-backed runtime path.
- How to test:
  - `zig build test-unit`
  - `zig build test-validation`
  - `zig build test`
  - `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`
  - inspect `src/runtime/reference/BundledOptics.zig` and confirm `Engine.execute` / `retrieval/common/synthetic_forward.zig` no longer call the `buildDemo*` helpers

### WP-02 Carry Scientific Measurement Vectors and Fields Into Result and Exporters [Status: Done 2026-03-15]

- Issue: the runtime path now uses tracked bundle assets, but `Result` and the official exporters still mostly surface metadata and mean-summary products instead of the spectral vectors and scientific fields needed for honest parity against `radianceIrradianceModule.f90` and `netcdfModule.f90`.
- Needs: typed measurement-space vectors in `Result`, exporter payloads that write wavelength/radiance/irradiance/reflectance/noise/jacobian arrays plus selected physical fields, and tests that validate real numeric payloads rather than only metadata tables.
- How: extend the measurement-space API to materialize reusable scientific vectors, add allocator-owned result payloads with explicit cleanup, and update NetCDF/Zarr backends to emit those vectors as first-class arrays.
- Why this approach: the remaining output gap is not about file formats alone; it is about the absence of scientific payloads in the result/export path.
- Recommendation rationale: runtime parity is still overstated while outputs stop at summaries and provenance metadata.
- Desired outcome: official exporters write real measurement-space numeric products instead of metadata-only or summary-dominant artifacts.
- Non-destructive tests:
  - `zig test src/exporters_wp12_test_entry.zig`
  - `zig build test-integration`
  - `zig build test-validation`
  - `zig build test`
- Files by type:
  - core/kernels/exporters: `src/core/**/*`, `src/kernels/transport/**/*`, `src/adapters/exporters/**/*`
  - tests/validation: `tests/**/*`, `validation/**/*`

- Implementation status (2026-03-15): done. `src/kernels/transport/measurement_space.zig` now materializes allocator-owned wavelength/radiance/irradiance/reflectance/noise/jacobian arrays and selected physical fields through `MeasurementSpaceProduct`. `src/core/Result.zig` now owns and explicitly deinitializes that payload. `src/core/Engine.zig` attaches the full product, and both official backends in `src/adapters/exporters/netcdf_cf.zig` and `src/adapters/exporters/zarr.zig` now emit those arrays and physical scalars as first-class output content instead of provenance-only artifacts.
- Why this works: the result/export path now carries the same spectral and physical data that the forward operator actually produced, so export parity is no longer blocked by a summary-only result surface. The ownership model is explicit, allocator-scoped, and enforced at every `Engine.execute` consumer.
- Proof / validation: `zig test src/exporters_wp12_test_entry.zig`, `zig build test-unit`, `zig build test-integration`, `zig build test-validation`, `zig build test-perf`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. Focused proof lives in the exporter backend tests, the `measurement-space product materializes spectral vectors and physical fields` unit test, and the integration tests that now assert `result.measurement_space_product != null`.
- How to test:
  - `zig test src/exporters_wp12_test_entry.zig`
  - `zig build test-unit`
  - `zig build test-integration`
  - inspect `src/core/Result.zig`, `src/kernels/transport/measurement_space.zig`, `src/adapters/exporters/netcdf_cf.zig`, and `src/adapters/exporters/zarr.zig`
  - confirm `Engine.execute` call sites deinitialize `Result` explicitly after use
