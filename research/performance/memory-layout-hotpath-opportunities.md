# Memory Layout Hot-Path Opportunities

Scratch analysis for the current Zig performance branch. This file groups the
existing `// hot path:` markers and `layout(64-bit)` struct comments into a
memory-access investigation map.

Scope:
- source tree: `src/**/*.zig`
- hot-path markers inspected: 223
- struct layout comments inspected: 310
- target CPU model for layout comments: 64-bit, 64 B cache line assumption
- experiment log entries record retained benchmark evidence; every implemented
  optimization still needs `uv run benchmark/run_benchmark.py` before it is
  treated as accepted

## Experiment Log

### Experiment 1: compact wavelength and integration plan storage

Changed:
- `WavelengthSampling` no longer embeds two full `IntegrationKernel` payloads
- each plan row now stores two compact `IntegrationKernelRef` descriptors
- the common 5-sample kernel is stored inline in the descriptor
- larger kernels use side storage for offsets and weights
- integration loops resolve the descriptor once to dense slices before iterating

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `WavelengthSampling` row | 65,592 B | 200 B | -99.70% |
| 701-row plan, row payload only | 45,979,992 B | 140,200 B | -99.70% |
| reusable `SummaryStorage` header | 584 B | 616 B | +32 B |
| transient `ResolvedSimulationPlan` header | 80 B | 144 B | +64 B |

Interpretation:
- the hot per-wavelength row payload dropped by about 328x
- small owner/view headers grew because rows, side offsets, and side weights are
  now separate slices
- the header growth is bounded and not proportional to spectral sample count
- side storage grows only for kernels larger than the inline 5-sample payload

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run validation/spectra/validate_spectra.py`: max_abs `9.569e-14`
- `uv run validation/spectra/validate_fast_mode_spectra.py`: worst scene
  `oblique aerosol`, max_abs `4.963e-04`, max_abs_over_noise `1.600e+00`
- `uv run validation/optimal_estimation/validate_optimal_estimation.py` after
  `ReleaseFast` benchmark sync: retrieval loop `0.643012 s`, RTM+jacobian
  `0.641490 s`, 4 iterations
- `uv run validation/optimal_estimation/validate_fast_mode_optimal_estimation.py`:
  mean retrieval speedup `+0.961 s`, max_abs_aod_delta `7.394e-03`,
  max_abs_pressure_delta `5.542e+00 hPa`
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.066544 s | 1.073332 s | 1.0064 |
| forward session cached median | 0.344714 s | 0.347028 s | 1.0067 |
| forward fast four-scene median | 5.096391 s | 5.099479 s | 1.0006 |
| OE session retrieval median | 1.446016 s | 1.442676 s | 0.9977 |
| OE fast retrieval median | 1.133139 s | 1.129291 s | 0.9966 |
| OE sweep session total wall | 21.836406 s | 21.802155 s | 0.9984 |
| OE sweep fast total wall | 12.105673 s | 12.053975 s | 0.9957 |

Conclusion:
- the memory win is large enough that the sub-1% forward timing movement should
  be treated as benchmark noise unless repeated runs show the same slowdown
- residual and OE gates stayed within the existing validation contract
- this experiment is acceptable as a first memory-layout reduction

### Experiment 2: fill prepared strong-line state directly

Changed:
- `prepareStrongLineStateInto` no longer builds a max-capacity
  `StrongLineConvTPState` and then copies active values into
  `StrongLinePreparedState`
- the prepared path now fills the already allocated exact-size prepared slices
  directly
- `strongLineContribution` now receives the max-capacity direct-evaluation
  state by pointer instead of by value

Memory traffic result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| prepared strong-line temp state | 136,208 B | 0 B | -100.00% |
| active prepared-state copy for 70 lines | 42,000 B | 0 B | -100.00% |
| per prepared profile node transient traffic | >=178,208 B | 0 B | -100.00% |
| 47-node O2 A spectroscopy profile | >=8,375,776 B | 0 B | -100.00% |
| retained prepared-state heap payload | unchanged | unchanged | 0 |

Interpretation:
- the retained heap layout was already compact because `StrongLinePreparedState`
  owns exact-size slices for `line_count`
- the waste was in transient preparation: a 133.0 KiB max-capacity stack object
  was filled first, then the active payload was copied into the retained slices
- the current O2 A strong-line asset has 70 strong lines and a 70 x 70
  relaxation matrix, so each prepared node copied 42,000 B after the temporary
  state had already been written
- the default spectroscopy profile has 47 data rows, so one optical prepare
  avoids at least 7.99 MiB of stack/copy traffic before considering possible
  return-value copies

Validation and benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  fast-mode spectra worst `4.963e-04` (`1.600x` noise); OE session AOD diff
  `8.699e-08`; fast-vs-session sweep max AOD delta `3.766e-03`, pressure delta
  `5.085e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.073332 s | 1.079016 s | 1.0053 |
| forward session cached median | 0.347028 s | 0.344589 s | 0.9930 |
| forward fast four-scene median | 5.099479 s | 5.098077 s | 0.9997 |
| OE session retrieval median | 1.442676 s | 1.444513 s | 1.0013 |
| OE fast retrieval median | 1.129291 s | 1.128454 s | 0.9993 |
| OE sweep session total wall | 21.802155 s | 21.761115 s | 0.9981 |
| OE sweep fast total wall | 12.053975 s | 12.036307 s | 0.9985 |

Conclusion:
- the retained footprint is unchanged, but preparation memory traffic drops by
  about 8.0 MiB per default O2 A optical prepare
- benchmark movement is flat-to-slightly-faster on the OE sweep and not a
  measured regression on the intended benchmark boundary
- this is an acceptable memory-traffic reduction and a better target than
  removing phase-coefficient memoization without a proven latency win

### Experiment 3: remove retained strong-line relaxation weights

Changed:
- `StrongLinePreparedState` no longer stores `relaxation_weights`
- strong-line preparation uses per-worker relaxation-matrix scratch, then
  retains only the arrays read by `strongLineContributionPrepared`
- profile-state cache cloning and prepared-state hashing now skip the removed
  intermediate matrix

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `StrongLinePreparedState` header | 112 B | 96 B | -16 B |
| retained relaxation weights per 70-line state | 39,200 B | 0 B | -100.00% |
| 47-node O2 A spectroscopy profile | 1,843,152 B | 0 B | -100.00% |
| cached clone of 47-node profile states | 1,843,152 B | 0 B | -100.00% |
| preparation scratch at 2 workers | 0 B | 78,400 B | transient |

Interpretation:
- the relaxation matrix is needed while deriving line-mixing coefficients
- after preparation, the hot evaluation path reads `population_t`, `dipole_t`,
  `mod_sig_cm1`, `half_width_cm1_at_t`, `line_mixing_coefficients`, and
  `sig_moy_cm1`
- storing the matrix in every prepared profile node memoized an intermediate
  value that was no longer consumed by the steady-state forward loop
- with the current O2 A assets, this removes about 1.76 MiB from the retained
  prepared profile and another 1.76 MiB from the cached clone, while adding
  only 76.6 KiB of temporary scratch under the benchmark's 2-worker cap

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  fast-mode spectra worst `4.963e-04` (`1.600x` noise); OE session AOD diff
  `8.699e-08`; fast-vs-session sweep max AOD delta `3.766e-03`, pressure delta
  `5.085e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.079016 s | 1.073135 s | 0.9945 |
| forward session cached median | 0.344589 s | 0.347627 s | 1.0088 |
| forward fast four-scene median | 5.098077 s | 5.078984 s | 0.9963 |
| OE session retrieval median | 1.444513 s | 1.441095 s | 0.9976 |
| OE fast retrieval median | 1.128454 s | 1.126522 s | 0.9983 |
| OE sweep session total wall | 21.761115 s | 21.796648 s | 1.0016 |
| OE sweep fast total wall | 12.036307 s | 12.004280 s | 0.9973 |

Conclusion:
- the retained strong-line prepared-state footprint drops materially without
  changing benchmark residuals
- the timing movement is within the benchmark noise band and not a regression
  on the intended OE boundary
- this follows the lazy/intermediate-data rule: keep derived coefficients that
  the hot loop reads, but do not retain the preparation-only relaxation matrix

### Experiment 4: move weak-line thermodynamic scalars out of each line

Changed:
- `WeakLinePreparedLineState` no longer stores `safe_temperature` and
  `safe_pressure` per line
- those two scalars now live once on `WeakLinePreparedState`
- prepared weak-line evaluation computes the thermodynamic scale once per
  profile node and reuses it across relevant weak-line contributions

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `WeakLinePreparedLineState` | 48 B | 32 B | -33.33% |
| `WeakLinePreparedState` header | 24 B | 40 B | +16 B |
| one 1,314-line prepared weak state | 63,096 B | 42,088 B | -33.29% |
| 47-node O2 A spectroscopy profile | 2,965,512 B | 1,978,136 B | -987,376 B |
| cached clone of 47-node profile states | 2,965,512 B | 1,978,136 B | -987,376 B |

Interpretation:
- temperature and pressure are properties of the thermodynamic profile node,
  not properties of each weak line
- moving them out of each line removes 16 B from every prepared weak-line row
  and adds only 16 B once per prepared profile node
- with the current O2 A line list and profile, the retained prepared profile
  drops by about 0.94 MiB and the process cache clone drops by another 0.94 MiB
- the hot weak-line loop also reads fewer bytes per relevant line

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  fast-mode spectra worst `4.963e-04` (`1.600x` noise); OE session AOD diff
  `8.699e-08`; fast-vs-session sweep max AOD delta `3.766e-03`, pressure delta
  `5.085e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.073135 s | 1.054551 s | 0.9827 |
