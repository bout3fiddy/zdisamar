# Validation Assets

This directory stores the tracked O2 A parity evidence that is intentionally
kept in git. Disposable validation traces, scratch runs, and exploratory
analysis belong under `out/`, not under this directory.

## Layout

The validation tree is split by target:

- `spectra/`: forward reflectance and reflectance-Jacobian parity evidence.
- `optimal_estimation/`: inverse-method retrieval evidence.
- `*/data/reference/`: committed DISAMAR/reference fixtures and baselines.
- `outputs/`: committed zdisamar benchmark outputs generated from those fixtures.

## Tracked Spectra Bundle

- `spectra/data/reference/o2a_jacobian_retrieval_instrument_forward.csv`: DISAMAR 701-sample forward
  reference used for the reflectance row.
- `spectra/data/reference/o2a_jacobian_simulation_instrument_reflectance.csv`: DISAMAR 701-sample
  reflectance-Jacobian reference used for the derivative rows.
- `spectra/data/reference/o2a_jacobian_reference_provenance.txt`: provenance for the retained
  DISAMAR Jacobian fixture.
- `outputs/spectra/o2a_validation.png`: committed 4x2 validation plot for forward
  reflectance and the three retained reflectance Jacobian columns.
- `outputs/spectra/o2a_validation_data.csv`: current zdisamar/reference values and
  residuals used by the plot.
- `outputs/spectra/comparison_metrics.json` and `outputs/spectra/bundle_manifest.json`:
  metadata for the tracked plot refresh.
- `spectra/data/reference/o2a_with_cia_disamar_reference.csv`: retained DISAMAR reference spectrum
  still consumed by older forward validation tests.
- `spectra/data/reference/o2a_vendor_forward_reflectance_baseline.json`: retained focused validation
  baseline consumed by validation tests.
- `optimal_estimation/data/reference/disamar_o2a_two_state_reference.json`: DISAMAR optimal-estimation two-state aerosol
  retrieval fixture for aerosol optical depth and fixed-thickness layer pressure.
- `outputs/optimal_estimation/zdisamar_o2a_two_state_summary.json`: generated zdisamar optimal-estimation validation
  summary.
- `outputs/optimal_estimation/zdisamar_o2a_two_state_benchmark.json`: timing benchmark from the
  optimal-estimation validation run.

## Baseline Commands

- `zig build test`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `zig build test-validation-o2a-optimal-estimation`
- `zig build o2a-plot-bundle`

`zig build o2a-plot-bundle` regenerates the tracked plot files under
`validation/outputs/spectra/` by running
`validation/spectra/plot_validation.py`.

## Residual Note

The tracked validation plot compares reflectance-space quantities because those
are the retrieval-facing parity signal. The retained threshold for every row in
the bundle is `1e-13` max absolute residual.

## YAML Runtime Coverage

- The live executable YAML surface is currently the retained O2A parity case at
  `data/examples/vendor_o2a_parity.yaml`.
- Validation-lane tests should stay aligned with the live YAML contract instead
  of the broader historical canonical-config story.
