# Ch. 10.3 - Reusability (p183)

Source: [Data-Oriented Design online book, "Reusability"](https://www.dataorienteddesign.com/dodbook/node11.html#SECTION001130000000000000000) (printed-book p183).

Summary: Reuse clear data-changing steps by feeding them simple data so functions are not tied to one large domain object.

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

Fabian's section is prose. Adapted:

```zig
pub fn runPrepared(
    prepared: *const PreparedInput,
    storage: *ProductStorage,
    options: RunOptions,
) !ProductView {
    try storage.ensureShape(prepared.shape(), options);
    return simulateProductWithWorkspace(prepared, storage, options);
}
```

What to notice: the reusable call takes prepared data and reusable storage. It
does not own every setup path; callers adapt their data into `PreparedInput`
first.

Zig syntax note: `options: RunOptions` is passed by value. `!ProductView` means
the function may return an error instead of a `ProductView`.

## Compiler Note

Chapter example tied to this note:

```zig
pub fn runPrepared(
    prepared: *const PreparedInput,
    storage: *ProductStorage,
    options: RunOptions,
) !ProductView
```

Wrong pattern:

```zig
pub fn run(scene: SceneInput, allocator: Allocator, options: RunOptions) !ProductView {
    const prepared = try prepare(scene, allocator);
    return runPreparedAllocating(prepared, allocator, options);
}
```

Better pattern:

```zig
pub fn runPrepared(
    prepared: *const PreparedInput,
    storage: *ProductStorage,
    options: RunOptions,
) !ProductView
```

Why this contrast matters: the wrong version owns setup and allocation, so it is
hard to reuse the repeated run. The better version accepts prepared data and
storage from the caller.

Wrong-pattern compiler artifact from
[`prepareEveryProduct`](codegen/dod_codegen_examples.zig):

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare inside repeated use
bl      _dod_codegen_examples.runPreparedForCodegen   ; run after rebuilding state
subs    x19, x19, #1                                  ; count down uses
b.ne    LBB2_2                                        ; repeat prepare and run
```

What goes wrong: a non-reusable function owns preparation, so each repeated use
rebuilds data before running.

Better-pattern compiler artifact from
[`runAlreadyPreparedProducts`](codegen/dod_codegen_examples.zig):

```asm
ldp     d0, d1, [x0]                                  ; load reusable prepared input
bl      _dod_codegen_examples.runPreparedForCodegen   ; compute from prepared input
fadd    d1, d0, d1                                    ; repeated loop only accumulates
b.ne    LBB5_5                                        ; no prepare call in the loop
```

What this proves: a reusable prepared boundary lets callers keep setup out of
the repeated run.

Related compiler artifact from a reusable output shape:

```llvm
define dso_local void @fillReflectance(
  ptr nocapture nonnull readonly align 8 %0,
  ptr nocapture nonnull readonly align 8 %1,
  ptr nocapture nonnull writeonly align 8 %2,
  ...
)
```

What this proves: the repeated function can read prepared input and write into
provided storage. It does not need to allocate output inside the loop.

Benchmark evidence: caller-owned output was `1.50x` faster than allocating
output every run, with the same checksum.

## zdisamar Reading Notes

- Read public prepare/run APIs in [`src/root.zig`](../../../src/root.zig).
- Read reusable session storage in
  [`src/input/o2a_reference/root.zig`](../../../src/input/o2a_reference/root.zig).
- Read shared workspaces in
  [`src/forward_model/instrument_grid/grid_calculation/storage.zig`](../../../src/forward_model/instrument_grid/grid_calculation/storage.zig).
