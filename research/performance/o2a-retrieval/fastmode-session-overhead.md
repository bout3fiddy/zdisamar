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

Follow-up: the Python OE paths now use this hook after resolving the loaded
state vector.  One-shot retrievals and single-worker native batches warm the
semi-analytical Jacobian route for the requested states; parallel native batches
still skip Python-handle warmup because their starts run in worker-owned
storage.

Scene-008 repeated public retrieval check, five starts with one session cache
and `ZDISAMAR_WORKER_LIMIT=10`:

```text
OE-route warm median:          406.376 ms
generic preload, no OE warm:   407.204 ms
```

Interpretation: the hook wiring is the correct route selection, but it is not a
large repeated-retrieval speedup on this scene.  The cost is dominated by the
native RTM/Jacobian evaluations and the sparse full-physics correction.

Rejected for automatic multistart batch use: prewarming the Python handle's
storage before a parallel native start batch does not warm the per-worker
`ProductStorage` instances that actually run the starts.  On the scene-008
25-start diagnosis boundary this added work without helping the worker
storages, so the batch path leaves warmup to the worker-owned storage.

Rejected follow-up: warming each native batch worker's own `ProductStorage`
before its run range also stayed inside timing noise.  It warmed the
semi-analytical route and captured profile preparation before the worker's
first start, but it did not reduce the measured boundary enough to justify the
extra warm pass.

```text
scene 008, 25 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3:  8.458 s
scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3: 33.484 s
```

Small accepted cleanup: parallel OE batch cache loads skip the generic
no-Jacobian warm because the native batch workers use their own product
storages.  One-shot retrievals and single-worker batches still warm the loaded
storage on the OE Jacobian route, preserving the repeated public retrieval path.

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

## 2026-05-27 Fused Native Fastmode Batch Handoff

Change: add a native fastmode batch handoff that runs the sparse fast-stage
batch and then feeds the fast-stage states directly into the sparse
full-physics correction batch.  This removes the Python round trip that copied
the fast-stage states, rebuilt corrected `StateVector` objects, and submitted a
second independent native batch.

Parity check:

```text
scene 008, 10 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
max_state_delta: 0.0
iterations_equal: true
fast_iterations_equal: true
correction_iterations_equal: true
converged_equal: true
correction_converged_equal: true
```

Timing evidence:

```text
scene 008, 25 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3: 8.508 s
scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3: 33.554 s
```

Interpretation: the fused handoff is semantically cleaner and removes a Python
boundary, but it is not the single-digit sweep win.  The realistic 100-start
boundary is still dominated by the native RTM/Jacobian evaluations themselves;
the Python fast-stage-to-correction copy was not a material cost at this scale.

## 2026-05-27 Multi-Start Native Boundary Rechecks

Scene-008 still spends almost all time in native model evaluations.  The
100-start fastmode diagnosis has 450 fast-stage RTM/Jacobian evaluations plus
100 sparse full-physics correction evaluations:

```text
scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
full fastmode+correction: 33.633 s, avg 0.336 s/start
fast stage only:          23.220 s, avg 0.232 s/start
fast-stage iteration histogram: {2: 1, 3: 13, 4: 33, 5: 43, 6: 9, 8: 1}
```

Changing outer start workers cannot replace the native forward-prefetch worker
path.  On the same 25-start scene-008 boundary, the many-start-worker shapes
were slower than keeping native prefetch at the host-core cap:

```text
native_worker_limit=1,  batch_workers=10: 11.120 s
native_worker_limit=1,  batch_workers=5:  13.528 s
native_worker_limit=2,  batch_workers=8:   9.936 s
native_worker_limit=3,  batch_workers=6:   9.239 s
native_worker_limit=5,  batch_workers=3:   9.058 s
native_worker_limit=10, batch_workers=1:   9.487 s
native_worker_limit=10, batch_workers=3:   8.495 s
```

Rejected for this pass:

- Per-worker fused fast-stage plus correction execution.  It matched the old
  two-batch path exactly (`max_state_delta=0`, identical iteration and
  convergence arrays), but timing stayed flat: 10 starts `3.568 s` versus
  `3.575 s` for the old path, 25 starts `8.494 s`, and 100 starts `33.633 s`.
- Directly merging `codex/zig-oe-performance`.  The branch carries real RTM
  hot-path work, but a whole-branch merge conflicts with old input-model files,
  benchmark artifacts, validation outputs, and most touched RTM files.  It needs
  source-level extraction, not a blind merge.
- The standalone fixed 12x10 q-series pivot patch from
  `codex/labos-qseries-rowswap`.  It builds and preserves the scene-008
  25-start boundary (`8.495 s`), but does not move this fastmode workload; the
  fast benchmark also drifted slightly slower within noise.

Current conclusion: the remaining single-digit target needs fewer OE
RTM/Jacobian evaluations or a real per-evaluation RTM/Jacobian speedup.  Session
handoff cleanup, Python object churn, and outer-worker policy are already below
the dominant cost for this scene.

## 2026-05-27 Native Prefetch Retest

