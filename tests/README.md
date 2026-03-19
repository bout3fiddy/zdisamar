# Test Suite Layout

The `tests/` tree contains executable checks that run quickly in CI and local
development.

- `tests/unit/`: lifecycle and contract-level checks with tight scope.
- `tests/integration/`: end-to-end API flow checks through the scaffold runtime.
- `tests/golden/`: assertions against golden fixtures in `validation/golden/`.
- `tests/perf/`: repeatable performance smoke checks with bounded loops.
- `tests/validation/`: schema and evidence-asset integrity checks for validation data.

Use `zig build check` for the fast local loop.
Use `zig build test-transport` for the focused transport/parity loop.

Run all suites with `zig build test`, or targeted suites with:

- `zig build test-unit`
- `zig build test-integration`
- `zig build test-integration-forward-model`
- `zig build test-golden`
- `zig build test-perf`
- `zig build test-validation`
- `zig build test-validation-compatibility`
- `zig build test-validation-o2a`
