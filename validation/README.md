# Validation Assets

This directory stores the tracked O2 A parity evidence that is intentionally
kept in git. Disposable validation traces, scratch runs, and exploratory
analysis belong under `out/`, not under this directory.

## Tracked O2 A Bundle

- `o2a_with_cia_disamar_reference.csv`: committed DISAMAR reference spectrum.
- `generated_spectrum.csv`: current zdisamar full-spectrum output from the
  tracked plot refresh.
- `comparison_metrics.json` and `bundle_manifest.json`:
  metadata for the tracked plot refresh.
- `current_vs_vendor_*.png`: committed full-spectrum comparison plots.
- `o2a_vendor_forward_reflectance_baseline.json`: retained focused validation
  baseline consumed by validation tests.

## Baseline Commands

- `zig build test`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build o2a-plot-bundle`

`zig build o2a-plot-bundle` regenerates the tracked plot files in this
directory.

## Residual Note

The committed DISAMAR reference should come from a fresh vendored DISAMAR run,
not from earlier scratch output. Refreshing the reference with the current
vendored run removes the structured O2 A reflectance spike around 756.8 nm: the
tracked reflectance comparison now has max absolute residual near `3.4e-15`
and RMS below `1.0e-15`.

The remaining raw radiance and irradiance residuals are last-bit-scale relative
to signals near `1e13` and `5e14`. They remain useful as regression evidence,
but the reflectance residual is the primary O2 A parity signal for this bundle.

## YAML Runtime Coverage

- The live executable YAML surface is currently the retained O2A parity case at
  `data/examples/vendor_o2a_parity.yaml`.
- Validation-lane tests should stay aligned with the live YAML contract instead
  of the broader historical canonical-config story.
