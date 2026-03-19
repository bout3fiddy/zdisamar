# Scripts

- Keep top-level `scripts/` for repo-wide automation entrypoints and bootstrap utilities.
- Testing-harness helper scripts belong under `scripts/testing_harness/`, not beside unrelated bootstrap scripts.
- Harness scripts should stay deterministic, take explicit CLI arguments, and write disposable outputs under `out/ci/`.
- Prefer `zig build` steps as the public entrypoints; scripts should support those steps rather than become the primary interface.
- Leave `bootstrap-upstream.sh` at the top level because it is a repo/bootstrap concern, not part of the test harness.
