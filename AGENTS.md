# Repo Notes

- `zdisamar` is an O2 A forward-model lab. Treat DISAMAR as the bundled reference family used for parity checks, not as the codebase architecture.
- `vendor/disamar-fortran/` is a local, gitignored reference clone. Use it for source comparison, but do not build new features around its global-state or file-driven structure.
- `docs/specs/` and `docs/workpackages/` are local scratch spaces and stay gitignored.
- Keep `src/kernels` free of file I/O, text parsing, CLI wiring, and global mutable state.
- Keep the public surface small and literal around `Case -> Data -> Optics -> Spectrum -> Report`.
- Do not reintroduce engine/planner/plugin/ABI scaffolding or string-keyed mutation APIs.
- No parsed control may be silently ignored. Every new config/input field must be consumed, rejected with a typed error, or explicitly documented as inert with a covering test.
- Do not silently drop enabled physics on unmatched identifiers, interval placements, or unsupported combinations. Fail fast when a nonzero or enabled control cannot be applied.
- Preserve retained O2 A semantics unless the change is an intentional compatibility break called out in the work package, PR summary, and focused regression coverage.

## Router

- Start in [src/AGENTS.md](src/AGENTS.md) for source-tree work.
- Use [tests/AGENTS.md](tests/AGENTS.md) and [validation/AGENTS.md](validation/AGENTS.md) for verification work.
- Use [scripts/AGENTS.md](scripts/AGENTS.md) for repo automation and testing-harness helper scripts.
- Use [vendor/AGENTS.md](vendor/AGENTS.md) before touching any vendored reference assets.
- Deep repo context lives in [.agents/repo-context/index.md](.agents/repo-context/index.md).

## Testing Harness

- The verification harness is layered; keep the current suite split and validation assets as the base layer instead of replacing them with one monolithic runner.
- `zig build` is the front door for local verification. Prefer adding or changing build steps before adding ad hoc shell commands.
- Python helper scripts in this repo are invoked with `uv run ...`, not `python3 ...`.
- When the user asks to "update O2A plots", run `zig build o2a-plot-bundle` and stage the changed tracked files under `validation/`.
- The default O2A plot refresh uses the committed vendor reference in `validation/o2a_with_cia_disamar_reference.csv` and does not rerun vendored DISAMAR.
- `zig build check` is the fast baseline: format check, compile the shipped O2A artifacts and suite roots, then run the root smoke tests.
- `zig build test-fast` is the broader presubmit lane for the retained O2A fast suites.
- `./scripts/clean-zig-caches.sh` removes accumulated repo-local Zig caches (`.zig-cache`, `.zig-cache-int`, and `zig-cache/`) after a run has finished.
- `./scripts/zig-build-ephemeral.sh ...` runs `zig build` with temporary local and global caches and deletes them on exit; use it for low-disk or one-shot verification, but keep plain `zig build ...` as the default front door.
- Keep heavier lanes like vendor differential runs and plot-bundle refreshes out of the default local loop unless the changed surface needs them.
- Aggregate build steps must have explicit coverage for composition. When a new focused lane or proof is added, tests or harness checks should prove that aggregate steps include it when required and omit it when intentionally opt-in.
- When a change adds both exact and alternate O2 A paths, add the smallest focused verification that proves intended semantic parity or intentional divergence across those paths.

## Before Push

- There is no repo CI workflow. Run the necessary checks locally before pushing larger changes.
- Minimum baseline: `zig build check`.
- If you touched runtime behavior, optics preparation, spectrum assembly, report generation, or validation fixtures, also run the relevant focused lanes such as `zig build test-fast`, `zig build test-transport`, `zig build test-validation-o2a`, `zig build test-validation-o2a-vendor`, `zig build o2a-forward-profile`, and `zig build o2a-plot-bundle` when warranted.
- Do not blindly run every retained scientific lane for every push. Pick the smallest set of lanes that actually covers the changed surface area.
- If you changed control propagation, interval ordering, placement semantics, or wavelength-dependent behavior, include at least one focused test that would fail if a stale fallback or reference-only path were still being used.

## Commands

- `zig build check` is the fast local verification command.
- `zig build test-fast` is the fast presubmit verification command.
- `zig build o2a-plot-bundle` regenerates the tracked O2A comparison bundle under `validation/`.
- The tracked O2 A validation bundle uses the committed vendor reference at `validation/o2a_with_cia_disamar_reference.csv`.
- `zig build test-transport` is the focused transport/parity verification command.
- `zig build test-validation-o2a` runs the retained O2A forward-shape validation lane.
- `zig build test-validation-o2a-vendor` runs the opt-in O2A vendor trend assessment lane.
- `zig build test-validation-o2a-vendor-profile` runs the profiled/unprofiled O2A report smoke lane.
- `zig build test-validation-o2a-vendor-line-list` runs the O2A vendor line-list helper smoke lane.
- `zig build test-validation-o2a-plot-bundle` runs the O2A plot bundle harness smoke test.
- `zig build test` is the full verification command.
- `zig build` builds the O2A library and the O2A forward-profile CLI.
- `./scripts/clean-zig-caches.sh` removes repo-local Zig caches after a run.
- `./scripts/zig-build-ephemeral.sh ...` is the zero-persistence wrapper when cache reuse is less important than disk pressure.
