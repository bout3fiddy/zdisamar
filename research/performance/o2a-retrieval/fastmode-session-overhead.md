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

## 2026-05-27 Case-Owned Controls And Repeated Starts

The canonical repeated-start shape keeps controls in the case and passes only
the varying state vector through the public retrieval call:

```python
with rtm.SessionCache() as cache:
    for start in starting_values:
        result = o2a.retrieve(
            case=case,
            measurement=measurement,
            state_vector=state_vector_for(start),
            cache=cache,
        )
```

Fastmode resolves `controls=None` from
`case.optimisation.fastmode.oe.controls`.  Non-fastmode keeps the existing
DISAMAR-style default controls.  Focused Python coverage checks the omitted
controls path so callers do not need to construct `RetrievalControls` for the
repeated-retrieval fastmode path.

Repeated-start timing with one caller-owned empty `SessionCache()`, five
different initial states, and no explicit controls:

```text
retrieval times: [252.639, 196.693, 193.307, 223.627, 196.890] ms
median: 196.890 ms
iterations: [5, 5, 5, 6, 5]
converged: [true, true, true, true, true]
```

The first call pays the initial sparse fast-stage load/warm cost.  Later calls
reuse the same fast-stage cache; the final correction does not replace it.

## 2026-05-27 Duplicate Cache-Match Checks

Finding: after `retrieve()` had already established that the supplied cache held
the sparse fast-stage case, pressure-profile resolution called the generic
`has_loaded_case` path again.  That path fingerprints the case by rebuilding the
native JSON payload.

Change: use a loaded-cache pressure-profile path once stale-cache protection has
already run at the retrieval boundary.  The caller-supplied cache still performs
one `has_loaded_case(fast_case)` check per retrieval so case or measurement
changes reload the cache correctly.

Timing evidence from the repeated-start probe:

```text
cache-match calls: 4 for 5 starts
total cache-match time: 1.607 ms
mean matched-call time: 0.402 ms
```

Accepted: removes one redundant fingerprint check from each already-loaded
pressure-profile resolution.  This is a sub-millisecond repeated-call win, not a
large latency change.

## 2026-05-27 Correction Prepare Investigation

The 4-sample full-physics correction load was split inside the Python binding:

```text
load samples_4.fast_False:
  apply_rtm_optimisation: 0.084 ms
  resolve_assets:         0.216 ms
  json_payload:           0.071 ms
  native_prepare:         7.572 ms
  python_bookkeeping:     0.006 ms
```

The current correction C entrypoint consumes a fully prepared `PreparedO2A`.
`correctPreparedO2A` copies that prepared case, switches derivative mode, and
simulates the RTM/Jacobian from `prepared.scene` and `prepared.prepared`.
It does not apply the correction initial state to a base scene and rebuild
state-dependent optical properties.

Rejected for this pass: simply keeping a prepared correction case alive in
Python.  That would reuse optics prepared at the wrong aerosol optical depth or
layer pressure for later starts.

Safe native direction: add a correction session that owns the sparse
full-physics correction inputs, route, weak-grid/profile preparation caches, and
workspace, then applies each fast-stage state and refreshes state-dependent
optics before the one-step correction.  That is the same semantic class as the
native multi-start session work and is too large for this wrapper-overhead PR.

## Remaining Overhead

The clean remaining per-call overhead target is the 4-sample full-physics
correction prepare, about `7-8 ms` in the current boundary.  The measured Python
payload work is below `0.4 ms`; the recoverable cost is in native preparation.
Removing it safely requires native correction-session state rather than another
Python cache reshuffle.
