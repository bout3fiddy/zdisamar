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
cache=None median: 230.234 ms
instrumented cache=None total: 229.178 ms
prepare.samples_12.fast_True: 8.413 ms
prepare.samples_4.fast_False: 6.874 ms
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
retrieval times: [226.053, 170.083, 178.657, 198.858, 172.902] ms
median: 178.657 ms
iterations: [5, 5, 5, 6, 5]
converged: [true, true, true, true, true]
```

The first call pays the initial sparse fast-stage load and warm cost.  Later
calls reuse the same fast-stage cache; the final correction does not replace it.

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
total cache-match time: 1.296 ms
mean matched-call time: 0.324 ms
```

Accepted: removes one redundant fingerprint check from each already-loaded
pressure-profile resolution.  This is a sub-millisecond repeated-call win, not a
large latency change.

## 2026-05-27 Correction Prepare Investigation

The 4-sample full-physics correction load was split inside the Python binding:

```text
load samples_4.fast_False:
  apply_rtm_optimisation: 0.075 ms
  resolve_assets:         0.239 ms
  json_payload:           0.073 ms
  native_prepare:         6.874 ms
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
correction prepare, about `7 ms` in the current boundary.  The measured Python
payload work is below `0.4 ms`; the recoverable cost is in native preparation.
Removing it safely requires native correction-session state rather than another
Python cache reshuffle.

## 2026-05-27 OE-Specific Warm Hook

Finding: native session warmup can now be requested for the semi-analytical OE
Jacobian route rather than the generic no-Jacobian spectrum route.  The C API
accepts the requested Jacobian state ids, switches the loaded route to
semi-analytical derivatives, and warms the session storage for that route.
`SessionCache.warm_optimal_estimation(...)` caches the state-name tuple so a
caller-owned session does not repeat the same warm request.

Rejected for automatic multistart batch use: prewarming the Python handle's
storage before a parallel native start batch does not warm the per-worker
`ProductStorage` instances that actually run the starts.  On the scene-008
25-start diagnosis boundary this added work without helping the worker
storages, so the batch path leaves warmup to the worker-owned storage.

Small accepted cleanup: parallel OE batch cache loads skip the generic
no-Jacobian warm because the native batch workers use their own product
storages.  One-shot retrievals and single-worker batches still warm the loaded
storage, preserving the repeated public retrieval path.

Timing evidence:

```text
scene 008, 25 starts, ZDISAMAR_WORKER_LIMIT=10
before cleanup, batch_workers=3: 8.764 s
after cleanup,  batch_workers=3: 8.480 s
```

Interpretation: this is not the large native-session win.  The larger win still
requires a fused fastmode/correction session or reusable correction session that
owns the worker storage used by the actual batch starts.

## 2026-05-27 Native Prefetch Worker Policy

The native forward path already uses `ZDISAMAR_WORKER_LIMIT` for the
high-resolution forward-miss prefetch loop.  The multi-start diagnosis should
therefore not silently cap that native prefetch setting below the host CPU
count in validation tooling, and it should keep automatic start-level workers
small enough that nested prefetch pools do not dominate scheduling.

Scene-008, 25-start checks on the same noisy machine:

```text
native_worker_limit=2,  batch_workers=1: 22.504 s
native_worker_limit=2,  batch_workers=2: 14.947 s
native_worker_limit=2,  batch_workers=3: 12.337 s
native_worker_limit=2,  batch_workers=4: 10.753 s
native_worker_limit=5,  batch_workers=3:  8.907 s
native_worker_limit=5,  batch_workers=4:  9.022 s
native_worker_limit=8,  batch_workers=3:  8.824 s
native_worker_limit=8,  batch_workers=4:  8.943 s
native_worker_limit=10, batch_workers=3:  8.731 s
native_worker_limit=10, batch_workers=4:  8.763 s
```

Scene-008, 100-start checks:

```text
native_worker_limit=10, batch_workers=1: 36.873 s
native_worker_limit=10, batch_workers=3: 33.216 s
native_worker_limit=10, batch_workers=5: 34.034 s
native_worker_limit=10, batch_workers=10: 34.302 s
```

Accepted cleanup: use the host CPU count as the validation script's default
native prefetch worker cap, matching the native runtime default when the
environment is unset.  Cap automatic diagnosis start workers at `3`, which was
the best observed shape for the 100-start boundary and avoids turning a
10-worker native prefetch run into a 5x nested worker fanout by default.
