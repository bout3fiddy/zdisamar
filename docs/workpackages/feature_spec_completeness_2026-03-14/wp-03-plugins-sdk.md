# Work Package Detail: Plugin Runtime and SDK Completeness

## Metadata

- Package: `docs/workpackages/feature_spec_completeness_2026-03-14/`
- Scope: `src/plugins`, `src/api/c`, `packages`, `plugins/examples`
- Input sources:
  - `docs/specs/architecture.md`
  - `docs/specs/original-plan.md`
  - current plugin scaffolding in `src/plugins/`
- Constraints:
  - keep native plugins behind the C ABI
  - plugin changes invalidate future plans, not active hot loops
  - no in-loop plugin callback dispatch

## Background

The current plugin surface covers manifests, registry state, ABI declarations, and example manifests. That is enough to define a contract, but not enough to load or execute a plugin, ship substantive builtin plugin families, or enforce the two-lane plugin architecture end to end.

## Overarching Goals

- Turn the current plugin metadata scaffold into a usable runtime/SDK.
- Make the two-lane declarative/native model real instead of nominal.
- Close the gap between “manifest exists” and “capability can actually run.”

## Non-goals

- Claiming arbitrary native plugins are memory-safe.
- Putting plugin callbacks inside transport hot paths.
- Expanding plugin scope into mission logic or file parsing in the core.

### WP-07 Implement the Native Plugin Resolver and Dynamic Loader [Status: Done 2026-03-15]

- Issue: the original plan names `resolver.zig`, `dynlib.zig`, `abi_types.zig`, and `host_api.zig`, but the current plugin runtime stops at manifest validation, capability registration, and ABI header declarations.
- Needs: a real resolution path from manifest to loaded native capability, host API wrappers, ABI type definitions, and lifecycle handling for native plugin instances.
- How: add the missing loader and ABI-support modules, define typed wrappers around dynamic loading, and integrate plan-time resolution so prepared plans carry resolved function tables instead of only metadata.
- Why this approach: without this layer, native plugins are declarative metadata with no execution path.
- Recommendation rationale: native plugins should either exist as trusted executable extensions or not be advertised as part of the architecture. This WP makes the contract honest.
- Desired outcome: a trusted native plugin can be resolved, version-checked, prepared, executed at a coarse grain, and destroyed through the stable C ABI.
- Non-destructive tests:
  - `zig build test`
  - focused ABI and loader tests
  - plugin example smoke tests under `tests/validation/`
- Files by type:
  - loader: `src/plugins/loader/*.zig`
  - ABI helpers: `src/plugins/abi/*.zig`, `src/api/c/*`
  - validation: `plugins/examples/*`, `tests/validation/*`
- Implementation status (2026-03-15): added typed native ABI support in `src/plugins/abi/abi_types.zig` and `src/plugins/abi/host_api.zig`; added dynamic/static symbol loading in `src/plugins/loader/dynlib.zig`; added manifest-to-native resolution in `src/plugins/loader/resolver.zig`; added plan-time runtime freezing in `src/plugins/loader/runtime.zig`; and extended `src/core/Plan.zig` plus `src/core/Engine.zig` so prepared plans carry resolved native hooks instead of only plugin metadata.
- Why this works: manifest validation, ABI compatibility checks, host callback wiring, symbol lookup, and coarse-grained prepare/execute/destroy hooks now run through one typed path before execution starts, which makes native plugins an executable capability instead of a nominal manifest field.
- Proof / validation: `zig build test` passed on 2026-03-15 with resolver/runtime tests, engine lifecycle tests, C ABI lifecycle coverage, and the existing plugin example manifest smoke tests all green.
- How to test: run `zig build test` and inspect `src/plugins/loader/dynlib.zig`, `src/plugins/loader/resolver.zig`, `src/plugins/loader/runtime.zig`, `src/plugins/abi/abi_types.zig`, and `src/core/Engine.zig`.

### WP-08 Ship Substantive Builtin Plugin Families and Model Packs [Status: Done 2026-03-15]

- Issue: only builtin exporters have any actual files. Builtin instruments, retrieval, surfaces, and transport remain empty placeholders, and packages mostly stop at metadata.
- Needs: real builtin plugin content and package payloads for the standard DISAMAR family, mission adapters, and official exporters.
- How: populate builtin plugin families with actual manifests plus implementation or declarative data packs, and ensure `packages/disamar_standard`, `packages/mission_s5p`, and `packages/builtin_exporters` describe real shipped bundles rather than only package manifests.
- Why this approach: the architecture treats DISAMAR as a bundled model family. That bundle must be materially present, not just named.
- Recommendation rationale: without actual builtin packs, the plugin model cannot serve as the product-distribution mechanism the spec expects.
- Desired outcome: builtin plugin families are populated enough that the standard model pack is a real package set rather than a placeholder label.
- Non-destructive tests:
  - `zig build test`
  - package-manifest and builtin-plugin validation tests
  - fixture validation of shipped manifests and datasets
