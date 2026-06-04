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
zdisamar:        100/100 converged, median    3.624 s, mean    3.667 s
```

The result is not a different optimal-estimation shape. zdisamar is faster
because it runs a narrow in-process O2 A path, reuses forward-session state
inside the retrieval, and asks only for Jacobian columns in the state vector.

Fastmode is a case-owned zdisamar optimisation lane. It runs OE with resolved
fastmode RTM controls, sparse fast-stage wavelength sampling, and one sparse
full-physics OE update after fastmode convergence. The retained 100-case sweep
reports:

```text
fullmode: 100/100 converged, median 1.807 s, mean 1.763 s
fastmode: 100/100 converged, median 0.420 s, mean 0.411 s
```

The retained fastmode default uses 12 fast-stage wavelengths and 4
full-physics correction wavelengths in the validation sweep. It keeps median
speedup at `+1.393 s` versus fullmode while staying within `4.182e-04` AOD and
`0.551 hPa` pressure maximum retrieved-state deltas.
The reported fullmode and fastmode durations are wall-clock timings around the
public retrieval call, including session/cache creation, native case load and
preparation, native OE work, and the sparse full-physics correction.

The retained benchmark artifact for code-speed changes is
[`benchmark/results.json`](../../../benchmark/results.json), regenerated on
2026-05-27 with `uv run benchmark/run_benchmark.py`. It uses the benchmark
worker cap of 2 and keeps setup separate from the timed retrieval loop:

```text
forward no-session median                      0.976 s
forward session cached-run median              0.263 s
OE single session retrieval median             1.098 s
OE single fastmode retrieval median            0.529 s
OE 5-case session sweep retrieval median       2.491 s
OE 5-case fastmode sweep retrieval median      0.804 s
OE 5-case fastmode sweep retrieval total       4.368 s
```

Use the benchmark artifact for retained local timing changes. Use the 100-case
fastmode sweep above for accuracy, convergence, and wavelength-shape claims.

For the 10-worker baseline-case wrapper boundary, the current one-shot fastmode
public call is `0.230 s` median. A repeated-start loop with a caller-owned
session cache is `0.179 s` median after the first sparse-case load. See
[`fastmode-session-overhead.md`](fastmode-session-overhead.md) for that focused
probe.

Read these notes in order:

- [Measurement provenance](measurement-provenance.md)
- [Current retrieval elapsed time](current-retrieval-elapsed-time.md)
- [Fastmode sampling and final correction](fastmode-final-correction.md)
- [Fastmode session overhead log](fastmode-session-overhead.md)
- [Multistart calculation telemetry probe](multistart-calculation-telemetry.md)
- [Optimisation notes](optimisation-notes/)
- [Session reuse](session-reuse.md)
- [State-vector Jacobians](state-vector-jacobians.md)
- [Inter-iteration hillclimb](inter-iteration-hillclimb.md)
- [Paired DISAMAR/zdisamar validation](paired-disamar-zdisamar-validation.md)
- [Open questions](open-questions.md)
