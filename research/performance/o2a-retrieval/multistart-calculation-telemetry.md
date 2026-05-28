# Multistart Calculation Telemetry Probe

Question: for repeated fastmode OE starts on one fixed O2 A scene, which
calculations are invariant enough to justify session-level reuse?

## Probe

Scene: validation scene 008.

Starts: five starts from the multistart diagnosis generator, with
`a_priori == start` for each row.

Boundary: the real native same-scene fastmode diagnosis path:

```text
diagnose_retrieval
  -> diagnosis_batch
  -> run_native_fastmode_retrieval_batch
  -> zds_run_o2a_fastmode_optimal_estimation_batch
  -> runO2AFastmodeBatch
```

The fast stage used the case-owned fastmode settings used by `diagnose()`:
12 fast-stage wavelengths, sparse fast RTM settings, and then one sparse
full-physics correction on 4 wavelengths. The run used one prepared fast case,
one prepared correction case, and `batch_workers=2`, matching
`diagnosis_batch_worker_count_for_limit(5, 10)`.

Instrumentation added row context to the validation-only calculation telemetry:
scene, start, fast/correction stage, OE iteration, forward-evaluation index,
forward sample/wavelength, state hash, and first three state values. The context
is copied into native batch workers and forward-prefetch workers, so rows remain
attributable under parallel execution.

Storage policy: raw Parquet was written under `/tmp`, aggregated immediately,
and deleted. Raw size was 1.5 GiB. The retained compact output is 56 KiB:

```text
out/fastmode-diagnosis-telemetry/scene008-5starts/
```

## Row Volume

Telemetry run:

| Table | Rows |
| --- | ---: |
| scalar_expression_rows | 2,236,508 |
| reduction_expression_rows | 83 |
| decision_rows | 49,284,480 |

The telemetry run took 58.91 s because row-level Parquet writing dominates this
instrumented build. A normal ReleaseFast public-path run for the same scene and
five starts took 1.718 s total, or 0.344 s/start including setup and plotting
script overhead.

## Timing Gap Audit

I rechecked the current worktree before adding more native optimization
machinery. Same-boundary settings: ReleaseFast package sync,
`ZDISAMAR_WORKER_LIMIT=10`, unchanged fastmode controls, fixed case and
measurement, one reused `rtm.SessionCache()`, no `final_evaluation` access
inside timed loops, two native diagnosis workers, and 25 starts.

| Worktree/path | Scene | Boundary | Wall time [s] | Per start [s] | Median start [s] | Converged | State delta |
| --- | ---: | --- | ---: | ---: | ---: | ---: | ---: |
| current | 008 | native `diagnose()` fast+correction | 7.708 | 0.308 | n/a | 25/25 | 0 |
| current | 008 | native fast stage only | 5.094 | 0.204 | n/a | 25/25 | n/a |
| current | 008 | public repeated `retrieve()` | 9.802 | 0.392 | 0.377 | n/a | 0 |
| current | 005 | native `diagnose()` fast+correction | 7.541 | 0.302 | n/a | 25/25 | 0 |
| current | 005 | native fast stage only | 5.111 | 0.204 | n/a | 25/25 | n/a |
| current | 005 | public repeated `retrieve()` | 9.689 | 0.388 | 0.391 | n/a | 0 |

The remembered 170-180 ms steady repeated-start number did not reproduce on
this machine with the full fast+correction path. Local release worktrees were
slower on the same public repeated boundary: `0.0.17` measured 0.418 s/start
for scene 008 and 0.413 s/start for scene 005; the `0.0.16` check measured
0.490 s/start and 0.484 s/start respectively. The closest current-worktree
number was fast-stage-only public repeated retrieval: about 0.232 s/start with
medians around 0.224-0.226 s/start.

Direct FFI timing shows that the native C call, not Python wrapper churn,
owns the current native diagnosis cost:

| Scene | Fixture build [s] | Cache load + state resolve [s] | Python request/copy/free [s] | Native C call [s] | Native share |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 008 | 0.692 | 0.020 | 0.0002 | 7.582 | 99.7% |
| 005 | 0.686 | 0.021 | 0.0001 | 7.509 | 99.7% |

