# Work Package Detail: Output Containers and Data Asset Parity

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_followup_2026-03-15/`
- Scope: `src/adapters/exporters`, `data`, `packages`, `validation`
- Input sources:
  - `vendor/disamar-fortran/src/netcdfModule.f90`
  - `vendor/disamar-fortran/src/FourierCoefficientsModule.f90`
  - `vendor/disamar-fortran/src/readIrrRadFromFileModule.f90`
- Constraints:
  - keep file I/O at the adapter boundary
  - preserve NetCDF/CF and Zarr as the target output direction
  - treat vendor ASCII-HDF output as a reference signal, not the preferred new public format

## Background

The Zig tree now has concrete exporter modules and baseline bundle manifests, but the vendor code still materially exceeds it in two areas: actual scientific container output and mature ingestion/reference-asset handling.

The clearest example is `vendor/disamar-fortran/src/netcdfModule.f90`, which is a real NetCDF API integration. By contrast, `src/adapters/exporters/netcdf_cf.zig` currently renders a CF/CDL-style text artifact that is useful for typed contract checks but not yet a true scientific product.

### WP-01 Replace Placeholder Scientific Result Stores with Real NetCDF/Zarr Output [Status: Done 2026-03-15]

- Issue: current Zig exporters write deterministic artifacts, but they are not yet true scientific storage implementations comparable to the vendor NetCDF output path.
- Needs: binary NetCDF/CF output, richer Zarr group/array emission, and artifact validation beyond “file exists and contains expected strings”.
- How: replace the current text-focused writer bodies with real container emitters, keep the typed adapter dispatch, and expand validation to inspect container structure and required metadata.
- Why this approach: the architecture intentionally moved output to adapters, but that boundary still has to emit real scientific artifacts.
- Recommendation rationale: the placeholder exporters had become the clearest false-positive parity signal in the repo. Replacing them with actual container layouts removed that ambiguity without violating the adapter-only I/O boundary.
- Desired outcome: NetCDF/CF and Zarr exports are real official products, not contract placeholders.
- Non-destructive tests:
  - `zig build test`
  - focused exporter backend tests
  - artifact inspection checks over produced NetCDF/Zarr outputs
- Files by type:
  - adapter writers: `src/adapters/exporters/*.zig`
  - bundle metadata: `packages/builtin_exporters/*`
  - validation: `tests/unit/*`, `tests/integration/*`, `validation/*`

Implementation status (2026-03-15):
- `src/adapters/exporters/netcdf_cf.zig` now emits a real NetCDF classic (`CDF-1`) binary file with named dimensions, global attributes, and typed provenance/string tables instead of a CDL-style text stub.
- `src/adapters/exporters/zarr.zig` now emits a structured Zarr v2 store with root/group metadata, per-array `.zarray` descriptors, `.zattrs`, and chunk payloads for metadata/provenance/diagnostic arrays.
- `src/adapters/exporters/root.zig` and backend-local tests now validate container structure rather than only checking for placeholder text payloads.

Why this works:
- The implementation stays entirely in adapter code, so core/runtime purity is preserved.
- The new NetCDF writer produces a valid binary container that external tooling can identify as NetCDF rather than a text contract artifact.
- The Zarr backend now materializes the directory and metadata model that downstream array tooling expects, which is the actual interoperability surface that matters.

Proof / validation:
- `zig test src/exporters_wp12_test_entry.zig`
- `zig build test`
- `zig build`
- `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

How to test:
1. Run `zig test src/exporters_wp12_test_entry.zig`.
2. Run `zig build test`.
3. Inspect generated `.nc` files for the `CDF\\x01` magic bytes and generated `.zarr` stores for `.zgroup`, `.zattrs`, `.zarray`, and chunk files.

### WP-02 Build Typed Radiance/Irradiance and Reference-Asset Ingestion at the Adapter Boundary [Status: Done 2026-03-15]

- Issue: the vendor tree has mature read-paths and operational data replacement flows around irradiance, radiance, LUTs, and reference spectra; the Zig tree currently has only baseline bundle manifests and narrow mission/request builders.
- Needs: typed adapter-level ingestion for measured radiance/irradiance and reference assets, plus package ownership and provenance hooks for imported science data.
- How: add ingestion modules under adapters and package/data management layers, keep runtime-facing results typed, and align imported assets with dataset cache/provenance expectations.
- Why this approach: the current bundle manifests prove packaging, but not operational data ingestion.
- Recommendation rationale: actual mission and compatibility execution depends on ingesting real arrays and reference products, not only catalog metadata. The adapter boundary now owns that ingestion work explicitly.
- Desired outcome: adapter code can load real measured/reference inputs into typed `Request`/mission structures without pulling parsing into core runtime code.
- Non-destructive tests:
  - `zig build test`
  - adapter ingestion tests over representative vendor-derived fixtures
  - dataset/provenance validation checks
- Files by type:
  - adapters: `src/adapters/**/*`
  - data/packages: `data/*`, `packages/*`
  - validation: `tests/validation/*`, `validation/compatibility/*`

Implementation status (2026-03-15):
- `src/adapters/ingest/spectral_ascii.zig` now parses vendor-style irradiance/radiance ASCII channel files into typed adapter structs and bridges them into the current `Measurement`, `SpectralGrid`, and `Request` contracts.
- `src/adapters/ingest/reference_assets.zig` now loads tracked bundle manifests, validates SHA-256 digests, parses numeric CSV assets, and registers dataset/LUT provenance into engine caches through typed adapter helpers.
- `data/examples/irr_rad_channels_demo.txt` and `tests/unit/adapter_ingest_test.zig` provide executable coverage over both the spectral-input and reference-asset paths.

Why this works:
- Parsing stays in adapters and returns typed values, so core and kernels remain free of text/file concerns.
- The manifest-backed asset loader turns the tracked bundle metadata into executable provenance rather than dead documentation.
- Engine cache registration now has an adapter path driven by real asset content and verified digests, which is the missing bridge between files on disk and typed runtime provenance.

Proof / validation:
- `zig build test-unit`
- `zig build test`
- `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`

How to test:
1. Run `zig build test-unit`.
2. Run `zig build test`.
3. Read `data/examples/irr_rad_channels_demo.txt` through `src/adapters/ingest/spectral_ascii.zig` or the unit tests and confirm the derived measurement/request summary.
4. Load `data/cross_sections/bundle_manifest.json` and `data/luts/bundle_manifest.json` through `src/adapters/ingest/reference_assets.zig` and verify that hashes and engine cache entries match the tracked manifests.
