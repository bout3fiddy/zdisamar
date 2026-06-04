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

  fn buildLayerTables(layers: []const Layer, table: LayerTables) void {
      for (layers, table.optical_depth, table.source) |layer, *tau, *src| {
          // Split the larger layer row into the columns later loops read.
          tau.* = layer.optical_depth;
          src.* = layer.source;
      }
  }

  fn sumOpticalDepth(table: LayerTables) f64 {
      var total: f64 = 0;
      for (table.optical_depth) |tau| {
          // This loop reads optical depth and does not touch source.
          total += tau;
      }
      return total;
  }

  fn sumSourceContribution(table: LayerTables) f64 {
      var total: f64 = 0;
      for (table.optical_depth, table.source) |tau, src| {
          // This loop reads aligned columns from the same prepared table.
          total += tau * src;
      }
      return total;
  }

  fn sumPreparedOpticalDepth(layers: []const Layer, table: LayerTables) f64 {
      buildLayerTables(layers, table);
      return sumOpticalDepth(table);
  }
  ```

  Notice that `buildLayerTables` splits larger layer rows into columns.
  `sumPreparedOpticalDepth` then passes the filled table to
  `sumOpticalDepth`, which reads only `table.optical_depth`.
  `sumSourceContribution` shows the other case: a loop can read two aligned
  columns from the same table when it needs both values.

  The columns could be passed as separate slices, but their lengths and order
  still have to match. If one column is filtered or reordered alone, optical
  depth for one layer can line up with source data from another. `LayerTables`
  keeps the columns together while still allowing loops to read only one column.

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
