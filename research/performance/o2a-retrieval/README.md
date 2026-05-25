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

The fast-accurate retrieval mode is a separate zdisamar-only multi-fidelity
validation lane. It runs fast-mode OE to convergence, then applies one
full-physics correction on a retained O2 A correction window. The retained
100-case sweep reports:

```text
reference:      100/100 converged, median 1.887 s, mean 1.951 s
fast:           100/100 converged, median 0.998 s, mean 1.019 s
fast-accurate:  100/100 converged, median 1.408 s, mean 1.472 s
```

Fast-accurate stays closer to fast-mode latency than full-reference latency
while reducing fast-mode state errors by more than an order of magnitude.

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current retrieval elapsed time](current-retrieval-elapsed-time.md)
- [Fast-accurate correction](fast-accurate-correction.md)
- [Optimisation notes](optimisation-notes/)
- [Session reuse](session-reuse.md)
- [State-vector Jacobians](state-vector-jacobians.md)
- [Inter-iteration hillclimb](inter-iteration-hillclimb.md)
- [Paired DISAMAR/zdisamar validation](paired-disamar-zdisamar-validation.md)
- [Open questions](open-questions.md)
