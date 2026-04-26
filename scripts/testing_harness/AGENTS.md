# Testing Harness Scripts

- Keep this directory for testing-harness automation such as policy checks, benchmark/report helpers, and future CI-facing evidence generation.
- Scripts here should be small, deterministic, and callable from `zig build` steps.
- Invoke Python helpers with `uv run ...`; do not add new `python3 ...` entrypoints.
- Write generated artifacts to `out/ci/` and avoid mutating tracked validation assets unless the calling workflow explicitly does regeneration.
- Tracked validation artifacts are allowed only for explicit regeneration workflows under `validation/`; keep all other disposable evidence under `out/`.
- Treat failures as signal: advisory lanes may emit reports and exit non-zero, while non-gating summary lanes should still produce their artifact when possible.
