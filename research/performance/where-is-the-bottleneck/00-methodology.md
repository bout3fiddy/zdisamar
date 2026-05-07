# 00. Methodology

The trace harness has two jobs:

1. keep normal forward-model builds clean;
2. explain the current O2 A wall by descending from major sections to repeated primitives.

## Build Gate

The trace is controlled by `enable_labos_trace`. In [build.zig](../../../build.zig#L57-L65), normal modules receive `enable_labos_trace=false`, while the trace executable receives a separate options module with `enable_labos_trace=true`.

```zig
const build_options = b.addOptions();
build_options.addOption(bool, "enable_labos_trace", false);

const trace_build_options = b.addOptions();
trace_build_options.addOption(bool, "enable_labos_trace", true);
```

When tracing is disabled, trace references become zero-sized types in [performance_trace.zig](../../../src/forward_model/performance_trace.zig#L9-L17):

```zig
pub const RunRef = if (enabled) ?*Run else void;
pub const WorkerRef = if (enabled) ?*Worker else void;

comptime {
    if (!enabled) {
        if (@sizeOf(RunRef) != 0) @compileError("disabled trace run references must remain zero-sized");
        if (@sizeOf(WorkerRef) != 0) @compileError("disabled trace worker references must remain zero-sized");
    }
}
```

That matters because `Implementations`, LABOS workspace state, and orders workspace state sit on the forward path. The normal build should not carry an extra trace pointer or runtime trace sink just because the research harness exists; the compile-time size checks are there to catch that kind of regression.

## Timing Scopes

The O2 A forward path parallelizes high-resolution radiance samples across worker threads. For that reason the artifacts report two different quantities:

- **wall time**: elapsed time seen by the caller;
- **worker CPU time**: accumulated time inside worker-local traced sections.

This is why worker percentages can exceed 100% of wall time. For example, the retained run measured `1.724581500 s` of forward wall but `9.450074 s` of aggregate LABOS worker CPU time across 10 workers.

## Simple Python Shape

The trace is designed to become a no-op when disabled:

```python
TRACE_ENABLED = False


class Trace:
    def add(self, section, seconds):
        if not TRACE_ENABLED:
            return
        print(section, seconds)


trace = Trace()
trace.add("labos.rt_layer_build", 6.497375)  # disabled: does nothing
```

In Zig this is stronger than a runtime `if`: disabled trace references become zero-sized types, so hot structs do not carry trace pointers.

## Measurement Files

The trace executable writes `summary.json`, `sections.csv`, `counters.csv`, and `worker_sections.csv`. `zig build bench` writes `labos_kernel_bench.txt`. The summarizer combines the trace counters and kernel timings into `primitive_estimates.csv` and `rollup.json`.

The top-level summary writer is in [labos_bottleneck_trace_cli.zig](../../../src/validation/performance/labos_bottleneck_trace_cli.zig#L120-L180):

```zig
const labos_cpu_ns = trace.totalWorkerSectionNs(.labos_execute);
const rt_layer_cpu_ns = trace.totalWorkerSectionNs(.rt_layer_build);
const orders_cpu_ns = trace.totalWorkerSectionNs(.orders_total);

try writer.interface.print(
    \\  "high_resolution_misses": {},
    \\  "fourier_terms": {},
    \\  "layer_visits": {},
    \\  "doubled_layers": {},
    \\  "doubling_steps": {},
    \\  "labos_execute_cpu_ns": {},
    \\  "rt_layer_build_cpu_ns": {},
    \\  "orders_cpu_ns": {}
);
```

The trace is not used as a correctness oracle. `zig build check` still verifies the normal disabled-trace build.
