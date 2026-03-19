# WP-15 Plugin, Adapter, And Hygiene After Scientific Parity

## Metadata

- Created: 2026-03-18
- Scope: clean up plugin/runtime overreach, split oversized adapters, remove style hazards, and tighten public surfaces only after scientific parity work has stabilized
- Input sources:
  - current Zig plugin/adapter/runtime files
  - prior parity workpackages and findings
  - vendor code only as a capability baseline, not as an architecture template
- Dependencies:
  - `WP-01` through `WP-14`
- Reference baseline:
  - none for architecture; vendor code is a scientific baseline, not the architecture target

## Background

The Zig repo already has several good typed seams, especially provider-style boundaries. But it also carries some premature native-plugin/runtime complexity, oversized adapters, and runtime-facing style hazards. Those should be addressed after the scientific core is stable so cleanup work does not interfere with parity-critical development.

## Overarching Goals

- Keep the useful typed provider seams.
- Reduce or gate architecture that is ahead of the scientific core.
- Split oversized files and remove runtime-facing style hazards.

## Non-goals

- Rewriting the repo around the Fortran architecture.
- Pushing cleanup ahead of scientific parity.
- Removing typed extensibility that already pays for itself.

### WP-15 Plugin, adapter, and hygiene after scientific parity [Status: Todo]

Issue:
The repo contains both good typed seams and some complexity that is premature relative to the current scientific core. Cleanup should happen, but only after the parity work above stabilizes.

Needs:
- smaller public surfaces
- experimental gating for native-plugin/ABI paths that are not yet first-class
- split adapter/config monoliths
- removal of runtime-facing `unreachable`/panic hazards and non-idiomatic style leftovers

How:
1. Keep the provider seam, trim or gate the native-plugin path.
2. Split oversized config/ingest/export files into focused modules.
3. Remove runtime-facing `unreachable`, `catch unreachable`, and panic-on-user-input patterns.
4. Collapse umbrella files to zero-logic re-export modules only.

Why this approach:
Cleanup after scientific parity avoids refactoring the same files repeatedly while the core algorithms are still changing. It also keeps the architecture work grounded in real needs rather than speculation.

Recommendation rationale:
This is intentionally last. It becomes valuable once the parity-critical code paths are stable enough that cleanup will stick.

Desired outcome:
The repo keeps its strong typed-engine shape, but with less unstable public surface, fewer monolith files, clearer experimental gating, and cleaner runtime-facing error handling.

Non-destructive tests:
- `zig build test-unit --summary all`
- `zig build test-integration --summary all`
- `zig build test-validation --summary all`
- `zig test tests/unit/plugin_native_resolution_test.zig`
- `zig test tests/unit/canonical_config_test.zig`
- `zig test tests/integration/cli_integration_test.zig`

Files by type:
- Plugin/runtime targets:
  - `src/plugins/providers/root.zig`
  - `src/plugins/providers/transport.zig`
  - `src/plugins/providers/instrument.zig`
  - `src/plugins/providers/optics.zig`
  - `src/plugins/providers/surface.zig`
  - `src/plugins/providers/noise.zig`
  - `src/plugins/providers/retrieval.zig`
  - `src/plugins/selection.zig`
  - `src/plugins/slots.zig`
  - `src/plugins/registry/CapabilityRegistry.zig`
  - `src/plugins/loader/manifest.zig`
  - `src/plugins/loader/dynlib.zig`
  - `src/plugins/loader/resolver.zig`
  - `src/plugins/loader/runtime.zig`
  - `src/plugins/abi/abi_types.zig`
  - `src/plugins/abi/host_api.zig`
  - `src/plugins/abi/plugin.h`
  - `src/plugins/root.zig`
- Adapter/export targets:
  - `src/adapters/canonical_config/Document.zig`
  - `src/adapters/canonical_config/yaml.zig`
  - `src/adapters/exporters/netcdf_cf.zig`
  - `src/adapters/exporters/zarr.zig`
  - `src/adapters/ingest/reference_assets.zig`
  - `src/adapters/legacy_config/*`
