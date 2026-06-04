# Ch. 9.3 - Write Buffer Awareness (p165)

Source: [Data-Oriented Design online book, "Write buffer awareness"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001030000000000000000) (printed-book p165).

Summary: Fabian treats writing as its own performance problem. Reading data,
changing data, and writing new data are different jobs, and mixing them can make
memory traffic harder for the machine.

He links this to Ulrich Drepper's memory work and to the hardware idea of
writing data straight through memory. If data will not be reused soon, keeping
it close to the CPU can push out data that would have been more useful. Simple
read-and-write patterns give the machine and compiler more room to do the right
thing.

Take home: Write outputs in a clear, continuous order when possible. Keep
read-only inputs and write-only outputs separate so the work is easy for both
people and the compiler to follow.

## Main Lessons

- Write results in a straight line when you can.
  This is easier for the CPU than writing to many unrelated places.

  ```zig
  for (input_values, output_values) |value, *dst| {
      dst.* = value * scale;
  }
  ```

  Notice that `output_values` is written from left to right. The loop does
  not jump around to write each result.


- Keep data you only read separate from data you change.
  This makes it clearer which arrays are inputs and which arrays are outputs.

  ```zig
  const RunBuffers = struct {
      input_values: []const f64,
      output_values: []f64,
  };

  fn fillOutputs(buffers: RunBuffers) void {
      for (buffers.input_values, buffers.output_values) |value, *dst| {
          // Read one input value and write the matching output slot.
          dst.* = computeValue(value);
      }
  }

  fillOutputs(buffers);
  try writeOutputs(buffers.output_values);
  ```

  Notice that `fillOutputs` reads `input_values` and writes `output_values`.
  The next step reads the filled output slice. Passing those slices separately
  is possible, but the two lengths must match and slot `i` in `output_values`
  must be the output for slot `i` in `input_values`. `RunBuffers` keeps that
  pairing visible while still separating read-only input from writable output.


- Let the caller keep output memory between runs.
  This avoids allocating new arrays for every run.

  ```zig
  try storage.output_values.resize(allocator, item_count);
  try fillOutputs(storage.input_values.items, storage.output_values.items);
  ```

  Notice that the storage object keeps the `output_values` array. The run
  resizes and fills that existing array instead of making a new output array
  from scratch.

## Practical Example

Here is a pattern that allocates output as part of the output fill.

```zig
const out = try allocator.alloc(f64, numerator.len);
defer allocator.free(out);
for (numerator, denominator, out) |top, bottom, *dst| {
    dst.* = if (bottom != 0.0) top / bottom else 0.0;
}
```

The compiler output below is generated machine code. It makes the allocation
and cleanup calls from the code above visible.

```asm
ldr     x8, [x0]       ; load allocator.alloc function pointer
mov     x0, x3         ; pass output length to allocator
blr     x8             ; call allocator before writing output
ldr     x8, [x19, #8]  ; load allocator.free function pointer
blr     x8             ; call free after using output
```

The loop has to call the allocator before it can start writing results, and then
call `free` afterward.

A better approach receives output storage from the caller.

```zig
for (numerator, denominator, out) |top, bottom, *dst| {
    dst.* = if (bottom != 0.0) top / bottom else 0.0;
}
```

The first version allocates and frees output around the loop. The better version
receives output storage from the caller, so the repeated work is just reads,
arithmetic, and stores.

The generated output for the better approach is easier to read.

```llvm
%wide.load = load <2 x double>, ptr ...
%17 = select <2 x i1> %9, <2 x double> %13, <2 x double> zeroinitializer
store <2 x double> %17, ptr ...
```

The compiler sees read arrays and a write array, then emits vector loads, vector
select, and vector stores.

A benchmark for caller-owned output showed it was `1.50x` faster than
allocating output every run, with the same checksum.

## zdisamar Reading Notes

- [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig)
  owns the reusable output buffers for product calculation.
- [`src/forward_model/radiative_transfer/labos/workspace.zig`](../../../src/forward_model/radiative_transfer/labos/workspace.zig)
  separates scratch memory from physics logic.
