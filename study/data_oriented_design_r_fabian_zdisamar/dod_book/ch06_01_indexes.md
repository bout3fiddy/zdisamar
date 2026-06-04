# Ch. 6.1 - Indexes (p113)

Source: [Data-Oriented Design online book, "Indexes"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00710000000000000000) (printed-book p113).

Summary: Fabian treats an index as a remembered answer to a question the
program asks often. The index costs extra space and upkeep, so it is worth
building when repeated searching has become a real cost.

The origin is database management systems. Indexes were built after a query had
proved important enough, and the stored answer could be updated as the tables
changed. Fabian brings that feedback loop into game data instead of treating
indexes as clever structures written in advance.

Take home: If the same lookup happens again and again, find the positions once
and reuse them. The index should help the repeated step skip search, not replace
the original data.

## Main Lessons

- An index is a helper list that saves repeated searching.
  Build it once when the same lookup will happen many times.
  The important habit is this: do the lookup work once, store the positions,
  then reuse those positions in the repeated loop.

- The index should point to the real data, not replace it.
  If the index stores positions, the values still live in the values array.

  ```zig
  const value = values[index.items[i]];
  ```

  Notice that `index.items[i]` is only a position. The value still comes from
  `values`.

- In the loop that runs many times, use the saved positions directly.
  The loop should not rediscover which result belongs to which input row.

  ```zig
  for (row.result_indices) |result_index| {
      sum += results[result_index].score;
  }
  ```

  Notice that the loop does not search for the result. It uses the saved
  `result_index` and reads the score directly.

## Practical Example

Here is a pattern that searches for a result during every repeated row.

```zig
for (row.result_keys) |result_key| {
    const result_index = findResultIndex(results, result_key);
    sum += results[result_index].score;
}
```

The compiler output below is generated machine code. It makes the repeated
result-key search from the code above visible.

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested key
ldr     d2, [x2, x11, lsl #3]  ; load candidate result key
fcmp    d2, d1                 ; compare candidate with requested value
b.eq    LBB11_7                ; branch when the search finds a match
```

This shows that the repeated loop contains a second loop that searches keys
before it can read the score.

A better approach stores the result positions during preparation, then reuses
them in the repeated loop.

```zig
for (row.result_indices) |result_index| {
    sum += results[result_index].score;
}
```

The first loop searches during every repeated row. The better loop pays that
lookup earlier and stores the result index.

The generated output for the better approach is easier to read.

```llvm
%10 = load i32, ptr %scevgep
%13 = load double, ptr %12
%14 = fadd double %.0810, %13
```

The matching machine code shows the saved-index load.

```asm
ldr     w11, [x1, x9, lsl #2]  ; load a saved u32 result index
ldr     d1, [x2, w11, uxtw #3] ; load the f64 score at results[result_index]
fadd    d0, d0, d1             ; add the score into the total
```

The loop uses a saved position, then reads the result. It does not search for
the result inside the repeated loop.

A benchmark for prepared indexes showed they were `803.65x` faster than
linear search, with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for `ForwardMissPlan`.
- Read [`src/forward_model/radiative_transfer/labos/workspace.zig`](../../../src/forward_model/radiative_transfer/labos/workspace.zig)
  for cache keys and reuse reporting.