Splitting the exact native work into two batch calls gives the same shape:

| Scene | Fast native [s] | Fast per start [s] | Correction native [s] | Correction per start [s] | Split total [s] |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 008 | 5.108 | 0.204 | 2.574 | 0.103 | 7.682 |
| 005 | 5.050 | 0.202 | 2.489 | 0.100 | 7.539 |

Interpretation: there is no evidence here that native diagnosis is slower
because of Python request construction, C FFI copying, result materialization,
or cache loading. The remaining exact-safe opportunity must remove native
forward/Jacobian work or make the same native RTM/Jacobian work cheaper; it
cannot come from wrapper cleanup alone.

An 8 s macOS `sample` capture of the Python child process during a 100-start
scene-008 native diagnosis run confirmed the same attribution. The sampled run
timed 32.362 s total, or 0.324 s/start. In the active native C call stack,
`zds_run_o2a_fastmode_optimal_estimation_batch` accounted for 5,053 samples.
Under that, `simulateProductWithWorkspace` accounted for 4,019 samples,
`computeForwardSampleAtWavelengthWithScratch` for 3,924 samples, and LABOS
`layerResolvedLabosWithWorkspace`/`calcRTlayersIntoWithBasis`/`doDouble12x10`
dominated the nested RTM work. A worker-pool thread independently showed the
same shape: 4,771 samples in `computeForwardSampleAtWavelengthWithScratch`,
2,934 in `layerResolvedLabosWithWorkspace`, and 2,616 in
`calcRTlayersIntoWithBasis`. Optical spectroscopy preparation appeared only as
small leaf samples in this capture; it was not the dominant current gap.

## Scene-Invariant Setup

The wavelength-plan reductions are invariant inside each stage:

| Stage | Sampling shape result | Forward-miss unique fraction |
| --- | ---: | ---: |
| fast | 3,256 | 0.405405 |
| correction | 1,420 | 1.000000 |

These rows are setup-level signals, not state-dependent solver outputs. They
support keeping wavelength sampling plans, forward miss plans, and output buffer
shape under the session cache.

## Iteration Structure

Fast-stage row volume varies materially by start and iteration. Examples from
decision rows:

| Start | Fast evals | Fast decision rows |
| ---: | ---: | ---: |
| 1 | 4 | 5,516,449 |
| 2 | 4 | 5,371,809 |
| 3 | 3 | 4,056,057 |
| 4 | 5 | 5,593,304 |
| 5 | 4 | 4,647,387 |

Correction has one forward evaluation per start, but row count still separates
by basin: starts 1-3 each produced 5,122,534 decision rows; starts 4-5 produced
about 4,365,9xx rows.

## Decision Stability

Fraction of decision rows whose coordinate group was present in all five starts
with the same row count and same taken-count:

| Decision | Fast | Correction |
| --- | ---: | ---: |
| labos_doubling_trigger | 68.4% | 98.5% |
| labos_qseries_skip | 54.3% | 85.1% |
| labos_qseries_rd_product | 54.2% | 84.3% |
| labos_qseries_tu_product | 54.0% | 84.0% |
| labos_qseries_td_product | 54.2% | 83.5% |
| fourier_tail_break | 74.3% | 99.1% |
| orders_convergence | 13.7% | 20.2% |

Interpretation: correction-stage LABOS and Fourier masks are strong reuse
candidates. Fast-stage masks are partially stable but basin/iteration dependent.
`orders_convergence` is not stable enough to cache as a reusable mask.

After separating scene 008 by the two observed correction basins, correction
mask stability becomes much stronger. The correction initial states split into a
high-AOD basin near AOD 0.550 / ALH 670 hPa for starts 1-3 and a low-AOD basin
near AOD 0.121 / ALH 334 hPa for starts 4-5.