- Style-hazard targets:
  - `src/kernels/transport/adding.zig`
  - `src/kernels/transport/labos.zig`
  - `src/plugins/loader/resolver.zig`
  - `src/api/zig/wrappers.zig`
  - any remaining bottom-import files and panic/unreachable runtime boundaries

## Exact Patch Checklist

- [ ] `src/plugins/providers/*`, `src/plugins/selection.zig`, `src/plugins/slots.zig`: keep the typed provider seam and remove unnecessary stringly internal routing.
  - Resolve provider/slot IDs once and pass compact typed identifiers internally.
  - Do not delete the provider seam; it is one of the better parts of the Zig design.

- [ ] `src/plugins/registry/CapabilityRegistry.zig`, `src/plugins/loader/*`, `src/plugins/abi/*`: gate the native-plugin path if it is still not required as a first-class shipping feature.
  - This path is useful groundwork, but it should not dominate the main scientific code path or public surface before it is actually needed.
  - Keep builtin providers first-class even if the native-plugin path becomes experimental.

- [ ] `src/adapters/canonical_config/Document.zig`, `src/adapters/canonical_config/yaml.zig`, `src/adapters/ingest/reference_assets.zig`, `src/adapters/exporters/netcdf_cf.zig`, `src/adapters/exporters/zarr.zig`: split remaining oversized files.
  - The goal is not churn for its own sake; it is to keep each file focused enough that future scientific changes do not recreate monoliths.
  - Preserve typed boundaries established in earlier WPs.

- [ ] Runtime-facing error/style cleanup: `src/kernels/transport/adding.zig`, `src/kernels/transport/labos.zig`, `src/plugins/loader/resolver.zig`, `src/api/zig/wrappers.zig`, and any remaining bottom-import files.
  - Remove `unreachable` and `catch unreachable` from real input/provider/runtime boundaries.
  - Replace panic-on-user-input or panic-on-ABI-conversion with typed errors.
  - Move imports to the top and normalize file style once behavior is stable.

- [ ] `tests/unit/plugin_native_resolution_test.zig`, `tests/unit/canonical_config_test.zig`, `tests/integration/cli_integration_test.zig`: update tests to reflect the cleaned and gated architecture.
  - Confirm that builtin provider resolution remains stable.
  - Confirm that experimental native-plugin paths are clearly gated and tested only when enabled.
  - Confirm that adapter splits do not change CLI-visible behavior unexpectedly.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Proof / validation section filled with exact commands and outcomes
- [ ] How to test section is reproducible
- [ ] `overview.md` rollup row updated
- [ ] Typed provider seams remain intact while unstable native-plugin paths are clearly gated
- [ ] Oversized adapters are split without regrowing new monoliths
- [ ] Runtime-facing panic/unreachable hazards are removed from real user/provider boundaries

## Implementation Status (2026-03-18)

Planning only. No code changes yet.

## Why This Works

By deferring hygiene work until parity-critical code is stable, the cleanup can be decisive instead of provisional. The result should be a smaller, safer, more idiomatic Zig surface without sacrificing the architecture that already helps the scientific core.

## Proof / Validation

- Planned: `zig test tests/unit/plugin_native_resolution_test.zig` -> builtin and gated-native plugin paths behave as expected
- Planned: `zig test tests/unit/canonical_config_test.zig` -> adapter splits and stricter errors preserve canonical-config behavior
- Planned: `zig test tests/integration/cli_integration_test.zig` -> CLI-visible behavior remains stable after cleanup

## How To Test

1. Build and run the full unit/integration/validation suite after cleanup.
2. Enable and disable any experimental native-plugin flag and confirm behavior changes only where expected.
3. Scan runtime-facing modules for remaining `unreachable`, `catch unreachable`, and panic-on-input patterns.
4. Confirm the public/root export surface is smaller and more intentional than before.
