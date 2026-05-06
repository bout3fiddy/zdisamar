# Repo Context Index

owner: zdisamar
last_verified: 2026-05-06

## Current Shape

- Public flow: input -> forward model -> output.
- Source code: `src/input/`, `src/forward_model/`, `src/output/`, `src/common/`, `src/validation/disamar_reference/`.
- Scientific assets: `data/reference_data/`.
- Tracked DISAMAR-reference evidence: `validation/`.
- Performance research notes and demo notebooks: `research/performance/`.

## Verification Baseline

- `zig build check`: fast local baseline.
- `zig build test-fast`: broader fast presubmit lane.
- `zig build test`: full retained verification baseline.
- `zig build o2a-plot-bundle`: regenerate tracked O2 A comparison plots.

## Local-Only Areas

- `tmp/` is the scratch planning space and stays gitignored. Older `docs/specs/` and `docs/workpackages/` paths are also gitignored for backwards compatibility but are no longer present in the tree.
- `vendor/disamar-fortran/` is a local upstream clone recreated by `./scripts/bootstrap-upstream.sh`.
- Python tool caches (`.ruff_cache/`, `.ropeproject/`, `.pytest_cache/`, `.venv/`) stay gitignored.
