# Ch. 6.1 - Indexes (p113)

Source: [Data-Oriented Design online book, "Indexes"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00710000000000000000) (printed-book p113).

Summary: Build indexes once so repeated loops use saved positions instead of searching every time.

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

  What to notice: `sample_index.items[i]` is only a position. The wavelength
  value still comes from `high_res_wavelengths`.

- In the loop that runs many times, use the saved positions directly.
  The loop should not rediscover which result belongs to which sample.

  ```zig
  for (row.sample_indices) |result_index| {
      sum += forward_results[result_index].radiance;
  }
  ```

  What to notice: the loop does not search for the result. It uses the saved
  `result_index` and reads the radiance directly.

## Code Material

Fabian's section is conceptual. A direct `zdisamar`-shaped sketch:

```zig
const ForwardMissPlan = struct {
    rows: []const MissRow,
    sample_indices: []const usize,
};

fn samplesFor(plan: ForwardMissPlan, row_index: usize) []const usize {
    const row = plan.rows[row_index];
    return plan.sample_indices[row.start .. row.start + row.count];
}
```

What to notice: `MissRow` stores `start` and `count`. That lets the function
return the saved sample indexes for one nominal wavelength without searching.

Zig syntax note: `a[b .. c]` makes a slice from index `b` up to, but not
including, index `c`.

## Compiler Note

Chapter example tied to this note:

```zig
for (row.sample_indices) |result_index| {
    sum += forward_results[result_index].radiance;
}
```

Wrong pattern:

```zig
for (row.sample_wavelengths) |wavelength_nm| {
    const result_index = findResultIndex(forward_results, wavelength_nm);
    sum += forward_results[result_index].radiance;
}
```

Better pattern:

```zig
for (row.sample_indices) |result_index| {
    sum += forward_results[result_index].radiance;
}
```

Why this contrast matters: the wrong version searches during every integration
row. The better version pays that lookup earlier and stores the result index.

Wrong-pattern compiler artifact from
[`integrateLinearSearch`](codegen/dod_codegen_examples.zig):

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested wavelength
ldr     d2, [x2, x11, lsl #3]  ; load candidate result wavelength
fcmp    d2, d1                 ; compare candidate with requested value
b.eq    LBB11_7                ; branch when the search finds a match
```

What goes wrong: the integration loop contains a second loop that searches
wavelengths before it can read radiance.

Better-pattern compiler artifact from
[`integrateIndexed`](codegen/dod_codegen_examples.zig):

```llvm
%10 = load i32, ptr %scevgep
%13 = load double, ptr %12
%14 = fadd double %.0810, %13
```

Machine code:

```asm
ldr     w11, [x1, x9, lsl #2]  ; load a saved u32 result index
ldr     d1, [x2, x11]          ; load the radiance f64 at that computed result address
fadd    d0, d0, d1             ; add the radiance into the integration total
```

What this proves: the loop uses a saved position, then reads the result. It does
not search for the result inside the repeated integration loop.

Benchmark evidence: prepared indexes were `803.65x` faster than linear search,
with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for `ForwardMissPlan`.
- Read [`src/forward_model/radiative_transfer/labos/workspace.zig`](../../../src/forward_model/radiative_transfer/labos/workspace.zig)
  for cache keys and reuse reporting.
