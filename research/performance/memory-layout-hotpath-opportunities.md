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

### 1. Instrument wavelength plans store maximum kernels inline

Files:
- `src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`
- `src/forward_model/implementations/instrument/types.zig`
- `src/forward_model/implementations/instrument/adaptive_plan.zig`
- `src/forward_model/implementations/instrument/adaptive_cache.zig`
- `src/forward_model/instrument_grid/grid_calculation/wavelength_sampling.zig`

Relevant layout facts:

| struct | size | dominant payload | unused bits |
| --- | ---: | --- | ---: |
| `WavelengthSampling` | 65,592 B | two `IntegrationKernel` values | 0 |
| `IntegrationKernel` | 32,784 B | `[2048]f64` offsets + `[2048]f64` weights | 63 |
| `AdaptiveIntervalPlan` | 49,160 B | `[2048]AdaptiveIntervalDescriptor` | 0 |
| `AdaptiveKernelCache` | 49,184 B | embedded `AdaptiveIntervalPlan` | 63 |

Memory access shape:
- one `WavelengthSampling` is allocated per nominal wavelength plan
- each plan row reserves space for two 2048-sample kernels even when a channel
  is disabled or uses the default small kernel
- adaptive planning also creates fixed 2048-element scratch arrays for sample
  wavelengths and raw weights
- `collectUniqueForwardMisses` scans the plan rows and then builds a hash map
  of cache misses

Potential direction:
- make `WavelengthSampling` a descriptor: nominal/radiance/irradiance
  wavelength plus kernel handles or ranges into side storage
- keep the common small kernel inline, for example 5 offsets and weights
- store large adaptive kernels out-of-band only for rows that need them
- encode disabled integration as a tag or empty range instead of a bool inside
  a 32 KiB object
- deduplicate kernels by handle when radiance or irradiance kernels repeat

Why this is the first memory-layout experiment:
- the current layout is `sample_count * 64.1 KiB`
- if a run has 701 nominal samples, the plan array alone is
  `65,592 * 701 = 45,979,992 B`, or about 43.85 MiB
- most of that footprint is maximum capacity, not active payload
- this is a clean fit for handles, small-inline storage, sparse side storage,
  and boolean-out-of-band strategies

### 2. LABOS attenuation already moved toward lazy storage, but transport fields remain AoS-heavy

Files:
- `src/forward_model/radiative_transfer/labos/attenuation.zig`
- `src/forward_model/radiative_transfer/labos/types.zig`
- `src/forward_model/radiative_transfer/labos/orders.zig`
- `src/forward_model/radiative_transfer/labos/layers.zig`
- `src/forward_model/radiative_transfer/labos/reflectance.zig`

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
| `OrdersWorkspace` | 104 B plus backing slices | `UD*`, active flags | 0 |

Memory access shape:
- historical notes show LABOS layer doubling and order transport dominate
  forward time
- `AttenArray` is the old full matrix form; `RuntimeAttenArray` keeps adjacent
  layer transmittance and top-to-level transmittance and lazily multiplies
  uncommon non-adjacent paths
- `UDField` and `UDLocal` group `U` and `D` together even though transport has
  separate upward and downward passes
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
| `PreparedSublayer` | 3,896 B | three `[151]f64` phase arrays | 48 |
| `SharedOpticalCarrier` | 2,472 B | two `[151]f64` phase arrays | 0 |
| `SharedBoundaryCarrier` | 6,096 B | multiple `[151]f64` phase arrays | 0 |
| `RtmQuadratureLevel` | 7,272 B | phase and phase-jacobian arrays | 0 |
| `SharedRtmSubgrid` | 2,056 B | `[128]f64` altitudes + weights | 0 |
| `WavelengthCarrierCache` | 120 B plus backing slices | valid flags + carrier slice | 0 |

Memory access shape:
- scalar optical-depth values and phase coefficient vectors are stored in the
  same row objects
- `PreparedSublayer` carries aerosol, cloud, and combined phase coefficients
  even though scalar absorption/extinction fields are often the first hot data
  consumed
- `WavelengthCarrierCache` uses `support_row_valid: []bool` and a
  `[]SharedOpticalCarrier` cache for support-row reuse
- `SharedRtmSubgrid` reserves 128 nodes in each value even when the sample count
  is small
- historical notes show phase matrix construction is significant and repeated
  layer-specific fill of phase arrays dominates the PLM basis itself

Potential direction:
- split scalar optical-depth columns from phase-coefficient side storage
- store phase coefficient handles or ranges on rows and keep the actual arrays
  in side storage only for scattering-positive particle support
- use generation tags or active support-row lists for `support_row_valid` when
  the cache is repeatedly reset per wavelength
- make `SharedRtmSubgrid` a small inline buffer with side storage or a workspace
  slice if actual `sample_count` is usually far below 128
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
| `ProfileSpectroscopyCache` | 20,504 B | ten `[256]f64` arrays | 0 |
| `ProfileNodeSpectroscopyCache` | 4,104 B | total values + second derivatives | 0 |
| `ProfileCacheValueWorker` | 2,360 B | `StrongLineWavelengthWindow` | 0 |
| `StrongLineWavelengthWindow` | 2,080 B | fixed line-window payload | 0 |

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
| `StrongLineConvTPState` | 136,208 B | `relaxation_weights[128 * 128]f64` | 0 |

Memory access shape:
- per-line arrays are 1 KiB each, but the relaxation matrix is 128 KiB by
  itself
- the type carries maximum strong-line sidecar capacity independent of active
  `line_count`
- `weightAt` indexes by `row * line_count + col`, so active payload is logically
  dense only for `line_count * line_count`

Potential direction:
- store relaxation weights as dynamic `line_count * line_count` side storage
  when strong-line counts are normally below the maximum
- if the physical matrix has sparse or triangular access, encode only the used
  coefficients
- pass large convolution state by pointer in hot calls to avoid value copies
- measure strong-line count distribution first; this is a capacity waste only
  when active counts are well below 128

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

1. compact wavelength plan and integration-kernel storage
2. split optical carrier scalar state from phase coefficient side storage
3. prototype LABOS order workspace SoA and active-layer lists
4. use total-only spectroscopy cache by default and side-store breakdown arrays
5. right-size strong-line relaxation weights
6. generation tags or active lists for repeatedly reset valid-bit caches
