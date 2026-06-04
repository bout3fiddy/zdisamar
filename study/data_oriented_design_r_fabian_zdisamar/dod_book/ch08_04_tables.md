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
  If the code needs to do the same thing for every item, an item list is easy
  to read and easy to loop over.

  ```zig
  for (items) |item| {
      total += item.amount;
  }
  ```

  Notice that the loop reads one item after another. A plain item list
  matches that access pattern.


- Split fields only when that helps the loop.
  If one loop reads only `amount`, keeping amounts together can help. If the
  loop always needs the full item, splitting may not help.

  ```zig
  const ItemTables = struct {
      amount: []const f64,
      weight: []const f64,
  };

  fn buildItemTables(items: []const Item, table: ItemTables) void {
      for (items, table.amount, table.weight) |item, *amount, *weight| {
          // Split the larger item row into the columns later loops read.
          amount.* = item.amount;
          weight.* = item.weight;
      }
  }

  fn sumAmounts(table: ItemTables) f64 {
      var total: f64 = 0;
      for (table.amount) |amount| {
          // This loop reads amount and does not touch weight.
          total += amount;
      }
      return total;
  }

  fn sumWeightedAmounts(table: ItemTables) f64 {
      var total: f64 = 0;
      for (table.amount, table.weight) |amount, weight| {
          // This loop reads aligned columns from the same prepared table.
          total += amount * weight;
      }
      return total;
  }

  buildItemTables(items, table);
  const total_amount = sumAmounts(table);
  const weighted_total = sumWeightedAmounts(table);
  ```

  Notice that `buildItemTables` splits larger item rows into columns.
  The next two calls show why the table exists: one loop reads only
  `table.amount`, while another loop reads `table.amount` and `table.weight`
  together.

  The columns could be passed as separate slices, but their lengths and order
  still have to match. If one column is filtered or reordered alone, amount
  data for one item can line up with weight data from another. `ItemTables`
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
for (items) |item| {
    total += item.amount;
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
for (amounts) |amount| {
    total += amount;
}
```

The first loop uses a row table even though it only needs one column. The better
loop stores that one repeated value as the thing the loop walks.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d2          ; add another loaded lane into the running total
```

A column loop walks contiguous numeric values instead of striding through larger
rows.

A benchmark for a separate `[]f64` amount column showed it was `1.49x`
faster than reading the field out of full rows, with the same checksum. That is
why the table layout choice can matter.

## zdisamar Reading Notes

- Read [`src/forward_model/optical_properties/state_build/prepared_state.zig`](../../../src/forward_model/optical_properties/state_build/prepared_state.zig)
  for the prepared optical table.
- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for tables and compact references used by convolution planning.
