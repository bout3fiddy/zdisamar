# Work Packages

These work package files were derived from the migration goals in `docs/specs/original-plan.md` and aligned to the scaffold in `src/`, `packages/`, `tests/`, and `validation/`.

Architecture and Fortran mapping references used by these packages now live under local-only `docs/specs/` notes rather than tracked `specs/` files.

## Mandatory Invocable Skills

- `[$workflows](/Users/swadhinnanda/.agents/skills/workflows/SKILL.md)` must be invoked before resuming or executing any work package so agents follow the standard lifecycle, status updates, and resume semantics.
- `[$coding](/Users/swadhinnanda/.agents/skills/coding/SKILL.md)` must be invoked before implementation so agents keep a reuse-first read path, make modular changes, avoid fallback shims, and record verification.

## Completion Gate

An agent may only mark a `WP-*` entry as done after every checkbox in that item is ticked and the item includes completed values for:

- `Implementation status (YYYY-MM-DD)`
- `Why this works`
- `Proof / validation`
- `How to test`

The matching rollup row in that work-package file must be updated in the same change.

Each package now lives as a single Markdown file under `docs/workpackages/`.

## Package Index

- `docs/workpackages/migration_core_runtime_model_2026-03-14.md`
- `docs/workpackages/migration_memory_layout_linalg_2026-03-14.md`
- `docs/workpackages/migration_transport_retrieval_2026-03-14.md`
- `docs/workpackages/migration_plugins_abi_2026-03-14.md`
- `docs/workpackages/migration_adapters_packages_exports_2026-03-14.md`
- `docs/workpackages/migration_validation_parity_2026-03-14.md`
