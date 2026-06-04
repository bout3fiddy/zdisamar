# Ch. 6.2 - Data-Oriented Lookup (p115)

Source: [Data-Oriented Design online book, "Data-oriented Lookup"](https://www.dataorienteddesign.com/dodbook/node7.html#SECTION00720000000000000000) (printed-book p115).

Summary: Search narrow key arrays so lookup code does not pull full payload rows into the search loop.

## Main Lessons

- Search only the values needed for the search.
  If you search by time, keep the times in a separate array so the search does
  not pull full payload structs into memory.

  ```zig
  const KeyTable = struct {
      times: []const f32,
      payloads: []const KeyPayload,
  };
  ```

  What to notice: `times` is separate from `payloads`. Searching by time reads
  only the small time values.

- Find the position first, then read the larger data once.
  The search loop should touch small key values. After it finds the index, it
  can fetch the full payload.

  ```zig
  const index = lowerBound(table.times, t);
  return table.payloads[index];
  ```

  What to notice: the payload is read after the index is known. The search does
  not repeatedly load full payload rows.

- If the same search is still too slow, add one more helper table.
  The helper table jumps close to the answer before doing the small local search.

  ```zig
  const block = table.first_stage[coarseIndex(t)];
  const index = linearSearch(table.times[block.start..block.end], t);
  ```

  What to notice: `first_stage` chooses a smaller range. The final search only
  scans that range.

  Zig syntax note: `table.times[block.start..block.end]` passes only part of the
  `times` slice into `linearSearch`.

## Code Material

Fabian gives animation-key lookup listings: first binary search through full key
objects, then separate key times from key payloads, then add a small pre-index
using otherwise spare cache-line space. Adapted:

```zig
const KeyPayload = struct {
    translation: Vec3,
    scale: Vec3,
    rotation: Quat,
};

const KeyTable = struct {
    times: []const f32,
    payloads: []const KeyPayload,

    fn find(self: KeyTable, t: f32) KeyPayload {
        const index = lowerBound(self.times, t);
        return self.payloads[index];
    }
};

const IndexedKeyTable = struct {
    times: []const f32,
    payloads: []const KeyPayload,
    first_stage: [11]f32,

    fn find(self: IndexedKeyTable, t: f32) KeyPayload {
        const block = firstStageBlock(self.first_stage, t);
        const index = linearSearchBlock(self.times, block, t);
        return self.payloads[index];
    }
};
```

What to notice: `times` is searched first because it is the small lookup data.
`payloads` is read only after the index is found. `first_stage` is an extra
helper that narrows the search range.

## Compiler Note

Chapter example tied to this note:

```zig
const index = lowerBound(table.times, t);
return table.payloads[index];
```

Wrong pattern:

```zig
for (table.payloads) |payload| {
    if (payload.time >= t) return payload;
}
```

Better pattern:

```zig
const index = lowerBound(table.times, t);
return table.payloads[index];
```

Why this contrast matters: the wrong version reads payload rows while it is only
trying to answer "which time?". The better version searches the small key array
first, then reads one payload.

Wrong-pattern compiler artifact from
[`lookupPayloadLinear`](codegen/dod_codegen_examples.zig):

```asm
ldur    d0, [x8, #-16]  ; load the time field from a 32-byte payload row
fcmp    d0, d1          ; compare payload.time with the search key
b.ge    LBB14_5         ; branch when this payload row matches
add     x8, x8, #32     ; move to the next full payload row
```

What goes wrong: the search walks full payload rows even though it only needs
the key.

Better-pattern compiler artifact from
[`lowerBound`](codegen/dod_codegen_examples.zig):

```llvm
%7 = load double, ptr %6
%8 = fcmp olt double %7, %2
%.17 = select i1 %8, i64 %9, i64 %.068
```

What this proves: the search loop loads only the key array. It does not load the
payload rows while searching.

Benchmark evidence from the related index test: using prepared indexes was
`803.65x` faster than repeated linear search. This proves the value of moving
lookup work out of the repeated path.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- The radiance path uses precomputed result indexes so integration reads dense
  arrays instead of searching wavelengths inside the nominal loop.
