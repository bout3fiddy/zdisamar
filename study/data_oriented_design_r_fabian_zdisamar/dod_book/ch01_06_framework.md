# Ch. 1.6 - The Framework (p21)

Source: [Data-Oriented Design online book, "The framework"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00260000000000000000) (printed-book p21).

Summary: Fabian uses database practice as the model for handling complex data
through staged, valid transformations rather than hidden object interactions.
The lesson is that framework shape should make data integrity and operation
order visible.

The circumstance he points to is large-scale game development: rare
one-in-a-million data bugs become public when millions of players run the game,
and live economies or in-app purchases make integrity failures business
failures. That is why he looks back to database ACID ideas from financial
transaction systems.

Take home: Keep the top-level flow visible so readers can see where data is
prepared and where model work begins. In `zdisamar`, that means named phases for
load, prepare, run, and output, with boundaries that are easy to inspect.

## Main Lessons

- The top-level code should show the order of work.
  A reader should be able to see that the program prepares data first, then runs
  the model on that prepared data.
  The important part is the visible order: prepare first, run second.

- Give each big data change its own function.
  For example, one function builds optical state. Another function turns that
  optical state into one wavelength's RTM input.
  The function names should say which data shape is being built.

- Avoid hiding important work inside a method with a vague name.
  The high-level path should read like a small list of steps.

## Code Material

Fabian's section is prose. The study code shape is:

```zig
pub fn simulate(input: Input, storage: *ProductStorage) !Output {
    const prepared = try prepare(input, storage.prepare_scratch);
    const product = try runPrepared(prepared, storage.product_workspace);
    return finish(product, storage.output_scratch);
}
```

What to notice: this function is a readable chain. It prepares data, runs the
prepared data, then turns the product into output.

Zig syntax note: `!Output` means the function can return either an `Output` or
an error.

## Compiler Note

Chapter example tied to this note:

```zig
pub fn simulate(input: Input, storage: *ProductStorage) !Output {
    const prepared = try prepare(input, storage.prepare_scratch);
    const product = try runPrepared(prepared, storage.product_workspace);
    return finish(product, storage.output_scratch);
}
```

Wrong pattern:

```zig
pub fn simulate(input: Input, allocator: Allocator) !Output {
    const prepared = try prepare(input, allocator);
    const product = try runPreparedAllocating(prepared, allocator);
    return finish(product, allocator);
}
```

Better pattern:

```zig
pub fn simulate(input: Input, storage: *ProductStorage) !Output {
    const prepared = try prepare(input, storage.prepare_scratch);
    const product = try runPrepared(prepared, storage.product_workspace);
    return finish(product, storage.output_scratch);
}
```

Why this contrast matters: the wrong wrapper lets allocation and setup follow
the repeated product run. The better wrapper gives each phase its own storage,
so the repeated step can become plain numeric work.

Wrong-pattern compiler artifact from
[`prepareEveryProduct`](codegen/dod_codegen_examples.zig):

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare runs in the repeated path
bl      _dod_codegen_examples.runPreparedForCodegen   ; run consumes newly prepared data
subs    x19, x19, #1                                  ; count down product runs
b.ne    LBB2_2                                        ; loop back to prepare again
```

What goes wrong: the framework boundary is too wide, so setup work remains in
the repeated loop.

Better-pattern compiler artifact from
[`runAlreadyPreparedProducts`](codegen/dod_codegen_examples.zig):

```asm
ldp     d0, d1, [x0]                                  ; load the already-prepared input
bl      _dod_codegen_examples.runPreparedForCodegen   ; run the prepared computation
fadd    d1, d0, d1                                    ; repeated loop adds the result
b.ne    LBB5_5                                        ; no prepare call inside the loop
```

What this proves: splitting prepare/run lets the repeated part avoid rebuilding
the prepared data.

Compiler output for this wrapper would mostly show calls. The useful proof is
inside the repeated step. In the compiled transform example, LLVM sees:

```llvm
tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> %17, ptr %scevgep29
```

What this proves: when the framework separates preparation from the repeated
array transform, the repeated step becomes plain numeric work.

Benchmark evidence: the caller-owned output version of reflectance was `1.50x`
faster than allocating output every run. That gives a concrete reason for the
framework shape: keep setup and storage ownership outside the repeated call.

## zdisamar Reading Notes

- The main public flow in [`src/root.zig`](../../../src/root.zig) should read
  as `input -> prepare -> run -> output`.
- The staged O2 A path in [`src/input/o2a_reference/run.zig`](../../../src/input/o2a_reference/run.zig)
  is a good reading target because the phases are named and traced.
