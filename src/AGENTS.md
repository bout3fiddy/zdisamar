# Source Tree

- `src/core/` owns engine lifecycle, typed requests/results, provenance, and explicit ownership boundaries.
- `src/model/` owns canonical scene and observation-domain types. Do not fork separate simulation and retrieval object trees.
- `src/kernels/` is for reusable numeric kernels only. Keep hot paths free of I/O and coarse-grained plugin dispatch.
- `src/retrieval/` layers inverse methods on the canonical scene model.
- `src/runtime/` owns caches, schedulers, and per-thread execution support.
- `src/plugins/` owns manifests, capability registration, and plugin ABI boundaries.
- `src/api/` owns the stable C ABI and Zig-facing wrappers.
- `src/adapters/` owns CLI, legacy config import, mission wiring, and export shims.

## Local Rules

- Push domain-heavy guidance into the nearest scoped `AGENTS.md` before expanding this file.
- Prefer moving legacy behavior to `src/adapters/` instead of leaking it back into `src/core/`.
