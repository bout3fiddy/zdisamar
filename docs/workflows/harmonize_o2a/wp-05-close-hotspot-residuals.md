# WP-05 Close hotspot residuals

## Metadata

- Created: 2026-04-19
- Scope: converge the harmonization packages into one accepted hotspot outcome
  and lock the retained probe and validation expectations for the O2A path
- Input sources:
  - `out/analysis/o2a/function_diff/20260419T142237Z/diff/summary.txt`
  - `validation/compatibility/o2a_plots/comparison_metrics.json`
  - `validation/compatibility/o2a_plots/current_vs_vendor_reflectance.png`
  - `build.zig`
  - `scripts/testing_harness/o2a_function_diff.py`
- Dependencies:
  - `WP-02`
  - `WP-03`
  - `WP-04`
- Reference baseline:
  - current hotspot `761.75 nm` reflectance mismatch and full probe output

## Background

The harmonization effort needs one closing package that reruns the trusted
probe surfaces, verifies hotspot improvement, and captures the retained parity
expectations as regression gates instead of one-off debugging notes.

## Overarching Goals

- Re-run the trusted hotspot probe after the upstream fixes land.
- Confirm the hotspot residual shrinks for the right reasons.
- Lock the retained harmonized behavior into focused validation lanes.

## Non-goals

- Introducing a new architecture or planning system.
- Expanding parity work beyond the O2A hotspot and adjacent residual band until
  the hotspot is understood.
- Treating a numerical improvement as sufficient without a causal explanation.

### WP-05 Close hotspot residuals [Status: Todo]

Issue:
Even after the comparison zones are known, the repo still needs one explicit
closure package that proves the fixes work together and that the retained
scientific lanes enforce the intended behavior.

Needs:
- one rerun of the normalized hotspot probe after upstream packages land
- refreshed O2A plot bundle and metrics
- acceptance gates that tie the trusted probe output to retained validation
  coverage

How:
1. Re-run the full hotspot probe once `WP-02`, `WP-03`, and `WP-04` are done.
2. Re-run the O2A plot bundle and compare the updated residual morphology.
3. Add or tighten focused validations so the improved behavior is retained.
4. Record the accepted first-divergence stage and residual thresholds in the
   implementation summary.

Why this approach:
The harmonization effort is only done when the improved parity is both
observable and retained. A closing package prevents the work from ending as an
unrepeatable debugging session.

Desired outcome:
The hotspot probe, O2A plot bundle, and retained validation lanes all agree on
an improved O2A forward-model state.

Non-destructive tests:
- `zig build check`
- `zig build test-fast`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build o2a-function-diff`
- `zig build o2a-plot-bundle`

Files by type:
- New targets:
  - none
- Existing targets to refactor:
  - `build.zig`
  - `scripts/testing_harness/o2a_function_diff.py`
  - `validation/compatibility/o2a_plots/*`
- Validation targets:
  - `tests/validation/o2a_forward_shape_test.zig`
  - `tests/validation/o2a_vendor_reflectance_assessment_test.zig`
  - `scripts/testing_harness/o2a_function_diff_test.py`

## Exact Patch Checklist

- [ ] Re-run the full normalized hotspot probe after the upstream packages land.
- [ ] Refresh the O2A plot bundle and compare updated metrics against the
      current baseline.
- [ ] Tighten validation coverage around the accepted harmonized behavior.
- [ ] Record the final accepted first-divergence stage and residual movement in
      the package notes or implementation summary.
- [ ] Confirm no retained O2A validation lane regresses.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] Hotspot probe shows a materially improved divergence profile
- [ ] O2A plot bundle metrics improve from the current baseline

## Implementation Status (2026-04-19)

Planning only. No code changes yet.

## Why This Works

The upstream packages localize and fix the causal mismatches, but this package
proves they work together and turns the current analysis into a retained
scientific guardrail.

## Proof / Validation

- Planned: hotspot `summary.txt` and `summary.json` show a later or smaller
  first meaningful physics divergence
- Planned: hotspot reflectance and radiance residuals improve in the refreshed
  plot bundle
- Planned: retained O2A validation lanes pass with the new harmonized behavior

## How To Test

1. Run `zig build o2a-function-diff`.
2. Inspect the new `diff/summary.txt` and `diff/summary.json`.
3. Run `zig build o2a-plot-bundle`.
4. Compare `validation/compatibility/o2a_plots/comparison_metrics.json` and
   the hotspot region in the refreshed plots.
5. Run the retained O2A validation lanes and confirm they pass.

