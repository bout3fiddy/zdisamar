# Repo Context Index

owner: zdisamar
last_verified: 2026-03-14

## Canonical References

- [Architecture spec](/Users/swadhinnanda/Projects/git/zdisamar/specs/architecture.md)
- [Fortran mapping spec](/Users/swadhinnanda/Projects/git/zdisamar/specs/fortran-mapping.md)
- [Root AGENTS router](/Users/swadhinnanda/Projects/git/zdisamar/AGENTS.md)

## Local-Only Areas

- `docs/specs/` is for scratch plans and working notes that should not be committed.
- `vendor/disamar-fortran/` is a local upstream clone recreated by `./scripts/bootstrap-upstream.sh`.

## Verification Baseline

- The repo currently verifies with `zig build test`.
- Treat changes under `src/core`, `src/kernels`, `src/retrieval`, `src/runtime`, `src/plugins`, and `src/api` as code changes that should keep that baseline green.
