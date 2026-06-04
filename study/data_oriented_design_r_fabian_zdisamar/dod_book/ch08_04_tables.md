# Ch. 8.4 - Tables (p146)

Source: [Data-Oriented Design online book, "Tables"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00940000000000000000) (printed-book p146).

Summary: Fabian recommends lists and table-like layouts because many programs
spend their time reading lists, changing lists, or joining lists. He also warns
that no layout rule is always right.

He gets there through small measured layout examples. A particle or node update
can improve when reads and writes become continuous, but blindly splitting
`x`, `y`, and `z` can make a vector operation load more memory blocks than
before. The anecdote is a warning against turning data-oriented design into a
recipe.

Take home: Choose the layout that matches how the data is used. Keep values
together when they are read together, and split them only when that makes the
common work clearer or faster.

## Main Lessons

- A list is often the clearest shape for repeated work.
  If the code needs to do the same thing for every layer, a layer list is easy
  to read and easy to loop over.

  ```zig
  for (layers) |layer| {
      total_tau += layer.optical_depth;
  }
  ```

  Notice that the loop reads one layer after another. A plain layer list
  matches that access pattern.


- Split fields only when that helps the loop.
  If one loop reads only optical depth, keeping optical depths together can help.
  If the loop always needs the full layer, splitting may not help.

  ```zig
  const LayerTables = struct {
      optical_depth: []const f64,
      source: []const f64,
  };
  ```

  Notice that `optical_depth` and `source` are separate arrays. This only
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

  Notice that the code advances through both lists once. It does not scan
  all of `b` for every item in `a`.

## Code Material

Fabian gives listings that move from mixed `pos/velocity` structs to separate
position and velocity streams, then compares merge joins with nested-loop joins.
Adapted:

```zig
const MotionTable = struct {
    // Position is written in place; velocity is read-only input.
    positions: []Vec3,
    velocities: []const Vec3,

    fn step(self: MotionTable, dt: f32) void {
        for (self.positions, self.velocities) |*pos, vel| {
            // Both lists advance together.
            pos.* = pos.* + vel.scale(dt);
        }
    }
};

fn mergeJoin(a: []const RowA, b: []const RowB, out: *ArrayList(Joined)) !void {
    var ia: usize = 0;
    var ib: usize = 0;
    // The inputs are sorted by id, so one pass can join matching rows.
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

Notice that `MotionTable.step` writes positions in order while reading
velocities in order. `mergeJoin` walks two sorted lists once instead of nesting
one full scan inside another.


## Practical Example

Here is a pattern that stores rows but reads only one field from each row.

```zig
for (layers) |layer| {
    total_tau += layer.optical_depth;
}
```

The compiler output below is generated machine code. It makes the row stride
from the code above visible.

```asm
ldur    d1, [x9, #-48]  ; load one f64 field from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load the same field from the next unrolled row
add     x9, x9, #96     ; advance the row pointer by four 24-byte rows
```

This shows that the compiler does not load unused fields, but the loop still
steps through full 24-byte rows to read one field.

A better approach stores the field the loop reads repeatedly in its own list.

```zig
for (optical_depths) |tau| {
    total_tau += tau;
}
```

The first loop uses a row table even though it only needs one column. The better
loop stores that one repeated value as the thing the loop walks.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

A column loop walks contiguous numeric values instead of striding through larger
rows.

A benchmark for a separate `[]f64` optical-depth column showed it was `1.49x`
faster than reading the field out of full rows, with the same checksum. That is
why the table layout choice can matter.

## zdisamar Reading Notes

- Read [`src/forward_model/optical_properties/state_build/prepared_state.zig`](../../../src/forward_model/optical_properties/state_build/prepared_state.zig)
  for the prepared optical table.
- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for tables and compact references used by convolution planning.