- Files by type:
  - builtins: `src/plugins/builtin/*`
  - package definitions: `packages/*`
  - example manifests: `plugins/examples/*`
- Implementation status (2026-03-15): replaced the empty builtin plugin family placeholders with native builtin modules under `src/plugins/builtin/transport/root.zig`, `src/plugins/builtin/retrieval/root.zig`, `src/plugins/builtin/surfaces/root.zig`, and `src/plugins/builtin/instruments/root.zig`; added `src/plugins/builtin/root.zig` as the builtin resolution catalog; registered those packs in `src/plugins/registry/CapabilityRegistry.zig`; and updated `packages/disamar_standard/package.json`, `packages/mission_s5p/package.json`, and `packages/builtin_exporters/package.json` so the shipped bundle metadata names real builtin families and data manifests.
- Why this works: the standard and mission package layers now point at actual builtin plugin content across transport, retrieval, surfaces, instruments, and exporters, so package manifests describe shipped capability families rather than only placeholder labels.
- Proof / validation: `zig build test` passed on 2026-03-15 with builtin catalog/runtime tests, package metadata checks, and downstream engine/integration suites consuming the populated builtin registry.
- How to test: run `zig build test` and inspect `src/plugins/builtin/root.zig`, the family roots under `src/plugins/builtin/*/root.zig`, `src/plugins/registry/CapabilityRegistry.zig`, `packages/disamar_standard/package.json`, and `packages/mission_s5p/package.json`.

### WP-09 Enforce Hot-Swap, Host-Service, and Provenance Rules [Status: Done 2026-03-15]

- Issue: the spec requires plan-boundary hot-swap semantics, coarse-grained execution, and host callback tables, but the current implementation only snapshots plugin metadata and dataset hashes.
- Needs: resolver invalidation rules, host callback/service registration, resolved capability ownership, and provenance that captures loaded capability identity at execution time.
- How: extend the plugin runtime so capability resolution happens once per plan, host services are explicit, and results/provenance can describe the resolved executable path without runtime ambiguity.
- Why this approach: plugin architecture is not complete when only the manifest side exists. The execution and invalidation semantics are the point.
- Recommendation rationale: provenance and hot-swap semantics must be fixed before plugin-powered transport, retrieval, or export can be trusted.
- Desired outcome: plugin lifecycle and provenance behave exactly as the architecture notes describe.
- Non-destructive tests:
  - `zig build test`
  - generation/invalidation regression tests
  - plugin validation matrix expansion in `validation/plugin_tests/`
- Files by type:
  - registry/runtime: `src/plugins/registry/*.zig`, `src/plugins/loader/*.zig`
  - provenance/result: `src/core/provenance.zig`, `src/core/Result.zig`
  - validation: `validation/plugin_tests/*`, `tests/validation/*`
- Implementation status (2026-03-15): extended `src/plugins/registry/CapabilityRegistry.zig` snapshots with native entry-symbol/library-path metadata; resolved native capabilities once per plan in `src/plugins/loader/runtime.zig`; stored that frozen runtime on `src/core/Plan.zig`; executed coarse-grained plugin hooks from `src/core/Engine.zig`; extended `src/core/provenance.zig` and `schemas/result.schema.json` with native capability slot and entry-symbol evidence; and updated `validation/golden/result_provenance_golden.json` plus the provenance tests to assert those fields.
- Why this works: plugin identity is now frozen at plan preparation time, active execution uses that frozen resolution instead of consulting mutable registry state, and result provenance can report which native capability slots and entry symbols were actually resolved for the run.
- Proof / validation: `zig build test` passed on 2026-03-15 with plan snapshot regression tests, golden provenance checks, validation asset checks, and end-to-end engine execution through the frozen plugin runtime.
- How to test: run `zig build test` and inspect `src/plugins/registry/CapabilityRegistry.zig`, `src/plugins/loader/runtime.zig`, `src/core/Plan.zig`, `src/core/provenance.zig`, `schemas/result.schema.json`, and `validation/golden/result_provenance_golden.json`.
