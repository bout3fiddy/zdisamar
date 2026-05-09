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
DISAMAR Fortran: 100/100 converged, median 1228.826 s, mean 1189.862 s
zdisamar:        100/100 converged, median    4.349 s, mean    4.309 s
```

The result is not a different optimal-estimation shape. zdisamar is faster
because it runs a narrow in-process O2 A path, reuses forward-session state
inside the retrieval, and asks only for Jacobian columns in the state vector.

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current retrieval elapsed time](current-retrieval-elapsed-time.md)
- [Optimisation notes](optimisation-notes/)
- [Session reuse](session-reuse.md)
- [State-vector Jacobians](state-vector-jacobians.md)
- [Paired DISAMAR/zdisamar validation](paired-disamar-zdisamar-validation.md)
- [Open questions](open-questions.md)
