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
  If the index stores positions, the wavelength values still live in the
  wavelength array.

  ```zig
  const wavelength = high_res_wavelengths[sample_index.items[i]];
  ```

  Notice that `sample_index.items[i]` is only a position. The wavelength
  value still comes from `high_res_wavelengths`.

- In the loop that runs many times, use the saved positions directly.
  The loop should not rediscover which result belongs to which sample.

  ```zig
  for (row.sample_indices) |result_index| {
      sum += forward_results[result_index].radiance;
  }
  ```

  Notice that the loop does not search for the result. It uses the saved
  `result_index` and reads the radiance directly.

## Code Material

The code material keeps miss rows next to the packed indexes they point into:

```zig
const ForwardMissPlan = struct {
    rows: []const MissRow,
    // Packed result indexes for all rows.
    sample_indices: []const usize,
};

fn samplesFor(plan: ForwardMissPlan, row_index: usize) []const usize {
    const row = plan.rows[row_index];
    // The saved start/count chooses this row's indexes.
    return plan.sample_indices[row.start .. row.start + row.count];
}
```

Notice that `MissRow` stores `start` and `count`. That lets the function
return the saved sample indexes for one nominal wavelength without searching.

Each row's `start` and `count` point into `sample_indices`. If `rows` and
`sample_indices` are passed around separately, it becomes easy to pair a row
list with the wrong `sample_indices` list and read the wrong samples.


## Practical Example

Here is a pattern that searches for a result during every integration row.

```zig
for (row.sample_wavelengths) |wavelength_nm| {
    const result_index = findResultIndex(forward_results, wavelength_nm);
    sum += forward_results[result_index].radiance;
}
```

The compiler output below is generated machine code. It makes the repeated
wavelength search from the code above visible.

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested wavelength
ldr     d2, [x2, x11, lsl #3]  ; load candidate result wavelength
fcmp    d2, d1                 ; compare candidate with requested value
b.eq    LBB11_7                ; branch when the search finds a match
```

This shows that the integration loop contains a second loop that searches
wavelengths before it can read radiance.

A better approach stores the result positions during preparation, then reuses
them in the repeated loop.

```zig
for (row.sample_indices) |result_index| {
    sum += forward_results[result_index].radiance;
}
```

The first loop searches during every integration row. The better loop pays that
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
ldr     d1, [x2, x11]          ; load the radiance f64 at that computed result address
fadd    d0, d0, d1             ; add the radiance into the integration total
```

The loop uses a saved position, then reads the result. It does not search for
the result inside the repeated integration loop.

A benchmark for prepared indexes showed they were `803.65x` faster than
linear search, with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for `ForwardMissPlan`.
- Read [`src/forward_model/radiative_transfer/labos/workspace.zig`](../../../src/forward_model/radiative_transfer/labos/workspace.zig)
  for cache keys and reuse reporting.