| Basin | Decision | Correction same-taken row fraction |
| --- | --- | ---: |
| high AOD | labos_doubling_trigger | 1.000000 |
| high AOD | labos_qseries_skip | 0.999988 |
| high AOD | labos_qseries_rd_product | 0.999974 |
| high AOD | labos_qseries_tu_product | 0.999970 |
| high AOD | labos_qseries_td_product | 0.999985 |
| high AOD | fourier_tail_break | 1.000000 |
| low AOD | labos_doubling_trigger | 1.000000 |
| low AOD | labos_qseries_skip | 0.999968 |
| low AOD | labos_qseries_rd_product | 0.999952 |
| low AOD | labos_qseries_tu_product | 0.999933 |
| low AOD | labos_qseries_td_product | 0.999700 |
| low AOD | fourier_tail_break | 1.000000 |

Interpretation: a basin-keyed correction mask is much more plausible than a
global same-scene correction mask. It is still not exactly identical for every
q-series/downstream row, so a production cache must not blindly force all
q-series decisions from a coarse basin key. Safe variants are: exact
basin-keyed Fourier/layer-doubling masks, a q-series mask that keeps unstable
coordinates on the normal computed path, or an explicitly validated approximate
mask with residual gates.

## Numeric Stability

Median relative span of scalar outputs across starts for matching coordinates:

| Scalar | Fast | Correction |
| --- | ---: | ---: |
| labos_effective_scattering_depth | 0.545 | 0.780 |
| fourier_weighted_reflectance | 0.693 | 0.608 |
| labos_jacobian_norm1 | 0.587 | 0.513 |
| labos_reflectance_clamp | 0.00474 | 0.00152 |

Do not cache full numeric forward/LABOS values across arbitrary starts. The
state changes are large enough that optical depths, reflectance terms, and
Jacobian norms are genuinely state-dependent.

## Recommendations

Keep chasing reuse at the structural level:

- Session-owned wavelength sampling plans, forward miss routes, sparse-stage
  route setup, pressure-altitude profile, weak-grid/session storage, and result
  buffers.
- Stage-specific active masks for LABOS q-series/downstream product gates and
  Fourier tail decisions, especially in the correction stage.
- Mask keys should include stage, wavelength/sample, coordinate tuple, and a
  basin/state fingerprint. A global same-scene mask is too coarse for fast-stage
  iterations.
- Do not pursue cross-start caching of final numeric forward samples or Jacobian
  columns unless it is guarded by a very tight state fingerprint.

Next implementation target: compact per-stage active-mask storage in the native
session, starting with correction-stage LABOS/Fourier decisions where row-level
stability is above 83-99%.

## Accepted Iteration-Workspace Cleanup

I kept one exact micro-optimization in the native OE core. Batch summary runs
do not materialize posterior covariance or averaging-kernel output, and the
general `IterationWorkspace` carried two matrices that were no longer read by
the solver path. The retained cleanup removes those unused workspace fields and
avoids initializing `final_posterior_precision` before it is assigned by the
first completed iteration. This does not cache forward samples, Jacobians, or
branch decisions, and it does not change controls, convergence tests, output
order, or public API.

Same-boundary ReleaseFast timing used `ZDISAMAR_WORKER_LIMIT=10`, two native
start workers, 25 starts, and scenes 005 and 008. The immediate baseline timed
scene 005/008 at 7.660/8.297 s. The retained workspace cleanup timed 7.424/7.695
s. Comparing `runs.csv` with `retrieval_s` and `batch_wall_s` excluded showed
no non-timing differences and a maximum retrieved-state delta of 0. A 100-start
scene-008 target run timed 30.746 s, which remains inside the retained baseline
band for this machine.

Conclusion: this cleanup is exact and removes dead stack work, but it is not
the missing 170-180 ms repeated-start path. The remaining material opportunity
is still inside RTM/Jacobian/LABOS work, not summary-result bookkeeping.

## Rejected Summary Accumulation Probe

I tested a second summary-only OE cleanup: compile the normal-system
accumulation in a batch-summary mode that skips chi-square history bookkeeping
and `J^T S_e^-1 J` storage when no full `Result` is materialized. This kept the
same residual vector, Jacobian projection, `b` vector, `g` matrix, solver step,
state update, and convergence test. It did not change controls, physics,
retrieval priors, output order, or public API.

