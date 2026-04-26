# Validation Assets

This directory stores the tracked O2 A parity evidence that is intentionally
kept in git. Disposable validation traces, scratch runs, and exploratory
analysis belong under `out/`, not under this directory.

## Tracked O2 A Bundle

- `o2a_with_cia_disamar_reference.csv`: committed DISAMAR reference spectrum.
- `generated_spectrum.csv`: current zdisamar full-spectrum output from the
  tracked plot refresh.
- `comparison_metrics.json`, `profile_summary.json`, and `bundle_manifest.json`:
  metadata for the tracked plot refresh.
- `current_vs_vendor_*.png`: committed full-spectrum comparison plots.
- `o2a_vendor_forward_reflectance_baseline.json`: retained focused validation
  baseline consumed by validation tests.

## Baseline Commands

- `zig build test`
- `zig build test-validation`
- `zig build o2a-plots`

`zig build o2a-plots` and `zig build o2a-plot-bundle` regenerate the tracked
plot files in this directory.

## Irradiance Residual Note

The remaining O2 A irradiance residuals are best understood as floating-point
evaluation noise, not a physical or interpolation mismatch. The focused
`irradiance_contributions.csv` function-diff trace at `773.9 nm` shows exact
agreement in sample wavelengths and support irradiance values, with the first
differences appearing in kernel-weight/product arithmetic. At an irradiance
scale near `5e14`, one binary64 ULP is about `0.0625`, so residuals such as
`0.125`, `0.375`, and `0.4375` are only a few representable floating-point
steps.

The jagged residual shape is therefore the fingerprint of last-bit arithmetic
through the slit convolution: tiny kernel-weight differences around `1e-17`,
multiplied by large irradiance values and accumulated over hundreds of samples.
The absolute residual looks visually structured because the y-axis is in raw
irradiance units, but the relative error is around `1e-15`. Further reduction
here likely requires matching Fortran's exact dot-product/summation path, not
changing irradiance physics or support data.

## YAML Runtime Coverage

- The live executable YAML surface is currently the retained O2A parity case at
  `data/examples/vendor_o2a_parity.yaml`.
- Older YAML examples under `data/examples/` are design-only reference shapes
  until they are backed by a real runtime path again.
- Validation-lane tests should stay aligned with the live YAML contract instead
  of the broader historical canonical-config story.
