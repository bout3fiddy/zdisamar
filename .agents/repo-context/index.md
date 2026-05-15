# Repo Context Index

owner: zdisamar
last_verified: 2026-05-15

## Current Shape

- Public flow: input -> forward model -> output.
- Source code: `rust_src/input/`, `rust_src/forward_model/`, `rust_src/output/`, `rust_src/common/`, `rust_src/api/`.
- Scientific assets: `data/reference_data/`.
- Tracked DISAMAR-reference evidence: `validation/`.
- Performance research notes and demo notebooks: `research/performance/`.

## Verification Baseline

- `cargo test`: fast local baseline.
- `cargo clippy --all-targets --all-features -- -D warnings`: Rust lint gate.
- `prek run --all-files`: full pre-commit gate.
- `uv run validation/spectra/validate_spectra.py`: regenerate tracked O2 A spectra plots.
- `uv run validation/optimal_estimation/validate_optimal_estimation.py`: focused OE validation.

## Local-Only Areas

- `tmp/` is the scratch planning space and stays gitignored. Older `docs/specs/` and `docs/workpackages/` paths are also gitignored for backwards compatibility but are no longer present in the tree.
- `vendor/disamar-fortran/` is a local upstream clone recreated by `./scripts/bootstrap-upstream.sh`.
- Python tool caches (`.ruff_cache/`, `.ropeproject/`, `.pytest_cache/`, `.venv/`) stay gitignored.
