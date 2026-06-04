# Ch. 9.7 - False Sharing (p169)

Source: [Data-Oriented Design online book, "False sharing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001070000000000000000) (printed-book p169).

Summary: Fabian describes false sharing as a threading problem where workers
touch different values that happen to share one memory block. The values are
different, but the hardware can still make the workers interfere.

This is another place where he describes the experimental process. Trying to
reproduce false sharing in tiny examples only showed the effect after turning
optimizations off. That failure is part of the lesson: check that the suspected
hardware problem is real before and after the change.

Take home: Let each worker write to its own area while it is doing the main
work. Combine shared results after the worker has finished its local loop.

## Main Lessons

- Give each worker its own scratch area.
  Workers should not fight over the same output memory while they are doing
  their main work.

  ```zig
  fn runWorker(range: Range, output: []Miss) !void {
      try fillWorkerMisses(range, output);
  }

  fn workerMisses(range: Range, output: []Miss) ![]const Miss {
      try runWorker(range, output);
      return output;
  }
  ```

  Notice that the worker receives the output area it is allowed to write. The
  main work writes there, not into another worker's output. `workerMisses`
  returns that filled worker slice for the caller to read after `runWorker`
  finishes.


- Add into a local variable first.
  Write the worker's final answer once, after the loop is done.

  ```zig
  var local_sum: f64 = 0;
  for (range) |i| local_sum += values[i];
  partial_sums[worker_id] = local_sum;
  ```

  Notice that the loop updates `local_sum`, which only one worker can see.
  Shared memory is written once at the end.

- Do not guess that false sharing is the problem.
  First compare one worker, two workers, four workers, and so on.

## Practical Example

Here is a pattern that writes each worker's partial result on every item.

```zig
for (range) |i| {
    partial_sums[worker_id] += values[i];
}
```

The compiler output below is generated machine code. It makes the repeated
shared-slot store from the code above visible.

```asm
ldr     d1, [x9], #8  ; load one input value
fadd    d0, d0, d1    ; update the running sum
str     d0, [x1]      ; write partial sum storage every item
b.lo    LBB21_2       ; repeat the load/add/store loop
```

This shows that the repeated loop stores to shared result memory on every item.
In a real multi-worker run, that can create false sharing if workers write near
each other.

A better approach accumulates locally and writes once.

```zig
var local_sum: f64 = 0;
for (range) |i| local_sum += values[i];
partial_sums[worker_id] = local_sum;
```

The first version writes to shared result storage on every item. The better
version accumulates in a local variable and writes the worker result once.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x10, #-32]  ; load two vector registers of input values
fadd    d0, d0, d1           ; add one loaded f64 lane into local accumulator d0
fadd    d0, d0, d3           ; add another loaded f64 lane into local accumulator d0
```

The repeated loop loads values and accumulates in register `d0`. There is no
store to shared memory inside the loop body. That supports the lesson: write the
worker result once after local accumulation.

A benchmark for local accumulation showed it was `4.22x` faster than
forcing a shared slot write on every item, with the same checksum. This is a
single-threaded microbenchmark, so it proves the cost of repeated stores, not
the full multi-worker false-sharing cost.

## zdisamar Reading Notes

- Read worker scratch ownership in
  [`src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_forward.zig).
- Read scheduling policy in
  [`src/forward_model/work_partition.zig`](../../../src/forward_model/work_partition.zig).
