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
fastmode RTM controls, sparse fast-stage wavelength sampling, and one sparse
full-physics OE update after fastmode convergence. The retained 100-case sweep
reports:

```text
fullmode: 100/100 converged, median 1.944 s, mean 1.899 s
fastmode: 100/100 converged, median 0.538 s, mean 0.528 s
```

The retained fastmode default uses 38 fast-stage wavelengths and 12
full-physics correction wavelengths in the validation sweep. It keeps median
speedup at `+1.416 s` versus fullmode while staying within `5.285e-04` AOD and
`0.668 hPa` pressure maximum retrieved-state deltas.
The reported fullmode and fastmode durations are wall-clock timings around the
public retrieval call, including session/cache creation, native case load and
preparation, native OE work, and the sparse full-physics correction.

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current retrieval elapsed time](current-retrieval-elapsed-time.md)
- [Fastmode sampling and final correction](fastmode-final-correction.md)
- [Optimisation notes](optimisation-notes/)
- [Session reuse](session-reuse.md)
- [State-vector Jacobians](state-vector-jacobians.md)
- [Inter-iteration hillclimb](inter-iteration-hillclimb.md)
- [Paired DISAMAR/zdisamar validation](paired-disamar-zdisamar-validation.md)
- [Open questions](open-questions.md)
