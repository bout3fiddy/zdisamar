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

### WP-01 Import Tracked Vendor-Subset Spectroscopy References [Status: Todo]

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

### WP-02 Extend Spectroscopy Evaluation Beyond Single-Lane Bounded Mixing [Status: Todo]

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
