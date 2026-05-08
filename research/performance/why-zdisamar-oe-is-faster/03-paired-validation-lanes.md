# 03. Isolate the Paired Validation Lanes

The paired sweep is not a cross-retrieval experiment. zdisamar does not retrieve
a DISAMAR synthetic spectrum, and DISAMAR does not retrieve a zdisamar synthetic
spectrum.

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

This isolates the two retrieval systems while preserving an apples-to-apples
scene and a-priori comparison. The parquet rows include the true state, initial
state, retrieved state, convergence flag, iteration count, signed error,
absolute error, and wall time for each lane.

The raw DISAMAR case directories stay under `out/` because a 2000-case sweep can
produce large generated files. Only the plots and manifest derived from the
merged parquet are intended to be version-controlled.