The relevant native prefetch knob is `ZDISAMAR_WORKER_LIMIT`; the multi-start
validation script now defaults that cap to the host CPU count, and the focused
scene-008 timings above use `ZDISAMAR_WORKER_LIMIT=10`.  The retained benchmark
canary intentionally uses a smaller two-worker cap, so it is not the right
boundary for judging the 10-core multi-start diagnosis timing.

## 2026-05-28 Start-Level Tail Balance

Finding: scene-008 broad start grids do not cost the same per start.  With
static contiguous assignment, the 100-start fast-stage-only run had the same
global iteration histogram, but the 3-worker chunks owned uneven iteration
loads:

```text
iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
static 3-worker iteration sums: [132, 131, 151]
```

Change: keep the inner native forward-prefetch policy unchanged, but let the
outer native OE batch workers claim one start at a time from `ChunkQueue`.
Each worker still owns its prepared case and product storage; the queue only
balances which start index is run next.

Timing evidence on the same scene-008 100-start boundary:

```text
ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
fast stage only, before: 21.50-21.60 s
fast stage only, after:  21.283 s
full correction, before: 31.848 s
full correction, after:  31.688 s
```

Checksums and iteration histograms were unchanged:

```text
fast-stage-only checksum: 53299.59263402397
full-correction checksum: 54177.55550248104
```

Accepted as a small tail-balance cleanup.  It does not change the current
conclusion: this workload still needs fewer OE RTM/Jacobian evaluations or a
per-evaluation RTM/Jacobian speedup to reach single-digit 100-start sweeps.

Two narrow prefetch scheduling probes were rejected:

- Increasing the reused-session pooled forward-prefetch chunk from `8` to `16`
  misses was slower on the same scene-008 boundary: 10 starts `3.633 s` versus
  the current `3.575 s` check, and 25 starts `8.827 s` versus the current
  `~8.48 s` range.
- Replacing the thread-pool prefetch queue with static per-worker ranges was
  visibly worse on the 10-start scene-008 smoke and was stopped before
  completion.  The pooled workers are already warm; the queue is still useful
  for balancing variable LABOS miss costs in this boundary.

Conclusion: keep the current native prefetch policy.  The speed problem is not
an omitted worker cap or a simple queue/chunk setting; the remaining cost is the
number and price of the RTM/Jacobian evaluations.

## 2026-05-27 Diagnosis Driver Worker Default

Finding: the validation multi-start script defaulted `--batch-workers` to `1`,
which bypassed the bounded worker policy used by `Result.diagnose()`.  On
scene 008 this selected a pathological same-scene batch shape:

```text
Debug-synced binding, batch_workers=1, 10 starts: 90.058 s
ReleaseFast binding, batch_workers=3, 10 starts: 3.666 s
```

Change: the validation driver now resolves omitted `--batch-workers` through
`diagnosis_batch_worker_count_for_limit(...)`, matching the public diagnosis
path.  The default no longer silently takes the single-worker path.

Timing evidence with the packaged binding rebuilt by
`zig build -Doptimize=ReleaseFast sync-python-package`:

```text
scene 008, 10 starts, native_worker_limit=10, auto batch_workers=3: 3.586 s
scene 008, 25 starts, native_worker_limit=10, auto batch_workers=3: 8.469 s
```

## 2026-05-28 Fastmode Convergence Threshold

Finding: the broad scene-008 basin sweep is slower than the steady repeated
retrieval prefetch probe because it has many more OE iterations.  On the
100-start fast-stage-only boundary, the current default produced this iteration
mix:

```text
state_vector_convergence_threshold=1.0
elapsed: 23.861 s
iteration histogram: {2: 1, 3: 13, 4: 33, 5: 43, 6: 9, 8: 1}
```

Rejected: increasing `max_change_transformed_state`.  It did not materially
reduce the scene-008 25-start runtime and only moved states by small amounts.
Very loose convergence thresholds were also rejected: threshold `50` reduced
the 100-start scene-008 fast-stage-only boundary to `19.607 s`, but moved the
retrieved state by `7.17e-4` AOD and `1.15 hPa` versus the retained fastmode
default, outside the retained validation pressure gate.

Change: set the case-owned fastmode OE
`state_vector_convergence_threshold` to `10.0` and make retained validation
callers omit explicit controls so they exercise the same case-owned fastmode
path as public `retrieve(..., controls=None)` and `Result.diagnose()`.

Scene-008 fast-stage-only timing evidence:

```text
state_vector_convergence_threshold=10.0
elapsed: 21.476 s
iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
all 100 starts converged
```

Retained fastmode-vs-reference validation was regenerated with the fullmode
rows unchanged and the fastmode rows rerun under the new case-owned controls:

```text
fastmode rows: 100
fast-stage converged: 100
fastmode median retrieval: 0.389819 s
fastmode-reference max_abs AOD delta: 4.181641e-4
fastmode-reference max_abs pressure delta: 5.458586e-1 hPa
```

Interpretation: this is a real, modest iteration-count win.  It does not make
the 100-start diagnosis single-digit because most starts still require four or
five RTM/Jacobian evaluations, but it moves the retained fastmode latency and
keeps the existing accuracy contract.

