# Current Retrieval Elapsed Time

Current paired sweep:

```text
RUN_COUNT = 100
SCENE_SAMPLE_COUNT = 500
BATCH_SIZE = 10
ZDISAMAR_WORKERS = 1
```

`ZDISAMAR_WORKERS = 1` means one retrieval process at a time. Each retrieval is
still free to use the forward model's internal CPU parallelism. Earlier
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
measurement build                   1.029640 s
direct forward-only median          0.744821 s
direct forward+jacobian median      0.901555 s
jacobian increment median           0.159105 s
session first-use elapsed time      3.109521 s
session reused elapsed time         2.835175 s
lazy final evaluation when requested 1.297817 s
iterations                          3
lazy final evaluation cached        true
```

The slow-case result says the remaining zdisamar retrieval elapsed time is mostly
repeated forward+jacobian work. The solver update itself is millisecond-scale.
