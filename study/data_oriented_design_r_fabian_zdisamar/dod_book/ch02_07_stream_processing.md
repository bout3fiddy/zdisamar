# Ch. 2.7 - Stream Processing (p54)

Source: [Data-Oriented Design online book, "Stream Processing"](https://www.dataorienteddesign.com/dodbook/node3.html#SECTION00370000000000000000) (printed-book p54).

Summary: Stream stages should read rows and write outputs in a regular loop so the work is easy to follow and optimize.

## Main Lessons

- Stream processing means: run the same step over many rows.
  Each row gets handled the same way. The code reads one row, writes one result,
  then moves to the next row.

  ```zig
  for (misses, results) |miss, *result| {
      result.* = solveMiss(miss, constants);
  }
  ```

  What to notice: one `miss` produces one `result`. The loop does not depend on
  hidden state from another row.

  Zig syntax note: `for (misses, results)` loops over two slices together.
  `miss` is the current input row. `*result` captures a pointer to the current
  output slot, and `result.* = ...` writes through that pointer.

- Give temporary memory to the function instead of hiding it somewhere else.
  This makes it clear which memory the function is allowed to use.

  ```zig
  fn fillRadiance(misses: []const Miss, scratch: *Scratch, out: []f64) !void {
      for (misses, out) |miss, *dst| dst.* = try radianceAt(miss, scratch);
  }
  ```

  What to notice: the function signature shows all three important memory
  areas: input rows, scratch memory, and output rows.

  Zig syntax note: `[]const Miss` is a read-only slice. `*Scratch` is a pointer.
  `out: []f64` is a writable slice. `!void` means the function returns no value
  on success, but may return an error. `try radianceAt(miss, scratch)` returns
  early if `radianceAt` fails.

- Each stage should say what it reads and what it writes.
  That makes it easier to test the stage, time it, and replace it later.

  ```zig
  const plan = try buildPlan(wavelengths, storage.plan);
  try fillRadiance(plan, storage.radiance);
  try assembleReflectance(storage.radiance, storage.reflectance);
  ```

  What to notice: `fillRadiance` writes radiance, then `assembleReflectance`
  reads radiance and writes reflectance. The handoff is explicit.

## Code Material

Fabian does not provide a standalone listing in this section. The code lesson is
to structure stages like kernels:

```zig
fn fillRadiance(rows: []const MissRow, constants: Constants, out: []f64) void {
    for (rows, out) |row, *dst| {
        dst.* = solveOne(row, constants);
    }
}
```

What to notice: every row uses the same constants and writes one output slot.
There is no hidden global accumulator inside the loop.

## Compiler Note

Chapter example tied to this note:

```zig
for (misses, results) |miss, *result| {
    result.* = solveMiss(miss, constants);
}
```

Wrong pattern:

```zig
for (misses) |miss| {
    try results.append(solveMiss(miss, constants));
}
```

Better pattern:

```zig
for (misses, results) |miss, *result| {
    result.* = solveMiss(miss, constants);
}
```

Why this contrast matters: the wrong version may check list capacity or grow
storage inside the stream. The better version writes into already-sized output
slots, so the compiler sees a regular read/write loop.

Wrong-pattern compiler artifact from
[`appendLayerSourceChecked`](codegen/dod_codegen_examples.zig):

```asm
ldr     x9, [x1, #16]          ; load output capacity
cmp     x0, x9                 ; compare current length with capacity
b.hs    LBB7_4                 ; branch out if the list is full
str     d1, [x9, x0, lsl #3]   ; store at items[len]
str     x0, [x1, #8]           ; write the updated length
```

What goes wrong: append-style output keeps capacity checks and length updates in
the stream loop.

Better-pattern compiler artifact from
[`fillLayerSource`](codegen/dod_codegen_examples.zig):

```llvm
%17 = tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> %17, ptr %scevgep29
```

Machine code from the same function:

```asm
fmla.2d  v22, v3, v2           ; do two f64 multiply-adds in one vector register
stp      q22, q2, [x9, #-32]   ; store two vector registers into output slots
```

What this proves: the compiler recognized a regular stream transform and used
vector multiply-add plus vector stores. This only works because the source shape
has clear input rows and output slots.

Benchmark evidence: the related caller-owned output benchmark was `1.50x`
faster than allocating output every run, with the same checksum. That supports
the stream-processing habit of passing output storage into the stage.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/simulate.zig`](../../../src/forward_model/instrument_grid/grid_calculation/simulate.zig)
  as a stream of product stages: setup, plan resolution, prefetch, radiance,
  irradiance, reflectance, Jacobian assembly.
- The ideal is that each stage makes its read/write sets obvious.
