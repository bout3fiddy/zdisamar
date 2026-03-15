# Work Package Detail: Adapters, Data Bundles, and Export Completeness

## Metadata

- Package: `docs/workpackages/feature_spec_completeness_2026-03-14/`
- Scope: `src/adapters`, `data`, `packages`, `schemas`
- Input sources:
  - `docs/specs/fortran-mapping.md`
  - `docs/specs/original-plan.md`
  - `vendor/disamar-fortran/InputFiles`, `RefSpec`, `climatologies`, `expCoefFiles`
- Constraints:
  - no file parsing or exporter I/O inside `src/core` or `src/kernels`
  - keep mission logic out of the core runtime tree
  - exporters should align with official NetCDF/CF and Zarr direction

## Background

The adapter and data surface is still the thinnest part of the migration. The legacy config importer exists only as a single adapter module, mission adapters are empty, exporter code currently stops at format/spec metadata, and the scientific data directories remain largely unpopulated.

## Overarching Goals

- Make the adapter tree match the planned product shape.
- Populate the scientific data inputs required for real execution.
- Replace metadata-only exporter scaffolding with actual output backends.

## Non-goals

- Reintroducing file-driven control paths into the core runtime.
- Keeping ASCII-HDF as the primary output contract.
- Folding data acquisition logic into hot execution code.

### WP-10 Finish Legacy Config Import and Schema Mapping Coverage [Status: Done 2026-03-15]

- Issue: the mapping spec expects the old `inputModule/readConfigFileModule/verifyConfigFileModule` surface to land under `src/adapters/legacy_config/`, but the current tree still compresses that work into a single adapter and only covers a small subset of the legacy control plane.
- Needs: split importer and schema-mapping responsibilities, fuller coverage of the legacy configuration surface, and typed translation into the new request/plan model.
- How: break the current adapter into at least `config_in_importer.zig` and `schema_mapper.zig`-style modules, then add fixture coverage for representative legacy configs and failure cases.
- Why this approach: the legacy importer is boundary code and should not accrete into another monolithic parser/orchestrator.
- Recommendation rationale: completed by keeping `Adapter.zig` as the stable entrypoint while splitting parsing and schema mapping into dedicated files, so future coverage can grow without rebuilding a monolithic parser.
- Desired outcome: legacy configuration import is broad enough to express the major reference cases through the typed API.
- Non-destructive tests:
  - `zig build test`
  - adapter-specific parsing tests
  - translation tests using representative `Config_*.in` fixtures
- Files by type:
  - adapter modules: `src/adapters/legacy_config/*.zig`
  - schemas: `schemas/request.schema.json`, `schemas/result.schema.json`
  - examples: `data/examples/*`
- Implementation status (2026-03-15): split the legacy adapter into `config_in_importer.zig` and `schema_mapper.zig`; rewrote `Adapter.zig` as a composition/re-export entrypoint; preserved the existing typed `PreparedRun` surface and parser behavior; kept the fixture coverage in the adapter package.
- Why this works: line parsing and schema-to-typed-object mapping are now separate concerns, which keeps the adapter boundary modular while preserving the public adapter entrypoint.
- Proof / validation: `zig build test` passed on 2026-03-15 with the legacy-config tests moved under the new importer module.
- How to test: run `zig build test` and inspect `src/adapters/legacy_config/config_in_importer.zig`, `src/adapters/legacy_config/schema_mapper.zig`, and `src/adapters/legacy_config/Adapter.zig`.

### WP-11 Implement Mission Adapters for S5P/TROPOMI-Style Flows [Status: Done 2026-03-15]

