# Work Package Detail: Validation, Parity, Data, and Public API Completeness

## Metadata

- Package: `docs/workpackages/feature_spec_completeness_2026-03-14/`
- Scope: `validation`, `tests`, `data`, `src/api`
- Input sources:
  - `docs/specs/original-plan.md`
  - `docs/specs/architecture.md`
  - `vendor/disamar-fortran/test/`
  - `vendor/disamar-fortran/InputFiles/`
- Constraints:
  - keep tests first-class and reproducible
  - preserve stable C ABI as the public foreign boundary
  - make parity claims measurable rather than narrative

## Background

The current validation tree proves the scaffold shape, not scientific parity. Data bundles are missing, compatibility cases are planned rather than executed against reference outputs, and the public C/Zig API is still narrower than the architecture intends.

## Overarching Goals

- Turn validation assets into an actual parity harness.
- Populate the scientific data required for meaningful comparisons.
- Finish the C/Zig public boundary so it matches the architecture contract.

## Non-goals

- Claiming scientific parity before reference comparisons exist.
- Expanding the foreign API through string-keyed mutation.
- Treating example outputs as a substitute for test harnesses.

### WP-13 Populate Scientific Data Bundles and Acquisition Tooling [Status: Done 2026-03-15]

- Issue: the original plan expects `data/climatologies`, `data/cross_sections`, and `data/luts` to become real bundle roots, but those directories are still placeholders while the DISAMAR reference clone carries substantial data/input trees.
- Needs: acquisition scripts or documented import paths, provenance metadata, package ownership for datasets, and cache-compatible bundle layouts.
- How: define bundle structure, add representative baseline assets, connect them to package manifests, and ensure dataset hashes/provenance line up with runtime cache expectations.
- Why this approach: no meaningful completeness or parity story exists without real science data.
- Recommendation rationale: data completeness is a first-class migration track, not a side effect of later implementation.
- Desired outcome: the engine has real packaged climatology, cross-section, and LUT inputs that can drive tests and plans.
- Non-destructive tests:
  - dataset-manifest validation
  - `zig build test`
  - hash/provenance checks in validation suites
- Files by type:
  - data bundles: `data/*`
  - package manifests: `packages/*`
  - validation assets: `validation/*`
- Implementation status (2026-03-15): replaced the empty bundle roots with tracked baseline assets and manifests under `data/climatologies`, `data/cross_sections`, and `data/luts`; added `data/README.md` to document the bundle/import policy; removed the obsolete `.gitkeep` placeholders; added `validation/compatibility/vendor_import_registry.json` plus `validation/compatibility/README.md`; and updated `packages/disamar_standard/package.json` and `validation/release/release_readiness.json` so bundle manifests are part of the shipped evidence set.
- Why this works: the repo now carries reproducible baseline science bundles with digests, upstream provenance hints, and package ownership metadata, which is enough to drive cache/provenance tests and future richer imports without pushing acquisition logic into the runtime.
- Proof / validation: `zig build test` passed on 2026-03-15 with the validation asset suite checking bundle manifests, asset digests, vendor import registry coverage, and release-readiness artifact presence.
- How to test: run `zig build test` and inspect `data/README.md`, the bundle manifests under `data/*/bundle_manifest.json`, the baseline CSV assets, and `validation/compatibility/vendor_import_registry.json`.

### WP-14 Build Parity, Compatibility, and Performance Harnesses Against DISAMAR [Status: Done 2026-03-15]

- Issue: the validation tree currently describes cases and budgets, but it does not yet execute a serious comparison loop against the local DISAMAR reference clone and its sample inputs/outputs.
- Needs: runner infrastructure, selected reference cases, metric comparison policy, and performance baselines tied to the actual missing feature areas.
- How: build compatibility runners over selected `vendor/disamar-fortran/InputFiles` and `test/` cases, expand golden/perf assets into executable checks, and record bounded parity claims instead of open-ended aspirations.
- Why this approach: parity cannot be inferred from directory shape or placeholder solver behavior.
- Recommendation rationale: this is the package that separates “architecturally aligned” from “scientifically credible.”
- Desired outcome: compatibility and performance evidence is generated from real reference scenarios with explicit tolerances.
- Non-destructive tests:
  - `zig build test`
  - dedicated compatibility runner commands
  - perf scenarios backed by actual case data
