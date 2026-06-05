# Zig 0.16 Cached Jacobian Boundary

This note captures the retained evidence for the Zig 0.16 migration draft. It
uses the benchmark-shaped O2 A Jacobian case, not the heavier default retained
trace case, because the fast canary regression is in the reused
session/Jacobian boundary.

## Boundary

- Entry point: `SessionCache.spectrum(jacobian=true, states=forward_states)`.
- Trace harness: `labos-bottleneck-trace --case benchmark-jacobian --jacobian`.
- Worker cap: `ZDISAMAR_WORKER_LIMIT=2`, matching `benchmark/run_benchmark_fast.py`.
- Workload: 301 samples, 758 nm to 770 nm, aerosol layer 875 hPa to 925 hPa.
- Output invariant: mean reflectance `0.10950249886516362` on both Zig 0.15.2 and
  Zig 0.16.0 runs.

## Timings

Phase timing disabled for the clean comparison:

| Compiler | Cached runs | Cached central value |
| --- | ---: | ---: |
| Zig 0.15.2 | 10 | 0.257274458 s |
| Zig 0.16.0 | 10 | 0.279688625 s |

The matched trace reproduces the fast canary symptom at about +8.7% on the
cached benchmark-shaped Jacobian boundary. First-run setup is near parity, so
the severe symptom is not input preparation or first-use cache construction.

## Phase Attribution

With phase timing enabled on Zig 0.16.0, the first cached run is dominated by
`forward_prefetch`:

| Phase | Time |
| --- | ---: |
| `forward_prefetch` | 336,864,667 ns |
| `profile_spectroscopy_cache` | 13,500 ns |
| `radiance_cache_integration` | 65,125 ns |
| `irradiance_sampling` | 443,208 ns |
| `jacobian_processing` | 875 ns |

The LABOS counters under that boundary are dominated by layer build and
doubling:

| LABOS counter | Time | Count |
| --- | ---: | ---: |
| `rt_layer_build` | 398,879,446 ns | 3,736 |
| `rt_layer_doubling` | 331,963,076 ns | 104,608 |
| `fourier_loop` | 554,431,278 ns | 3,736 |
| `orders_total` | 144,770,897 ns | 3,736 |

The result-copy and Jacobian postprocessing phases are microsecond or smaller.
The regression is therefore inside the cached forward-prefetch RTM work, with
LABOS layer build/doubling as the dominant measured subphase.

## Codegen Check

The earlier assembly-size hypothesis does not hold for normal product builds.

| Symbol | Zig 0.15.2 | Zig 0.16.0 | Delta |
| --- | ---: | ---: | ---: |
| `doDouble12x10` hot lines | 16,814 | 16,786 | -28 |
| `computeForwardSampleAtWavelengthWithScratch` hot lines | 2,213 | 1,831 | -382 |
| `calcRTlayersIntoWithBasis*` hot lines | 9,692 | 8,883 | -809 |

The trace-only growth in `doDouble12x10` came from phase-timing calls through
`Io.Clock.now`, not from the product executable. The current root cause is a
Zig 0.16 runtime/codegen performance regression in the cached
forward-prefetch/LABOS layer-build boundary, not extra work, result copying,
Jacobian postprocessing, or larger product assembly.
