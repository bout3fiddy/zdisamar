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
