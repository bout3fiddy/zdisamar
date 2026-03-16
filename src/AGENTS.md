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

## Port Regression Notes

- Temporary checklist: remove an item once the Zig port and its tests prove that failure mode is impossible.
- Avoid 1-based/0-based flattening mistakes when mapping multidimensional coefficient tensors; no linearized port path may read a synthetic element `0` or transpose coefficient axes silently.
- Avoid backtracking underflow in config/text readers; rewinds and backspaces must stop cleanly at the start of a buffer instead of reading before the first byte.
- Avoid calling `len`/`size`-equivalent operations on absent or uninitialized storage just to validate required inputs; return a typed configuration/input error first.
- Avoid allocate-without-reset behavior for static config buffers; repeated config loads must free, reuse, or overwrite existing storage safely.
- Avoid allocate-without-reset behavior for per-request workspace buffers; repeated retrievals on the same workspace must be idempotent with respect to owned memory.
- Avoid cleanup paths that assume full initialization; partial-init and early-error teardown must guard every optional resource before release.
- Avoid singular/plural field-name drift between declarations and use sites; shared ported structures need one canonical name per field and compile-time coverage in tests.
- Avoid build-order assumptions in Zig build logic or generated C/Fortran interop steps; dependency edges must be explicit so parallel builds stay correct.
