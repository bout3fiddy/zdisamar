# Tracy Forward-Model Tracing

This folder owns the Tracy/ztracy tracing workflow for the forward-model
performance investigation.

## Capture

From the repo root:

```sh
scaffolding/instrumentation/trace/capture/capture-tracy-forward-model.sh
```

The script builds the LABOS bottleneck trace executable with:

```sh
zig build labos-bottleneck-trace -Denable-ztracy=true -Doptimize=ReleaseFast
```

`-Denable-ztracy=true` always enables the full nested forward/LABOS zone set.
There is no shallow tracing mode.

## Output

Generated trace outputs are written under:

```text
scaffolding/instrumentation/trace/evidence/
```

The retained JSON summary is a coarse sanity check. The detailed phase, nesting,
overlap, and per-thread view is the `.tracy` capture opened in `tracy-profiler`.

## Optimal-Estimation Trace

The OE trace harness is an explicit validation/performance target. It does not
add timing fields to the Python package or C API; normal builds keep the trace
facade disabled.

```sh
zig build optimal-estimation-trace -Doptimize=ReleaseFast -- \
  --output-dir out/optimal-estimation-trace
```

Use Tracy zones for phase breakdown by enabling ztracy on the same target:

```sh
zig build optimal-estimation-trace -Doptimize=ReleaseFast -Denable-ztracy=true -- \
  --output-dir out/optimal-estimation-trace-ztracy
```

The JSON summaries are scratch output under `out/`; they are useful for local
sanity checks, while the timeline capture is the phase evidence.

## Lauka PMU Counters

Lauka records Apple Silicon PMU counters around a command. Use it for aggregate
hardware-counter evidence; keep using Tracy when you need the timeline, nesting,
overlap, and per-thread view.

From the repo root:

```sh
scaffolding/instrumentation/trace/capture/record-lauka-forward-model.sh
```

The script uses the pinned Lauka checkout described in:

```text
scaffolding/instrumentation/trace/capture/lauka.lock
```

If the pinned binary is missing, the script bootstraps Lauka into ignored local
storage under `out/tools/lauka/`. The lock pins a project Lauka fork commit
that contains the child-pid PMU filter fix, so Lauka measures the workload
process instead of Lauka's own wait loop.

The default counter set is restricted to counters reported as supported by
`lauka counters --details` for Apple Silicon PMU collection:

```text
fixed_cycles,fixed_instructions,arm_l1d_cache_refill,arm_l1d_cache,arm_br_mis_pred,arm_br_pred
```

The script builds the same LABOS forward harness in `ReleaseFast`, but
without ztracy:

```sh
zig build labos-bottleneck-trace-bin -Doptimize=ReleaseFast
```

It then records the forward-model executable with Lauka. The wrapper is
forward-only: it does not run the optimal-estimation retrieval loop. It records
both a serial run with `ZDISAMAR_WORKER_LIMIT=1` and a threaded run with the
normal worker count, then writes a compact PMU summary with IPC, L1D miss, and
branch-miss metrics.

Apple Silicon PMU counters normally require `sudo`.

Generated Lauka outputs are written under:

```text
scaffolding/instrumentation/trace/evidence/lauka-forward/
```

Raw Lauka reports are ignored. The compact retained summary is:

```text
scaffolding/instrumentation/trace/evidence/lauka-forward/pmu-summary.json
```