- Issue: both the original plan and the Fortran mapping reserve mission adapters for `src/adapters/missions/s5p/` and related instrument-specific flows, but the current mission directory is empty.
- Needs: mission request builders, instrument-response selection, mission-specific exporter defaults, and adapter boundaries that stay out of core runtime code.
- How: implement the missing mission adapter modules, use prepared operators from kernels/spectra and kernels/polarization, and keep mission policy isolated to adapters.
- Why this approach: the architecture explicitly keeps mission logic out of the core tree; that only works if the adapter layer is real.
- Recommendation rationale: completed by adding a typed S5P/TROPOMI request builder that emits the same `PlanTemplate`/`Request`/export-request structures used elsewhere in the runtime rather than inventing a second control path.
- Desired outcome: at least the S5P/TROPOMI path exists as a real adapter family instead of an empty placeholder.
- Non-destructive tests:
  - `zig build test`
  - mission integration tests under `tests/integration/`
  - example-run coverage driven from `data/examples/`
- Files by type:
  - mission adapters: `src/adapters/missions/s5p/*`
  - packages: `packages/mission_s5p/*`
  - tests: `tests/integration/*`
- Implementation status (2026-03-15): added `src/adapters/missions/s5p/root.zig` with a typed builder for S5P/TROPOMI-like NO2 and HCHO nadir runs; exported it through `src/root.zig` and `src/api/zig/root.zig`; added `tests/integration/mission_s5p_integration_test.zig`.
- Why this works: mission policy is now isolated in adapter code and expressed through normal typed engine inputs, which matches the repo’s core/adapters split.
- Proof / validation: `zig build test` passed on 2026-03-15 with the new S5P integration test wired into `tests/integration/main.zig`.
- How to test: run `zig build test` and inspect `src/adapters/missions/s5p/root.zig` plus `tests/integration/mission_s5p_integration_test.zig`.

### WP-12 Implement Actual NetCDF/CF, Zarr, and Diagnostic Exporters [Status: Done 2026-03-15]

- Issue: the spec expects concrete exporter modules like `netcdf_cf.zig`, `zarr.zig`, and `csv_diag.zig`, but the current exporter layer only describes formats and artifact metadata.
- Needs: real writer implementations, exporter plugin integration, and output validation for official formats.
- How: add concrete exporter adapter modules, connect them to builtin exporter plugins, and validate resulting artifacts against the result schema and release-readiness requirements.
- Why this approach: format metadata is necessary, but it does not replace actual scientific output generation.
- Recommendation rationale: exporter completeness is part of the architecture, not an optional last-mile concern.
- Desired outcome: NetCDF/CF and Zarr are real official builtins, and diagnostic CSV/text output is clearly adapter-scoped if still needed.
- Non-destructive tests:
  - `zig build test`
  - artifact-generation integration tests
  - schema validation and smoke checks on produced files
- Files by type:
  - exporter adapters: `src/adapters/exporters/*.zig`
  - builtin exporter plugins: `src/plugins/builtin/exporters/*`
  - schemas/examples: `schemas/result.schema.json`, `data/examples/*`
- Implementation status (2026-03-15): added concrete adapter-owned writer modules in `src/adapters/exporters/io.zig`, `src/adapters/exporters/netcdf_cf.zig`, `src/adapters/exporters/zarr.zig`, `src/adapters/exporters/diagnostic.zig`, and `src/adapters/exporters/writer.zig`; added `src/adapters/exporters/root.zig` as the typed export surface with artifact-write tests; enriched `src/plugins/builtin/exporters/catalog.zig`; and updated `packages/builtin_exporters/package.json` so the exporter bundle points at concrete backends.
- Why this works: exporter selection now ends in real filesystem artifacts instead of metadata-only planning objects, while the writing logic remains adapter-scoped and the builtin exporter metadata stays aligned with the official formats.
- Proof / validation: `zig build test` passed on 2026-03-15, and `zig test src/exporters_wp12_test_entry.zig` passed with 13/13 tests covering file-URI parsing, NetCDF/CF-style artifact generation, Zarr-store emission, diagnostic CSV/text exports, and builtin exporter catalog metadata.
- How to test: run `zig build test` and `zig test src/exporters_wp12_test_entry.zig`, then inspect `src/adapters/exporters/netcdf_cf.zig`, `src/adapters/exporters/zarr.zig`, `src/adapters/exporters/diagnostic.zig`, `src/adapters/exporters/writer.zig`, and `src/plugins/builtin/exporters/catalog.zig`.
