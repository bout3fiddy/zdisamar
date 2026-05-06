# Scripts

- Keep top-level `scripts/` for repo-wide automation entrypoints and bootstrap utilities.
- Keep `scripts/demo/` for executable explanatory notebooks and the minimal notebook runner that executes them.
- Demo notebooks should explain the scientific question, inputs, Python API calls, generated tables or plots, and interpretation.
- Demo notebook execution should write disposable outputs under `out/demo/` unless an existing CI-only output path is intentional.
- Real tests and contract checks live under `tests/`; do not park test harnesses under `scripts/`.
- DISAMAR-reference evidence and tracked validation bundle maintenance stay under `validation/`.
- Prefer `zig build` steps as the public entrypoints; scripts and notebooks should support those steps rather than become the primary interface.
- Leave `bootstrap-upstream.sh`, cache cleanup, the ephemeral Zig build wrapper, and the inline-test guard at the top level because they are repo automation.
- Advisory policy scripts should emit stable finding codes and machine-readable reports so trends and recurring failure classes can be tracked across PRs.
- If a script validates aggregate lanes or manifests, it should check both required inclusions and intentional exclusions so opt-in lanes do not leak into default verification by accident.
