# Runtime

- `src/runtime/` owns long-lived caches, batch scheduling, and per-thread execution support.
- Cache ownership must be explicit and compatible with prepared-plan reuse.
- Workspace reset behavior should favor reuse without reintroducing hidden global state.
