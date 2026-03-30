# Test Suite Layout

The `tests/` tree contains executable checks that run quickly in CI and local
development.

- `tests/unit/`: lifecycle and contract-level checks with tight scope.
- `tests/integration/`: end-to-end API flow checks through the scaffold runtime.
- `tests/golden/`: assertions against golden fixtures in `validation/golden/`.
- `tests/perf/`: repeatable performance smoke checks with bounded loops.
- `tests/validation/`: schema and evidence-asset integrity checks for validation data.

Use `zig build check` for the fast local loop.
Use `zig build test-fast` for the fast presubmit lane.
Use `zig build bench` for the non-gating benchmark summary lane.
Use `zig build tidy` for architecture and policy checks.
Use `zig build test-transport` for the focused transport/parity loop, including the operational measured-input compatibility classification proof.
Use `zig build test-validation-compatibility` for fast compatibility smoke checks.
Use `zig build test-validation-o2a-vendor` only for the opt-in O2A vendor trend assessment lane.

Run all suites with `zig build test`, or targeted suites with:

- `zig build fmt-check`
- `zig build test-unit`
- `zig build test-integration`
- `zig build test-integration-forward-model`
- `zig build test-golden`
- `zig build test-perf`
- `zig build test-validation`
- `zig build test-validation-compatibility`
- `zig build test-validation-compatibility-transport-measurement`
- `zig build test-validation-compatibility-retrieval`
- `zig build test-validation-compatibility-optics`
- `zig build test-validation-compatibility-rtm-controls`
- `zig build test-validation-compatibility-asciihdf`
- `zig build test-validation-compatibility-operational-measured-input`
- `zig build test-validation-compatibility-full`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
