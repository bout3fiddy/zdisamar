# Scripts

- Keep top-level `scripts/` for repo-wide automation entrypoints and bootstrap utilities.
- Testing-harness helper scripts belong under `scripts/testing_harness/`, not beside unrelated bootstrap scripts.
- Harness scripts should stay deterministic, take explicit CLI arguments, and write disposable outputs under `out/ci/`.
- Prefer `zig build` steps as the public entrypoints; scripts should support those steps rather than become the primary interface.
- Leave `bootstrap-upstream.sh` at the top level because it is a repo/bootstrap concern, not part of the test harness.
- Advisory policy scripts should emit stable finding codes and machine-readable reports so trends and recurring failure classes can be tracked across PRs.
- Prefer growing repo-specific structural and contract checks in `scripts/testing_harness/` before introducing general-purpose linters. Add rules that target known failure modes such as silent no-op config application, duplicate physical scaling, aggregate-lane drift, and fragile ownership cleanup patterns.
- If a script validates aggregate lanes or manifests, it should check both required inclusions and intentional exclusions so opt-in lanes do not leak into default verification by accident.