The same-boundary ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. The immediate baseline
timed scene 005/008 at 7.422/7.667 s. The candidate timed 7.428/7.628 s.
Comparing `runs.csv` with `retrieval_s` and `batch_wall_s` excluded showed no
non-timing differences; maximum absolute and relative retrieved-state deltas
were both 0.

Conclusion: the candidate is exact, but the timing effect is run-noise scale
and mixed by scene. Do not keep extra solver-core control flow for this. The
small amount of removed normal-system bookkeeping is not the current material
cost; RTM/Jacobian/LABOS remains dominant.

## Rejected Scratch-Retention Probe

I tested a narrower structural-reuse candidate before adding an active-mask
cache: move `ForwardSampleScratch` and its LABOS workspace under
`ProductStorage` so repeated starts keep per-worker transport buffers alive.
This kept all numeric forward samples and Jacobians recomputed.

The same-boundary ReleaseFast timing did not clear the bar. With
`ZDISAMAR_WORKER_LIMIT=10`, 100 starts, and two native start workers, scene 008
varied between about 30.3 and 31.6 s on the baseline worktree and about 30.4 to
31.9 s with the scratch-retention candidate. Scene 005 ranged from about 28.9
to 30.5 s on baseline and about 30.1 to 30.7 s with the candidate. Convergence,
iteration sums, and retrieved-state checksum summaries matched exactly.

Conclusion: keeping the per-worker scratch allocations alive is not a reliable
optimization on this workload. The next production implementation should stay
focused on the telemetry-backed LABOS/Fourier active-mask problem rather than
adding generic scratch-retention machinery.

## Rejected Phase-Support Reuse Probe

I also tested a smaller exact structural reuse: cache each aerosol phase
coefficient row's maximum active phase index while filling per-layer LABOS
phase support. This removes repeated scans of shared coefficient rows, but it
does not cache numeric forward samples, Jacobians, q-series terms, or Fourier
values.

