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
