# Ch. 10.3 - Reusability (p183)

Source: [Data-Oriented Design online book, "Reusability"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001130000000000000000) (printed-book p183).

Summary: Fabian argues that reuse is not just copying source files. The more
important thing to reuse is the knowledge of what steps happen and what data
they need.

He develops this against the object-oriented story of reuse through adapters,
wrappers, and agents. The positive example he keeps is `FILE` from `stdio.h`:
a small handle into a complex platform system, not a large object graph that
every caller must inherit.

Take home: Make reusable work depend on simple inputs, not one large object. A
clear sequence of data-changing steps is easier to reuse than a class tied to
one project.

## Main Lessons

- Reuse the sequence of steps, not only the source file.
  If many runs need "prepare, then run", keep that sequence clear and reusable.
  The reusable idea is the sequence itself: prepare once, then run on prepared
  data.

- Reuse a data-changing function by feeding it the simple data it expects.
  If a function sums numbers, collect the numbers first instead of passing a
  large object.
  For example, a sum function should receive numbers. It should not need the
  whole scene or a layer object if it only adds one field.

- A reusable function should ask for only what it needs.
  This makes it easier to call from another place without building extra data.
  A good reusable forward-model function should ask for prepared input and
  reusable storage. It should not ask for files, parser state, or Python wrapper
  state.

## Code Material

The code material reuses prepared input and caller-owned storage:

```zig
pub fn runPrepared(
    prepared: *const PreparedInput,
    storage: *ProductStorage,
    options: RunOptions,
) !ProductView {
    // Match storage to the prepared input before running.
    try storage.ensureShape(prepared.shape(), options);
    // The run step receives explicit storage instead of allocating inside.
    return simulateProductWithWorkspace(prepared, storage, options);
}
```

Notice that the reusable call takes prepared data and reusable storage. It
does not own every setup path; callers adapt their data into `PreparedInput`
first.


## Practical Example

Here is a pattern that ties reusable work to setup and allocation.

```zig
pub fn run(scene: SceneInput, allocator: Allocator, options: RunOptions) !ProductView {
    const prepared = try prepare(scene, allocator);
    return runPreparedAllocating(prepared, allocator, options);
}
```

The compiler output below is generated machine code. It makes the repeated
prepare call from the code above visible.

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare inside repeated use
bl      _dod_codegen_examples.runPreparedForCodegen   ; run after rebuilding state
subs    x19, x19, #1                                  ; count down uses
b.ne    LBB2_2                                        ; repeat prepare and run
```

This shows that a non-reusable function owns preparation, so each repeated use
rebuilds data before running.

A better approach exposes the prepared run as its own function.

```zig
pub fn runPrepared(
    prepared: *const PreparedInput,
    storage: *ProductStorage,
    options: RunOptions,
) !ProductView
```

The first version owns setup and allocation, so it is hard to reuse the repeated
run. The better version accepts prepared data and storage from the caller.

The generated output for the better approach is easier to read.

```asm
ldp     d0, d1, [x0]                                  ; load reusable prepared input
bl      _dod_codegen_examples.runPreparedForCodegen   ; compute from prepared input
fadd    d1, d0, d1                                    ; repeated loop only accumulates
b.ne    LBB5_5                                        ; no prepare call in the loop
```

Because the function accepts prepared input, callers can keep setup out of the
repeated run.

A related output-shape example shows the same split between input data and
reusable storage.

```llvm
define dso_local void @fillReflectance(
  ptr nocapture nonnull readonly align 8 %0,
  ptr nocapture nonnull readonly align 8 %1,
  ptr nocapture nonnull writeonly align 8 %2,
  ...
)
```

The repeated function can read prepared input and write into provided storage.
It does not need to allocate output inside the loop.

A benchmark for caller-owned output showed it was `1.50x` faster than
allocating output every run, with the same checksum.

## zdisamar Reading Notes

- Read public prepare/run APIs in [`src/root.zig`](../../../src/root.zig).
- Read reusable session storage in
  [`src/input/o2a_reference/root.zig`](../../../src/input/o2a_reference/root.zig).
- Read shared workspaces in
  [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig).
