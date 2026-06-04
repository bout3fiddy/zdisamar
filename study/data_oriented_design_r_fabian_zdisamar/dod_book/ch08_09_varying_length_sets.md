# Ch. 8.9 - Varying Length Sets (p155)

Source: [Data-Oriented Design online book, "Varying length sets"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00990000000000000000) (printed-book p155).

Summary: Fabian explains what happens when one input does not always make one
output. Filters can shrink data, emissions can grow it, and both need a plan
for where the results go.

Fabian comes at this from fixed-size graphics buffers, sorting methods that
count output sizes first, and multi-worker filtering where each worker writes a
private output list before the lists are joined. He then connects the same
problem to deletion, object pools, and worker-owned storage.

Take home: Store variable-size groups with counts, starts, or ranges. That lets
later code find each group directly without guessing or allocating for every
item.

## Main Lessons

- One input row may create zero, one, or many output rows.
  One instrument kernel can add several samples, while another kernel may add
  only one.

  ```zig
  for (kernels) |kernel| {
      try appendSamplesForKernel(kernel, &samples);
  }
  ```

  What to notice: `samples` is appended to inside the loop. Each kernel can add
  a different number of samples.

- Store variable-size groups in one big list.
  Each row stores where its group starts and how many items belong to it.

  ```zig
  const KernelRef = struct {
      sample_start: u32,
      sample_count: u16,
  };
  ```

  What to notice: the row does not store the samples themselves. It stores where
  its samples start and how many to read.

- A prefix sum turns counts into starting positions.
  If worker 0 wrote 3 items and worker 1 wrote 5 items, worker 1 starts at 3.

  ```zig
  starts[0] = 0;
  for (counts[0 .. counts.len - 1], 1..) |count, i| {
      starts[i] = starts[i - 1] + count;
  }
  ```

  What to notice: each start is the previous start plus the previous count.
  Counts become positions.

  Zig syntax note: `counts[0 .. counts.len - 1]` skips the last count.
  `1..` produces indexes starting at 1. The loop reads a count and its matching
  output index together.

## Code Material

Fabian discusses steps that keep some rows, steps that make extra rows, prefix
sums, worker-local output, and pooling. Adapted:

```zig
const KernelRef = struct {
    inline_count: u8,
    inline_samples: [4]Sample,
    side_start: u32,
    side_count: u32,
};

fn samples(ref: KernelRef, side: []const Sample) []const Sample {
    if (ref.inline_count > 0) {
        return ref.inline_samples[0..ref.inline_count];
    }
    return side[ref.side_start .. ref.side_start + ref.side_count];
}

fn prefixStarts(counts: []const usize, starts: []usize) void {
    var total: usize = 0;
    for (counts, starts) |count, *start| {
        start.* = total;
        total += count;
    }
}
```

What to notice: `KernelRef` stores either inline samples or a side-list range.
`prefixStarts` turns per-group counts into start positions for a packed output
list.

Zig syntax note: `ref.inline_samples[0..ref.inline_count]` returns only the
filled part of the fixed-size inline array.

## Practical Example

Here is a pattern that recomputes the start offset for a group whose length can
change.

```zig
var start: u32 = 0;
for (counts[0..i]) |count| {
    start += count;
}
return samples[start..][0..counts[i]];
```

The compiler output below is generated machine code. It makes the repeated
count-summing work from the code above visible.

```asm
ldp     q4, q5, [x8, #-32]  ; load counts for this query
ldp     q6, q7, [x8], #64   ; load more counts and advance
add.4s  v0, v4, v0          ; add counts into a running sum
add.4s  v1, v5, v1          ; keep summing counts for this query
```

This shows that each query spends loop work recomputing the start offset from
earlier counts.

A better approach builds start positions once and reuses them.

```zig
const start = starts[i];
return samples[start..][0..counts[i]];
```

The first version re-adds counts for every query. The better version builds
`starts` once, then each query reads one saved start position.

The generated output for the better approach is easier to read.

```llvm
%6 = load i32, ptr %lsr.iv
store i32 %7, ptr %lsr.iv19
```

Building starts is a real setup pass. It reads counts and writes starts.

A benchmark for prepared starts showed querying them was `2039.62x` faster than
re-summing counts for every query, with the same checksum. That is why the setup
pass is worth it when reused.

## zdisamar Reading Notes

- [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  uses inline samples for the common case and side storage for larger kernels.
- [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig)
  is the main reusable pool/workspace surface.