## 2026-05-28 Fused Fastmode Batch Workers

Finding: the `~175 ms` repeated-retrieval probe is not the same workload as the
scene-008 basin sweep.  The broad 100-start scene-008 grid still performs 414
fast-stage RTM/Jacobian evaluations plus 100 sparse full-physics correction
evaluations, so the fast-stage-only boundary alone is above the `17.5 s`
estimate:

```text
scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
fast stage only: 21.490 s
iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
```

Change: `runO2AFastmodeBatch` now gives each native batch worker both the
fast-stage prepared case and the sparse correction prepared case.  Each worker
runs its assigned starts end-to-end, avoiding the intermediate `BatchResult`
state table and the second batch/thread handoff between fast-stage and
correction solves.

Focused scene-008 checks after the change:

```text
scene 008, 25 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
elapsed: 8.019 s
checksum: 13628.270821723605

scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
elapsed: 31.848 s
iteration histogram: {3: 3, 4: 20, 5: 42, 6: 31, 7: 3, 8: 1}
fast-stage iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
checksum: 54177.55550248104
```

The same live 100-start probe immediately before the native worker fusion was
`32.156 s` with the same checksum and iteration histograms.  This is a modest
native-boundary cleanup, not the single-digit answer.  The remaining target
still requires fewer OE RTM/Jacobian evaluations or a per-evaluation forward
model speedup.

## 2026-05-28 Prefetch-Mode Boundary Check

The retained `~175 ms` figure comes from the steady repeated-start public API
path: one caller-owned empty `SessionCache()`, fixed case and measurement,
`ZDISAMAR_WORKER_LIMIT=10`, omitted controls, and only the starting state vector
changing after an initial warm call.  It is a valid prefetch-session number, but
it should not be multiplied across the scene-008 basin grid without rechecking
the actual scene/start workload.

Scene-008, 100 starts, fast-stage-only, same starts and measurement:

```text
public repeated retrieve, one SessionCache:
  warm: 0.216 s
  elapsed: 24.489 s
  median: 254.193 ms
  iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
  checksum: 53262.16281631299

native diagnose batch, batch_workers=1:
  elapsed: 23.985 s
  iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
  checksum: 53262.16281631299

native diagnose batch, batch_workers=2:
  elapsed: 21.430 s
  iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
  checksum: 53262.16281631299

native diagnose batch, batch_workers=3:
  elapsed: 21.681 s
  iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
  checksum: 53262.16281631299
```

Interpretation: the current native `diagnose()` path is already at least as
fast as the exact prefetch-session repeated path for this workload.  The
remaining gap from a naive `100 * 175 ms` estimate is not Python wrapper churn;
the broad scene-008 starts need more expensive RTM/Jacobian evaluations than
the small repeated-start timing probe.

## 2026-05-28 Diagnosis Row Handoff

Change: `Result.diagnose()` now passes one resolved state-vector template plus
row-major start/prior values into the native batch boundary.  It no longer
materializes one Python `StateVector` object per start before handing the sweep
to native code.

Scene-008 fast-stage-only check after the row handoff and native worker-pool
experiments:

```text
scene 008, 100 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=2
elapsed: 21.038 s
iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
checksum: 53262.16281631299

scene 008, 25 starts, ZDISAMAR_WORKER_LIMIT=10, batch_workers=2
elapsed: 5.310 s
iteration histogram: {3: 7, 4: 10, 5: 6, 6: 2}
checksum: 13399.690497323336

scene 008, 100 starts with sparse final correction, ZDISAMAR_WORKER_LIMIT=10, batch_workers=3
elapsed: 31.375 s
iteration histogram: {3: 3, 4: 20, 5: 42, 6: 31, 7: 3, 8: 1}
fast-stage iteration histogram: {2: 3, 3: 20, 4: 42, 5: 31, 6: 3, 7: 1}
checksum: 54138.99689749256
```

Interpretation: this is small by itself because the boundary is dominated by
native RTM/Jacobian evaluations, but it keeps the Python API aligned with the
intended native design: one diagnosis call, one prepared template, many start
rows.

## 2026-05-28 Auto Worker Cap Tightening

Finding: after the row handoff, scene-008 worker scans still favored two
outer start workers over three on the 10-core native prefetch boundary.  The
third outer worker competes with the inner forward-prefetch pool more than it
helps tail balance for this workload.

Focused 25-start checks, `ZDISAMAR_WORKER_LIMIT=10`:

```text
fast-stage-only:
  batch_workers=1: 6.056 s
  batch_workers=2: 5.317 s
  batch_workers=3: 5.400 s
  batch_workers=4: 5.411 s

sparse final correction:
  batch_workers=1: 8.803 s
  batch_workers=2: 8.068 s
  batch_workers=3: 8.178 s
  batch_workers=4: 8.257 s
```

Change: cap the automatic `Result.diagnose()` start-worker policy at two
workers while leaving explicit `batch_workers=` unchanged.  This preserves the
native prefetch worker cap and keeps the public diagnosis default on the faster
measured boundary.
