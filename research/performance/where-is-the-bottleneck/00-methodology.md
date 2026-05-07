# 00. Methodology

The trace harness has two jobs:

1. keep normal forward-model builds clean;
2. explain the current O2 A wall by descending from major sections to repeated primitives.

## Build Gate

The trace is controlled by `enable_labos_trace`.

Normal build modules set:

```text
enable_labos_trace = false
```

The research executable uses a separate build-options module with:

```text
enable_labos_trace = true
```

When tracing is disabled, trace references use zero-sized types. That matters because `Implementations`, LABOS workspace state, and orders workspace state are hot-path objects. The normal build should not carry an extra trace pointer or runtime branch just because the research harness exists.

## Timing Scopes

The O2 A forward path parallelizes high-resolution radiance samples across worker threads. For that reason the artifacts report two different quantities:

- **wall time**: elapsed time seen by the caller;
- **worker CPU time**: accumulated time inside worker-local traced sections.

This is why worker percentages can exceed 100% of wall time. For example, the retained run measured `1.958912208 s` of forward wall but `11.484103 s` of aggregate LABOS worker CPU time across 10 workers.

## Measurement Files

The trace executable writes:

```text
summary.json
sections.csv
counters.csv
worker_sections.csv
```

`zig build bench` writes:

```text
labos_kernel_bench.txt
```

The summarizer combines counters and kernel timings into:

```text
primitive_estimates.csv
rollup.json
```

The trace is not used as a correctness oracle. `zig build check` still verifies the normal disabled-trace build.
