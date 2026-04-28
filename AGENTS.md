# Repo Notes

- `zdisamar` is an O2 A forward-model lab. Treat DISAMAR as the reference family used for validation, not as the codebase architecture.
- Keep the public flow simple: input -> forward model -> output.
- Keep routines under `src/forward_model/` free of file I/O, CLI wiring, text parsing, and hidden global state.
- Keep scientific assets under `data/reference_data/`; loaders and parsers live under `src/input/reference_data/`.
- Do not reintroduce old framework scaffolding or string-keyed mutation APIs.
- No parsed control may be silently ignored. Consume it, reject it with a typed error, or document it as inert with focused coverage.
- Do not silently drop enabled physics on unmatched identifiers, interval placements, or unsupported combinations.

## Router

- Source-tree rules: [src/AGENTS.md](src/AGENTS.md).
- Tests and validation: [tests/AGENTS.md](tests/AGENTS.md), [validation/AGENTS.md](validation/AGENTS.md).
- Data assets: [data/AGENTS.md](data/AGENTS.md).
- Scripts: [scripts/AGENTS.md](scripts/AGENTS.md).
- Docs: [docs/AGENTS.md](docs/AGENTS.md).
- Deep context index: [.agents/repo-context/index.md](.agents/repo-context/index.md).

## Commands

- Fast baseline: `zig build check`.
- Broader fast presubmit: `zig build test-fast`.
- Full retained verification: `zig build test`.
- Regenerate tracked O2 A plots: `zig build o2a-plot-bundle`.
- Plot-bundle harness smoke test: `zig build test-validation-o2a-plot-bundle`.
- Python helper scripts are invoked with `uv run ...`.
