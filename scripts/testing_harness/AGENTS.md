# Testing Harness Scripts

- Keep this directory for testing-harness automation such as policy checks, benchmark/report helpers, and future CI-facing evidence generation.
- Scripts here should be small, deterministic, and callable from `zig build` steps.
- Write generated artifacts to `out/ci/` and avoid mutating tracked validation assets unless the calling workflow explicitly does regeneration.
- Treat failures as signal: advisory lanes may emit reports and exit non-zero, while non-gating summary lanes should still produce their artifact when possible.