- Files by type:
  - validation: `validation/compatibility/*`, `validation/golden/*`, `validation/perf/*`
  - tests: `tests/validation/*`, `tests/perf/*`
  - vendor inputs: `vendor/disamar-fortran/InputFiles`, `vendor/disamar-fortran/test`
- Implementation status (2026-03-15): converted `validation/compatibility/parity_matrix.json` and `validation/perf/perf_matrix.json` into executable contract-level matrices with upstream anchors; added `tests/validation/disamar_compatibility_harness_test.zig` and `tests/perf/parity_perf_harness_test.zig`; wired them into `tests/validation/main.zig` and `tests/perf/main.zig`; and expanded `tests/validation/parity_assets_test.zig` so the matrices, assets, and release evidence are all mechanically validated.
- Why this works: parity claims are now tied to concrete vendor-anchored cases, runtime expectations, and bounded performance scenarios that execute in CI instead of living only as narrative matrices.
- Proof / validation: `zig build test` passed on 2026-03-15 with the compatibility harness, performance harness, and validation asset suites all green against the local vendor clone when present.
- How to test: run `zig build test`, then inspect `validation/compatibility/parity_matrix.json`, `validation/perf/perf_matrix.json`, `tests/validation/disamar_compatibility_harness_test.zig`, and `tests/perf/parity_perf_harness_test.zig`.

### WP-15 Complete C/Zig API Parity and ABI Hardening [Status: Done 2026-03-15]

- Issue: the architecture calls for a stable C ABI plus ergonomic Zig wrappers, but the current foreign interface still exposes only a subset of the intended request/result and plugin-host surface.
- Needs: richer request/result descriptors, ownership/lifetime tests, ABI-stability checks, and wrapper ergonomics that remain typed rather than string-driven.
- How: extend the C bridge and headers, add missing wrapper modules, and create ABI-focused tests that fail on enum/layout drift or ownership ambiguity.
- Why this approach: the public API is the long-lived contract. It cannot stay at scaffold depth if the rest of the engine matures.
- Recommendation rationale: the C/Zig boundary is one of the non-negotiables in the original plan and should be treated as a first-class completeness track.
- Desired outcome: the foreign API is explicit, versioned, tested, and broad enough to carry real prepared plans, requests, results, and plugin host services.
- Non-destructive tests:
  - `zig build test`
  - ABI layout tests for C headers and bridge structs
  - wrapper tests in Zig for ownership and conversion semantics
- Files by type:
  - C ABI: `src/api/c/*`
  - Zig wrappers: `src/api/zig/*`
  - tests: `tests/unit/*`, `tests/integration/*`
- Implementation status (2026-03-15): expanded `src/api/c/disamar.h` and `src/api/c/bridge.zig` with typed engine/plan/workspace lifecycle entrypoints, richer request/result descriptors, diagnostics flags, derivative-mode controls, and explicit result-string ownership through workspace-scoped buffers; aligned the bridge with `Plan.deinit()`; and added/updated Zig wrapper coverage in `src/api/zig/wrappers.zig` and `tests/unit/api_wrappers_test.zig`.
- Why this works: the foreign boundary now exposes the core prepared-plan lifecycle explicitly, keeps ownership and null-terminated string lifetimes inside the C bridge, and preserves the typed Zig wrapper layer instead of falling back to string-keyed mutation APIs.
- Proof / validation: `zig build test` and `zig build` both passed on 2026-03-15, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in` completed successfully after the ABI changes.
- How to test: run `zig build test`, `zig build`, and `./zig-out/bin/zdisamar --config data/examples/legacy_config.in`, then inspect `src/api/c/disamar.h`, `src/api/c/bridge.zig`, `src/api/zig/wrappers.zig`, and `tests/unit/api_wrappers_test.zig`.
