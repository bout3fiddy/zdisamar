# Work Packages

These work package files were derived from the migration goals in `docs/specs/original-plan.md` and aligned to the scaffold in `src/`, `packages/`, `tests/`, and `validation/`.

For work-package authoring and execution, prefer the stable local reference set in `docs/specs/`:

- `docs/specs/architecture.md`
- `docs/specs/fortran-mapping.md`
- `docs/specs/original-plan.md`

## Mandatory Invocable Skills

- `$workflows` must be invoked before resuming or executing any work package so agents follow the standard lifecycle, status updates, and resume semantics.
- `$coding` must be invoked before implementation so agents keep a reuse-first read path, make modular changes, avoid fallback shims, and record verification.

## Completion Gate

An agent may only mark a `WP-*` entry as done after every checkbox in that item is ticked and the item includes completed values for:

- `Implementation status (YYYY-MM-DD)`
- `Why this works`
- `Proof / validation`
- `How to test`

The matching rollup row in that work-package file must be updated in the same change.

Packages may be either a single Markdown file or a folder under `docs/workpackages/`. New multi-item packages should follow the folder layout from the work-package workflow with a required `overview.md` entry point.

## Package Index

- `docs/workpackages/feature_spec_completeness_2026-03-14/`
- `docs/workpackages/feature_vendor_parity_followup_2026-03-15/`
- `docs/workpackages/feature_vendor_parity_closure_2026-03-15/`
- `docs/workpackages/feature_vendor_runtime_activation_2026-03-15/`
- `docs/workpackages/migration_core_runtime_model_2026-03-14.md`
- `docs/workpackages/migration_memory_layout_linalg_2026-03-14.md`
- `docs/workpackages/migration_transport_retrieval_2026-03-14.md`
- `docs/workpackages/migration_plugins_abi_2026-03-14.md`
- `docs/workpackages/migration_adapters_packages_exports_2026-03-14.md`
- `docs/workpackages/migration_validation_parity_2026-03-14.md`
