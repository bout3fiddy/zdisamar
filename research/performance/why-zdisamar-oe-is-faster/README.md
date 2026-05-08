# Why zdisamar Optimal Estimation Is Faster Than DISAMAR

Scope: aerosol-only O2 A optimal estimation with aerosol optical depth and
fixed-thickness aerosol layer mid pressure in the state vector. Surface albedo,
surface pressure, geometry, aerosol single-scattering albedo, asymmetry factor,
Angstrom exponent, and layer thickness are varied across scenes but are fixed
inside each retrieval.

The paired validation harness is:

```sh
uv run validation/optimal_estimation/paired_disamar_zdisamar_sweep.py
uv run validation/optimal_estimation/plot_paired_disamar_zdisamar.py
```

`paired_disamar_zdisamar_sweep.py` is currently configured for
`RUN_COUNT = 100`, sampled from the first 100 scenes in the original
500-scene Latin-hypercube pool. It writes generated spectra, DISAMAR case
directories, per-case row shards, and merged parquet data under:

```text
out/validation/optimal_estimation/paired_disamar_zdisamar/
```

Those data are intentionally gitignored. The tracked figure outputs are:

```text
validation/outputs/optimal_estimation/paired_oe_retrieved_scatter.png
validation/outputs/optimal_estimation/paired_oe_error_histograms.png
validation/outputs/optimal_estimation/paired_oe_latency.png
validation/outputs/optimal_estimation/paired_oe_plot_manifest.json
```

The checked-in plots currently come from the 100-case paired sweep. The
manifest records the source row count and model summary so the plotted evidence
is auditable without checking in the generated parquet.

## Current Paired Sweep

The completed paired sweep used the same sampled scenes and the same aerosol
optical-depth and mid-pressure a priori for both retrieval systems. Each
system generated its own synthetic spectrum:

```text
DISAMAR Fortran: 100/100 converged, median 1228.826 s,
                 max AOD error 1.789e-4,
                 max mid-pressure error 0.661 hPa
zdisamar:        100/100 converged, median 15.240 s,
                 max AOD error 3.951e-5,
                 max mid-pressure error 0.087 hPa
```

The zdisamar retrieval uses the same baseline SNR covariance implied by the
DISAMAR configuration. A flat reflectance variance made weak spectral signals
look converged too early in some scenes; the SNR covariance removes that
artificial early-convergence tail.

## Documents

- [01. Reuse the O2 A forward session](01-reuse-o2a-forward-session.md):
  keeps scene-invariant preparation and storage alive across retrieval
  iterations.
- [02. Keep Jacobians state-vector sized](02-state-vector-sized-jacobians.md):
  asks the forward model only for the state-vector columns used by this
  aerosol-only retrieval.
- [03. Isolate the paired validation lanes](03-paired-validation-lanes.md):
  compares two retrieval systems over the same scenes without sharing synthetic
  spectra between them.

## Main Mechanism

DISAMAR runs a broad configurable executable. For every paired case here it
builds its simulation spectrum, prepares the retrieval model, iterates, writes
large text and binary outputs, and only then can the harness extract the
retrieved state.

zdisamar runs the O2 A retrieval as a narrow in-process Python/Zig path. The
retrieval loop passes a forward session into `O2AInverseForwardModel`, so each
iteration can prepare the new aerosol state using the same session object
instead of rebuilding the entire execution context. The forward call also
receives the state-vector Jacobian names, so aerosol-only retrievals do not ask
for the surface-albedo derivative column.

The result is not that the retrieval math is different. The result is that the
data handling around the same kind of Gauss-Newton optimal-estimation loop is
much smaller: fewer process boundaries, less file output, reusable scene
storage, and Jacobian work limited to the requested state vector.

## Validation Status

The retained evidence is the 100-case parquet under `out/` plus regenerated
tracked plots and manifest under `validation/outputs/optimal_estimation/`.
The full DISAMAR run is still long enough that larger sweeps should be
scheduled as resumable batch jobs across available cores rather than as
interactive smoke tests.
