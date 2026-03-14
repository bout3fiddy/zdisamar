# Repo Notes

- `zdisamar` is the Zig radiative-transfer platform scaffold. Treat DISAMAR as one bundled model family, not as the whole engine shape.
- `vendor/disamar-fortran/` is a local, gitignored reference clone. Use it for source comparison, but do not build new features around its global-state or file-driven structure.
- `specs/` holds tracked architecture and migration specs. `docs/specs/` is local-only scratch space and stays gitignored.
- Keep `src/core` and `src/kernels` free of file I/O, text parsing, mission-specific wiring, and global mutable state.
- Keep the public surface typed around `Engine -> Plan -> Workspace -> Request -> Result`. Do not reintroduce string-keyed mutation APIs.
- Native plugin contracts must stay behind the C ABI in `src/api/c` and `src/plugins/abi`.

## Router

- Start in [src/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/src/AGENTS.md) for source-tree work.
- Use [specs/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/specs/AGENTS.md) for tracked architecture docs.
- Use [packages/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/packages/AGENTS.md) for distributable bundles.
- Use [tests/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/tests/AGENTS.md) and [validation/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/validation/AGENTS.md) for verification work.
- Use [vendor/AGENTS.md](/Users/swadhinnanda/Projects/git/zdisamar/vendor/AGENTS.md) before touching any vendored reference assets.
- Deep repo context lives in [.agents/repo-context/index.md](/Users/swadhinnanda/Projects/git/zdisamar/.agents/repo-context/index.md).

## Commands

- `./scripts/bootstrap-upstream.sh` refreshes the local DISAMAR Fortran reference clone.
- `zig build test` is the default verification command.
- `zig build` builds the scaffold CLI and library.