| forward session setup | 0.731015 s | 0.710656 s | 0.9721 |
| forward session cached median | 0.347627 s | 0.345292 s | 0.9933 |
| forward fast four-scene median | 5.078984 s | 5.018039 s | 0.9880 |
| OE session setup median | 0.736181 s | 0.717431 s | 0.9745 |
| OE session retrieval median | 1.441095 s | 1.436078 s | 0.9965 |
| OE fast retrieval median | 1.126522 s | 1.124246 s | 0.9980 |
| OE sweep session total wall | 21.796648 s | 21.647506 s | 0.9932 |
| OE sweep fast total wall | 12.004280 s | 11.955781 s | 0.9960 |

Conclusion:
- this is both a retained-footprint reduction and a measured speedup on the
  benchmark boundary
- the change is data-layout-only: per-line thermodynamic duplicates moved to
  the state that actually owns that thermodynamic context
- this is a strong follow-up target because it improves memory footprint,
  preparation setup time, forward time, and OE sweep time together

### Experiment 5: tighten spectroscopy profile cache capacity

Changed:
- profile spectroscopy caches now reserve 64 profile nodes instead of 256
- this affects the total-only prepared-state cache and the full layer
  spectroscopy cache
- cache construction still returns an empty cache when the runtime node count is
  outside the fixed capacity, so larger profiles use the existing direct
  evaluation path instead of silently truncating data

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `ProfileNodeSpectroscopyCache` | 4,104 B | 1,032 B | -74.85% |
| `ProfileSpectroscopyCache` | 20,504 B | 5,144 B | -74.91% |
| retained table across 701 cached forward misses | 2,876,904 B | 723,432 B | -2,153,472 B |
| prepare-time layer spectroscopy cache | 20,504 B | 5,144 B | -15,360 B |

Interpretation:
- the current retained O2 A profile has 47 data rows, so 64 nodes leaves room
  for the measured profile while removing fixed unused cache capacity
- the total-only cache is retained per cached forward miss, so the 3,072 B
  per-instance reduction compounds across the 701-sample benchmark grid
- the full layer cache is a stack-local prepare cache, so the same capacity
  tightening reduces preparation memory traffic and cache span
- there is no unused padding or bool slack in either struct; the removed memory
  is fixed-capacity array storage that the benchmark profile does not fill

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture reflectance max_abs `5.393e-14`;
  session-vs-no-session residuals all `0.0`; fast-mode spectra worst
  `4.963e-04` (`1.600x` noise); OE session AOD diff `8.699e-08`;
  fast-vs-session sweep max AOD delta `3.778e-03`, pressure delta
  `5.099e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.054551 s | 1.056516 s | 1.0019 |
| forward session setup | 0.710656 s | 0.709138 s | 0.9979 |
| forward session cached median | 0.345292 s | 0.348221 s | 1.0085 |
| forward fast four-scene median | 5.018039 s | 5.020846 s | 1.0006 |
| OE session setup median | 0.717431 s | 0.715823 s | 0.9978 |
| OE session retrieval median | 1.436078 s | 1.449589 s | 1.0094 |
| OE fast retrieval median | 1.124246 s | 1.133547 s | 1.0083 |
| OE sweep session total wall | 21.647506 s | 21.652913 s | 1.0002 |
| OE sweep fast total wall | 11.955781 s | 11.963831 s | 1.0007 |

Conclusion:
- the memory win is concentrated in one cache family: about 2.05 MiB less
  retained profile-cache payload across the benchmark grid, plus a smaller
  prepare-time stack reduction
- end-to-end benchmark movement is flat on the sweep boundary; single-case
  retrieval medians moved by less than 1%
- this is acceptable as capacity tightening, but the next larger target remains
  splitting total-only spectroscopy data from breakdown arrays instead of only
  shrinking the fixed capacity

### Experiment 6: share prepared strong-line window across profile-cache workers

Changed:
- `ProfileCacheValueWorker` now stores a pointer to the prepared strong-line
  wavelength window instead of embedding the full window payload
- `ProfileSpectroscopyCache.init` builds the wavelength window once and shares
  it read-only across the worker records used for cache initialization
- the spectroscopy calculation still receives the same window data; only the
  worker-control layout changes

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `ProfileCacheValueWorker` | 2,360 B | 288 B | -87.80% |
| `[64]ProfileCacheValueWorker` stack buffer | 151,040 B | 18,432 B | -132,608 B |
| active worker records under 2-worker cap | 4,720 B | 576 B | -4,144 B |

Interpretation:
- the wavelength window is request-local and immutable during profile-cache
  initialization, so worker records only need to reference it
- the old layout replicated a 2,072 B window in each worker record even though
  all workers read the same relevant-line window and anchor table
- the fixed worker buffer reserves one slot for each `work_partition.max_workers`
  entry, so the struct-size reduction matters even when the benchmark runs with
  only two active native workers
- this removes stack footprint and per-worker copy traffic without changing the
  retained `ProfileSpectroscopyCache` arrays

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture reflectance max_abs `5.393e-14`;
  session-vs-no-session residuals all `0.0`; fast-mode spectra worst
  `4.963e-04` (`1.600x` noise); OE session AOD diff `8.699e-08`;
  fast-vs-session sweep max AOD delta `3.778e-03`, pressure delta
  `5.099e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.056516 s | 1.056962 s | 1.0004 |
| forward session setup | 0.709138 s | 0.711963 s | 1.0040 |
| forward session cached median | 0.348221 s | 0.345946 s | 0.9935 |
| forward fast four-scene median | 5.020846 s | 5.012337 s | 0.9983 |
| OE session setup median | 0.715823 s | 0.714524 s | 0.9982 |
| OE session retrieval median | 1.449589 s | 1.436470 s | 0.9909 |
| OE fast retrieval median | 1.133547 s | 1.121925 s | 0.9897 |
| OE sweep session total wall | 21.652913 s | 21.636607 s | 0.9992 |
| OE sweep fast total wall | 11.963831 s | 11.905910 s | 0.9952 |

Conclusion:
- this is a small retained-memory change but a clear stack-layout improvement
  in the profile-cache initialization hot path
- benchmark timing is flat-to-slightly-faster on the retained evidence boundary
- it is worth keeping because it removes replicated worker-control payload
  without adding recomputation, extra branches, or lifetime ambiguity

### Experiment 7: encode strong-line anchors with sentinel indexes

Changed:
- `StrongLineWavelengthWindow.anchors` now stores `usize` indexes with a
  sentinel for missing anchors instead of `?usize`
- the index range is unchanged; this only removes the optional tag storage from
  each anchor slot
- weak-line exclusion, diagnostic line-contribution output, and support helpers
  now test the sentinel explicitly

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `StrongLineWavelengthWindow` | 2,072 B | 1,048 B | -49.42% |
| anchor array inside each window | 2,048 B | 1,024 B | -50.00% |

Interpretation:
- there are at most 128 strong-line sidecars, and every anchor slot either
  names the relevant weak-line index or stores the missing sentinel
- using a sentinel keeps the full `usize` index range while avoiding the 16 B
  per-slot cost of `?usize` on 64-bit targets
- this reduces stack payload in direct prepared strong-line evaluation,
  profile-cache initialization, band-mean calculation, and line-contribution
  diagnostics
- the profile-cache worker records already reference one shared window after
  Experiment 6, so this experiment reduces the shared window payload itself

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture reflectance max_abs `5.393e-14`;
  session-vs-no-session residuals all `0.0`; fast-mode spectra worst
  `4.963e-04` (`1.600x` noise); OE session AOD diff `8.699e-08`;
  fast-vs-session sweep max AOD delta `3.778e-03`, pressure delta
  `5.099e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.056962 s | 1.058444 s | 1.0014 |
| forward session setup | 0.711963 s | 0.711574 s | 0.9995 |
| forward session cached median | 0.345946 s | 0.346334 s | 1.0011 |
| forward fast four-scene median | 5.012337 s | 5.002590 s | 0.9981 |
| OE session setup median | 0.714524 s | 0.716066 s | 1.0022 |
| OE session retrieval median | 1.436470 s | 1.434888 s | 0.9989 |
| OE fast retrieval median | 1.121925 s | 1.122163 s | 1.0002 |
| OE sweep session total wall | 21.636607 s | 21.625501 s | 0.9995 |
| OE sweep fast total wall | 11.905910 s | 11.912201 s | 1.0005 |

Conclusion:
- this is a narrow encoding improvement: same logical anchor data, half the
  anchor payload
- benchmark timing is flat on the retained boundary, and residuals are
  unchanged
- this is worth keeping because it removes optional-tag storage from a repeated
  strong-line setup object without adding range limits or extra lookup work

### Experiment 8: make shared RTM subgrid a scratch-backed view

Changed:
- `SharedRtmSubgrid` no longer embeds fixed `[128]f64` altitude and weight
  arrays
- `resolveSharedRtmSubgrid` writes transformed altitude and weight values into
  the existing `GaussRuleScratch` buffers and returns slices over that scratch
- shared-layer evaluation and pseudo-spherical sample filling iterate over the
  returned slice length instead of a separate `count` field

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `SharedRtmSubgrid` | 2,056 B | 32 B | -98.44% |
| inline arrays per returned subgrid | 2,048 B | 0 B | -100.00% |

Interpretation:
- the subgrid is request-local and consumed immediately while the caller-owned
  `GaussRuleScratch` remains alive
- the previous value copied altitude and weight samples into a second fixed
  array object even though the scratch already had two `[128]f64` buffers
- the O2 A benchmark uses four sublayer divisions, so this removes a repeated
  max-capacity return object without changing the Gauss-rule capacity or the
  numerical quadrature rule
- the retained scratch capacity is unchanged; this experiment removes duplicate
  stack/value payload in the shared RTM layer route

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture reflectance max_abs `5.393e-14`;
  session-vs-no-session residuals all `0.0`; fast-mode spectra worst
  `4.963e-04` (`1.600x` noise); OE session AOD diff `8.699e-08`;
  fast-vs-session sweep max AOD delta `3.778e-03`, pressure delta
  `5.099e+00 hPa`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.058444 s | 1.056010 s | 0.9977 |
| forward session setup | 0.711574 s | 0.709332 s | 0.9968 |
| forward session cached median | 0.346334 s | 0.345011 s | 0.9962 |
| forward fast four-scene median | 5.002590 s | 5.003318 s | 1.0001 |
| OE session setup median | 0.716066 s | 0.715836 s | 0.9997 |
| OE session retrieval median | 1.434888 s | 1.435147 s | 1.0002 |
| OE fast retrieval median | 1.122163 s | 1.121711 s | 0.9996 |
| OE sweep session total wall | 21.625501 s | 21.636362 s | 1.0005 |
| OE sweep fast total wall | 11.912201 s | 11.925660 s | 1.0011 |

Conclusion:
- this is a local stack/value-layout improvement, not a retained heap reduction
- benchmark timing is effectively flat; the slight sweep movement is smaller
  than the normal single-run noise while forward/session timings improved
- this is worth keeping because it removes duplicate fixed-capacity arrays and
  keeps the same quadrature samples in one scratch owner

### Experiment 9: drop unused gas phase interface payload

Changed:
- `SharedBoundaryCarrier` no longer stores the unused
  `gas_phase_coefficients: [151]f64` payload
- `SourceInterfaceInput` no longer stores the same unused gas phase coefficient
  row
- source-interface construction stopped copying a 1,208 B payload that the
  downstream interface routines did not read

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| gas phase coefficient row | 1,208 B | 0 B | -100.00% |
| `SharedBoundaryCarrier` | 6,096 B | 4,888 B | -19.82% |
| `SourceInterfaceInput` | 3,680 B | 2,472 B | -32.83% |

Interpretation:
- the removed field was a full phase-coefficient-width row in two interface
  carrier structs
- the hot source-interface path already receives the scattering and source
  quantities it actually consumes through other fields
- this is not lazy recomputation; it is deletion of copied data with no reader
- the remaining carriers keep the source-interface inputs in their existing
  order and keep residuals unchanged

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; OE session AOD diff
  `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.056010 s | 1.058139 s | 1.0020 |
