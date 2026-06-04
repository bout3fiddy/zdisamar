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
  One order can add several line items, while another order may add only one.

  ```zig
  for (orders) |order| {
      try appendLineItems(order, &line_items);
  }
  ```

  Notice that `line_items` is appended to inside the loop. Each order can add a
  different number of line items.

- Store variable-size groups in one big list.
  Each row stores where its group starts and how many items belong to it.

  ```zig
  const GroupRef = struct {
      item_start: u32,
      item_count: u16,
  };

  fn groupItems(ref: GroupRef, items: []const LineItem) []const LineItem {
      // Turn the saved start/count into the line items for this group.
      return items[ref.item_start .. ref.item_start + ref.item_count];
  }
  ```

  Notice that `groupItems` is how the row is used. `GroupRef` stores where the
  line items start and how many to read from the packed item list.

  Passing `item_start` and `item_count` separately is not wrong by itself.
  The problem is that the two values must always change together. If one is
  copied without the other, the range can point at the wrong `items`.
  `GroupRef` keeps the range with the row that uses it.

- A prefix sum turns counts into starting positions.
  If worker 0 wrote 3 items and worker 1 wrote 5 items, worker 1 starts at 3.

  ```zig
  starts[0] = 0;
  for (counts[0 .. counts.len - 1], 1..) |count, i| {
      starts[i] = starts[i - 1] + count;
  }
  ```

  Notice that each start is the previous start plus the previous count.
  Counts become positions.

## Practical Example

Here is a pattern that recomputes the start offset for a group whose length can
change.

```zig
var start: u32 = 0;
for (counts[0..i]) |count| {
    start += count;
}
return line_items[start..][0..counts[i]];
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
return line_items[start..][0..counts[i]];
```

The first version re-adds counts for every query. The better version builds
`starts` once, then each query reads one saved start position.

The generated output for the better approach is easier to read.

```llvm
%6 = load i32, ptr %lsr.iv
store i32 %7, ptr %lsr.iv19
```

Building `starts` is a real setup pass. It reads `counts` and writes `starts`.

A benchmark for prepared starts showed querying them was `2039.62x` faster than
re-summing counts for every query, with the same checksum. That is why the setup
pass is worth it when reused.

## zdisamar Reading Notes

- [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  uses inline samples for the common case and side storage for larger kernels.
- [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig)
  is the main reusable pool/workspace surface.
