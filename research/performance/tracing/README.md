# Tracy Forward-Model Tracing

This folder owns the Tracy/ztracy tracing workflow for the O2 A forward-model
performance investigation.

## Capture

From the repo root:

```sh
research/performance/tracing/capture-tracy-forward-model.sh
```

The script builds the LABOS bottleneck trace executable with:

```sh
zig build labos-bottleneck-trace -Denable-ztracy=true -Dtrace-optimize=ReleaseFast
```

`-Denable-ztracy=true` always enables the full nested forward/LABOS zone set.
There is no shallow tracing mode.

## Output

Generated trace outputs are written under:

```text
research/performance/tracing/output/
```

The retained JSON summary is a coarse sanity check. The detailed phase, nesting,
overlap, and per-thread view is the `.tracy` capture opened in `tracy-profiler`.

## Lauka PMU Counters

Lauka records Apple Silicon PMU counters around a command. Use it for aggregate
hardware-counter evidence; keep using Tracy when you need the timeline, nesting,
overlap, and per-thread view.

From the repo root:

```sh
research/performance/tracing/record-lauka-forward-model.sh
```

The default counter set is restricted to counters reported as supported by
`lauka counters --details` on the current Apple Silicon machine:

```text
fixed_cycles,fixed_instructions,arm_l1d_cache_refill,arm_l1d_cache,arm_br_mis_pred,arm_br_pred
```

The script builds the same O2 A LABOS forward harness in `ReleaseFast`, but
without ztracy:

```sh
zig build labos-bottleneck-trace-bin -Dtrace-optimize=ReleaseFast
```

It then records the forward-model executable with Lauka. The wrapper is
forward-only: it does not run the optimal-estimation retrieval loop.

Lauka must be on `PATH`, and on Apple Silicon it normally needs `sudo` for PMU
counters. Pass `--no-sudo` only if your local Lauka setup does not require it.

Generated Lauka outputs are written under:

```text
research/performance/tracing/output/lauka-forward/
```
