# Ch. 8.5 - Transforms (p151)

Source: [Data-Oriented Design online book, "Transforms"](https://www.dataorienteddesign.com/dodbook/node9.html#SECTION00950000000000000000) (printed-book p151).

Summary: Fabian uses "transform" for a step that changes data from one shape
into another. A good transform separates collecting the data from doing the
operation.

The route here is language and algorithm history. Some languages make
list-changing operations feel natural, while C++ often makes programmers build
that shape themselves. Fabian rebuilds the idea from tables and from combine
steps that can be split, such as joining strings, multiplying matrices, or
combining colors.

Take home: Keep loading and setup out of the repeated work. Give each step the
data it needs, and make it clear what shape comes out.

## Main Lessons

- Keep loading separate from data-changing work.
  Loading reads files or reference tables. The next step should receive normal
  typed data and change it into the shape the next step needs. A repeated loop
  should not load files as part of its work.

- Give the next step only the data it will read.
  This keeps the function small and makes the cost easier to see.

  ```zig
  const ctx = RunContext{
      .items = prepared.items,
      .rates = cache.rates,
      .batch_id = batch_id,
  };
  ```

  Notice that `RunContext` lists the data the next step needs: `items`,
  `rates`, and `batch_id`.

  The next step could take each value separately, but those values were prepared
  as one set. If they travel separately, a later call can mix `items` from one
  prepared request with `rates` from another. `RunContext` passes the prepared
  read set without also passing the full request or lookup tables.


- Some totals can be built from smaller totals.
  If the math allows `left + right`, different chunks can be computed separately
  and combined later.

  ```zig
  const left = sumValues(values[0..mid]);
  const right = sumValues(values[mid..]);
  const total = left + right;
  ```

  Notice that the final answer is made from two partial answers. That means
  the two halves can be computed separately if needed.

## Practical Example

Here is a pattern that hides preparation inside a transform.

```zig
fn fillRunInput(
    request: RequestInput,
    lookups: LookupTables,
    batch_id: u32,
    out: *RunInput,
) !void {
    const ctx = try prepareContext(request, lookups);
    for (ctx.items, out.items) |item, *dst| {
        dst.* = makeRunItem(item, ctx.rates, batch_id);
    }
}
```

The compiler output below is generated machine code. It makes the prepare call
inside the repeated transform visible.

```asm
bl      _prepareInputForCodegen  ; prepare inside the repeated path
bl      _runPreparedForCodegen   ; run after rebuilding prepared data
subs    x19, x19, #1             ; count down repeated runs
b.ne    LBB2_2                   ; loop back to prepare again
```

This shows that setup still runs inside the transform, so the compiler keeps
the prepare call in the repeated loop.

A better approach sends prepared context into the transform.

```zig
fn fillRunInput(
    ctx: PreparedContext,
    batch_id: u32,
    out: *RunInput,
) void {
    for (ctx.items, out.items) |item, *dst| {
        dst.* = makeRunItem(item, ctx.rates, batch_id);
    }
}

fillRunInput(ctx, batch_id, out);
const result = runBatch(out, scratch);
```

The first version hides preparation inside the transform. The better version
gives the repeated transform prepared input and a place to write.
The next line then passes the filled `out` value to the batch run.

The generated output for the better approach is easier to read.

```llvm
tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> ...
```

Once loading and parsing are outside the transform, the compiler sees numeric
input and output arrays. It can generate vector arithmetic for the repeated
step.

A benchmark for caller-owned output showed it was `1.50x` faster than
allocating output every run, with the same checksum. That supports making the
transform step receive prepared data and storage instead of doing setup inside
the repeated work.

## zdisamar Reading Notes

- [`src/forward_model/instrument_grid/grid_calculation/forward_input.zig`](../../../src/forward_model/instrument_grid/grid_calculation/forward_input.zig)
  is the repeated step that turns prepared optical state into RTM-ready input.
- [`src/root.zig`](../../../src/root.zig) shows the higher-level split between
  preparing data and running the model.
