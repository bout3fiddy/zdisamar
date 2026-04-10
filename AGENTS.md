# Repo Notes

- `zdisamar` is the Zig radiative-transfer platform scaffold. Treat DISAMAR as one bundled model family, not as the whole engine shape.
- `vendor/disamar-fortran/` is a local, gitignored reference clone. Use it for source comparison, but do not build new features around its global-state or file-driven structure.
- `docs/specs/` and `docs/workpackages/` are local scratch spaces and stay gitignored.
- Keep `src/core` and `src/kernels` free of file I/O, text parsing, mission-specific wiring, and global mutable state.
- Keep the public surface typed around `Engine -> Plan -> Workspace -> Request -> Result`. Do not reintroduce string-keyed mutation APIs.
- Native plugin contracts must stay behind the C ABI in `src/api/c` and `src/plugins/abi`.
- No parsed control may be silently ignored. Every new config/input field must be consumed, rejected with a typed error, or explicitly documented as inert with a covering test.
- Do not silently drop enabled physics on unmatched identifiers, interval placements, or unsupported combinations. Fail fast when a nonzero or enabled control cannot be applied.
- Preserve legacy semantics on legacy paths unless the change is an intentional compatibility break called out in the work package, PR summary, and focused regression coverage.

## Router

- Start in [src/AGENTS.md](src/AGENTS.md) for source-tree work.
- Use [packages/AGENTS.md](packages/AGENTS.md) for distributable bundles.
- Use [tests/AGENTS.md](tests/AGENTS.md) and [validation/AGENTS.md](validation/AGENTS.md) for verification work.
- Use [scripts/AGENTS.md](scripts/AGENTS.md) for repo automation and testing-harness helper scripts.
- Use [vendor/AGENTS.md](vendor/AGENTS.md) before touching any vendored reference assets.
- Deep repo context lives in [.agents/repo-context/index.md](.agents/repo-context/index.md).

## Testing Harness

- The verification harness is layered; keep the current suite split and validation assets as the base layer instead of replacing them with one monolithic runner.
- `zig build` is the front door for local verification. Prefer adding or changing build steps before adding ad hoc shell commands.
- Python helper scripts in this repo are invoked with `uv run ...`, not `python3 ...`.
- When the user asks to "update O2A plots", run `zig build o2a-plot-bundle` and stage the changed tracked files under `validation/compatibility/o2a_plots/`.
- The default O2A plot refresh uses the committed vendor reference in `validation/reference/o2a_with_cia_disamar_reference.csv` and does not rerun vendored DISAMAR.
- `zig build check` is the fast baseline: format check, compile the shipped artifacts and suite roots, then run unit tests.
- `zig build test-fast` is the broader presubmit lane: unit plus integration, including the leak/lifecycle coverage that uses allocation-failure and `DebugAllocator` checks.
- `zig build bench` is non-gating. It reuses `validation/perf/perf_matrix.json` and writes disposable benchmark summaries to `out/ci/bench/summary.json`.
- `zig build tidy` is the advisory architecture lane. It writes `out/ci/tidy/report.json` and is expected to fail while findings still exist.
- `./scripts/clean-zig-caches.sh` removes accumulated repo-local Zig caches (`.zig-cache`, `.zig-cache-int`, and `zig-cache/`) after a run has finished.
- `./scripts/zig-build-ephemeral.sh ...` runs `zig build` with temporary local and global caches and deletes them on exit; use it for low-disk or one-shot verification, but keep plain `zig build ...` as the default front door.
- Keep heavier lanes like vendor differential runs, perf guardrails, and Valgrind out of the default local loop until their backing assets and packages are ready.
- Aggregate build steps must have explicit coverage for composition. When a new focused lane or proof is added, tests or harness checks should prove that aggregate steps include it when required and omit it when intentionally opt-in.
- When a change adds both legacy and explicit paths, add the smallest focused verification that proves intended semantic parity or intentional divergence across those paths.

## Before Push

- There is no repo CI workflow. Run the necessary checks locally before pushing larger changes.
- Minimum baseline: `zig build check`.
- If you touched runtime behavior, planners, retrieval, exporters, adapters, or validation fixtures, also run the relevant focused lanes such as `zig build test-fast`, `zig build test-transport`, `zig build test-validation-compatibility`, `zig build test-validation-o2a`, `zig build test-validation-o2a-vendor`, `zig build bench`, and `zig build tidy`.
- Do not blindly run the full scientific integration suite for every push. Pick the smallest set of lanes that actually covers the changed surface area.
- If you changed parser/adapter controls, field propagation, interval ordering, placement semantics, or wavelength-dependent behavior, include at least one focused test that would fail if the old fallback or reference-only path were still being used.

## Commands

- `zig build check` is the fast local verification command.
- `zig build test-fast` is the fast presubmit verification command.
- `zig build bench` emits the non-gating benchmark summary at `out/ci/bench/summary.json`.
- `zig build tidy` runs advisory architecture checks and writes `out/ci/tidy/report.json`.
- `zig build o2a-plot-bundle` regenerates the tracked O2A comparison bundle under `validation/compatibility/o2a_plots/`.
- `zig build o2a-vendor-reference-refresh` explicitly reruns vendored DISAMAR to refresh `validation/reference/o2a_with_cia_disamar_reference.csv`.
- `zig build test-transport` is the focused transport/parity verification command.
- `zig build test-validation-compatibility` is the fast compatibility smoke command.
- `zig build test-validation-compatibility-full` runs the full DISAMAR compatibility harness.
- `zig build test-validation-o2a-vendor` runs the opt-in O2A vendor trend assessment lane.
- `zig build test-validation-o2a-plot-bundle` runs the O2A plot bundle harness smoke test.
- `zig build test` is the full verification command.
- `zig build` builds the scaffold CLI and library.
- `./scripts/clean-zig-caches.sh` removes repo-local Zig caches after a run.
- `./scripts/zig-build-ephemeral.sh ...` is the zero-persistence wrapper when cache reuse is less important than disk pressure.
