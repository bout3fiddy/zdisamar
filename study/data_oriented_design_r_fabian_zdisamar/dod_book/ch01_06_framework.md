# Ch. 1.6 - The Framework (p21)

Source: [Data-Oriented Design online book, "The framework"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00260000000000000000) (printed-book p21).

Summary: Fabian looks at databases because they show how to handle important
data through careful steps. The point is not to copy database software, but to
make the order of work visible and reliable.

The circumstance is large-scale game development. A rare bug can become common
when millions of players run the game, and mistakes in live economies or
payments can become business failures. Databases had already learned from
money-handling systems, so Fabian borrows their habit of making each step
explicit.

Take home: Make the top-level flow easy to read: prepare the data, do the work,
then produce the result. Avoid hiding important steps inside vague helper calls.

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

## Practical Example

Here is a pattern where one wrapper owns preparation, allocation, running, and
finishing.

```zig
pub fn simulate(input: Input, allocator: Allocator) !Output {
    const prepared = try prepare(input, allocator);
    const product = try runPreparedAllocating(prepared, allocator);
    return finish(product, allocator);
}
```

The compiler output below is generated machine code. It makes the repeated calls
from the code above visible.

```asm
bl      _dod_codegen_examples.prepareInputForCodegen  ; prepare runs in the repeated path
bl      _dod_codegen_examples.runPreparedForCodegen   ; run consumes newly prepared data
subs    x19, x19, #1                                  ; count down product runs
b.ne    LBB2_2                                        ; loop back to prepare again
```

The wrapper keeps `prepare` inside the repeated loop, so setup runs alongside
the product computation.

A better approach gives the phases their own storage so the repeated step can
stay focused.

```zig
pub fn simulate(input: Input, storage: *ProductStorage) !Output {
    const prepared = try prepare(input, storage.prepare_scratch);
    const product = try runPrepared(prepared, storage.product_workspace);
    return finish(product, storage.output_scratch);
}
```

The first wrapper keeps allocation and setup attached to each product run. The
better wrapper gives each phase its own storage, so the repeated step can become
plain numeric work.

The generated output for the better approach is easier to read.

```asm
ldp     d0, d1, [x0]                                  ; load the already-prepared input
bl      _dod_codegen_examples.runPreparedForCodegen   ; run the prepared computation
fadd    d1, d0, d1                                    ; repeated loop adds the result
b.ne    LBB5_5                                        ; no prepare call inside the loop
```

Splitting prepare/run lets the repeated part avoid rebuilding the prepared data.

Compiler output for this wrapper would mostly show calls. The useful proof is
inside the repeated step. In the compiled transform example, LLVM sees:

```llvm
tail call <2 x double> @llvm.fma.v2f64(...)
store <2 x double> %17, ptr %scevgep29
```

When the framework separates preparation from the repeated array transform, the
repeated step becomes plain numeric work.

A benchmark for caller-owned reflectance output showed that version
was `1.50x` faster than allocating output every run. That gives a concrete
reason for the framework shape: keep setup and storage ownership outside the
repeated call.

## zdisamar Reading Notes

- The main public flow in [`src/root.zig`](../../../src/root.zig) should read
  as `input -> prepare -> run -> output`.
- The staged O2 A path in [`src/input/o2a_reference/run.zig`](../../../src/input/o2a_reference/run.zig)
  is a good reading target because the phases are named and traced.
