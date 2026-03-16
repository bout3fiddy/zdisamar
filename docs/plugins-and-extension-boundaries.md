# Plugins and Extension Boundaries

If you want the simplest walkthrough first, read [Plugin System End-To-End Flow](./plugin-system-end-to-end.md) before this page.

## Purpose Of The Plugin System

The plugin system exists to make capability selection explicit without weakening the scientific execution model. In a radiative-transfer and retrieval codebase, "extension" can easily become a source of hidden state, private callbacks, and irreproducible execution. The architecture in `zdisamar` is designed to avoid that failure mode.

The stable execution contract remains:

`Engine -> Plan -> Workspace -> Request -> Result`

Plugins may supply capabilities inside that life cycle, but they do not redefine it.

## What A Capability Is

A plugin capability is a versioned provider bound to a slot. The capability metadata records at least:

- slot name,
- provider name,
- manifest id,
- package and version,
- execution lane,
- dataset hashes or native-entry metadata when relevant.

This information is assembled in `src/plugins/registry/CapabilityRegistry.zig` and frozen into the plan snapshot. The result provenance then records the frozen inventory.

## Two Execution Lanes

The current system distinguishes two plugin lanes.

### Declarative lane

Declarative plugins describe a capability surface without loading native code. They are useful for data packs, catalogs, and provenance-bearing capabilities that do not need runtime hooks.

The builtin example in the current tree is:

- `builtin.cross_sections`
  - slot: `absorber.provider`
  - package: `disamar_standard`
  - role: declares the standard spectroscopy data pack and its dataset hashes

### Native lane

Native plugins resolve through the C ABI under `src/api/c` and `src/plugins/abi`. They expose a manifest, an entry symbol, and `prepare` / `execute` hooks.

The native lane remains the only supported external ABI boundary, but the default engine policy keeps `allow_native_plugins = false`. In that default mode, builtin manifests that carry native metadata are still registered for provenance and provider selection, but execution stays on typed Zig providers unless native loading is explicitly enabled.

Builtin manifests with opt-in native metadata are:

- `builtin.transport_dispatcher`
  - slot: `transport.solver`
- `builtin.oe_solver`
  - slot: `retrieval.algorithm`
- `builtin.lambertian_surface`
  - slot: `surface.model`

Current builtin declarative capability surfaces include:

- `builtin.cross_sections`
  - slot: `absorber.provider`
- `builtin.generic_response`
  - slot: `instrument.response`
- default-mode typed-provider registrations for transport, retrieval, and surface lanes when native loading is disabled
- builtin noise registrations
  - slot: `noise.model`
  - providers catalogued today: `scene_noise`, `none_noise`, `shot_noise`, `s5p_operational_noise`
- `builtin.default_diagnostics`
  - slot: `diagnostics.metric`
- builtin exporter registrations
  - slot: `exporter`
  - formats catalogued today: `netcdf_cf`, `zarr`

## Why The ABI Boundary Is Strict

Native capability contracts stay behind the C ABI for three reasons.

- Internal Zig implementation details should remain free to change without silently breaking external extensions.
- Provenance must record capability identity at a stable binary boundary.
- Scientific runs must not depend on a plugin reaching into internal engine state that was never declared in the plan.

That is why `src/plugins/abi/plugin.h` and `src/api/c/disamar.h` are treated as the public extension boundary.

## Plan-Time Freezing

Capability choice is a plan concern, not a mid-run side effect.

The sequence is:

1. manifests and builtin providers are registered,
2. `Engine.preparePlan(...)` snapshots the registry,
3. native capabilities are resolved from that snapshot only when native loading is enabled,
4. the frozen capability inventory is attached to provenance,
5. request execution observes the already-selected runtime.

This matters scientifically. A result should be traceable to a fixed set of providers, versions, and dataset hashes. If capability resolution were allowed to drift during execution, reproducing a retrieval or a validation case would become much harder.

## What The Current Builtins Mean

The builtin capabilities in the repository serve two related purposes.

### Stable extension contracts

They establish the slots that matter scientifically:

- transport family selection,
- retrieval algorithm selection,
- surface-model selection,
- instrument-response selection,
- exporter-format identity,
- reference-data pack identity.

### Runtime and provenance scaffolding

They also prove that the manifest, registry, runtime-resolution, and provenance path is working end to end.

At present, the core O2 A-band science path still lives mainly in the typed core, model, runtime, and adapter code rather than inside dynamically loaded physics plugins. The plugin system therefore should be understood as an explicit extension boundary with real provenance and optional runtime hooks, not as a claim that all scientific content has been moved out of the main codebase or that native loading is the default path today.

## What Should Not Be A Plugin

Several important responsibilities are intentionally kept outside plugins:

- mission file parsing,
- scene typing,
- reference-data bundle parsing,
- optics preparation internals,
- core request and result shapes.

Those pieces define the scientific state being solved. They are part of the engine contract, not optional extensions.

## When Plugins Are Appropriate

The plugin boundary is appropriate when a capability can be stated cleanly as a replaceable provider. Examples include:

- an alternative transport solver family,
- an additional retrieval algorithm,
- a new surface model,
- an instrument-response model,
- a formally versioned exporter family.

The key test is whether the capability can fit the typed life cycle without hidden mutation or private file-I/O paths.

## How To Add A New Plugin

The current extension workflow is:

1. define the capability slot and provider identity in a manifest,
2. decide whether the capability is declarative or native,
3. for native plugins, implement the C-ABI entry point and the `prepare` / `execute` hooks,
4. register the manifest so it enters the capability registry,
5. verify that the plan snapshot and result provenance expose the new provider correctly.

If a proposed extension cannot pass through those steps without inventing a side channel, it probably does not belong in the plugin system.

## Exporters As A Special Case

Exporter formats are catalogued as capabilities, but their current execution path is adapter-owned rather than part of the prepared native runtime. That is intentional: exporters operate on `Result` after the scientific run is complete, whereas transport, retrieval, surface, and instrument-response capabilities affect the run itself.

## Reading Order In Code

To understand the current plugin system:

1. read `src/plugins/loader/manifest.zig`,
2. read `src/plugins/registry/CapabilityRegistry.zig`,
3. read `src/plugins/loader/runtime.zig`,
4. read `src/core/Plan.zig`,
5. read `src/core/provenance.zig`,
6. inspect the builtin capability roots under `src/plugins/builtin/`.
