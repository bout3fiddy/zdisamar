# Ch. 9.6 - Cache Line Utilisation (p168)

Source: [Data-Oriented Design online book, "Cache line utilisation"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001060000000000000000) (printed-book p168).

Summary: Put fields together only when the same loop reads them together so cache lines carry useful data.

## Main Lessons

- When the CPU reads memory, it reads a small block, not one field.
  Fields stored next to each other may arrive together.

- Put fields together only when the same loop reads them together.
  This keeps useful data close without making every row too large.

  ```zig
  const KernelRef = struct {
      start: u32,
      count: u16,
      inline_count: u8,
  };
  ```

  What to notice: `start`, `count`, and `inline_count` describe how to read the
  kernel samples. Keeping them together helps the sample-reading loop.

- Move debug names and rarely used data away from the row used by the loop that
  runs many times.
  That loop should not pull a source name into memory if it only needs a sample
  range.

  ```zig
  const KernelDebug = struct {
      source_name: []const u8,
      build_note: []const u8,
  };
  ```

  What to notice: `source_name` and `build_note` are useful for debugging, but
  not for the repeated sample loop. Keeping them elsewhere avoids loading them
  by accident.

  Zig syntax note: `[]const u8` is the common Zig type for read-only bytes, often
  used for string-like data.

## Code Material

Fabian references the lookup examples from Chapter 6 and gives cache-line size
reasoning. Adapted:

```zig
const KernelRef = extern struct {
    nominal_index: u32,
    side_start: u32,
    side_count: u16,
    inline_count: u8,
    flags: u8,
    inline_samples: [4]SampleRef,
};

comptime {
    assert(@sizeOf(KernelRef) <= 64);
}
```

What to notice: the fields in `KernelRef` are the fields the sample-reading
loop needs together. The point is not "make every struct 64 bytes"; it is to
keep related repeated-read fields together.

Zig syntax note: `extern struct` asks Zig to use a C-like field layout.
`comptime { ... }` runs at compile time. `@sizeOf(KernelRef)` asks the compiler
for the size of the type.

## Compiler Note

Chapter example tied to this note:

```zig
const KernelRef = struct {
    start: u32,
    count: u16,
    inline_count: u8,
};
```

Wrong pattern:

```zig
for (layers) |layer| {
    total_tau += layer.optical_depth;
}
```

Better pattern:

```zig
for (optical_depths) |tau| {
    total_tau += tau;
}
```

Why this contrast matters: the wrong version walks whatever else is stored next
to `optical_depth` in each row. The better version puts the hot field in the
memory order the loop actually reads.

Wrong-pattern compiler artifact from
[`sumOpticalDepth`](codegen/dod_codegen_examples.zig):

```asm
ldur    d1, [x9, #-48]  ; load one f64 field from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load the same field from the next unrolled row
add     x9, x9, #96     ; advance the row pointer by four 24-byte rows
```

What goes wrong: unused fields are not loaded, but full row stride still
matters. The loop advances by 96 bytes to consume four `f64` values.

Better-pattern compiler artifact from [`sum`](codegen/dod_codegen_examples.zig):

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

What this proves: the column layout keeps the repeated reads closer together in
memory.

Benchmark evidence: the optical-depth column was `1.49x` faster than reading
the same field out of full rows.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig`](../../../src/forward_model/instrument_grid/grid_calculation/wavelength_plan.zig)
  for compact kernel references.
- Read [`src/forward_model/optical_properties/state_build/state_spectroscopy.zig`](../../../src/forward_model/optical_properties/state_build/state_spectroscopy.zig)
  for fixed inline spectroscopy cache rows.
