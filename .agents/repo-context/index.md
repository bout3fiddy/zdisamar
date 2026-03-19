# Repo Context Index

owner: zdisamar
last_verified: 2026-03-18

## Canonical References

- root AGENTS.md

## Local-Only Areas

- `docs/specs/` is for scratch plans and working notes that should not be committed.
- `vendor/disamar-fortran/` is a local upstream clone recreated by `./scripts/bootstrap-upstream.sh`.

## Verification Baseline

- Use `zig build check` for the fast local verification loop.
- Use `zig build test-transport` for focused transport/parity verification.
- Use `zig build test-validation-compatibility` for fast compatibility smoke checks.
- Use `zig build test-validation-o2a-vendor` for the O2A vendor trend assessment lane.
- Use `zig build test` for the full verification baseline.
- Treat changes under `src/core`, `src/kernels`, `src/retrieval`, `src/runtime`, `src/plugins`, and `src/api` as code changes that should keep that baseline green.
