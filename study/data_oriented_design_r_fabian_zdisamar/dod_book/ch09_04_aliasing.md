# Ch. 9.4 - Aliasing (p166)

Source: [Data-Oriented Design online book, "Aliasing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001040000000000000000) (printed-book p166).

Summary: Fabian explains aliasing as uncertainty: two references might point to
the same memory. When that is possible, the compiler has to be more cautious
after a write.

Fabian makes this concrete with C and C++ examples. Copying between overlapping
memory ranges has to proceed carefully because output can affect later input,
and passing a loop limit by reference can force reloads because another pointer
might change it.

Take home: Make it obvious which data is only read and which data is written.
Avoid letting input and output secretly refer to the same storage.

## Main Lessons

- Mark input slices as read-only when the function should not change them.
  This helps the reader and the compiler know that `input` is not written.

  ```zig
  fn scale(input: []const f64, factor: f64, output: []f64) void {
      for (input, output) |value, *dst| dst.* = value * factor;
  }
  ```

  Notice that `input` is `[]const f64`, so this function promises not to
  write through that slice. `output` is writable.

- Do not let input and output secretly point to the same memory.
  If they overlap, a write to the output can change a value the function has not
  read yet.
  Keep the read buffer and write buffer separate, and say that rule near the
  function that writes output.

- Pass small settings directly.
  A copied setting cannot be changed through another pointer while the function
  is running.
  This is useful for small configuration values. Do not use it as an excuse to
  copy large arrays.

## Code Material

The code material keeps input read-only and writes into a separate output:

```zig
fn fillOutput(input: []const f64, scale: f64, output: []f64) void {
    // Callers keep output separate from input.
    for (input, output) |value, *dst| {
        // Read input and write the separate output slot.
        dst.* = value * scale;
    }
}

fn run(prepared: *const PreparedInput, workspace: *Workspace) !void {
    // Prepared data is read; temporary output lives in workspace.
    try fillOutput(prepared.optical_depths, prepared.scale, workspace.tmp);
}
```

Notice that prepared data is read through `*const PreparedInput`, and output
goes into `workspace.tmp`. The read side and write side are separate.


## Practical Example

Here is a pattern whose signature leaves input/output ownership unclear.

```zig
fn fillOutput(input: []f64, output: []f64) void {
    for (input, output) |value, *dst| {
        dst.* = value * 2.0;
    }
}
```

The compiler output below is generated machine code. It makes the runtime
overlap checks from the code above visible.

```asm
sub     x9, x2, x0  ; compute distance between output and first input
cmp     x9, #64     ; check whether the slices might overlap
b.lo    LBB8_3      ; use scalar fallback if overlap is too close
sub     x9, x2, x1  ; repeat the overlap check for the second input
```

When aliasing is possible, the compiler adds runtime overlap checks before it
can use the fast vector loop.

A better approach marks input read-only and says the output must be separate.

```zig
fn fillOutput(input: []const f64, output: []f64) void {
    // The caller passes a separate output slice.
    for (input, output) |value, *dst| {
        dst.* = value * 2.0;
    }
}
```

The first signature does not tell the reader which slice is input and which
slice is output. The better signature marks the input read-only and states that
output is separate, which is the case the fast vector loop needs.

The generated output for the better approach is easier to read.

```asm
ldp     q0, q1, [x10, #-32]  ; load radiance vectors directly
ldp     q4, q5, [x11, #-32]  ; load irradiance vectors directly
fdiv.2d v0, v0, v4           ; divide vector lanes
stp     q0, q1, [x9, #-32]   ; store output vectors
```

The no-alias version can enter the vector loop without the same overlap-check
setup.

A related vector-path output shows why overlap matters.

```llvm
vector.memcheck:
br i1 %conflict.rdx, label %Then.preheader13, label %vector.ph
```

`vector.memcheck` is the compiler's overlap check before the fast vector loop.
Clear read/write ownership makes that fast path easier to justify.

A benchmark for caller-owned output showed it was `1.50x` faster than
allocating output every run, with the same checksum.

## zdisamar Reading Notes

- Read borrowed view and owned output boundaries in
  [`src/forward_model/instrument_grid/grid_calculation/types.zig`](../../../src/forward_model/instrument_grid/grid_calculation/types.zig).
- Read immutable profile/table borrowing in
  [`src/forward_model/optical_properties/state_build/context.zig`](../../../src/forward_model/optical_properties/state_build/context.zig).
