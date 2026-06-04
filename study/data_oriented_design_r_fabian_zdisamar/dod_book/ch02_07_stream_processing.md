# Ch. 2.7 - Stream Processing (p54)

Source: [Data-Oriented Design online book, "Stream Processing"](https://www.dataorienteddesign.com/dodbook/node3.html#SECTION00370000000000000000) (printed-book p54).

Summary: Fabian's stream-processing lesson is simple: many tasks become easier
when each item is handled the same way, using only the input it was given and
writing its own result.

He reaches this through two histories at once. Database tables can be treated
as sets of rows, and graphics hardware had already pushed small graphics
programs into a similar shape: read shared inputs, use temporary local work
space, and write the result for one vertex or pixel. If those small programs
could change random shared data, the machine would need locks or would have to
run much more work one item at a time.

Take home: Prefer steps that read a list, process each item, and write a clear
output list. This makes the work easier to understand, test, split up, and run
again.

## Main Lessons

- Stream processing means: run the same step over many rows.
  Each row gets handled the same way. The code reads one row, writes one result,
  then moves to the next row.

  ```zig
  for (misses, results) |miss, *result| {
      result.* = solveMiss(miss, constants);
  }
  ```

  Notice that one `miss` produces one `result`. The loop does not depend on
  hidden state from another row.


- Give temporary memory to the function instead of hiding it somewhere else.
  This makes it clear which memory the function is allowed to use.

  ```zig
  fn fillRadiance(misses: []const Miss, scratch: *Scratch, out: []f64) !void {
      for (misses, out) |miss, *dst| dst.* = try radianceAt(miss, scratch);
  }
  ```

  Notice that the function signature shows all three important memory
  areas: input rows, scratch memory, and output rows.


- Each stage should say what it reads and what it writes.
  That makes it easier to test the stage, time it, and replace it later.

  ```zig
  const plan = try buildPlan(wavelengths, storage.plan);
  try fillRadiance(plan, storage.radiance);
  try assembleReflectance(storage.radiance, storage.reflectance);
  ```

  Notice that `fillRadiance` writes radiance, then `assembleReflectance`
  reads radiance and writes reflectance. The handoff is explicit.

## Code Material

Fabian does not provide a standalone listing in this section. The code lesson is
to structure stages like kernels:

```zig
fn fillRadiance(rows: []const MissRow, constants: Constants, out: []f64) void {
    for (rows, out) |row, *dst| {
        // One input row writes one matching output slot.
        dst.* = solveOne(row, constants);
    }
}
```

Notice that every row uses the same constants and writes one output slot.
There is no hidden global accumulator inside the loop.

## Practical Example

Here is a pattern that appends results while the stream is running.

```zig
for (misses) |miss| {
    try results.append(solveMiss(miss, constants));
}
```

The compiler output below is generated machine code. It makes the capacity
check, length update, and store from the code above visible.

```asm
ldr     x9, [x1, #16]          ; load output capacity
cmp     x0, x9                 ; compare current length with capacity
b.hs    LBB7_4                 ; branch out if the list is full
str     d1, [x9, x0, lsl #3]   ; store at items[len]
str     x0, [x1, #8]           ; write the updated length
```

This shows that append-style output keeps capacity checks and length updates in
the stream loop.

A better approach sizes the output ahead of time and writes each result into
its slot.

```zig
for (misses, results) |miss, *result| {
    result.* = solveMiss(miss, constants);
}
```

The append loop may check list capacity or grow storage while the stream is
running. The better loop writes into already-sized output slots, so the
compiler sees a regular read/write pass.

The generated output for the better approach is easier to read.

```llvm
%17 = tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> %17, ptr %scevgep29
```

The matching machine code shows the vector arithmetic and vector stores.

```asm
fmla.2d  v22, v3, v2           ; do two f64 multiply-adds in one vector register
stp      q22, q2, [x9, #-32]   ; store two vector registers into output slots
```

The compiler recognized a regular stream transform and used vector multiply-add
plus vector stores. That happens because the loop has clear input rows and
output slots.

A benchmark for caller-owned output showed it was `1.50x` faster than
allocating output every run, with the same checksum. That supports the
stream-processing habit of passing output storage into the stage.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/simulate.zig`](../../../src/forward_model/instrument_grid/grid_calculation/simulate.zig)
  as a stream of product stages: setup, plan resolution, prefetch, radiance,
  irradiance, reflectance, Jacobian assembly.
- The ideal is that each stage makes its read/write sets obvious.
