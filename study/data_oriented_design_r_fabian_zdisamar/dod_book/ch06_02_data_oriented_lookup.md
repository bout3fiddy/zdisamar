# Ch. 6.2 - Data-Oriented Lookup (p115)

Source: [Data-Oriented Design online book, "Data-oriented Lookup"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00720000000000000000) (printed-book p115).

Summary: Fabian's lookup lesson is to search only the small data needed to make
the decision. If the search is by time, search the times first; do not drag the
full record into memory for every comparison.

His concrete example is animation-key lookup. He first rewrites a search over
full animation records, then goes further because console work on the PS3 and
Xbox 360 made wasted memory loading a visible cost. The search needed the key,
not every value attached to the key.

Take home: Separate keys from larger records when the key is all the search
needs. Find the position first, then fetch the larger data once.

## Main Lessons

- Search only the values needed for the search.
  If you search by time, keep the times in a separate array so the search does
  not pull full payload structs into memory.

  ```zig
  const KeyTable = struct {
      times: []const f32,
      payloads: []const KeyPayload,
  };

  fn findPayload(table: KeyTable, t: f32) KeyPayload {
      // Search compact keys first, then read one larger payload.
      const index = lowerBound(table.times, t);
      return table.payloads[index];
  }
  ```

  Notice that `findPayload` searches the small `times` array first. It reads
  one payload only after the index is known.

  `times` and `payloads` are separate arrays, but they are still one table. The
  index found in `times` must be used on `payloads`. Keeping both arrays in
  `KeyTable` prevents code from searching one table and reading another.

- Find the position first, then read the larger data once.
  The search loop should touch small key values. After it finds the index, it
  can fetch the full payload.

  ```zig
  const index = lowerBound(table.times, t);
  return table.payloads[index];
  ```

  Notice that the payload is read after the index is known. The search does
  not repeatedly load full payload rows.

- If the same search is still too slow, add one more helper table.
  The helper table jumps close to the answer before doing the small local search.

  ```zig
  const block = table.first_stage[coarseIndex(t)];
  const index = linearSearch(table.times[block.start..block.end], t);
  ```

  Notice that `first_stage` chooses a smaller range. The final search only
  scans that range.


## Code Material

The code material separates lookup keys from payloads, then adds a small coarse
index:

```zig
const KeyPayload = struct {
    // Larger data returned after a time key has found one row.
    translation: Vec3,
    scale: Vec3,
    rotation: Quat,
};

const KeyTable = struct {
    // Search the compact time column first.
    times: []const f32,
    payloads: []const KeyPayload,

    fn find(self: KeyTable, t: f32) KeyPayload {
        const index = lowerBound(self.times, t);
        // Read the payload only after the lookup chooses an index.
        return self.payloads[index];
    }
};

const IndexedKeyTable = struct {
    times: []const f32,
    payloads: []const KeyPayload,
    // Coarse time index used to narrow the final search.
    first_stage: [11]f32,

    fn find(self: IndexedKeyTable, t: f32) KeyPayload {
        const block = firstStageBlock(self.first_stage, t);
        const index = linearSearchBlock(self.times, block, t);
        return self.payloads[index];
    }
};
```

Notice that `times` is searched first because it is the small lookup data.
`payloads` is read only after the index is found. `first_stage` is an extra
helper that narrows the search range.

The `times` column and `payloads` column have to stay in the same order. If
helpers accepted those columns separately, a caller could pass mismatched slices
and get a `payloads` entry for the wrong `times` entry. The table keeps the
paired columns together.

## Practical Example

Here is a pattern that searches full payload rows even though the search key is
only `payload.time`.

```zig
for (table.payloads) |payload| {
    if (payload.time >= t) return payload;
}
```

The compiler output below is generated machine code. It makes the full-row
stride and time-field comparison from the code above visible.

```asm
ldur    d0, [x8, #-16]  ; load the time field from a 32-byte payload row
fcmp    d0, d1          ; compare payload.time with the search key
b.ge    LBB14_5         ; branch when this payload row matches
add     x8, x8, #32     ; move to the next full payload row
```

This shows that the search walks full payload rows even though it only needs
the key.

A better approach searches the time keys first, then fetches one payload.

```zig
const index = lowerBound(table.times, t);
return table.payloads[index];
```

The first loop reads payload rows while it is only trying to answer "which
time?". The better loop searches the small key array first, then reads one
payload.

The generated output for the better approach is easier to read.

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

The search loop loads only the key array. It does not load the payload rows
while searching.

A benchmark for prepared indexes showed they were `803.65x` faster than
repeated linear search. That is the value of moving lookup work out of the
repeated path.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- The radiance path uses precomputed result indexes so integration reads dense
  arrays instead of searching wavelengths inside the nominal loop.
