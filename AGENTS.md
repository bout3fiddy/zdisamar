# Repo Notes

- `zdisamar` is the Zig radiative-transfer platform scaffold. Treat DISAMAR as one bundled model family, not as the whole engine shape.
- `vendor/disamar-fortran/` is a local, gitignored reference clone. Use it for source comparison, but do not build new features around its global-state or file-driven structure.
- `docs/specs/` and `docs/workpackages/` are local scratch spaces and stay gitignored.
- Keep `src/core` and `src/kernels` free of file I/O, text parsing, mission-specific wiring, and global mutable state.
- Keep the public surface typed around `Engine -> Plan -> Workspace -> Request -> Result`. Do not reintroduce string-keyed mutation APIs.
- Native plugin contracts must stay behind the C ABI in `src/api/c` and `src/plugins/abi`.

## Router

- Start in [src/AGENTS.md](src/AGENTS.md) for source-tree work.
- Use [packages/AGENTS.md](packages/AGENTS.md) for distributable bundles.
- Use [tests/AGENTS.md](tests/AGENTS.md) and [validation/AGENTS.md](validation/AGENTS.md) for verification work.
- Use [vendor/AGENTS.md](vendor/AGENTS.md) before touching any vendored reference assets.
- Deep repo context lives in [.agents/repo-context/index.md](.agents/repo-context/index.md).

## Commands

- `zig build check` is the fast local verification command.
- `zig build test-transport` is the focused transport/parity verification command.
- `zig build test` is the full verification command.
- `zig build` builds the scaffold CLI and library.
