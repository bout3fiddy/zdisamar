# 03. Isolate Paired Validation Lanes

Current paired sweep evidence:

```text
DISAMAR Fortran: 100/100 converged, median 1227.947 s
zdisamar:        100/100 converged, median    3.327 s
```

In short: compare complete retrieval lanes without sharing synthetic spectra
across engines.

Source links:

- DISAMAR
  - [Executable entry](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/main_DISAMAR.f90#L101-L119): runs DISAMAR as a full executable lane, including simulation, retrieval, and output handling.
  - [Module setup](https://gitlab.com/KNMI-OSS/disamar/disamar/-/blob/d17c52884a875cb87b98e4c4ea7f722659e685ac/src/DISAMARModule.f90#L2100-L2115): prepares the broad DISAMAR run state for each generated case.
- zdisamar
  - [Paired sweep](https://github.com/bout3fiddy/zdisamar/blob/aa3bdc776e605229b18b54a7999632fb276546e2/validation/optimal_estimation/paired_disamar_zdisamar_sweep.py#L157-L224): builds the same scene/state sampling while keeping zdisamar simulation and retrieval in its own lane.

The paired sweep compares retrieval systems, not cross-system spectra. Both
systems receive the same sampled scene and the same a priori state, but each
system generates and retrieves its own synthetic spectrum.

```python
for scene in sampled_scenes:
    initial = initial_state_for(scene)

    disamar_measurement = disamar_simulate(scene)
    disamar_result = disamar_retrieve(scene, initial, disamar_measurement)

    zdisamar_measurement = zdisamar_simulate(scene)
    zdisamar_result = zdisamar_retrieve(scene, initial, zdisamar_measurement)

    record_pair(scene, disamar_result, zdisamar_result)
```

This avoids a misleading hybrid comparison where one retrieval engine is asked
to retrieve the other engine's synthetic spectrum. The paired result answers the
throughput and convergence question for each complete retrieval lane.
