# O2 A Retrieval Performance

Scope: aerosol-only O2 A optimal estimation with two state-vector dimensions:

```text
aerosol optical depth
aerosol layer mid pressure
```

Surface albedo, surface pressure, geometry, aerosol single-scattering albedo,
asymmetry factor, Angstrom exponent, and layer thickness can vary across scenes,
but they are fixed inside each retrieval.

Current paired sweep summary:

```text
DISAMAR Fortran: 100/100 converged, median 1227.947 s, mean 1197.811 s
zdisamar:        100/100 converged, median    3.327 s, mean    3.235 s
```

The result is not a different optimal-estimation shape. zdisamar is faster
because it runs a narrow in-process O2 A path, reuses forward-session state
inside the retrieval, and asks only for Jacobian columns in the state vector.

Fastmode is a case-owned zdisamar optimisation lane. It runs OE with resolved
fastmode RTM controls, and the corrected variant applies one sparse full-physics
OE update after fastmode convergence. The retained 100-case sweep reports:

```text
reference:          100/100 converged, median 1.790 s, mean 1.741 s
fast:               100/100 converged, median 0.954 s, mean 0.919 s
fastmode corrected: 100/100 converged, median 1.140 s, mean 1.115 s
```

Corrected fastmode stays closer to fastmode latency than full-reference latency
while reducing fastmode state errors by more than an order of magnitude.

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current retrieval elapsed time](current-retrieval-elapsed-time.md)
- [Fastmode final correction](fastmode-final-correction.md)
- [Optimisation notes](optimisation-notes/)
- [Session reuse](session-reuse.md)
- [State-vector Jacobians](state-vector-jacobians.md)
- [Inter-iteration hillclimb](inter-iteration-hillclimb.md)
- [Paired DISAMAR/zdisamar validation](paired-disamar-zdisamar-validation.md)
- [Open questions](open-questions.md)