| forward session cached median | 0.345011 s | 0.345345 s | 1.0010 |
| forward fast four-scene median | 5.003318 s | 5.004702 s | 1.0003 |
| OE session retrieval median | 1.435147 s | 1.430738 s | 0.9969 |
| OE fast retrieval median | 1.121711 s | 1.118815 s | 0.9974 |
| OE sweep session total wall | 21.636362 s | 21.573211 s | 0.9971 |
| OE sweep fast total wall | 11.925660 s | 11.889423 s | 0.9970 |

Conclusion:
- this removes 1,208 B from each affected source-interface carrier without
  adding computation or changing interface semantics
- benchmark timing is flat-to-slightly-faster on the OE boundaries
- the experiment is worth keeping because it deletes copied payload that had no
  hot-path consumer

### Experiment 10: encode aerosol quadrature Jacobian row

Changed:
- `RtmQuadratureLevel` no longer stores a dense
  `[jacobian.state_count][151]f64` phase-coefficient Jacobian payload
- the retained quadrature level now stores only the aerosol phase-coefficient
  derivative row that the RTM layer route consumes
- the default derivative row is zero-filled so inactive derivatives do not
  introduce a unit phase coefficient

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| dense phase Jacobian rows | 3,624 B | 1,208 B | -66.67% |
| `RtmQuadratureLevel` | 7,272 B | 4,856 B | -33.22% |
| savings per RTM quadrature level | 0 B | 2,416 B | -2,416 B |

Interpretation:
- the old layout carried one full phase-coefficient derivative row per state
  column, even though the layer route only used the aerosol scattering phase
  derivative
- this is an encoding change from dense state matrix to the active derivative
  row used by the hot RTM path
- the row still has the full `151` phase-coefficient width, so phase-order
  accuracy is unchanged
- this reduces per-level retained prepared-state payload and the memory read by
  the source-interface layer path

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; OE session AOD diff
  `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.058139 s | 1.049360 s | 0.9917 |
| forward session cached median | 0.345345 s | 0.337821 s | 0.9782 |
| forward fast four-scene median | 5.004702 s | 4.943020 s | 0.9877 |
| OE session retrieval median | 1.430738 s | 1.399653 s | 0.9783 |
| OE fast retrieval median | 1.118815 s | 1.094454 s | 0.9782 |
| OE sweep session total wall | 21.573211 s | 21.406189 s | 0.9923 |
| OE sweep fast total wall | 11.889423 s | 11.735139 s | 0.9870 |

Conclusion:
- this is a clear retained-footprint reduction and also a measured speedup on
  the benchmark boundary
- the win comes from not carrying inactive state rows through each quadrature
  level
- the residual rows stayed unchanged after correcting the zero-derivative
  default

### Experiment 11: remove dense static attenuation table

Changed:
- the old dense `AttenArray` storage for all Fourier orders and all possible
  level pairs was removed from the LABOS layer path
- one-layer LABOS attenuation now uses `RuntimeAttenArray` and stack buffers for
  the active transmittance/top-to-level values
- LABOS exports now expose `max_attenuation_levels` instead of the removed dense
  array type and fill helper

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| dense static attenuation table | 405,616 B | 0 B | -100.00% |
| table payload shape | `[12][65][65]f64` | active slices | removed |
| one-layer active buffers | dense table | `[nmutot]f64 + [nmutot * 2]f64` | active-only |

Interpretation:
- the removed table allocated every Fourier-order and level-pair combination up
  to the maximum capacity even when the one-layer path only needs active
  attenuation values
- the runtime path now stores the active one-layer values directly in bounded
  stack buffers and passes a view over those buffers
- this is an active-data encoding rather than a physics change: attenuation
  values are still computed from the same layer inputs
- the large struct disappeared from the size ranking after this commit

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; OE session AOD diff
  `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.049360 s | 1.050646 s | 1.0012 |
| forward session cached median | 0.337821 s | 0.339688 s | 1.0055 |
| forward fast four-scene median | 4.943020 s | 4.938934 s | 0.9992 |
| OE session retrieval median | 1.399653 s | 1.405865 s | 1.0044 |
| OE fast retrieval median | 1.094454 s | 1.096403 s | 1.0018 |
| OE sweep session total wall | 21.406189 s | 21.545654 s | 1.0065 |
| OE sweep fast total wall | 11.735139 s | 11.751053 s | 1.0014 |

Conclusion:
- this is a large fixed-footprint removal with unchanged benchmark residuals
- timing moved slightly slower on the session sweep and slightly faster on the
  four-scene forward median, all within about 0.7%
- the memory reduction is worth keeping because it deletes a max-capacity table
  from the one-layer path and replaces it with active data

### Experiment 12: encode adaptive interval plan storage

Changed:
- `AdaptiveIntervalPlan` no longer stores a `[2048]AdaptiveIntervalDescriptor`
  array with start, end, and `usize` division count per interval
- interval starts are encoded by the plan global start and the previous interval
  end
- division counts are stored as `u16` values, matching the bounded adaptive-grid
  controls
- adaptive sample construction now uses the caller sample arrays as candidate
  storage instead of allocating a second pair of 2048-element candidate arrays

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `AdaptiveIntervalPlan` | 49,160 B | 20,504 B | -58.29% |
| `AdaptiveKernelCache` | 49,184 B | 20,512 B | -58.29% |
| duplicate candidate arrays per adaptive sample build | 32,768 B | 0 B | -100.00% |
| two adaptive caches in wavelength sampling | 98,368 B | 41,024 B | -57,344 B |

Interpretation:
- interval starts are sequential and already implied by the previous end point
- the old descriptor paid 8 B for `division_count` per interval even though the
  configured counts are small bounded integers
- moving to end-points plus compact division counts keeps the interval order and
  avoids pointer chasing
- reusing the caller sample arrays removes duplicate temporary candidate storage
  before final support selection

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; OE session AOD diff
  `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.050646 s | 1.051584 s | 1.0009 |
| forward session cached median | 0.339688 s | 0.339848 s | 1.0005 |
| forward fast four-scene median | 4.938934 s | 4.956055 s | 1.0035 |
| OE session retrieval median | 1.405865 s | 1.407150 s | 1.0009 |
| OE fast retrieval median | 1.096403 s | 1.098145 s | 1.0016 |
| OE sweep session total wall | 21.545654 s | 21.562965 s | 1.0008 |
| OE sweep fast total wall | 11.751053 s | 11.783081 s | 1.0027 |

Conclusion:
- this is a substantial stack/cache layout reduction for the adaptive
  instrument-grid hot path
- benchmark residuals stayed unchanged; timing moved slower by less than 0.35%
  on the retained benchmark metrics
- this is acceptable as a memory-layout win because it removes fixed-capacity
  descriptor payload and duplicate candidate buffers without changing the
  integration samples

### Experiment 13: share prepared particle phase payloads

Changed:
- `PreparedSublayer` no longer stores aerosol, cloud, and combined phase
  coefficient arrays per support row
- prepared aerosol/cloud phase coefficients are stored once on the request-level
  `PreparationContext` and retained `PreparedOpticalState`
- carrier evaluation and RTM quadrature paths now combine phase coefficients
  from the prepared state instead of copying them through sublayer, boundary,
  and interpolation helper payloads
- the unused prepared combined phase array was removed rather than recomputed or
  moved elsewhere

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `PreparedSublayer` | 3,896 B | 272 B | -93.02% |
| per support-row phase payload | 3,624 B | 0 B | -100.00% |
| `PreparedOpticalState` | 1,056 B | 3,472 B | +2,416 B once |
| `PreparationContext` | 976 B | 3,392 B | +2,416 B temporary once |
| `ParticleBoundaryCarrier` | 2,448 B | 32 B | -98.69% |
| `InterpolatedQuadratureState` | 2,496 B | 80 B | -96.79% |
| `ParitySupportRowWorker` | 2,720 B | 304 B | -88.82% |
| `LevelCarrier` | 2,432 B | 1,224 B | -49.67% |

Interpretation:
- particle phase coefficients are wavelength/request-level data in the prepared
  path; the old layout copied the same two `[151]f64` arrays into every support
  row
- combined phase coefficients are derived from gas/aerosol/cloud scattering and
  were already recomputed by the wavelength carrier paths that consume them
- this moves a repeated max-capacity payload out of the hot support-row array and
  replaces it with one retained copy per prepared state
- temporary carrier structs now carry scalar particle depth fields and read the
  shared phase arrays only when constructing the final combined rows

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; OE session AOD diff
  `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.051584 s | 1.004895 s | 0.9556 |
