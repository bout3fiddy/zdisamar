# Repo Notes

- `zdisamar` is an O2 A RTM lab. Treat DISAMAR as the reference family used for validation, not as the codebase architecture.
- Keep the public flow simple: input -> RTM -> output.
- Keep routines under `src/rtm/`, `src/optics/`, `src/spectrum/`, and `src/retrieval/` free of file I/O, CLI wiring, text parsing, and hidden global state.
- Keep scientific assets under `data/reference_data/`; loaders and parsers live under `src/input/reference_data/`.
- No parsed control may be silently ignored. Consume it, reject it with a typed error, or document it as inert with focused coverage.
- Do not silently drop enabled physics on unmatched identifiers, interval placements, or unsupported combinations.

## Router

- Source-tree rules: [src/AGENTS.md](src/AGENTS.md).
- Forward-model instrumentation: [src/instrumentation/AGENTS.md](src/instrumentation/AGENTS.md).
- Tests and validation: [tests/AGENTS.md](tests/AGENTS.md), [validation/AGENTS.md](validation/AGENTS.md).
- Benchmarks: [benchmark/AGENTS.md](benchmark/AGENTS.md).
- Data assets: [data/AGENTS.md](data/AGENTS.md).
- Scaffolding: [scaffolding/AGENTS.md](scaffolding/AGENTS.md).
- Scripts: [scripts/AGENTS.md](scripts/AGENTS.md).

## Scratch Docs

- For local reports, TODOs, investigation notes, or other docs that should not
  be committed, write them under the root `scratch/` directory. Use
  `scratch/reports/` for report-style artifacts.

## Commands

- Fast baseline: `zig build check`.
- Broader fast presubmit: `zig build test-fast`.
- Full retained verification: `zig build test`.
- Fast performance canary: `uv run benchmark/run_benchmark_fast.py`.
- Full retained benchmark: `uv run benchmark/run_benchmark.py`.
- Before committing: `prek run --all-files`.
- Before finalizing code changes, read `STYLEGUIDE.md`, run the relevant
  styleguide scripts on changed files, and fix readability findings:
  `uv run scripts/linting/check-zig-styleguide.py <zig paths>`.
- Validation evidence scripts are invoked directly with `uv run ...`; do not
  expose one-off validation plot or sweep scripts through `zig build`.
