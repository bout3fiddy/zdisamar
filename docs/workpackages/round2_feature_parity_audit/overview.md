# Round 2 Feature Parity Audit Work Packages

## Execution Directive (Standard)

```text
REQUIRED: Replace every <VARIABLE> placeholder before running this directive. Do not leave any <...> token unresolved.

start implementing fixes per work package: docs/workpackages/round2_feature_parity_audit

if a directory path is provided (for example `docs/review/workpackages_<name>_<date>/`):
- scan all markdown files in that directory
- read `overview.md` first (required canonical status summary)
- start from the primary entry doc (`overview.md` when present, otherwise first alphabetical markdown file)
- continue from the first non-done `WP-*` status across the directory

ensure changes are non-destructive.
the app is locally hosted at not-applicable-for-this-cli-library-repo.
started via not-applicable-for-this-cli-library-repo.
use playwright/browser tooling only when a generated artifact has an HTML or browser-viewable surface; otherwise validate with repo commands and artifact inspection.

when each work package item is implemented:
- complete every checkbox in that WP's `## Completion Checklist` — each box must be checked (`- [x]`) individually; do not bulk-mark
- update that WP section with:
  - updated Recommendation rationale
  - Implementation status (YYYY-MM-DD)
  - Why this works
  - Proof / validation
  - How to test
- mark the WP title status line as [Status: Done YYYY-MM-DD] only AFTER all checklist boxes are checked
- update `overview.md` rollup row for that `WP-*` with status, last-updated date, proof pointer, and next action

a WP item is NOT done until every checklist box is checked. do not advance to the next WP until the current one's checklist is fully complete.

commit and push periodically as coherent checkpoints.

when all work packages are done:
- run the PR review remediation loop until:
  - all required checks pass
  - no new actionable review comments remain
- create a staging release
- only after staging release, update Linear issue not-applicable-for-this-local-workpackage with shipped outcomes and move it to In Review

this command may be repeated.
if staging release already exists for this work package, treat repeats as reminder signals and continue only unfinished steps.

default to hard cutovers; do not add fallback branches/shims unless explicitly approved with owner + removal date + tracking issue.
```

## Metadata

- Created: 2026-03-16
- Scope: convert `audit.md` into a prioritized, patch-ready execution plan
- Input sources: `audit.md`, repo docs guidance, work-package workflow standard
- Constraints:
  - write only inside `docs/workpackages/round2_feature_parity_audit/`
  - no code changes in this planning pass
  - preserve the audit's ordering bias: correctness first, forward physics second, retrieval parity after the forward path is credible
  - keep all work non-destructive and hard-cutover by default
- Note: this folder name is a user-directed exception to the usual `docs/workpackages/<task_type>_<name>_<date>/` naming standard

## Background

The source audit already established that the current Zig tree is strongest in typed execution seams and weakest in method-faithful forward radiative-transfer numerics and retrieval numerics. This package translates that narrative into a sequence of implementation work packages with exact file-level edit intent, explicit validation expectations, and a second-pass coverage index so no audited file or section is left orphaned.

## Overarching Goals

- Fix correctness bugs that can invalidate every later parity step.
- Make the forward O2 A-band path scientifically honest before deep retrieval work.
- Implement one real retrieval family first, then the remaining families.
- Reduce type-system and lifecycle footguns that are currently hidden by the scaffold architecture.
- Trim or feature-gate runtime/plugin complexity that is ahead of the scientific core.
- Keep a permanent coverage map from audit finding to planned patch site.

## Non-goals

- Immediate implementation of the work packages in this pass.
- Blanket parity claims against the vendored Fortran implementation.
- New compatibility shims, dual paths, or soft-fallback behavior.
- Reprioritizing the audit around plugin/runtime polish ahead of forward and retrieval fidelity.

## Rollup

| WP ID | Status | Last updated | Proof / validation pointer | Next action |
| --- | --- | --- | --- | --- |
| [WP-01](./wp-01-critical-correctness.md) | Done | 2026-03-16 | `wp-01-critical-correctness.md` Proof / validation | Start `WP-02` and replace surrogate forward shaping with physically defensible O2A transport + measurement-space behavior |
| [WP-02](./wp-02-forward-transport-measurement-space.md) | Done | 2026-03-16 | `wp-02-forward-transport-measurement-space.md` Proof / validation | Start `WP-03` and resolve instrument, observation, noise, and ingest semantics on top of the repaired forward baseline |
| [WP-03](./wp-03-observation-instrument-noise-ingest.md) | Todo | 2026-03-16 | Planned validation in WP doc | Resolve instrument/observation/noise semantics once and wire ingests all the way through execution |
| [WP-04](./wp-04-optimal-estimation-parity.md) | Todo | 2026-03-16 | Planned validation in WP doc | Implement a real OE lane on top of the repaired forward path |
| [WP-05](./wp-05-doas-dismas-parity.md) | Todo | 2026-03-16 | Planned validation in WP doc | Implement real DOAS and DISMAS spectral fitting after OE is stable |
| [WP-06](./wp-06-core-runtime-type-hardening.md) | Todo | 2026-03-16 | Planned validation in WP doc | Split lifecycle types, tighten ownership, and trim unstable public/core surfaces |
| [WP-07](./wp-07-plugin-adapter-and-hygiene.md) | Todo | 2026-03-16 | Planned validation in WP doc | Reduce plugin/runtime overreach, split oversized adapters, and clean runtime-facing style hazards |

## Priority Ladder

1. `WP-01` must land before any parity claim, because the current bugs can invalidate measurement binding, plan capacity, sigma semantics, and result lifetime.
2. `WP-02` and `WP-03` are the forward-physics gate. Retrieval work should not proceed until both are materially complete.
3. `WP-04` is the first real inverse-method target.
4. `WP-05` should not start until `WP-04` establishes the shared spectral-evaluator and Jacobian machinery.
5. `WP-06` and `WP-07` can start opportunistically once they no longer collide with the earlier science-critical files.

## Coverage Proof

Every audit section and every explicitly named repo file is assigned in [coverage-index.md](./coverage-index.md). Files that the audit judged "good" but not currently worth changing are still listed there with a `Preserve / no immediate patch` disposition so the second pass can prove they were reviewed rather than forgotten.

## Second-Pass Audit Result

- `audit.md` file mentions checked: 149 repo paths, 149 assigned in `coverage-index.md`
- Workflow structure check: `overview.md` plus all `WP-*` docs contain the required workflow sections and completion checklist
- Omissions found and fixed during the second pass:
  - added `src/plugins/providers/retrieval.zig` to `WP-05`
  - added `src/plugins/abi/plugin.h` to `WP-07`
- Remaining unresolved gaps after the second pass: none found in the audited file/path inventory