| forward session cached median | 0.339848 s | 0.305400 s | 0.8986 |
| forward fast four-scene median | 4.956055 s | 4.851848 s | 0.9790 |
| OE session retrieval median | 1.407150 s | 1.279187 s | 0.9091 |
| OE fast retrieval median | 1.098145 s | 0.996457 s | 0.9074 |
| OE sweep session total wall | 21.562965 s | 21.150677 s | 0.9809 |
| OE sweep fast total wall | 11.783081 s | 11.470317 s | 0.9735 |

Conclusion:
- this is a multi-megabyte retained-layout win for any prepared state with many
  support rows: the repeated support-row payload drops by 3,624 B per row, paid
  back by one 2,416 B retained prepared-state copy
- benchmark residuals stayed unchanged and all retained median/tally timings
  improved in the five-case `run_benchmark.py` gate
- this experiment is worth keeping because it removes repeated memoized phase
  data while also reducing temporary carrier copy traffic

### Experiment 14: remove remaining copied aerosol phase carrier payloads

Changed:
- `SharedOpticalCarrier` no longer stores `aerosol_phase_coefficients`
- `PreparedQuadratureCarrier` no longer stores `aerosol_phase_coefficients`
- `SharedBoundaryCarrier` no longer stores aerosol phase arrays above and below
- RTM quadrature and aerosol source Jacobian paths continue to read the
  request-level aerosol phase coefficients from `PreparedOpticalState`

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `SharedOpticalCarrier` | 2,472 B | 1,264 B | -48.87% |
| `PreparedQuadratureCarrier` | 2,432 B | 1,224 B | -49.67% |
| `SharedBoundaryCarrier` | 4,888 B | 2,472 B | -49.43% |
| one 48-row support-carrier cache | 118,656 B | 60,672 B | -57,984 B |
| 701 forward misses x 48 support rows | 83,196,288 B | 42,549,504 B | -40,646,784 B |

Interpretation:
- these aerosol phase rows became write-only after the prepared phase arrays
  moved to `PreparedOpticalState`
- combined phase rows are still computed where the RTM and layer-reduction paths
  consume them, so this does not add lazy recomputation
- the support-carrier cache keeps the combined phase row because layer
  accumulation reads it directly
- the current benchmark grid has 701 forward misses and the retained O2 A support
  grid has 48 rows, so the support-cache field deletion removes about 38.76 MiB
  of possible copied row payload across one full miss fill
- boundary carriers also avoid copying two 151-f64 arrays per boundary return

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.004895 s | 1.014387 s | 1.0094 |
| forward session setup | 0.711873 s | 0.711899 s | 1.0000 |
| forward session cached median | 0.305400 s | 0.304713 s | 0.9978 |
| forward fast four-scene median | 4.851848 s | 4.859552 s | 1.0016 |
| OE session setup median | 0.717825 s | 0.719659 s | 1.0026 |
| OE session retrieval median | 1.279187 s | 1.267872 s | 0.9912 |
| OE fast retrieval median | 0.996457 s | 0.989494 s | 0.9930 |
| OE sweep session total wall | 21.150677 s | 21.100117 s | 0.9976 |
| OE sweep fast total wall | 11.470317 s | 11.477791 s | 1.0007 |

Conclusion:
- this keeps the large Experiment 13 phase-layout gain and removes the remaining
  carrier-local aerosol phase copies that had no readers
- the intended OE timing boundary is flat-to-faster, while the small forward
  movements are within single-run noise for this benchmark setup
- this is a safer alternative to removing combined phase memoization because it
  deletes copied write-only arrays without moving new arithmetic into the hot
  loop

### Experiment 15: stop clearing inactive integration-kernel capacity

Changed:
- `resetKernel` now resets only `enabled` and `sample_count`
- one-sample fallback kernels explicitly write `offsets_nm[0] = 0` and
  `weights[0] = 1`
- wavelength-plan construction reuses one `IntegrationKernel` scratch value per
  worker range and compacts radiance before reusing the scratch for irradiance

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| array bytes cleared by one `resetKernel` | 32,768 B | 0 B | -32,768 B |
| adaptive path clears per realized kernel | 65,536 B | 0 B | -65,536 B |
| 701 wavelengths x 2 channels, adaptive path | 91,881,472 B | 0 B | -87.62 MiB zero-fill traffic |
| wavelength-plan live integration scratch | 65,568 B | 32,784 B | -32,784 B |

Interpretation:
- `IntegrationKernel` stores max-capacity offset and weight arrays, but consumers
  only read `0..sample_count`
- zeroing inactive capacity does not contribute to correctness when the active
  identity kernel writes its first offset and weight explicitly
- adaptive/DISAMAR-realized kernels previously cleared the max arrays at function
  entry and again before finalizing the active samples
- the retained `WavelengthSampling` layout is unchanged; this experiment targets
  hot transient memory traffic and stack scratch, not retained heap size

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `6606719304614ce6973f50d78b688b32`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process check before and after timing showed no active zdisamar benchmark,
  validation, plotting, or forward-model process
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.014387 s | 1.004529 s | 0.9903 |
| forward session setup | 0.711899 s | 0.713348 s | 1.0020 |
| forward session cached median | 0.304713 s | 0.301993 s | 0.9911 |
| forward fast four-scene median | 4.859552 s | 4.891560 s | 1.0066 |
| OE session setup median | 0.719659 s | 0.716125 s | 0.9951 |
| OE session retrieval median | 1.267872 s | 1.267720 s | 0.9999 |
| OE fast retrieval median | 0.989494 s | 0.987037 s | 0.9975 |
| OE sweep session total wall | 21.100117 s | 21.117324 s | 1.0008 |
| OE sweep fast total wall | 11.477791 s | 11.409060 s | 0.9940 |

Conclusion:
- this removes tens of MiB of unnecessary zero-fill memory traffic in the
  integration-plan build without changing retained plan encoding or RTM math
- the benchmark gate is flat-to-faster on OE and session-cached paths; the
  single forward fast-mode increase is small and isolated in this run
- this is worth keeping as a low-risk companion to the retained-layout work; the
  larger remaining integration-kernel opportunity is to write compact plans
  directly instead of routing through max-capacity scratch arrays

### Experiment 16: encode RTM aerosol phase rows as scalars

Changed:
- `RtmQuadratureLevel` now stores aerosol scattering/source scalars instead of
  three scaled `[151]f64` aerosol phase rows
- `RtmQuadratureGrid` carries a pointer to the prepared aerosol unit phase row
- LABOS aerosol optical-depth and pressure-shift weighting multiply the scalar
  by the shared unit phase at the consumer boundary

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `RtmQuadratureLevel` | 4,856 B | 1,256 B | -74.14% |
| per RTM quadrature level | 4.742 KiB | 1.227 KiB | -3,600 B |
| 48-level RTM buffer | 233,088 B | 60,288 B | -172,800 B |
| 701 forward misses x 48 RTM levels | 163,394,688 B | 42,261,888 B | -121,132,800 B |
| `RtmQuadratureGrid` view | 16 B | 24 B | +8 B |
| `ForwardInput` | 288 B | 296 B | +8 B |

Interpretation:
- the old level layout stored `aerosol_ksca_phase_above_per_km`,
  `aerosol_ksca_phase_below_per_km`, and `aerosol_ksca_phase_jacobian` as full
  phase rows
- each row was the same prepared aerosol phase coefficients scaled by a
  per-level scattering or Jacobian scalar
- this keeps the combined `phase_coefficients` row inline because the integrated
  source-function reflectance path reads it per active RTM level
- the tradeoff is one 8 B prepared-phase pointer in the grid view and an 8 B
  `ForwardInput` size increase, while removing 3,600 B from every RTM level row

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `323393204562446faf91328641b4db2d`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.004529 s | 0.999941 s | 0.9954 |
| forward session setup | 0.713348 s | 0.724321 s | 1.0154 |
| forward session cached median | 0.301993 s | 0.296183 s | 0.9808 |
| forward fast four-scene median | 4.891560 s | 4.816070 s | 0.9846 |
| OE session setup median | 0.716125 s | 0.717254 s | 1.0016 |
| OE session retrieval median | 1.267720 s | 1.236359 s | 0.9753 |
| OE fast retrieval median | 0.987037 s | 0.970431 s | 0.9832 |
| OE sweep session total wall | 21.117324 s | 20.667756 s | 0.9787 |
| OE sweep fast total wall | 11.409060 s | 11.375178 s | 0.9970 |

Conclusion:
- this is a retained-layout win on a LABOS hot-path struct and removes about
  115.52 MiB of possible copied RTM-level aerosol phase payload across a
  701-miss, 48-level fill
- the benchmark is faster on all steady-state and OE retrieval surfaces; the
  only notable increase is session setup, which is outside the cached execution
  hot path and small relative to the retained row reduction
- this is the preferred shape over lazy recomputing three dense rows because the
  hot consumers now receive the exact scalar and the shared unit phase without
  carrying duplicate arrays through every level

### Experiment 17: encode strong-line anchors as compact indexes

Changed:
- `StrongLineAnchorIndex` is now a typed `u32` index into the relevant-line
  window
- `StrongLineWavelengthWindow.anchors` stores 128 compact anchor indexes instead
  of 128 host-width `usize` values
- missing anchors still use an explicit sentinel value, now sized to the compact
  anchor type

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `StrongLineWavelengthWindow` | 1,048 B | 536 B | -48.85% |
| anchor array inside each window | 1,024 B | 512 B | -512 B |
| anchor element width | 8 B | 4 B | -50.00% |
| cache span at 64 B per line | 17 lines | 9 lines | -8 lines |

