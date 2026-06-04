# Ch. 9.4 - Aliasing (p166)

Source: [Data-Oriented Design online book, "Aliasing"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001040000000000000000) (printed-book p166).

Summary: Make read-only inputs and writable outputs obvious so readers and the compiler know what may overlap.

## Main Lessons

- Mark input slices as read-only when the function should not change them.
  This helps the reader and the compiler know that `input` is not written.

  ```zig
  fn scale(input: []const f64, factor: f64, output: []f64) void {
      for (input, output) |value, *dst| dst.* = value * factor;
  }
  ```

  What to notice: `input` is `[]const f64`, so this function promises not to
  write through that slice. `output` is writable.

- Do not let input and output secretly point to the same memory.
  If they overlap, a write to the output can change a value the function has not
  read yet.
  Keep the read buffer and write buffer separate, and document that contract
  near the function that writes output.

- Pass small settings directly.
  A copied setting cannot be changed through another pointer while the function
  is running.
  This is useful for small configuration values. Do not use it as an excuse to
  copy large arrays.

## Code Material

Fabian gives examples where overlapping buffers and reference parameters force
the compiler to be conservative. Adapted:

```zig
fn fillOutput(input: []const f64, scale: f64, output: []f64) void {
    // Contract: output does not overlap input.
    for (input, output) |value, *dst| {
        dst.* = value * scale;
    }
}

fn run(prepared: *const PreparedInput, workspace: *Workspace) !void {
    try fillOutput(prepared.optical_depths, prepared.scale, workspace.tmp);
}
```

What to notice: prepared data is read through `*const PreparedInput`, and output
goes into `workspace.tmp`. The read side and write side are separate.

Zig syntax note: `*const PreparedInput` means a pointer to prepared input that
this function should not modify through that pointer.

## Compiler Note

Chapter example tied to this note:

```zig
fn fillOutput(input: []const f64, scale: f64, output: []f64) void {
    // Contract: output does not overlap input.
    for (input, output) |value, *dst| {
        dst.* = value * scale;
    }
}
```

Wrong pattern:

```zig
fn fillOutput(input: []f64, output: []f64) void {
    for (input, output) |value, *dst| {
        dst.* = value * 2.0;
    }
}
```

Better pattern:

```zig
fn fillOutput(input: []const f64, output: []f64) void {
    // Contract: output does not overlap input.
    for (input, output) |value, *dst| {
        dst.* = value * 2.0;
    }
}
```

Why this contrast matters: the wrong signature does not tell the reader which
slice is input and which slice is output. The better signature marks the input
read-only and documents the no-overlap contract used by the fast path.

Wrong-pattern compiler artifact from
[`fillReflectance`](codegen/dod_codegen_examples.zig):

```asm
sub     x9, x2, x0  ; compute distance between output and first input
cmp     x9, #64     ; check whether the slices might overlap
b.lo    LBB8_3      ; use scalar fallback if overlap is too close
sub     x9, x2, x1  ; repeat the overlap check for the second input
```

What goes wrong: when aliasing is possible, the compiler adds runtime overlap
checks before it can use the vector path.

Better-pattern compiler artifact from
[`fillReflectanceNoAlias`](codegen/dod_codegen_examples.zig):

```asm
ldp     q0, q1, [x10, #-32]  ; load radiance vectors directly
ldp     q4, q5, [x11, #-32]  ; load irradiance vectors directly
fdiv.2d v0, v0, v4           ; divide vector lanes
stp     q0, q1, [x9, #-32]   ; store output vectors
```

What this proves: the no-alias version can enter the vector loop without the
same overlap-check setup.

Related compiler artifact from the vector path setup:

```llvm
vector.memcheck:
br i1 %conflict.rdx, label %Then.preheader13, label %vector.ph
```

What this proves: when overlap is possible, the compiler adds a check before
using the vector path. Clear ownership and non-overlap contracts make the fast
path easier to justify.

Benchmark evidence: caller-owned output was `1.50x` faster than allocating
output every run, with the same checksum.

## zdisamar Reading Notes

- Read borrowed view and owned output boundaries in
  [`src/forward_model/instrument_grid/grid_calculation/types.zig`](../../../src/forward_model/instrument_grid/grid_calculation/types.zig).
- Read immutable profile/table borrowing in
  [`src/forward_model/optical_properties/state_build/context.zig`](../../../src/forward_model/optical_properties/state_build/context.zig).
