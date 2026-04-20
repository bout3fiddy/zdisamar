# O2A Parity Issues

This folder captures the remaining DISAMAR-vs-Zig parity gaps as code-side
comparisons, not just residual summaries.

Each report answers the same question:

- what object or algorithm DISAMAR actually realizes
- what object or algorithm Zig currently realizes
- why the Zig behavior is wrong for 1:1 parity
- where the current probes show the mismatch numerically
- what the minimal faithful correction direction is

## Reports

- [01-irradiance-interpolation-and-convolution.md](./01-irradiance-interpolation-and-convolution.md)
  DISAMAR spline + Gauss-grid irradiance realization versus Zig linear +
  uniform-grid realization.
- [02-radiance-optics-state-and-rtm-grid.md](./02-radiance-optics-state-and-rtm-grid.md)
  DISAMAR RTM support-grid optics preparation versus Zig physical-sublayer
  preparation.
- [03-radiance-measurement-kernel-realization.md](./03-radiance-measurement-kernel-realization.md)
  DISAMAR realized `wavelHRS` kernel versus Zig `.disamar_hr_grid` uniform
  explicit-HR kernel.
- [04-spectroscopy-thermodynamics-gap.md](./04-spectroscopy-thermodynamics-gap.md)
  Remaining partition-function / metadata provenance differences in
  spectroscopy, and why they are now secondary.

## Current Ranking

1. Radiance optics-state / RTM support-grid mismatch
2. Radiance measurement-kernel realization mismatch
3. Irradiance interpolation and convolution mismatch
4. Spectroscopy thermodynamics / provenance cleanup

## Probe Surfaces

- `755.0 nm` edge probe:
  [summary.txt](../../../out/analysis/o2a/function_diff/edge_7550_after_parity/diff/summary.txt)
- `759.62 nm` hotspot probe:
  [summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/summary.txt)
- weak contributors:
  [weak_line_contributors_summary.txt](../../../out/analysis/o2a/function_diff/hotspot_75962_after_parity/diff/weak_line_contributors_summary.txt)
- current bundle metrics:
  [comparison_metrics.json](../../../validation/compatibility/o2a_plots/comparison_metrics.json)
