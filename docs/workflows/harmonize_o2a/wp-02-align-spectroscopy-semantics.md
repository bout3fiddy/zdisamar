# WP-02 Align spectroscopy semantics

## Metadata

- Created: 2026-04-19
- Scope: align the Zig O2 strong-line and line-mixing semantics with the
  DISAMAR reference so `spectroscopy_summary.csv` stops being the first aligned
  physics stage with nonzero deltas
- Input sources:
  - `src/model/reference/spectroscopy/line_list_eval.zig`
  - `src/model/reference/spectroscopy/physics_core.zig`
  - `src/model/reference/spectroscopy/strong_lines.zig`
  - `src/model/reference/spectroscopy/line_list_ops.zig`
  - `src/o2a/data/vendor_parity_runtime.zig`
  - `vendor/disamar-fortran/src/HITRANModule.f90`
  - `out/analysis/o2a/function_diff/20260419T142237Z/vendor/spectroscopy_summary.csv`
  - `out/analysis/o2a/function_diff/20260419T142237Z/yaml/spectroscopy_summary.csv`
- Dependencies:
  - `WP-01`
- Reference baseline:
  - current spectroscopy hotspot diff at `761.75 nm`

## Background

After the measurement-free thermodynamic alignment, `spectroscopy_summary.csv`
is the first surface with matching row counts and matching keys, and it already
shows nonzero deltas. The strongest differences are in strong-line sidecar
usage, partitioning rules, and line-mixing preparation.

## Overarching Goals

- Make Zig strong-line state preparation structurally match DISAMAR.
- Align strong/weak partition semantics for O2 A-band.
- Reduce the first nonzero spectroscopy deltas before touching transport.

## Non-goals

- Kernel/sample-grid alignment; that belongs to `WP-03`.
- Reworking the public O2A case schema unless the missing control is necessary
  for parity.
- Replacing the entire spectroscopy subsystem with a direct Fortran port.

### WP-02 Align spectroscopy semantics [Status: Todo]

Issue:
Zig currently trims strong-line sidecars, uses anchor/tolerance matching, and
applies strong-line cutoff semantics differently from DISAMAR. That changes
`sig_moy`, `YT`, strong sigma, and line-mixing sigma before the measurement
kernel is even involved.

Needs:
- full strong-sidecar state comparable to the vendor SDF/RMF set
- exact O2-A strong/weak partition semantics matching DISAMAR metadata rules
- thermodynamic-state preparation rules that do not perturb partition
  functions, strong-line populations, or mixing tails relative to the vendor

How:
1. Remove the subset-trimming dependency between strong sidecars and weak-line
   anchors for the parity path.
2. Replace nearest-anchor/tolerance classification with exact O2-A metadata
   rules where the vendor semantics are known.
3. Revisit partition-function interpolation and strong-line cutoff behavior
   against `HITRANModule.f90`.
4. Re-run the hotspot probe and O2A validation lanes to measure the
   spectroscopy-stage improvement directly.

Why this approach:
The completed probe shows the first aligned physics delta at spectroscopy. That
means transport and convolution cannot be the first cause. Strong-line state
alignment is therefore the highest-leverage scientific fix surface.

Desired outcome:
`spectroscopy_summary.csv` becomes materially closer between vendor and Zig,
especially in strong sigma and line-mixing sigma at `761.75 nm`.

Non-destructive tests:
- `zig build test-fast`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build o2a-function-diff`

Files by type:
- New targets:
  - none
- Existing targets to refactor:
  - `src/o2a/data/vendor_parity_runtime.zig`
  - `src/model/reference/spectroscopy/line_list_ops.zig`
  - `src/model/reference/spectroscopy/line_list_eval.zig`
  - `src/model/reference/spectroscopy/physics_core.zig`
  - `src/model/reference/spectroscopy/strong_lines.zig`
- Validation targets:
  - `tests/validation/o2a_vendor_line_list_smoke_test.zig`
  - `tests/validation/o2a_forward_shape_test.zig`
  - `scripts/testing_harness/o2a_function_diff.py`

## Exact Patch Checklist

- [ ] Stop trimming strong O2-A sidecars to anchor-matched subsets in the
      parity/runtime loader.
- [ ] Replace tolerance-based strong-line partitioning with vendor-exact O2-A
      metadata rules where applicable.
- [ ] Align strong-line cutoff handling with vendor `CalculateLineMixingXsec`
      semantics.
- [ ] Revisit partition-function interpolation/clamping behavior against the
      vendor baseline.
- [ ] Add focused regression coverage for strong-line partition and prepared
      state behavior.

## Completion Checklist

- [ ] Implementation matches the described approach
- [ ] Non-destructive tests pass
- [ ] `spectroscopy_summary.csv` deltas improve materially at `761.75 nm`
- [ ] No unintended regression in retained O2A fast or validation lanes

## Implementation Status (2026-04-19)

Planning only. No code changes yet.

## Why This Works

The spectroscopy stage is the first aligned physics surface with nonzero
differences. Fixing the strong-line state and partition rules there addresses
the earliest causal mismatch instead of trying to compensate later in the
pipeline.

## Proof / Validation

- Planned: hotspot `spectroscopy_summary.csv` shows reduced strong and
  line-mixing deltas
- Planned: line-list helper and vendor validation lanes still pass
- Planned: the hotspot reflectance error decreases before measurement-only
  changes are applied

## How To Test

1. Run `zig build test-fast`.
2. Run `zig build test-validation-o2a` and
   `zig build test-validation-o2a-vendor`.
3. Run `zig build o2a-function-diff`.
4. Compare vendor vs Zig `spectroscopy_summary.csv` in the new trace root.

