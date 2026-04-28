# Repo Context Index

owner: zdisamar
last_verified: 2026-04-28

## Current Shape

- Public flow: input -> forward model -> output.
- Source code: `src/input/`, `src/forward_model/`, `src/output/`, `src/common/`, `src/validation/disamar_reference/`.
- Scientific assets: `data/reference_data/`.
- Tracked DISAMAR-reference evidence: `validation/`.

## Verification Baseline

- `zig build check`: fast local baseline.
- `zig build test-fast`: broader fast presubmit lane.
- `zig build test`: full retained verification baseline.
- `zig build o2a-plot-bundle`: regenerate tracked O2 A comparison plots.

## Local-Only Areas

- `docs/specs/` and `docs/workpackages/` are scratch planning spaces and stay gitignored.
- `vendor/disamar-fortran/` is a local upstream clone recreated by `./scripts/bootstrap-upstream.sh`.