The isolated same-worktree ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`,
25 starts, two native start workers, and scenes 005 and 008. Baseline timing:
scene 005 8.196 s, scene 008 7.683 s, 50/50 ok and converged. Candidate
timing: scene 005 7.977 s, scene 008 7.837 s, 50/50 ok and converged.

Conclusion: the change is semantically safe but not a reliable end-to-end
optimization. The likely removed work is too small relative to RTM/Jacobian
cost, and the mixed scene result is within run noise. Do not land this as the
main telemetry recommendation; keep the implementation target on the
correction-stage LABOS/Fourier active-mask cache.

## Rejected Fused Worker-Session Probe

I tested an internal native fastmode batch shape where each worker owned both
the fast-stage prepared case and the correction prepared case, then processed a
start through fast stage and correction before claiming another start. The
intent was to keep the worker's session resources hot across both stages and
remove the separate fast-worker phase followed by a separate correction-worker
phase. It did not cache numeric forward samples or Jacobians.

The same-boundary ReleaseFast diagnosis validation stayed numerically stable:
25-start scene 005/008 runs were 50/50 ok and converged, with retrieved-state
summary statistics matching the phase-separated path. Timing did not clear the
scene-008 bar. Scene 005/008 25-start timings were 7.767/8.006 s on the first
candidate run and 7.980/7.789 s on the repeat, compared with the retained
same-worktree phase-separated baseline of 8.196/7.683 s. On the 100-start
scene-008 stress case, the candidate took 30.793 s versus the retained
phase-separated baseline of 30.130 s.

Conclusion: fusing the fast and correction worker phases is not the right first
production optimization. It improves or ties some smaller runs but regresses the
target scene-008 workload. Keep the phase-separated native batch path and focus
the next implementation attempt on a correction-stage mask or workspace change
that reduces per-forward RTM/Jacobian work rather than only rearranging worker
lifetime.

## Rejected Caller ProductStorage Reuse Probe

I tested another narrow session-storage candidate in the parallel native batch
path: let the main worker borrow the caller-owned `ProductStorage` while spawned
workers kept independent local storage. This made one worker reuse the
session/cache storage across native batch calls without sharing mutable storage
between threads, and it did not cache numeric forward samples or Jacobians.

The same-boundary ReleaseFast validation used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. The first candidate run
timed scene 005/008 at 7.388/7.740 s; the repeat timed 7.834/7.900 s. Both runs
were 50/50 ok and converged. Compared with the retained same-worktree baseline
of 8.196/7.683 s, scene 005 sometimes improved, but the target scene 008 was
neutral to slower.

Conclusion: caller-owned `ProductStorage` reuse is semantically safe but not a
reliable speed win for the target workload. Do not land it as the first
production optimization. The next implementation should still target
correction-stage LABOS/Fourier masks or another change that removes repeated
per-forward RTM/Jacobian work.

## Rejected Correction Fourier-Mask Probe

I implemented a correction-stage Fourier-tail active-mask candidate behind the
native fastmode batch path only. The candidate recorded per-forward-sample
Fourier cutoff indices during a warmup correction subset, then applied the
largest observed cutoff to later correction starts in the same native diagnosis
batch. It stored only integer cutoffs, not forward samples or Jacobians, and it
left normal single retrieval and non-diagnosis paths disabled.

The five-start warmup version passed the focused Python smoke test and the
retained multistart validation, with scene 005/008 at 50/50 ok and converged.
Timing still did not beat the retained scene-008 boundary: 25-start scene
005/008 measured 7.555/7.769 s, and 100-start scene 008 measured 30.346 s
versus the retained phase-separated baseline of 30.130 s. A one-start warmup
probe was worse, timing scene 005/008 at 8.427/8.464 s for 25 starts.

Conclusion: Fourier-tail mask reuse alone is not a viable first production
optimization. The mask is stable enough to preserve the observed retrieval
summary on these runs, but it does not remove enough work to overcome warmup
and mask plumbing cost. Do not land the Fourier-cutoff cache. The next
candidate should target LABOS q-series/downstream product masks or a lower-level
mask representation inside the matrix-doubling path where the telemetry shows
large repeated decision volume.

## Rejected Correction Q-Zero Suppression Probe

I also tested a diagnosis-only correction-stage use of the existing LABOS
q-zero downstream product gates. The native fastmode batch correction input was
copied internally and the `qzero_rd_product_suppression`,
`qzero_tu_product_suppression`, and `qzero_td_product_suppression` flags were
enabled only for the sparse correction phase. This changed no public API and
did not affect normal single retrieval or non-batch fastmode code paths.

The probe passed the focused Python smoke test and retained multistart
validation. Scene 005/008 at 25 starts stayed 50/50 ok and converged, timing at
7.369/7.651 s. However, retrieved states shifted slightly relative to the
retained baseline; scene 008's high-AOD basin moved by about 7.4e-4 AOD and
about 0.24 hPa in layer pressure. The 100-start scene-008 target boundary did
not show a reliable win: repeated timings were 30.105 s and 30.209 s versus the
retained 30.130 s baseline.

Conclusion: enabling the existing q-zero downstream suppression only in
correction is not reliable enough to land. It is numerically close, but the
timing is noise-level and the output is no longer exact. A production mask needs
a lower-level representation that either preserves the exact branch decisions or
proves a stricter residual contract than this blanket correction-stage flag.

## Rejected Fixed 12x10 Trace-Carry Probe

I tested a lower-level exact candidate in the fixed 12x10 LABOS doubling path:
return Gaussian traces from the matrix helpers that write D, U, R, and T so the
q-series/downstream gates can carry those traces into the next doubling step
instead of rescanning the matrices. This cached no forward samples, no
Jacobians, and no approximate branch decisions; it only threaded exact traces
computed from the freshly written matrices.

The same-boundary ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. Baseline timing from
the current worktree was scene 005/008 at 7.359/7.630 s. The trace-carry
candidate timed 7.465/7.714 s. Excluding the timing columns, the two
`runs.csv` files were identical, so this was an exact-output change but not a
speed win.

Conclusion: do not land trace-carry helper variants as the first production
optimization. The extra helper plumbing and larger inlined fixed-shape matrix
code cost more than the removed trace scans on the retained diagnosis boundary.
The implementation target should remain a real correction-stage structural mask
or another change that removes repeated RTM/Jacobian work rather than moving
small trace reads around.

## Rejected Fixed 12x10 Direct-Trace Probe

I tested a smaller variant of the same fixed-shape idea: call a direct
12x10 Gaussian-trace helper from `doDouble12x10Step` instead of routing those
trace reads through the generic `gaussTrace(n, n_gauss, ...)` helper with
constant dimensions. This changed no matrix products, thresholds, q-series
decisions, output order, controls, physics, or public API; it only made the
fixed-shape trace path explicit.

The same-boundary ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. The immediate
baseline before the candidate timed scene 005/008 at 7.372/7.649 s. The
candidate timed 7.351/7.680 s. A post-revert baseline rerun timed 7.437/7.670
s. Comparing post-revert baseline and candidate `runs.csv` files with
`retrieval_s` and `batch_wall_s` excluded showed no non-timing differences,
and maximum retrieved-state absolute/relative delta was 0.

Conclusion: this is exact, but the effect is noise-scale and mixed on the
target scene. The compiler is already close enough to the desired fixed-shape
trace code that making this explicit is not worth retaining.

## Rejected Correction Queue-Chunk Probe

I tested an exact worker-scheduling candidate for the one-iteration correction
stage: change the internal correction chunk size from the retained value of 4
starts to either 8 starts or 2 starts. This does not change fastmode controls,
solver algebra, physics, start values, output order, or any public API.

The same-boundary ReleaseFast validation used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. Baseline repeat with
the retained chunk size 4 timed scene 005/008 at 7.513/7.783 s. Chunk size 8
timed 7.461/7.734 s. Chunk size 2 timed 7.516/7.718 s. All three runs were
50/50 ok and converged; comparing `runs.csv` with `retrieval_s` and
`batch_wall_s` excluded showed no non-timing differences for chunk sizes 2 or
8.

Conclusion: correction queue chunking is exact, but the measured differences
are run-noise scale and do not clear the target-scene confidence bar. Keep the
retained chunk size 4 for now. The useful audit result is that worker
scheduling is not the missing breakthrough; native RTM/Jacobian work still
dominates.

## Rejected Start-Worker Count Probe

I tested whether the current default of two native start-level workers is the
source of the remaining gap. This is an exact scheduling-only boundary: it does
not change controls, physics, solver algebra, output order, or public API.

The same-boundary ReleaseFast validation used `ZDISAMAR_WORKER_LIMIT=10`, 25
starts, and scenes 005 and 008. The retained default, two start workers, timed
scene 005/008 at 7.582/7.855 s. One start worker timed 8.356/8.515 s; three
start workers timed 7.726/7.953 s; four start workers timed 7.727/8.017 s.
The output rows matched apart from timing/NaN bookkeeping fields.

Conclusion: the current two-worker start policy remains the best of the tested
exact scheduling choices on this machine. The missing 170-180 ms repeated-start
target is not recovered by using one worker or by increasing start-level
parallelism above two.

## Rejected Static Shared-Pool Prefetch Probe

I also tested a second exact scheduling candidate in the shared forward-prefetch
pool used by parallel native diagnosis batches. The candidate kept the existing
static miss ranges when a thread pool is present instead of assigning misses
through the retained mutex chunk queue. Each worker still wrote the same
`results[index]` slots, so output order and numeric work were unchanged.

The 25-start scene 005/008 comparison was neutral: retained pooled queue
timing was 7.582/7.855 s, while static pooled ranges timed 7.676/7.832 s. A
100-start scene-008 target run with static pooled ranges timed 31.321 s, which
is inside the existing retained baseline band of roughly 30.3-31.6 s for this
machine.

Conclusion: shared-pool scheduling is not a reliable retained improvement.
Keep the chunk-queue pooled path for now; the remaining exact-safe opportunity
still has to remove or simplify RTM/Jacobian/LABOS work rather than only change
thread assignment.

## Rejected Cross-Stage Prefetch-Pool Lifetime Probe

I tested another exact scheduling/lifetime candidate in the staged native
fastmode batch path: create the shared forward-prefetch thread pool once around
`runO2AFastmodeBatch` and borrow it for both the sparse fast stage and the
sparse full-physics correction stage. This removed thread-pool
construction/destruction between the two sequential stages only. It did not
cache numeric forward samples, Jacobians, branch decisions, or optical state,
and it did not change controls, physics, output order, convergence tests, or
the public API.

The same-boundary ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. Immediate baseline
timing was scene 005/008 at 7.372/7.649 s. The cross-stage pool-lifetime
candidate timed 7.393/7.699 s. Comparing `runs.csv` with `retrieval_s` and
`batch_wall_s` excluded showed no non-timing differences, and maximum
retrieved-state absolute/relative delta was 0.

Conclusion: this is exact, but it is neutral to slightly slower on both scenes.
Do not add more lifetime plumbing for thread-pool setup alone. The next
candidate still needs to remove or simplify real RTM/Jacobian/LABOS work.

## Rejected State-Space Template Probe

I tested a final exact OE-bookkeeping candidate before stopping the source
experiments: build the invariant state-space template once per native batch
worker, including variance, bounds, derivative-state mask, and prior Cholesky
factors, then let each start provide only its initial and prior state vectors.
This avoided per-start `StateSpec` copying and repeated prior-covariance
factorization in the batch-summary path. It did not change the state values,
priors, controls, convergence tests, forward model, output order, public API, or
single-retrieval path.

The same-boundary ReleaseFast comparison used `ZDISAMAR_WORKER_LIMIT=10`, two
native start workers, 25 starts, and scenes 005 and 008. Immediate baseline
timing was scene 005/008 at 7.384/7.614 s. The state-space template candidate
timed 7.386/7.633 s. Comparing `runs.csv` with `retrieval_s` and
`batch_wall_s` excluded showed no non-timing differences, and maximum
retrieved-state absolute/relative delta was 0.

Conclusion: the candidate is exact, but it is neutral to slightly slower.
Per-start state-spec copying and prior Cholesky setup are not material on this
diagnosis boundary. Do not retain a special batch state-space template unless a
future profile shows solver setup, rather than RTM/LABOS, has become dominant.

## Refreshed Sampling Check

I reran an 8 s macOS `sample` capture against the retained ReleaseFast path
after the last exact-source probes. The sampled workload was scene 008 with 100
starts, `ZDISAMAR_WORKER_LIMIT=10`, two native start workers, unchanged
controls, and no `final_evaluation` access in the timed loop. The low-overhead
`uv run` boundary timed 31.147 s total. The separately sampled direct venv
Python run completed the native retrieval section at 32.214 s before failing in
PNG plot export because that direct environment did not have
`vl-convert-python`; the sample is therefore used only as native attribution,
not as validation evidence.

The active main thread showed 5,053 samples under
`zds_run_o2a_fastmode_optimal_estimation_batch`. Under that call,
`simulateProductWithWorkspace` accounted for 4,214 samples (83% of the native
C-call samples), `computeForwardSampleAtWavelengthWithScratch` for 4,101
samples (81%), `layerResolvedLabosWithWorkspace` for 2,501 samples (49%), and
`calcRTlayersIntoWithBasis` for 2,211 samples (44%). The active prefetch-worker
thread showed the same shape: 4,778 samples in
`computeForwardSampleAtWavelengthWithScratch`, 2,873 in
`layerResolvedLabosWithWorkspace`, and 2,560 in
`calcRTlayersIntoWithBasis` (about 51% of that thread's sampled stack).
`doDouble12x10` remained the dominant child under the RT-layer builder.

Conclusion: the last profile agrees with the earlier timing-zone split. Small
Python, C-ABI request, worker-lifetime, state-space, and solver-bookkeeping
changes are exhausted for this branch. A real additional speedup needs to
remove or simplify exact RTM/LABOS work, most plausibly through a carefully
validated native structural mask; otherwise the current branch should stop with
telemetry, documentation, and the small exact workspace cleanup only.
