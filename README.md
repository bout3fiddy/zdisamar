# zdisamar

`zdisamar` is the new Zig-based radiative-transfer platform scaffold that will eventually host DISAMAR as one bundled model family instead of treating the legacy application as the whole engine.

## Current Status

- The upstream Fortran reference implementation lives in a local, gitignored clone at `vendor/disamar-fortran/`.
- The new codebase is split into `core`, `model`, `kernels`, `retrieval`, `runtime`, `plugins`, `api`, and `adapters`.
- The initial public surface is a typed `Engine -> Plan -> Workspace -> Request -> Result` flow, with a C ABI boundary reserved under `src/api/c/`.
- Local scratch plans and design notes under `docs/specs/` stay gitignored.

## Local Bootstrap

Clone or refresh the upstream DISAMAR Fortran source with:

```bash
./scripts/bootstrap-upstream.sh
```

The scaffold expects Zig `0.15.2` or newer for local builds.
