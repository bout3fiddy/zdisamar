# Ch. 1.6 - The Framework (p21)

Source: [Data-Oriented Design online book, "The framework"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00260000000000000000) (printed-book p21).

Summary: Fabian looks at databases because they are a worked example of keeping
important state in a form that can survive change. The point is not to copy a
query engine into a game; it is to learn from tables, explicit operations, and
careful updates when program state matters.

The circumstance is large-scale game development. A rare bug can become common
when millions of players run the game, and mistakes in live economies or
payments can become business failures. Databases had already learned from
money-handling systems, so Fabian borrows their habit of making each step
explicit.

Take home: Keep important state changes explicit. In `zdisamar`, that usually
means a visible path from input preparation, to RTM work, to output assembly,
rather than hiding state changes behind vague helper calls.

## Main Lessons

- Important state changes should be named.
  A reader should be able to see where input becomes prepared data, where
  prepared data becomes product data, and where product data becomes output.
  The lesson is not the exact names; it is that state-changing steps are visible.

- Give each big data change its own function.
  For example, one function builds optical state. Another function turns that
  optical state into one wavelength's RTM input.
  The function names should say which data shape is being built.

- Avoid hiding important work inside a method with a vague name.
  The high-level path should read like a small list of steps.

## Practical Example

Here is a pattern where one wrapper owns preparation, allocation, running, and
finishing. In Fabian's database comparison, the risk is hidden state change. In
this `zdisamar`-shaped example, the hidden part is that allocation and setup sit
inside the same wrapper as the repeated product computation.

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
better wrapper names the state owned by each phase, so the repeated step can
stay focused on prepared input and product workspace.

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
repeated step becomes plain numeric work. This compiler output supports the
local `zdisamar` mapping of Fabian's framework lesson: explicit stages make it
clear which state is being created and which state is being consumed.

## zdisamar Reading Notes

- The main public flow in [`src/root.zig`](../../../src/root.zig) should read
  as `input -> prepare -> run -> output`.
- The staged O2 A path in [`src/input/o2a_reference/run.zig`](../../../src/input/o2a_reference/run.zig)
  is a good reading target because the phases are named and traced.
