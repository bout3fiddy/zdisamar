# Validation Assets

This directory stores tracked O2 A output-validation evidence that is
intentionally kept in git. The scripts compare zdisamar outputs against DISAMAR
reference outputs, zdisamar normal-mode outputs against fast-mode outputs, and
Python optimal-estimation retrieval outputs against retained reference cases.
Disposable validation traces, scratch runs, and exploratory analysis belong
under `out/`, not under this directory.

## Layout

The validation tree is split by target:

- `spectra/`: forward reflectance and reflectance-Jacobian parity evidence.
- `optimal_estimation/`: inverse-method retrieval evidence.
- `o2a/`: shared O2 A scene, baseline, and measurement-noise helpers used by
  both spectra and inverse-method validation.
- `common/`: generic validation plumbing such as paths and timers.
- `reference_data/`: committed DISAMAR/reference fixtures and baselines.
- `outputs/`: committed zdisamar benchmark outputs generated from those fixtures.

## Tracked Spectra Bundle

- `reference_data/spectra/o2a_jacobian_retrieval_instrument_forward.csv`: DISAMAR baseline-grid forward
  reference used for the reflectance row.
- `reference_data/spectra/o2a_jacobian_simulation_instrument_reflectance.csv`: DISAMAR baseline-grid
  reflectance-Jacobian reference used for the derivative rows.
- `reference_data/spectra/o2a_jacobian_reference_provenance.txt`: provenance for the retained
  DISAMAR Jacobian fixture.
- `outputs/spectra/o2a_validation.png`: committed 4x2 validation plot for forward
  reflectance and the three retained reflectance Jacobian columns.
- `outputs/spectra/o2a_validation_data.csv`: current zdisamar/reference values and
  residuals used by the plot.
- `outputs/spectra/comparison_metrics.json` and `outputs/spectra/bundle_manifest.json`:
  metadata for the tracked plot refresh.
- `outputs/spectra/o2a_fast_mode_spectra.png`,
  `outputs/spectra/o2a_fast_mode_spectra_data.csv`, and
  `outputs/spectra/o2a_fast_mode_spectra_metrics.json`: retained comparison of
  reference settings against the O2 A fast-mode preset over several scene
  geometries.
- `reference_data/spectra/o2a_with_cia_disamar_reference.csv`: retained DISAMAR reference spectrum
  still consumed by older forward validation tests.
- `reference_data/spectra/o2a_vendor_forward_reflectance_baseline.json`: retained focused validation
  baseline consumed by validation tests.
- `reference_data/optimal_estimation/disamar_o2a_two_state_reference.json`: DISAMAR optimal-estimation two-state aerosol
  retrieval fixture for aerosol optical depth and fixed-thickness layer pressure.
- `reference_data/optimal_estimation/baseline_config.in`: retained DISAMAR 4.1.5
  optimal-estimation baseline config kept as provenance for the historical
  paired-retrieval plots.
- `reference_data/optimal_estimation/disamar_oe_sweep_cases.json`: shared
  deterministic OE sweep-case manifest used by the normal zdisamar OE sweep and
  the fast-mode zdisamar OE sweep.
- `outputs/optimal_estimation/zdisamar_o2a_sweep_runs.csv` and
  `outputs/optimal_estimation/zdisamar_o2a_sweep_summary.json`: retained
  slow-mode zdisamar OE sweep outputs from
  `validation/optimal_estimation/sweep_optimal_estimation.py`.
- `outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison.png`,
  `outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_runs.csv`,
  and
  `outputs/optimal_estimation/zdisamar_o2a_fast_mode_sweep_comparison_summary.json`:
  retained fast-mode sweep comparison between zdisamar reference-threshold
  retrievals and zdisamar fast-mode retrievals, with posterior one-sigma error
  bars, fast-minus-reference retrieval deltas, and timing panels. Regenerate it
  with `validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py`.
- `outputs/optimal_estimation/paired_oe_retrieved_fast_scatter.png`: paired-style
  retrieved-state plot comparing zdisamar reference retrievals against zdisamar
  fast-mode retrievals on the fast-mode sweep scenes.
- `outputs/optimal_estimation/paired_oe_latency.png`: latency plot refreshed by
  the fast-mode sweep. When the historical paired manifest is present, the plot
  includes DISAMAR Fortran, zdisamar reference, and zdisamar-fast.
- `outputs/optimal_estimation/paired_oe_*.png` and
  `outputs/optimal_estimation/paired_oe_plot_manifest.json`: tracked
  paired-retrieval plot outputs kept as historical evidence.
## Baseline Commands

- `zig build test`
- `zig build test-validation-o2a`
- `zig build test-validation-o2a-vendor`
- `uv run validation/spectra/validate_spectra.py`
- `uv run validation/spectra/validate_fast_mode_spectra.py`
- `uv run validation/optimal_estimation/sweep_optimal_estimation.py`
- `uv run validation/optimal_estimation/sweep_fast_mode_optimal_estimation.py`

The validation scripts own their plots and tracked summaries. They are invoked
directly with `uv run ...`, not through `zig build`.

## Residual Note

The tracked validation plot compares reflectance-space quantities because those
are the retrieval-facing parity signal. The retained threshold for every row in
the bundle is `1e-13` max absolute residual.

## Baseline Case

Validation lanes use the typed O2 A baseline exposed by `zdisamar.defaultO2AInput()`
and mirrored in `validation/o2a/case.py`. Keep Zig validation
tests and Python validation scripts aligned with that case instead of introducing
a second serialized validation input.
