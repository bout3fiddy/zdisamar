# Ch. 9.7 - False Sharing (p169)

Source: [Data-Oriented Design online book, "False sharing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001070000000000000000) (printed-book p169).

Summary: Fabian describes false sharing as independent threads slowing each
other down by repeatedly writing different addresses that live on the same cache
line. He also warns not to assume this is the problem without evidence.

This is another place where he describes the experimental process: trying to
reproduce false sharing in trivial examples only showed the effect after
turning optimizations off. That failure is part of the lesson: validate that the
suspected hardware problem is real before and after the change.

Take home: Give workers separate memory while they work so threads do not keep
invalidating the same cache line. `zdisamar` worker code should accumulate in
local or worker-owned storage, then combine results after checking scaling
behavior.

## Main Lessons

- Give each worker its own scratch area.
  Workers should not fight over the same output memory while they are doing
  their main work.

  ```zig
  const slice = worker_scratch[worker_id];
  try fillWorkerMisses(range, slice);
  ```

  What to notice: each worker chooses its own scratch slice with `worker_id`.
  The main work writes into that worker's slice.

  Zig syntax note: `worker_scratch[worker_id]` indexes the scratch storage for
  the current worker.

- Add into a local variable first.
  Write the worker's final answer once, after the loop is done.

  ```zig
  var local_sum: f64 = 0;
  for (range) |i| local_sum += values[i];
  partial_sums[worker_id] = local_sum;
  ```

  What to notice: the loop updates `local_sum`, which belongs to one worker.
  Shared memory is written once at the end.

- Do not guess that false sharing is the problem.
  First compare one worker, two workers, four workers, and so on.

## Code Material

Fabian gives an OpenMP example contrasting per-thread shared slots with a local
accumulator. Adapted:

```zig
fn workerSum(range: Range, values: []const f64) f64 {
    var local: f64 = 0;
    for (range.start..range.end) |i| {
        local += values[i];
    }
    return local;
}

fn reduceWorkerSums(partials: []const f64) f64 {
    var total: f64 = 0;
    for (partials) |value| total += value;
    return total;
}
```

What to notice: each worker returns one local sum. The shared combine step
happens after the worker loop, not on every item.

## Compiler Note

Chapter example tied to this note:

```zig
var local_sum: f64 = 0;
for (range) |i| local_sum += values[i];
partial_sums[worker_id] = local_sum;
```

Wrong pattern:

```zig
for (range) |i| {
    partial_sums[worker_id] += values[i];
}
```

Better pattern:

```zig
var local_sum: f64 = 0;
for (range) |i| local_sum += values[i];
partial_sums[worker_id] = local_sum;
```

Why this contrast matters: the wrong version writes to shared result storage on
every item. The better version accumulates in a local variable and writes the
worker result once.

Wrong-pattern compiler artifact from
[`workerWriteEveryItem`](codegen/dod_codegen_examples.zig):

```asm
ldr     d1, [x9], #8  ; load one input value
fadd    d0, d0, d1    ; update the running sum
str     d0, [x1]      ; write partial sum storage every item
b.lo    LBB21_2       ; repeat the load/add/store loop
```

What goes wrong: the repeated loop stores to shared result memory on every item.
In a real multi-worker run, that can create false sharing if workers write near
each other.

Better-pattern compiler artifact from `workerSum`:

```asm
ldp     q1, q2, [x10, #-32]  ; load two vector registers of input values
fadd    d0, d0, d1           ; add one loaded f64 lane into local accumulator d0
fadd    d0, d0, d3           ; add another loaded f64 lane into local accumulator d0
```

What this proves: the repeated loop loads values and accumulates in register
`d0`. There is no store to shared memory inside the loop body. That supports the
lesson: write the worker result once after local accumulation.

Benchmark evidence: local accumulation was `4.22x` faster than forcing a shared
slot write on every item, with the same checksum. This is a single-threaded
microbenchmark, so it proves the cost of repeated stores, not the full
multi-worker false-sharing cost.

## zdisamar Reading Notes

- Read worker scratch ownership in
  [`src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig).
- Read scheduling policy in
  [`src/forward_model/work_partition.zig`](../../../src/forward_model/work_partition.zig).
