# Work Package Detail: Reference Imports and Spectroscopy Closure

## Metadata

- Package: `docs/workpackages/feature_vendor_parity_closure_2026-03-15/`
- Scope: `data/`, `src/adapters/ingest/`, `src/model/`, `src/kernels/optics/`, `validation/compatibility/`
- Input sources:
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - `vendor/disamar-fortran/RefSpec/`
  - `vendor/disamar-fortran/InputFiles/`
  - `docs/workpackages/feature_vendor_parity_followup_2026-03-15/wp-02-physics-and-retrieval-parity.md`
- Constraints:
  - keep reference imports tracked as bounded subsets, not full upstream dumps
  - keep parsed reference data in typed bundle structures
  - keep kernels independent from direct file parsing

## Background

The repo now accepts bounded fixed-width HITRAN-style line lists, but the vendor reference still has substantially richer input preparation:

- multiple line sources and sidecars
- strong/weak line partitioning
- first-order line-mixing inputs with relaxation-matrix support
- richer vendor reference import logic than a single normalized demo file

### WP-01 Import Tracked Vendor-Subset Spectroscopy References [Status: Done 2026-03-15]

- Issue: `vendor/disamar-fortran/src/HITRANModule.f90` reads several vendor-shaped reference products, while the current Zig tree still relies on a compact demo line asset.
- Needs: tracked vendor-subset imports for representative line lists and any supporting sidecars needed by the bounded parity target.
- How: add import tooling and bounded checked-in bundle subsets that normalize the relevant reference products into typed bundle manifests and deterministic adapter ingest paths.
- Why this approach: the current ingest proves format handling, but not the actual reference-shape workflow that parity depends on.
- Recommendation rationale: without representative imported reference subsets, every later spectroscopy claim is still based on a demo proxy.
- Desired outcome: the repo contains small tracked vendor-shaped reference subsets with verified hashes, provenance, and typed bundle metadata.
- Non-destructive tests:
  - `zig build test`
  - ingest tests over the new tracked subsets
  - compatibility asset checks over manifests and hashes
- Files by type:
  - data/validation: `data/**/*`, `validation/compatibility/**/*`
  - adapters/tests: `src/adapters/ingest/**/*`, `tests/unit/**/*`, `tests/validation/**/*`

- Implementation status (2026-03-15): done. The tracked cross-section bundle now carries an O2 A-band vendor subset line list in `data/cross_sections/o2a_hitran_subset_07_hit08_tropomi.par`, the matching LISA strong-line and RMF sidecars in `data/cross_sections/o2a_lisa_sdf_subset.dat` and `data/cross_sections/o2a_lisa_rmf_subset.dat`, updated digests in `data/cross_sections/bundle_manifest.json`, and explicit upstream provenance links in `validation/compatibility/vendor_import_registry.json`. Adapter ingest now exposes typed `spectroscopy_strong_line_set` and `spectroscopy_relaxation_matrix` lanes in `src/adapters/ingest/reference_assets.zig`.
- Why this works: this closes the vendor-shape gap from `HITRANModule.f90` without importing the full upstream database. The repo now proves bounded imports over the same O2 A-band family that `readLineParameters`, `readSDF`, and `readRMF` consume, while keeping all parsing inside adapters and all runtime state typed and allocator-owned.
- Proof / validation: `zig build test-unit` and `zig build test-validation` passed after the asset correction to the real O2 A-band subset. Coverage now includes `src/adapters/ingest/reference_assets.zig` and `tests/unit/adapter_ingest_test.zig` on the tracked vendor-shaped subset assets.
- How to test:
  - `zig build test-unit`
  - `zig build test-validation`
  - confirm the manifest hashes in `data/cross_sections/bundle_manifest.json` match the checked-in subset assets
  - inspect `validation/compatibility/vendor_import_registry.json` for the `RefSpec/07_HIT08_TROPOMI.par`, `RefSpec/O2A_LISA_SDF.dat`, and `RefSpec/O2A_LISA_RMF.dat` mappings

### WP-02 Extend Spectroscopy Evaluation Beyond Single-Lane Bounded Mixing [Status: Done 2026-03-15]

- Issue: the current evaluator supports bounded line mixing and temperature derivatives, but it does not separate strong/weak lines or consume sidecar relaxation inputs the way `HITRANModule.f90` does.
- Needs: typed separation of strong/weak line lanes, sidecar-driven first-order line mixing, and clearer provenance for which reference subset was used.
- How: introduce a typed spectroscopy-preparation layer that partitions imported reference subsets and exposes explicit evaluation modes to optical preparation.
- Why this approach: the missing vendor depth is not just file format; it is the evaluator structure behind those inputs.
- Recommendation rationale: this is the remaining scientific core under the current bounded HITRAN-style ingest path.
- Desired outcome: optical preparation can request vendor-bounded spectroscopy state that distinguishes continuum, weak-line, strong-line, and first-order mixing contributions.
- Non-destructive tests:
  - `zig build test-unit`
  - focused spectroscopy regression tests
  - compatibility checks against bounded vendor reference outputs
- Files by type:
  - model/kernels: `src/model/**/*`, `src/kernels/optics/**/*`
  - validation/tests: `tests/unit/**/*`, `tests/validation/**/*`

- Implementation status (2026-03-15): done. `src/model/ReferenceData.zig` now carries optional strong-line and RMF sidecars on `SpectroscopyLineList`, clones them through typed ownership, partitions weak and strong lanes, and computes sidecar-driven first-order line mixing near the strong-line core. `src/kernels/optics/prepare.zig` now preserves the full typed spectroscopy state inside `PreparedOpticalState` instead of reducing it to a flat slice, so wavelength-dependent optical preparation can keep using the partitioned evaluator.
- Why this works: the remaining vendor depth was structural, not just syntactic. The repo now mirrors the bounded shape of the O2 A-band path in `HITRANModule.f90`: weak lines remain in the baseline HITRAN subset, strong lines are identified from the LISA sidecar, and first-order mixing is driven from the relaxation matrix instead of the flat demo coefficient lane alone.
- Proof / validation: `zig build test-unit`, `zig build test-validation`, `zig build test-integration`, `zig build test-perf`, `zig test src/exporters_wp12_test_entry.zig`, `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` all passed. Focused proof lives in `src/model/ReferenceData.zig`, `tests/unit/adapter_ingest_test.zig`, and `tests/unit/optics_preparation_test.zig`.
- How to test:
  - `zig build test-unit`
  - `zig build test-validation`
  - `zig build test`
  - `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`
  - inspect the O2 A-band evaluation around `771.3 nm` in the new unit tests to verify non-zero weak-line, strong-line, and first-order mixing contributions
