# Ch. 8.8 - Necessity, Or Not Getting What You Did Not Ask For (p154)

Source: [Data-Oriented Design online book, "Necessity"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00980000000000000000) (printed-book p154).

Summary: Fabian's "necessity" lesson is to avoid carrying data that a task did
not ask for. Large objects often make code load many fields when it only needed
one or two.

The source of the lesson is C++ object practice. Classes can gather multiple
roles, inheritance can add baggage, and a method call can force the machine to
load extra object data before it even knows which data the method will need.

Take home: Give a repeated step only the fields it will use. Optional data
should exist only when a later step will actually read it.

## Main Lessons

- Do not put unused fields in the row used by the loop that runs many times.
  If a loop only reads two fields, make a small row for those two fields.

  ```zig
  const HotItem = struct {
      amount: f64,
      rate: f64,
  };

  fn buildHotItems(items: []const Item, out: []HotItem) void {
      for (items, out) |item, *hot| {
          // Keep only the fields the repeated score loop will read.
          hot.* = .{
              .amount = item.amount,
              .rate = item.rate,
          };
      }
  }

  fn sumScores(hot_items: []const HotItem) f64 {
      var total: f64 = 0;
      for (hot_items) |item| {
          total += item.amount * item.rate;
      }
      return total;
  }

  buildHotItems(items, hot_items);
  const total_score = sumScores(hot_items);
  ```

  Notice that `buildHotItems` does not return a new list. It fills the
  caller-provided `hot_items` slice, and the next line passes that filled slice
  into `sumScores`.

  The simpler-looking alternative is to pass full `Item` rows into `sumScores`.
  That makes the loop carry fields it never reads. `HotItem` is the loop's
  input shape, not a replacement for the full item description.

- Only allocate optional data when a later step will read it.
  Export buffers should exist for export runs, not for every run.

  ```zig
  if (need_export) {
      try storage.ensureExportBuffers(item_count);
  }
  ```

  Notice that the export buffers are created inside the `need_export` branch.
  Runs without export skip them.

- If a feature is disabled, skip the data for that feature.
  A basic run should not build data for an optional report.

  ```zig
  if (!config.write_report) {
      return runBasic(input, workspace);
  }
  ```

  Notice that the basic path returns early. It does not build the data needed
  only by the optional report.

## Practical Example

Here is a pattern that checks whether each item needs extra work inside the
repeated loop.

```zig
for (items) |item| {
    if (item.needs_extra_pass) try runExtraPass(item, workspace);
}
```

The compiler output below is generated machine code. It makes the per-row flag
load and branch from the code above visible.

```asm
ldrb    w12, [x9], #1  ; load one per-row flag
cbz     w12, LBB16_5   ; branch around work when the flag says no
ldr     d1, [x10]      ; load data only after the branch passes
str     d1, [x11]      ; write output for the active row
```

The loop carries a flag check for every item. Rows that do not need the extra
pass still carry the flag into the repeated loop.

A better approach stores only rows that need the extra pass, then runs the loop
that is actually needed.

```zig
for (extra_pass_items) |item| {
    try runExtraPass(item, workspace);
}
```

The first loop asks "does this item need extra work?" for every item. The
better version gives the repeated loop only the items where the answer is yes.

The generated output for the better approach is easier to read.

```asm
ldp       q1, q2, [x10], #32  ; load four selected f64 input values
fadd.2d   v1, v1, v1          ; double the two lanes in q1
fadd.2d   v2, v2, v2          ; double the two lanes in q2
stp       q1, q2, [x9], #32   ; store four output values
```

The better loop only receives rows that need work. It does not ask each row
whether extra work exists.

A related compiler output for optional storage shows the same zero-work check in
a smaller form.

```asm
cmp     x0, #0          ; check whether the requested work count is zero
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return the chosen size
```

Deciding "none requested" can be cheap. The bigger win is skipping the data and
loops that would have followed.

A benchmark for requested-row lists showed processing only requested rows was
`4.18x` faster elapsed time than scanning all rows with flags.

## zdisamar Reading Notes

- Read optional buffer handling in
  [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig).
- Read LABOS optional local-source storage in
  [`src/forward_model/radiative_transfer/labos/orders.zig`](../../../src/forward_model/radiative_transfer/labos/orders.zig).
