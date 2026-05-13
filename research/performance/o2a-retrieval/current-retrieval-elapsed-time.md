# Current Retrieval Elapsed Time

Current paired sweep:

```text
RUN_COUNT = 100
SCENE_SAMPLE_COUNT = 500
BATCH_SIZE = 10
ZDISAMAR_WORKERS = 1
```

`ZDISAMAR_WORKERS = 1` means one retrieval process at a time. Each retrieval is
still free to use the RTM's internal CPU parallelism. Earlier
multi-worker sweeps overcommitted the machine because each process also tried to
use the available cores.

Paired sweep results:

```text
DISAMAR Fortran:
  converged              100/100
  retrieval median       1227.947 s
  retrieval mean         1197.811 s
  max AOD error          1.789e-4
  max mid-pressure error 0.661 hPa

zdisamar:
  converged              100/100
  retrieval median       3.327 s
  retrieval mean         3.235 s
  max AOD error          1.521e-4
  max mid-pressure error 0.272 hPa
```

Slow retained zdisamar case:

```text
source case                          paired sweep case 71
measurement build                   1.189820 s
direct RTM-only median              0.885744 s
direct RTM+jacobian median          0.963766 s
jacobian increment median           0.081561 s
session first-use elapsed time      3.453297 s
session reused elapsed time         3.142969 s
lazy final evaluation when requested 1.311871 s
iterations                          3
lazy final evaluation cached        true
```

The slow-case result says the remaining zdisamar retrieval elapsed time is mostly
repeated RTM+jacobian work. The solver update itself is millisecond-scale.
