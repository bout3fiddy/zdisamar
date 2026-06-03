# Paired DISAMAR/zdisamar Validation

The paired sweep compares retrieval systems over the same scenes. It is not a
cross-retrieval spectrum experiment.

For each sampled scene:

```text
same scene parameters
same aerosol optical-depth a priori
same aerosol layer mid-pressure a priori

DISAMAR Fortran:
  DISAMAR simulation pass
  DISAMAR retrieval pass
  DISAMAR output parsing

zdisamar:
  zdisamar simulation pass
  zdisamar retrieval pass
  zdisamar result capture
```

DISAMAR retrieves a DISAMAR synthetic spectrum. zdisamar retrieves a zdisamar
synthetic spectrum. This isolates each retrieval system while keeping scene and
a-priori sampling aligned.

The parquet rows include:

```text
true state
initial state
retrieved state
convergence flag
iteration count
signed error
absolute error
elapsed time
```

Tracked outputs:

```text
validation/outputs/optimal_estimation/paired_oe_retrieved_scatter.png
validation/outputs/optimal_estimation/paired_oe_error_histograms.png
validation/outputs/optimal_estimation/paired_oe_latency.png
validation/outputs/optimal_estimation/paired_oe_plot_manifest.json
```

The plot manifest records the source row count and model summary so the plotted
evidence is auditable without checking in generated parquet data.