Interpretation:
- anchor slots store indexes into the current relevant-line window, not memory
  addresses or globally stable pointers
- the window has at most 128 strong-line sidecar slots; each slot is either a
  relevant-line index or the sentinel for missing anchor
- the cast guard preserves the index contract if a future relevant-line window
  ever exceeds the compact index range
- this keeps the existing array-of-anchors access pattern and only changes the
  width of the stored index

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `726382f4bf934fc7b354441cc8e386fe`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 0.999941 s | 0.998235 s | 0.9983 |
| forward session setup | 0.724321 s | 0.709712 s | 0.9798 |
| forward session cached median | 0.296183 s | 0.295524 s | 0.9978 |
| forward fast four-scene median | 4.816070 s | 4.815198 s | 0.9998 |
| OE session setup median | 0.717254 s | 0.715381 s | 0.9974 |
| OE session retrieval median | 1.236359 s | 1.236752 s | 1.0003 |
| OE fast retrieval median | 0.970431 s | 0.961629 s | 0.9909 |
| OE sweep session total wall | 20.667756 s | 20.440127 s | 0.9890 |
| OE sweep fast total wall | 11.375178 s | 11.186411 s | 0.9834 |

Conclusion:
- this is a narrow compact-index win for a hot stack/window struct used while
  selecting and applying prepared strong-line anchors
- the retained value is smaller per instance and crosses fewer cache lines, with
  the same logical anchor table and sentinel behavior
- benchmark movement is flat-to-faster on the retained harness; the only slower
  reported timing is a 0.03% OE session retrieval change, which is below this
  single-run noise floor and offset by faster sweep totals in the same run

### Experiment 18: split ConvTP relaxation scratch from returned state

Changed:
- `StrongLineConvTPState` no longer stores the
  `relaxation_weights[128 * 128]f64` preparation matrix
- `prepareStrongLineConvTPStateWithScratch` fills the same relaxation weights in
  caller-provided scratch while returning only the fields read by
  `strongLineContribution`
- the existing direct helper still provides internal scratch for callers that do
  not manage scratch explicitly

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `StrongLineConvTPState` | 136,208 B | 5,136 B | -96.23% |
| returned-state cache span | 2,129 lines | 81 lines | -2,048 lines |
| preparation-only relaxation scratch | 131,072 B | 131,072 B | unchanged |
| 47 direct profile-node returned states | 6,401,776 B | 241,392 B | -5.875 MiB |

Interpretation:
- relaxation weights are read while deriving `line_mixing_coefficients`
- after preparation, the direct strong-line contribution path reads
  `population_t`, `dipole_t`, `mod_sig_cm1`, `half_width_cm1_at_t`,
  `line_mixing_coefficients`, and `sig_moy_cm1`
- this keeps the same dense preparation scratch but stops carrying the scratch
  matrix as part of the post-preparation state
- prepared profile paths already use exact-size scratch; this experiment fixes
  the remaining direct ConvTP state shape without changing contribution math

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `197ad666abab4df9a9fff9f9198ebce0`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 0.998235 s | 1.005797 s | 1.0076 |
| forward session setup | 0.709712 s | 0.711739 s | 1.0029 |
| forward session cached median | 0.295524 s | 0.296306 s | 1.0026 |
| forward fast four-scene median | 4.815198 s | 4.814990 s | 1.0000 |
| OE session setup median | 0.715381 s | 0.716440 s | 1.0015 |
| OE session retrieval median | 1.236752 s | 1.236149 s | 0.9995 |
| OE fast retrieval median | 0.961629 s | 0.959866 s | 0.9982 |
| OE sweep session total wall | 20.440127 s | 20.465027 s | 1.0012 |
| OE sweep fast total wall | 11.186411 s | 11.185478 s | 0.9999 |

Conclusion:
- this removes the largest remaining fixed-capacity field from the direct
  strong-line state without removing the scratch required by the preparation
  algorithm
- the no-session forward median moved slower in this single run, but the OE
  retrieval and sweep surfaces are flat-to-slightly-faster or within the small
  single-run noise band
- this is worth keeping as a memory-layout win because the post-preparation
  state shrinks by 128 KiB per direct state while the benchmark gate does not
  show an end-to-end regression on the OE surfaces

### Experiment 19: encode minus PLM basis by parity

Changed:
- `FourierPlmBasis` now stores only the weighted plus-side PLM rows
- minus-side rows are recovered at the consumer boundary using
  `(-1)^(coef_idx - i_fourier)`
- the fallback `PlmArrays` helper uses the same encoding instead of carrying a
  second 12-value row

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| `FourierPlmBasis` | 29,008 B | 14,512 B | -49.97% |
| one cached Fourier basis array slot | 28.3 KiB | 14.2 KiB | -14,496 B |
| 151-slot workspace PLM cache | 4,380,208 B | 2,191,312 B | -2.087 MiB |
| fallback `PlmArrays` | 192 B | 96 B | -50.00% |

Interpretation:
- for a fixed Fourier order, the recurrence gives the minus-side basis as the
  plus-side basis with alternating coefficient parity
- phase matrix and phase-row builders read the plus row and apply the parity
  sign when building `Zmin`
- this removes one dense `[151][12]f64` array from each cached PLM basis without
  changing the phase coefficient input or matrix output layout
- the workspace still caches one basis per Fourier order; the cache now stores
  half the PLM payload per slot

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `11cb5060e18e449e830950b963e2a157`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.005797 s | 1.004422 s | 0.9986 |
| forward session setup | 0.711739 s | 0.709770 s | 0.9972 |
| forward session cached median | 0.296306 s | 0.295492 s | 0.9973 |
| forward fast four-scene median | 4.814990 s | 4.823127 s | 1.0017 |
| OE session setup median | 0.716440 s | 0.716281 s | 0.9998 |
| OE session retrieval median | 1.236149 s | 1.228667 s | 0.9939 |
| OE fast retrieval median | 0.959866 s | 0.954082 s | 0.9940 |
| OE sweep session total wall | 20.465027 s | 20.547215 s | 1.0040 |
| OE sweep fast total wall | 11.185478 s | 11.179253 s | 0.9994 |

Conclusion:
- this cuts the LABOS PLM basis payload roughly in half and removes about
  2.09 MiB from the full workspace PLM cache allocation
- the benchmark residuals are unchanged; OE single retrieval improves in this
  run, while the session sweep movement is a small 0.4% increase
- this is worth keeping because the consumer loop still streams dense plus rows
  and adds only one parity sign per coefficient term while halving the cached
  basis memory

### Experiment 20: reuse integration kernel arrays as adaptive sample scratch

Changed:
- adaptive integration builders no longer allocate separate
  `[2048]f64` wavelength and raw-weight sample arrays
- candidate wavelengths are written into `IntegrationKernel.offsets_nm` and raw
  weights into `IntegrationKernel.weights`
- `finalizeAdaptiveKernel` now sorts, merges, and normalizes those same arrays
  in place for the final kernel

Memory result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| duplicate adaptive sample scratch per builder call | 32,768 B | 0 B | -100.00% |
| builder-local sample storage plus `IntegrationKernel` | 65,552 B | 32,784 B | -49.99% |
| 701 wavelengths x 2 channels duplicate scratch | 45,940,736 B | 0 B | -43.81 MiB |
| retained `IntegrationKernel` layout | 32,784 B | 32,784 B | unchanged |

Interpretation:
- the adaptive builder needs candidate wavelengths and raw weights only until
  final normalization
- the output kernel already has two max-capacity arrays with the same element
  type and capacity
- using those arrays as scratch removes a second max-capacity sample pair from
  the call frame
- the retained compact wavelength-plan layout is unchanged; this only removes
  transient duplicate scratch from adaptive kernel construction

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `dadb8461a8fb4437811d5456a1a9617b`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.004422 s | 1.005817 s | 1.0014 |
| forward session setup | 0.709770 s | 0.711012 s | 1.0018 |
| forward session cached median | 0.295492 s | 0.295037 s | 0.9985 |
| forward fast four-scene median | 4.823127 s | 4.817733 s | 0.9989 |
| OE session setup median | 0.716281 s | 0.716079 s | 0.9997 |
| OE session retrieval median | 1.228667 s | 1.230433 s | 1.0014 |
| OE fast retrieval median | 0.954082 s | 0.954111 s | 1.0000 |
| OE sweep session total wall | 20.547215 s | 20.517402 s | 0.9985 |
| OE sweep fast total wall | 11.179253 s | 11.188192 s | 1.0008 |

Conclusion:
- this removes duplicate adaptive sample storage without changing the retained
  kernel or compact wavelength-plan representation
- the benchmark gate is flat: cached forward and session sweep improve, while
  no-session forward, OE session retrieval, and fast sweep move by less than
  0.2%
- this is worth keeping as a memory-traffic cleanup because the hot builder now
  carries one max-capacity sample pair instead of two

### Experiment 21: fill shared-grid layer inputs directly

Changed:
- shared support-row layer reduction now writes the final `LayerInput` row
  directly
- the older evaluated-layer return path remains for other callers, but the
  forward input shared-grid hot path no longer materializes an intermediate
  `EvaluatedLayer`
- phase coefficients are still accumulated from the same support-row carriers;
  the change removes the extra full-width layer payload between accumulation
  and the transport input row

Memory traffic result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| intermediate `EvaluatedLayer` per shared-grid transport layer | 1,280 B | 0 B | -100.00% |
| current 47-layer forward miss | 60,160 B | 0 B | -58.75 KiB |
| 701 forward misses x 47 transport layers | 42,172,160 B | 0 B | -40.22 MiB |

Interpretation:
- `EvaluatedLayer` carries a `[151]f64` phase row plus optical-depth scalars
  before `layerInputFromEvaluated` copies the same phase row into `LayerInput`
- the direct writer keeps the accumulation loop unchanged and writes the
  optical-depth scalars, cosines, Jacobian zero rows, and normalized phase row
  into the final transport row once
