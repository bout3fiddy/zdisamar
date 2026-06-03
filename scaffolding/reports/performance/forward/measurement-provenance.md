# Measurement Provenance

The performance notes contain three kinds of numbers. Keep them separate.

## Current Retained Forward Trace

The current retained trace is the checked-in labos-bottleneck artifact:

```text
scaffolding/instrumentation/trace/evidence/labos-bottleneck/summary.json
```

Those files describe the current baseline forward case. They are the source for
current claims in this folder.

## Historical Checkpoints

The older checkpoint series measured different commits, and some rows used an
older case. Those numbers explain how the implementation got faster; they are
not a current elapsed-time benchmark.

The retained checkpoint table is:

```text
scaffolding/reports/performance/forward/checkpoint-timings.md
```

Use checkpoint numbers only with historical wording such as "this checkpoint
saved" or "this commit moved the forward elapsed time from ... to ...".

## Generated Local Evidence

Some validation and sweep data live under `out/`. Those files are local
generated evidence and are intentionally gitignored. If a claim must survive in
the repository, keep a tracked summary, manifest, plot, or concise markdown note
under `scaffolding/reports/performance/` or `validation/outputs/`.

## Regeneration

Current forward bottleneck trace:

```sh
scaffolding/instrumentation/trace/capture/run-labos-bottleneck-trace.sh
```

Historical checkpoint timing:

```sh
MODE=all OUT=/tmp/zdisamar-perf-checkpoints.tsv \
  scaffolding/reports/performance/forward/run-checkpoint-timings.sh
```
