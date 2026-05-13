# O2 A OE Inter-Iteration Hillclimb

This note records the May 2026 audit of repeated work in the session-backed
O2 A optimal-estimation path.

## Evidence

The retained benchmark artifact is
`validation/outputs/optimal_estimation/zdisamar_o2a_slow_rtm_jacobian_benchmark.json`.
The current slow retained case reports:

- retrieval loop wall time: 3.142969 s
- retrieval iteration RTM plus Jacobian: 3.142008 s
- deferred final-state evaluation when requested: 1.311871 s
- remaining retrieval work: 0.000436 s

The session cache trace shows that all retrieval iterations hit the persistent
session caches:

- wavelength plan: 3 hits, 0 misses
- forward-miss list: 3 hits, 0 misses
- profile spectroscopy cache: 3 hits, 0 misses
- cached forward-miss/profile spectroscopy count: 3736

The lazy final-state evaluation also hits those caches once when requested. This
means the slow case is not repeatedly rebuilding the wavelength sampling plan,
forward-miss list, or profile spectroscopy caches between OE iterations.

The traced native Jacobian sweep is
`research/performance/tracing/output/o2a-jacobian-trace/summary.json`. For the
two-state aerosol Jacobian variant, the dominant native costs remain:

- RTM-only wall time: 2.437257 s
- two-state aerosol Jacobian wall time: 3.063149 s
- aerosol optical-depth-only Jacobian wall time: 2.845655 s
- aerosol layer-pressure-only Jacobian wall time: 2.787352 s
- result copy time: 0.000007 s for the two-state variant

## Conclusions

The main repeated inter-iteration work still visible from Python is not the
solver update, output copying, reflectance-Jacobian conversion, wavelength-plan
construction, or spectroscopy-cache construction. Those costs are small or
already cached.

The large repeated work is the physical RTM and Jacobian itself. In the current
algorithm each accepted state requires a full RTM-plus-Jacobian evaluation.
After convergence, exact final-state plots need a final-state RTM-plus-Jacobian
evaluation because the plotting surface uses final
reflectance, residuals, and final reflectance Jacobians. That work is now lazy:
retrieval callers that only need the state and diagnostics return before this
extra native evaluation, while plot consumers still compute the exact final
state product on demand.

The remaining inter-iteration prepare cost is measurable but small: repeated
prepare is about 15 ms per evaluation in the slow benchmark, mostly optical
setup. Caching or mutating optical state may be worth revisiting later, but it
is around one to two percent of a slow RTM-plus-Jacobian call
and would need careful parity coverage.

## Rejected Direction

A borrowed C result view for session-backed OE was tested to avoid cloning the
native product before Python copies arrays. Sequential benchmark runs did not
show a stable improvement, and the native trace reports result copy around
0.000007 s for the two-state Jacobian variant. The borrowed-view path was
removed rather than adding C ABI surface area for a non-bottleneck.

## Current Priority

Further speedups should target native LABOS work:

1. reduce repeated RT layer build work across nearby aerosol states,
2. reduce orders work inside the RTM samples,
3. reduce aerosol optical-depth and layer-pressure Jacobian weighting work,
4. only then revisit optical-state mutation or caching.