- this is a memory-traffic change, not a retained-footprint change: `LayerInput`
  remains the LABOS-facing row type consumed by the transport solver
- the current benchmark shared-grid shape has 701 forward misses and 47
  transport layers, so avoiding the intermediate row removes about 40.22 MiB of
  hot per-forward-fill payload movement

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `5a2ede235eec4ca7b79a5702a17dec9a`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- a first clean run was also taken and discarded for retained evidence because
  the session sweep moved +0.64%; the second clean run below is the retained
  benchmark artifact
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 1.005817 s | 0.999074 s | 0.9933 |
| forward session setup | 0.711012 s | 0.711489 s | 1.0007 |
| forward session cached median | 0.295037 s | 0.291684 s | 0.9886 |
| forward fast four-scene median | 4.817733 s | 4.810844 s | 0.9986 |
| OE session setup median | 0.716079 s | 0.716797 s | 1.0010 |
| OE session retrieval median | 1.230433 s | 1.226624 s | 0.9969 |
| OE fast retrieval median | 0.954111 s | 0.944750 s | 0.9902 |
| OE sweep session total wall | 20.517402 s | 20.579478 s | 1.0030 |
| OE sweep fast total wall | 11.188192 s | 11.169467 s | 0.9983 |

Conclusion:
- this removes about 40.22 MiB of intermediate phase-row layer traffic from the
  shared-grid forward fill without changing the LABOS input layout or adding
  recomputation
- the retained run is flat-to-faster on forward medians, cached forward, single
  OE retrieval, and fast sweep; the session sweep moved +0.30%, which is within
  the same small single-run band seen in prior memory-traffic experiments
- this is worth keeping as a direct-fill cleanup, while the next larger
  retained-footprint targets remain the inline phase rows in `LayerInput`,
  `SourceInterfaceInput`, and `RtmQuadratureLevel`

### Experiment 22: fill shared-grid boundary rows directly

Changed:
- shared-grid source-interface and RTM quadrature writers now fill final output
  rows directly from support-row gas carriers, particle boundary scalars, and
  prepared phase rows
- `SharedBoundaryCarrier` remains available for existing callers, but the hot
  carrier-cache writer no longer materializes it before writing
  `RtmQuadratureLevel`
- the spectroscopy-cache RTM path also no longer builds a local `LevelCarrier`
  just to copy the same above-boundary phase row into the quadrature level
- invalid source-interface boundary rows preserve the existing zero-scattering
  row with the RTM weight retained

Memory traffic result:

| item | before | after | change |
| --- | ---: | ---: | ---: |
| intermediate `SharedBoundaryCarrier` per shared-grid boundary | 2,472 B | 0 B | -100.00% |
| current 48-level RTM quadrature fill | 118,656 B | 0 B | -115.88 KiB |
| 701 forward misses x 48 RTM levels | 83,177,856 B | 0 B | -79.33 MiB |
| spectroscopy-cache local `LevelCarrier` per RTM level | 1,224 B | 0 B | -100.00% |

Interpretation:
- `SharedBoundaryCarrier` carries above and below combined phase rows; the RTM
  quadrature path only stores the above row plus boundary aerosol scattering
  scalars in `RtmQuadratureLevel`
- the direct writer computes the same above phase row into the final quadrature
  level and still carries below aerosol scattering as a scalar for the aerosol
  source-Jacobian path
- this is a memory-traffic change, not a retained-layout change:
  `SourceInterfaceInput` and `RtmQuadratureLevel` still expose the same fields to
  LABOS
- the source-interface shared-grid path receives the same direct-fill treatment,
  but the current retained benchmark primarily exercises the RTM quadrature
  carrier-cache path

Benchmark evidence:
- `zig build check`: passed
- `zig build test-fast`: passed
- `uv run benchmark/run_benchmark.py`: run
  `0af6293f0f774efc8ea786dac109a512`, `ZDISAMAR_WORKER_LIMIT=2`, host CPUs 10,
  effective native worker cap 2, `ReleaseFast` native sync before timing
- process checks showed no active zdisamar benchmark, validation, plotting, or
  forward-model process before or after timing
- a first final-code run also passed; the retained run below is the second clean
  final-code run after preserving the invalid-boundary RTM weight behavior
- benchmark residual rows: DISAMAR fixture worst interior max_abs `9.569e-14`;
  session-vs-no-session reflectance residual `0.0`; fast-mode spectra worst
  max_abs_over_noise `1.600`; OE session AOD diff `8.699e-08`

Benchmark comparison against the previous committed `benchmark/results.json`:

| metric | before | after | ratio |
| --- | ---: | ---: | ---: |
| forward no-session median | 0.999074 s | 1.008663 s | 1.0096 |
| forward session setup | 0.711489 s | 0.718924 s | 1.0104 |
| forward session cached median | 0.291684 s | 0.289888 s | 0.9938 |
| forward fast four-scene median | 4.810844 s | 4.818098 s | 1.0015 |
| OE session setup median | 0.716797 s | 0.724329 s | 1.0105 |
| OE session retrieval median | 1.226624 s | 1.207204 s | 0.9842 |
| OE fast retrieval median | 0.944750 s | 0.934268 s | 0.9889 |
| OE sweep session total wall | 20.579478 s | 20.468999 s | 0.9946 |
| OE sweep fast total wall | 11.169467 s | 11.126235 s | 0.9961 |

Conclusion:
- this removes about 79.33 MiB of intermediate boundary-carrier payload traffic
  from the current shared-grid RTM quadrature fill
- the retained OE timings improve materially, including both sweep totals; the
  no-session/setup forward surfaces moved slower in this retained run, so this
  should be treated as an OE-hot-path win rather than a universal forward
  latency win
- the next retained-footprint step should target the inline final phase rows
  themselves, but only with a representation that keeps LABOS phase access dense

Strategy checklist used while reading:
- use indexes, handles, or ranges instead of per-element pointers where the
  backing storage is stable
- move booleans out of dense objects when they describe loop membership
- split hot scalar columns from large cold payloads with struct-of-arrays
- keep sparse data out-of-band; prefer active arrays/ranges for numeric loops
  and hash maps only for true keyed lookup
- encode modes as prepared tags or specialized routes rather than dispatch in
  inner loops
- recompute cheap derived values instead of memoizing large fields that cause
  extra memory traffic

## Highest-Signal Findings

### 1. Instrument wavelength plans now use compact rows; adaptive scratch remains max capacity

Files:
- `src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`
- `src/forward_model/implementations/instrument/types.zig`
- `src/forward_model/implementations/instrument/adaptive_plan.zig`
- `src/forward_model/implementations/instrument/adaptive_cache.zig`
- `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `WavelengthSampling` | 200 B | nominal wavelength + compact kernel refs | 0 |
| `IntegrationKernel` | 32,784 B | `[2048]f64` offsets + `[2048]f64` weights | 63 |
| `AdaptiveIntervalPlan` | 20,504 B | interval ends + division counts | 0 |
| `AdaptiveKernelCache` | 20,512 B | embedded `AdaptiveIntervalPlan` + ready flag | 63 |

Memory access shape:
- one compact `WavelengthSampling` row is allocated per nominal wavelength plan
- plan rows store small inline kernels or ranges into side-storage offsets and
  weights instead of embedding two `IntegrationKernel` payloads
- adaptive planning still uses fixed 2048-capacity interval plans and
  `IntegrationKernel` scratch for candidate samples
- adaptive builders now reuse the output kernel arrays as candidate scratch
  instead of carrying duplicate sample arrays
- `collectUniqueForwardMisses` scans the plan rows and then builds a hash map
  of cache misses

Potential direction:
- inspect whether adaptive interval counts justify exact-size side storage
  rather than a fixed 2048-capacity `AdaptiveIntervalPlan`
- keep the common small kernel inline and store large adaptive kernels
  out-of-band only for rows that need them
- measure whether `IntegrationKernel` can become a caller-owned sample builder
  with exact active capacity without adding allocation to the hot path
- deduplicate kernels by handle when radiance or irradiance kernels repeat

Completed layout changes:
- compact wavelength rows removed the original `sample_count * 64.1 KiB`
  retained plan payload
- integration-kernel reset no longer clears inactive max capacity
- adaptive builders no longer carry duplicate max-capacity sample arrays
- remaining max-capacity storage is concentrated in explicit scratch types,
  not in retained wavelength-plan rows

### 2. LABOS attenuation already moved toward lazy storage, but transport fields remain AoS-heavy

Files:
- `src/forward_model/radiative_transfer/labos/attenuation.zig`
- `src/forward_model/radiative_transfer/labos/types.zig`
- `src/forward_model/radiative_transfer/labos/orders.zig`
- `src/forward_model/radiative_transfer/labos/layers.zig`
- `src/forward_model/radiative_transfer/labos/reflectance.zig`
- `src/forward_model/radiative_transfer/labos/phase_basis.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `AttenArray` | 405,616 B | `[12][65][65]f64` | 0 |
| `RuntimeAttenArray` | 48 B plus backing slices | adjacent and top-to-level slices | 0 |
| `Mat` | 1,160 B | `[144]f64` | 0 |
| `Vec` | 104 B | `[12]f64` + `n` | 0 |
| `Vec2` | 216 B | two `Vec` values + `n` | 0 |
| `LayerRT` | 2,320 B | `R` and `T` matrices | 0 |
| `UDField` | 536 B | `E`, `U`, `D` vectors | 0 |
| `UDLocal` | 432 B | `U`, `D` vectors | 0 |
| `Geometry` | 2,832 B | `dmu_plus`, `dmu_min`, `dmu_same` | 0 |
| `FourierPlmBasis` | 14,512 B | weighted plus-side PLM rows | 0 |
| `OrdersWorkspace` | 104 B plus backing slices | `UD*`, active flags | 0 |

Memory access shape:
- historical notes show LABOS layer doubling and order transport dominate
  forward time
- `AttenArray` is the old full matrix form; `RuntimeAttenArray` keeps adjacent
  layer transmittance and top-to-level transmittance and lazily multiplies
  uncommon non-adjacent paths
