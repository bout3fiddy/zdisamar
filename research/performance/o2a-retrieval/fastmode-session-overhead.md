# Fastmode Session Overhead Log

Goal: reduce overhead around one 10-worker O2 A fastmode OE retrieval without
changing the retrieval result or the fastmode accuracy contract.

Boundary:

- public Python `o2a.retrieve(...)`;
- `ZDISAMAR_WORKER_LIMIT=10`;
- baseline fastmode case;
- measurement construction outside the timed block;
- no lazy final-state spectrum evaluation.

## 2026-05-27 Pressure Profile Resolution

Finding: resolving pressure metadata for `AerosolLayerMidPressure` used the
original full measurement case before the fast-stage case was loaded. That
created a temporary 301-sample native prepare even though the pressure-altitude
profile is independent of the sparse wavelength subset.

Change: resolve the state vector against the already loaded sparse fast-stage
case, using the session cache's atmospheric budget table.

Correctness check:

```text
profile_altitude_max_abs_delta: 0.0
profile_pressure_max_abs_delta: 0.0
retrieved state: [0.2999956187216867, 899.9876335361299]
iterations: 5
converged: true
```

Timing evidence after the change:

```text
cache=None median: 235.899 ms
instrumented cache=None total: 234.069 ms
prepare.samples_12.fast_True: 8.760 ms
warm_cache: 44.567 ms
native fast OE: 101.010 ms
prepare.samples_4.fast_False: 7.325 ms
native full-physics correction: 69.418 ms
```

Accepted: removes the full-grid pressure-profile prepare from the timed
`cache=None` path with no retrieval-state change.

## 2026-05-27 Preserve Caller-Owned Sparse Cache

Finding: a caller can preload and warm the sparse fast-stage case before timing,
but the final correction loaded its 4-sample full-physics case into that same
cache. The first call stayed fast; repeated calls with the same sparse cache
then reloaded the fast-stage case and moved warmup work back into the
invocation.

Scratch comparison for five repeated calls with one caller-owned sparse cache:

```text
same cache overwritten by correction: [174.974, 236.268, 225.403, 237.640, 227.737] ms
temporary correction cache candidate: [175.907, 178.220, 189.373, 173.658, 172.922] ms
states_equal: true
```

Change: when the caller supplies a cache to fastmode OE, keep that cache loaded
with the fast-stage case and run the final correction on a temporary native
handle. The `cache=None` one-shot path keeps the previous single-handle shape.

Timing evidence after the change:

```text
repeated preloaded sparse cache: [173.289, 174.959, 170.268, 171.543, 177.524] ms
median: 173.289 ms
retrieved state: [0.2999956187216867, 899.9876335361299]
iterations: 5
converged: true
```

Accepted: preserves the warmed sparse fast-stage session across repeated calls
without changing the returned state.

## Remaining Overhead

The clean remaining per-call overhead target is the 4-sample full-physics
correction prepare, about `7 ms` in the current boundary. Removing it safely
requires a native correction path that applies the corrected state without
reparsing and repreparing the correction case, or a richer prepared correction
session. A Python cache reshuffle alone would not remove the state-dependent
optical preparation required by the correction.
