# Architecture Scaffold

This repository targets a reusable radiative-transfer platform with DISAMAR shipped as one standard model family instead of preserving the legacy application shape.

## Top-Level Split

- `src/core`: engine lifecycle, prepared plans, workspaces, typed requests/results, provenance.
- `src/model`: canonical scene and observation-domain types.
- `src/kernels`: transport, spectral, polarization, interpolation, quadrature, and linalg kernels.
- `src/retrieval`: inverse methods layered on the same canonical scene model.
- `src/runtime`: caches and thread/batch execution support.
- `src/plugins`: manifest handling, capability registry, trusted native ABI, and builtins.
- `src/api`: stable C ABI plus ergonomic Zig bindings.
- `src/adapters`: CLI, legacy `Config.in` import, mission adapters, and exporters.

## Runtime Objects

- `Engine`: owns the plugin registry, catalog, and long-lived caches.
- `Plan`: compiled selection of model family, transport route, and static options.
- `Workspace`: per-thread scratch state only.
- `Request`: one typed scene plus requested outputs.
- `Result`: typed outputs, diagnostics, and provenance.
- `Catalog`: discoverable inventory of model families and exporters.

## Plugin Model

- Declarative plugins are the default collaboration path for LUTs, cross sections, climatologies, priors, and exporter metadata.
- Native plugins are treated as trusted capability extensions behind a stable C ABI.
- Plugin resolution happens at plan preparation time; hot loops stay free of plugin callbacks.

## Output Direction

The intended default export targets are NetCDF/CF and Zarr, with legacy text and mission-specific formats moved into adapters or plugins instead of the core runtime.
