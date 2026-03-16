# Compatibility Harness

This directory defines bounded parity checks against selected
`vendor/disamar-fortran` reference assets.

## Scope

- Contract-level parity only for now:
  - plan preparation
  - transport-route selection
  - derivative-mode propagation
  - reproducible execution over curated upstream case anchors
- No claim of full scientific-output parity yet.

## Inputs

- `parity_matrix.json`: executable parity cases and runtime expectations.
- `vendor_import_registry.json`: mapping from upstream reference assets to tracked local bundles.

## Execution

- `zig build test-validation`
- `zig build test-perf`

