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
  retrieval median       1228.826 s
  retrieval mean         1189.862 s
  max AOD error          1.789e-4
  max mid-pressure error 0.661 hPa

zdisamar:
  converged              100/100
  retrieval median       4.349 s
  retrieval mean         4.309 s
  max AOD error          3.951e-5
  max mid-pressure error 0.087 hPa
```

Slow retained zdisamar case:

```text
source case                          paired sweep case 71
measurement build                   1.198284 s
direct forward-only median          0.841938 s
direct forward+jacobian median      1.010729 s
jacobian increment median           0.164841 s
non-session retrieval elapsed time  5.354143 s
session first-use elapsed time      4.425870 s
session reused elapsed time         4.098390 s
iterations                          4
session matches non-session result  true
```

The slow-case result says the remaining zdisamar retrieval elapsed time is mostly
repeated forward+jacobian work. The solver update itself is millisecond-scale.
