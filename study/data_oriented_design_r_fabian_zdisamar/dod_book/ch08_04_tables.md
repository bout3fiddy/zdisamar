# Ch. 8.4 - Tables (p146)

Source: [Data-Oriented Design online book, "Tables"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00940000000000000000) (printed-book p146).

Summary: Fabian recommends arrays and table-like layouts because most work is
reading arrays, transforming one array into another, or modifying a table in
place. He also warns that structure-of-arrays is not a universal rule; the
right layout follows the access pattern.

He gets there through small measured layout examples: a particle/node update
improves when read and write streams become continuous, but blindly splitting
`x`, `y`, and `z` can make a vector operation load more cache lines. The
anecdote is a warning against turning data-oriented design into a recipe.

Take home: Use table-like arrays for repeated row or column work so loops read
memory in a predictable shape. `zdisamar` should choose row, column, join, or
cache shapes based on what each loop really reads and writes.

## Main Lessons

- A list is often the clearest shape for repeated work.
  If the code needs to do the same thing for every layer, a layer list is easy
  to read and easy to loop over.

  ```zig
  for (layers) |layer| {
      total_tau += layer.optical_depth;
  }
  ```

  What to notice: the loop reads one layer after another. A plain layer list
  matches that access pattern.

  Zig syntax note: `|layer|` names the current item in the loop. Each pass
  through the loop gets the next item from `layers`.

- Split fields only when that helps the loop.
  If one loop reads only optical depth, keeping optical depths together can help.
  If the loop always needs the full layer, splitting may not help.

  ```zig
  const LayerTables = struct {
      optical_depth: []const f64,
      source: []const f64,
  };
  ```

  What to notice: `optical_depth` and `source` are separate arrays. This only
  helps if some loops read one without the other.

- Avoid "loop over everything inside another loop" for large data.
  If two lists are sorted by the same id, walk them together instead of scanning
  one whole list for every row in the other.

  ```zig
  while (i < a.len and j < b.len) {
      if (a[i].id == b[j].id) try out.append(join(a[i], b[j]));
      if (a[i].id <= b[j].id) i += 1 else j += 1;
  }
  ```

  What to notice: the code advances through both lists once. It does not scan
  all of `b` for every item in `a`.

## Code Material

Fabian gives listings that move from mixed `pos/velocity` structs to separate
position and velocity streams, then compares merge joins with nested-loop joins.
Adapted:

```zig
const MotionTable = struct {
    positions: []Vec3,
    velocities: []const Vec3,

    fn step(self: MotionTable, dt: f32) void {
        for (self.positions, self.velocities) |*pos, vel| {
            pos.* = pos.* + vel.scale(dt);
        }
    }
};

fn mergeJoin(a: []const RowA, b: []const RowB, out: *ArrayList(Joined)) !void {
    var ia: usize = 0;
    var ib: usize = 0;
    while (ia < a.len and ib < b.len) {
        if (a[ia].id == b[ib].id) {
            try out.append(.{ .a = a[ia], .b = b[ib] });
            ia += 1;
            ib += 1;
        } else if (a[ia].id < b[ib].id) {
            ia += 1;
        } else {
            ib += 1;
        }
    }
}
```

What to notice: `MotionTable.step` writes positions in order while reading
velocities in order. `mergeJoin` walks two sorted lists once instead of nesting
one full scan inside another.

Zig syntax note: `*pos` in the loop captures a pointer to the current position,
so `pos.* = ...` updates the position stored in the array.

## Compiler Note

Chapter example tied to this note:

```zig
for (layers) |layer| {
    total_tau += layer.optical_depth;
}
```

Wrong pattern:

```zig
for (layers) |layer| {
    total_tau += layer.optical_depth;
}
```

Better pattern:

```zig
for (optical_depths) |tau| {
    total_tau += tau;
}
```

Why this contrast matters: the wrong version uses a row table even though the
loop only needs one column. The better version stores that one hot value as the
thing the loop walks.

Wrong-pattern compiler artifact from
[`sumOpticalDepth`](codegen/dod_codegen_examples.zig):

```asm
ldur    d1, [x9, #-48]  ; load one f64 field from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load the same field from the next unrolled row
add     x9, x9, #96     ; advance the row pointer by four 24-byte rows
```

What goes wrong: the compiler does not load unused fields, but the loop still
steps through full 24-byte rows to read one field.

Better-pattern compiler artifact from [`sum`](codegen/dod_codegen_examples.zig):

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

What this proves: a column loop walks contiguous numeric values instead of
striding through larger rows.

Benchmark evidence: reading a separate `[]f64` optical-depth column was `1.49x`
faster than reading the field out of full rows, with the same checksum. That
proves the table layout choice can matter.

## zdisamar Reading Notes

- Read [`src/forward_model/optical_properties/state_build/prepared_state.zig`](../../../src/forward_model/optical_properties/state_build/prepared_state.zig)
  for the prepared optical table.
- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for tables and compact references used by convolution planning.
