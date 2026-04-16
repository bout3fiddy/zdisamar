# Validation Assets

This directory stores heavier evidence and compatibility assets that complement
fast executable tests in `tests/`.

## Ownership

- `validation/compatibility/`: bounded parity cases against the local
  `vendor/disamar-fortran` reference.
- `validation/golden/`: golden reference expectations consumed by test harnesses.
- `validation/perf/`: performance scenarios and guardrail budgets.
- `validation/plugin_tests/`: plugin-lane validation coverage and capability checks.
- `validation/release/`: release-readiness gates tying commands, package versions,
  provenance expectations, and required evidence artifacts together.

## Baseline Commands

- `zig build test`
- `zig build test-validation`
- `zig build test-golden`
- `zig build o2a-plots`

## YAML Runtime Coverage

- The live executable YAML surface is currently the retained O2A parity case at
  `data/examples/vendor_o2a_parity.yaml`.
- Older YAML examples under `data/examples/` are design-only reference shapes
  until they are backed by a real runtime path again.
- Validation-lane tests should keep release-readiness artifacts aligned with the
  live YAML contract instead of the broader historical canonical-config story.