- `UDField` and `UDLocal` group `U` and `D` together even though transport has
  separate upward and downward passes
- `FourierPlmBasis` now stores plus-side PLM rows and derives minus-side rows
  by coefficient parity while building `Zmin`
- `Vec` and `Vec2` carry `n` metadata inside many small fixed-capacity values
- `rt_active: []bool` marks active layers and is read during transport loops

Potential direction:
- keep extending the `RuntimeAttenArray` pattern where measured call sites do
  not need full level-to-level attenuation
- test an order workspace that stores `U0`, `U1`, `D0`, `D1`, and `E` as
  separate level-major arrays rather than nested `UDField` values
- replace scanned `rt_active` booleans with active level indexes when active
  layers are sparse enough to skip work
- keep fixed-size matrix kernels for `12 x 10` math where benchmarked kernels
  show the shape is the computational core
- remove per-value `n` metadata only if it stays derivable from the workspace or
  route without making call sites branchier

### 3. Optical-property carriers keep phase coefficient payloads with scalar state

Files:
- `src/forward_model/optical_properties/state_build/state_types.zig`
- `src/forward_model/optical_properties/state_build/carrier_eval.zig`
- `src/forward_model/optical_properties/state_build/shared_carrier.zig`
- `src/forward_model/optical_properties/state_build/layer_accumulation.zig`
- `src/forward_model/optical_properties/state_build/rtm_quadrature.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `PreparedSublayer` | 272 B | scalar layer state + shared phase references | 48 |
| `SharedOpticalCarrier` | 1,264 B | combined `[151]f64` phase row | 0 |
| `SharedBoundaryCarrier` | 2,472 B | above/below combined phase rows | 0 |
| `RtmQuadratureLevel` | 1,256 B | combined phase row + aerosol scattering scalars | 0 |
| `SharedRtmSubgrid` | 32 B | scratch-backed altitude/weight slices | 0 |
| `WavelengthCarrierCache` | 120 B plus backing slices | valid flags + carrier slice | 0 |

Memory access shape:
- scalar optical-depth values and phase coefficient vectors are stored in the
  same row objects
- `PreparedSublayer` now carries scalar layer state and reads shared prepared
  particle phase data instead of carrying per-row copies
- `WavelengthCarrierCache` uses `support_row_valid: []bool` and a
  `[]SharedOpticalCarrier` cache for support-row reuse
- `RtmQuadratureLevel` now keeps combined source phase inline but stores aerosol
  phase-dependent source/Jacobian data as scalars plus the grid-level unit phase
- shared-grid layer, source-interface, and RTM quadrature builders now write
  final rows directly instead of materializing `EvaluatedLayer`,
  `SharedBoundaryCarrier`, or local `LevelCarrier` intermediates
- `SharedRtmSubgrid` returns slices over `GaussRuleScratch`; the scratch still
  reserves capacity for dynamic Gauss rules
- historical notes show phase matrix construction is significant and repeated
  layer-specific fill of phase arrays dominates the PLM basis itself

Potential direction:
- split scalar optical-depth columns from phase-coefficient side storage
- inspect whether combined phase rows can use side storage without moving
  expensive phase recomputation into the LABOS hot loop
- use generation tags or active support-row lists for `support_row_valid` when
  the cache is repeatedly reset per wavelength
- keep `SharedRtmSubgrid` as a workspace slice and next inspect whether
  `GaussRuleScratch` capacity itself should remain 128
- benchmark before replacing phase memoization: recomputing phase coefficients
  may be cheaper than carrying arrays, but phase fill is already a known hot
  path and must be measured with the RTM caller intact

### 4. Profile spectroscopy caches store multiple breakdown arrays

Files:
- `src/forward_model/optical_properties/state_build/layer_spectroscopy.zig`
- `src/forward_model/optical_properties/state_build/state_spectroscopy.zig`
- `src/forward_model/optical_properties/state_build/absorbers.zig`
- `src/input/reference/spectroscopy/line_list_eval.zig`
- `src/input/reference/spectroscopy/line_list_ops.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `ProfileSpectroscopyCache` | 5,144 B | ten `[64]f64` arrays | 0 |
| `ProfileNodeSpectroscopyCache` | 1,032 B | total values + second derivatives | 0 |
| `ProfileCacheValueWorker` | 288 B | `SpectroscopyLineList` descriptor | 0 |
| `StrongLineWavelengthWindow` | 1,048 B | fixed anchor payload | 0 |

Memory access shape:
- the full profile cache stores weak, strong, line, line-mixing, total, and all
  corresponding second-derivative arrays
- the smaller node cache stores only total values and total second derivatives
- many forward paths appear to need the total profile value first; breakdown
  arrays are more valuable for diagnostics, validation, or derivative-specific
  paths
- worker structs embed the wavelength window payload directly

Potential direction:
- route plain forward execution through the total-only cache where breakdown
  output is not requested
- keep breakdown arrays in a side cache that is only allocated when diagnostics
  or a derivative path needs them
- store strong-line windows as ranges or handles into prepared line storage when
  the window is already derived from sorted line lists
- measure actual `node_count` distribution before replacing `[256]f64` with
  dynamic storage; if most runs are near the cap, fixed arrays may still be the
  right tradeoff

### 5. Strong-line convolution state has one very large dense matrix

File:
- `src/input/reference/spectroscopy/strong_lines.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `StrongLineConvTPState` | 5,136 B | five `[128]f64` prepared-state arrays | 0 |

Memory access shape:
- the returned direct state carries the prepared per-line arrays read by
  `strongLineContribution`
- the 128 KiB relaxation matrix is now preparation scratch instead of retained
  returned-state payload
- active prepared profile paths already use `line_count * line_count` scratch
  rather than retaining the relaxation matrix

Potential direction:
- inspect whether the direct public helper should also receive caller-owned
  exact-size scratch on every hot call site
- if the physical matrix has sparse or triangular access, encode only the used
  preparation coefficients
- measure strong-line count distribution before changing the remaining scratch
  shape; scratch is capacity waste only when active counts are below 128

### 6. Spectral caches already use sparse keyed lookup, but plan layout can make the lookup cheaper

Files:
- `src/forward_model/instrument_grid/grid_calculation/cache.zig`
- `src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`
- `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `SpectralEvaluationCache` | 96 B plus hash-map backing storage | forward and irradiance maps | 0 |
| `ForwardCacheMiss` | 16 B | key + wavelength | 0 |
| `ForwardIntegratedSample` | 24 B | scalar result fields | 0 |

Memory access shape:
- the forward cache is keyed by exact wavelength bit pattern
- `collectUniqueForwardMisses` uses a temporary `AutoHashMap(u64, void)` while
  scanning all plan rows
- hash maps are appropriate for exact-wavelength reuse, but the current scan
  pays the cost after reading large `WavelengthSampling` objects

Potential direction:
- after compacting plan rows, make forward-miss collection operate on dense
  kernel ranges and produce a sorted or insertion-ordered miss array
- keep hash maps for repeated exact-key forward/irradiance lookup unless a
  sorted array plus binary search benchmarks better for the typical miss count
- use `ensureTotalCapacity` with measured upper bounds to avoid hash-map growth
  in the prefetch hot path

## Strategy Notes By Category

### Indexes or handles instead of pointers

Best current candidate:
- `WavelengthSampling` should point to kernel storage by index/range instead of
  embedding two `IntegrationKernel` payloads.

Lower priority:
- worker structs with pointers are mostly one-per-worker, not per-element hot
  payloads
- API contexts and prepared state roots are large but sit at route boundaries;
  they should be passed by pointer but are not the first data-layout target

### Booleans out-of-band

Candidate fields and slices:
- `IntegrationKernel.enabled`
- `AdaptiveKernelCache.ready`
- `OrdersWorkspace.rt_active`
- `WavelengthCarrierCache.support_row_valid`
- `ForwardSampleScratch.support_carrier_valid`
- `Workspace.layer_phase_kernel_valid`
- `Workspace.plm_basis_cache_valid`
- `LineAbsorberState.strong_line_state_initialized`

Memory interpretation:
- a single bool inside a small boundary struct is usually not worth changing
- a bool slice that is reset and scanned in a hot loop can become an active
  index list or generation-tag array
- active lists matter when the loop would otherwise visit many inactive rows

### Struct-of-arrays

Best current candidates:
- `WavelengthSampling`: split row descriptors from kernel offsets/weights
- `UDField` and `UDLocal`: split upward/downward/source columns by level
- `SharedOpticalCarrier`: split scalar optical-depth columns from phase arrays
- `PreparedSublayer`: split scalar layer state from particle phase side storage
- profile spectroscopy cache: split total-only forward data from breakdown data

Less obvious candidates:
- `Mat`, `Vec`, and `LayerRT` are already fixed-shape math kernels; changing
  them without a microbenchmark risks losing the current dense numeric access
  pattern

### Sparse side storage and hash maps

Good uses:
- exact-wavelength spectral reuse with `AutoHashMap(u64, ...)`
- sparse diagnostic or breakdown data requested only by some output paths
- generated LUT assets or identifier-keyed reference lookups outside inner
  numeric loops

Avoid in inner numeric loops:
- replacing dense arrays with hash maps where the index space is naturally
  compact and repeated
- per-coefficient lookup in phase or matrix kernels

Preferred shape for numeric hot loops:
- dense active index arrays
- compact ranges into sorted backing storage
- generation tags for reused caches
- hash maps only at plan/build boundaries or exact-key reuse boundaries

### Encodings instead of polymorphism

Existing good shape:
- transport and instrument implementations use function-pointer tables at the
  route boundary, not every arithmetic operation
- many routes already prepare enums, masks, or fixed representations before
  entering loops

Potential direction:
- avoid carrying inactive representation payloads inside hot rows
- where a branch is invariant across a wavelength batch, specialize the batch
  route instead of checking it per sublayer or per sample
- keep union/tag dispatch at setup boundaries and expose dense typed slices to
  the hot loops

### Lazy calculation instead of memoized fields

Already present:
- `RuntimeAttenArray.get` lazily multiplies adjacent transmittance for
  uncommon non-adjacent paths instead of storing the whole level-to-level cube

Best next candidates:
- integration kernels: build or reference active offsets/weights only, not full
  2048-capacity arrays per plan row
- phase coefficients: store side arrays only for scattering-positive rows and
  benchmark recomputation against memory traffic
- profile spectroscopy breakdown: compute total in the default route and keep
  weak/strong/line breakdown side arrays for routes that need them
- strong-line relaxation weights: allocate the active `line_count * line_count`
  matrix instead of storing max capacity in every state

Fields likely worth keeping memoized until measured:
- LABOS geometry deltas (`dmu_plus`, `dmu_min`, `dmu_same`) because they are
  reused by heavy matrix/order kernels
- fixed-shape `Mat` payloads in layer doubling where the math kernel dominates
  and previous history shows fixed shapes helped

## Candidate Experiments

1. Compact wavelength plans

   Replace `WavelengthSampling`'s embedded kernels with small-inline kernel
   descriptors plus side storage for adaptive kernels. Measure:
   `buildWavelengthSampling`, `collectUniqueForwardMisses`, forward runtime,
   peak RSS, and parity outputs.

2. LABOS order workspace SoA

   Prototype a workspace-local layout for `U0`, `U1`, `D0`, `D1`, and `E`
   arrays by level. Keep the public math helpers stable until the benchmark
   shows whether the layout helps transport loops.

3. Carrier scalar/phase split

   Store scalar optical-depth values separately from `[151]f64` phase arrays.
   Add side storage only for rows with particle scattering or combined phase
   use. Measure layer construction and LABOS input building together.

4. Total-only spectroscopy profile cache

   Make the default forward path use `ProfileNodeSpectroscopyCache`-style
   total-only data and allocate breakdown arrays only for outputs or derivative
   paths that need them.

5. Active/generation tags for cache-valid state

   Replace repeated `@memset(false)` plus bool scans with generation tags or
   active index lists for support-row carriers and LABOS active layers.

6. Strong-line relaxation side storage

   Allocate relaxation weights to active `line_count * line_count` and inspect
   whether the access pattern is dense, triangular, or sparse.

## Deprioritized Structs

These are not ignored, but they are lower value for the memory-layout pass:
- API contexts and C ABI handles: large headers, but boundary-lifetime objects
- output diagnostic row structs: hot only when diagnostic outputs are requested
- namespace/root structs: compile-time organization, not runtime payload
- small structs with padding-only waste: usually less important than cache-line
  scale fixed-capacity arrays
- fixed math kernels that have already shown performance wins in history notes

## Hot-Path Coverage By Subsystem

| subsystem | markers | memory-layout focus |
| --- | ---: | --- |
| optical properties | 65 | carrier caches, phase arrays, spectroscopy caches, layer accumulation |
| radiative transfer | 42 | LABOS attenuation, layer matrices, order transport, phase basis |
| instrument grid | 41 | wavelength plans, integration kernels, spectral caches, calibration/noise |
| reference input | 28 | line-list windows, spectroscopy physics, CIA and climatology lookup |
| input instrument | 13 | LUT evaluation, line shape, solar spectrum |
| implementations | 11 | route dispatch, adaptive integration, noise/surface/instrument functions |
| common math | 9 | quadrature, interpolation, linear algebra |
| work partition | 3 | worker ranges and chunk scheduling |
| jacobian | 2 | state mask inclusion and derivative vector loops |
| atmosphere/reference data input | 2 | fraction controls and solar irradiance lookup |
| output diagnostics | 7 | output row construction when requested |

## Hot-Path Inventory By File

The source-level `// hot path:` markers are the exact per-function index. This
table verifies all markers are covered by this scratch analysis.

| markers | file |
| ---: | --- |
| 10 | `src/forward_model/optical_properties/state_build/carrier_eval.zig` |
| 9 | `src/forward_model/radiative_transfer/labos/layers.zig` |
| 8 | `src/forward_model/radiative_transfer/labos/reflectance.zig` |
| 8 | `src/forward_model/instrument_grid/grid_calculation/simulate.zig` |
| 7 | `src/forward_model/radiative_transfer/labos/orders.zig` |
| 7 | `src/forward_model/radiative_transfer/labos/attenuation.zig` |
| 6 | `src/input/reference/spectroscopy/line_list_ops.zig` |
| 6 | `src/forward_model/instrument_grid/spectral_math/noise.zig` |
| 6 | `src/forward_model/instrument_grid/spectral_math/calibration.zig` |
| 6 | `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig` |
| 5 | `src/forward_model/optical_properties/state_build/absorbers.zig` |
| 5 | `src/forward_model/optical_properties/shared/particle_profiles.zig` |
| 5 | `src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig` |
| 5 | `src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig` |
| 5 | `src/forward_model/implementations/instrument/adaptive_plan.zig` |
| 4 | `src/input/reference/spectroscopy/physics_core.zig` |
| 4 | `src/input/reference/spectroscopy/line_list_eval.zig` |
| 4 | `src/input/reference/cia.zig` |
| 4 | `src/forward_model/radiative_transfer/labos/matrix.zig` |
| 4 | `src/forward_model/radiative_transfer/labos/execute.zig` |
| 4 | `src/forward_model/optical_properties/state_build/vertical_grid.zig` |
| 4 | `src/forward_model/optical_properties/state_build/state_spectroscopy.zig` |
| 4 | `src/forward_model/optical_properties/state_build/state_scalar.zig` |
| 4 | `src/forward_model/optical_properties/state_build/layer_accumulation.zig` |
| 4 | `src/common/math/quadrature/gauss_legendre.zig` |
| 3 | `src/input/reference/airmass_phase.zig` |
| 3 | `src/input/instrument/solar_spectrum.zig` |
| 3 | `src/input/instrument/line_shape.zig` |
| 3 | `src/input/instrument/cross_section_lut_eval.zig` |
| 3 | `src/forward_model/work_partition.zig` |
| 3 | `src/forward_model/radiative_transfer/labos/phase_basis.zig` |
| 3 | `src/forward_model/optical_properties/state_build/spectroscopy.zig` |
| 3 | `src/forward_model/optical_properties/state_build/shared_carrier.zig` |
| 3 | `src/forward_model/optical_properties/state_build/layer_spectroscopy.zig` |
| 3 | `src/forward_model/implementations/noise.zig` |
| 2 | `src/output/radiative_transfer_diagnostics.zig` |
| 2 | `src/output/o2_line_contributions.zig` |
| 2 | `src/input/reference/spectroscopy/strong_lines.zig` |
| 2 | `src/input/reference/cross_sections.zig` |
| 2 | `src/input/reference/climatology.zig` |
| 2 | `src/input/instrument/cross_section_lut_basis.zig` |
| 2 | `src/input/instrument/cross_section_lut.zig` |
| 2 | `src/forward_model/optical_properties/state_build/state_optical_depth.zig` |
| 2 | `src/forward_model/optical_properties/state_build/source_interfaces.zig` |
| 2 | `src/forward_model/optical_properties/state_build/rtm_quadrature.zig` |
| 2 | `src/forward_model/optical_properties/state_build/pseudo_spherical.zig` |
| 2 | `src/forward_model/optical_properties/state_build/profile_state_cache.zig` |
| 2 | `src/forward_model/optical_properties/state_build/forward_layers.zig` |
| 2 | `src/forward_model/optical_properties/state_build/accumulation.zig` |
| 2 | `src/forward_model/optical_properties/shared/phase_functions.zig` |
| 2 | `src/forward_model/jacobian/root.zig` |
| 2 | `src/forward_model/instrument_grid/grid_calculation/postprocess.zig` |
| 2 | `src/forward_model/implementations/instrument/integration.zig` |
| 2 | `src/common/math/linalg/cholesky.zig` |
| 2 | `src/common/math/interpolation/spline.zig` |
| 1 | `src/output/o2_o2_cia.zig` |
| 1 | `src/output/instrument_response.zig` |
| 1 | `src/output/atmospheric_budget.zig` |
| 1 | `src/input/reference_data/solar_irradiance.zig` |
| 1 | `src/input/reference/rayleigh.zig` |
| 1 | `src/input/atmosphere/fraction_control.zig` |
| 1 | `src/forward_model/optical_properties/state_build/shared_geometry.zig` |
| 1 | `src/forward_model/optical_properties/state_build/operational_o2.zig` |
| 1 | `src/forward_model/optical_properties/state_build/builder.zig` |
| 1 | `src/forward_model/optical_properties/shared/band_means.zig` |
| 1 | `src/forward_model/instrument_grid/spectral_math/sampling.zig` |
| 1 | `src/forward_model/instrument_grid/spectral_math/convolution.zig` |
| 1 | `src/forward_model/instrument_grid/grid_calculation/forward_input.zig` |
| 1 | `src/forward_model/implementations/instrument/response.zig` |
| 1 | `src/common/math/linalg/small_dense.zig` |

## Measurements Needed Before Editing

- distribution of nominal output sample counts
- distribution of `IntegrationKernel.sample_count` for radiance and irradiance
- adaptive interval count distribution
- support-row cache count and cache-hit rate per wavelength
- particle-scattering-positive row count
- profile spectroscopy `node_count` distribution
- strong-line active `line_count` distribution
- frequency of non-adjacent `RuntimeAttenArray.get` calls
- active-layer density for `rt_active`

## Current Priority Order

1. measure adaptive interval and integration sample-count distributions before
   changing remaining max-capacity scratch
2. prototype LABOS order workspace SoA and active-layer lists
3. generation tags or active lists for repeatedly reset support-row valid caches
4. use total-only spectroscopy cache by default and side-store breakdown arrays
5. inspect whether remaining combined phase rows can use side storage without
   adding scattered source reads
6. measure non-adjacent `RuntimeAttenArray.get` calls before changing
   attenuation storage again
