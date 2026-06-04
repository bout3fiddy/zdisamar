# Compiler Codegen Notes

These notes look at small Zig kernels that mirror the DOD study examples.
They are not production `zdisamar` functions. They are compileable shapes used
to ask one question: what does the compiler do with this kind of data layout or
loop?

Tracked source and generated evidence:

- [`dod_codegen_examples.zig`](dod_codegen_examples.zig)
- [`dod_codegen_examples.s`](dod_codegen_examples.s)
- [`dod_codegen_examples.ll`](dod_codegen_examples.ll)
- [`dod_codegen_bench.zig`](dod_codegen_bench.zig)
- [`benchmark_results.md`](benchmark_results.md)

Local generated file, not meant for version control:

- `dod_codegen_examples.o`

Command used:

```sh
zig build-obj study/data_oriented_design_r_fabian_zdisamar/dod_book/codegen/dod_codegen_examples.zig \
  -OReleaseFast \
  -fstrip \
  -femit-bin=study/data_oriented_design_r_fabian_zdisamar/dod_book/codegen/dod_codegen_examples.o \
  -femit-asm=study/data_oriented_design_r_fabian_zdisamar/dod_book/codegen/dod_codegen_examples.s \
  -femit-llvm-ir=study/data_oriented_design_r_fabian_zdisamar/dod_book/codegen/dod_codegen_examples.ll
```

Toolchain and target used for these notes:

- Zig `0.15.2`
- Darwin `arm64`
- optimized build mode: `ReleaseFast`

Do not treat this as a speed claim for the full model. It is compiler evidence
for the source shape. Workload speed still needs a benchmark around the real
`zdisamar` boundary.

## How To Read The Assembly

- `x0`, `x1`, `x2` are integer or pointer registers. Function arguments often
  arrive in these registers.
- `d0`, `d1` are 64-bit floating-point registers.
- `q0`, `q1` are 128-bit vector registers. On this target, one `q` register can
  hold two `f64` values.
- `ldr` loads one value from memory. `str` stores one value.
- `ldp` loads a pair of registers. `stp` stores a pair of registers.
- `fadd` adds floating-point values. `fdiv` divides floating-point values.
- `fmadd` computes `a * b + c` in one instruction.
- `fmla.2d` is the vector form of multiply-add for two `f64` lanes.
- `cbz` means "compare with zero and branch if zero."
- `cmp` compares values. `b.*` branches based on a comparison.
- `csel` and `fcsel` choose between two values without a normal branch.
- `lsl #3` means shift left by 3 bits, which is the same as multiplying by 8.
  That often appears when indexing an `f64` array because each `f64` is 8 bytes.

## Lesson Map

| Codegen symbol | Study lessons it supports | Main point |
|---|---|---|
| `sumOpticalDepth` | Ch. 1.2, Ch. 8.4, Ch. 9.6 | A loop that reads one field from each row can become a simple repeated load/add. |
| `fillLayerSource` | Ch. 2.7, Ch. 3.4, Ch. 8.5, Ch. 9.3 | A straight input-to-output transform can vectorize when the memory shape is clear. |
| `fillReflectance` | Ch. 9.3, Ch. 9.4 | Separate read-only inputs and a write-only output give the compiler room to vectorize. |
| `integrateIndexed` | Ch. 6.1, Ch. 8.9, Ch. 9.2 | A saved index removes search work, but indexed gather loads are still less regular than a plain stream. |
| `lowerBound` | Ch. 6.2, Ch. 10.4 | Searching a small key array avoids pulling payload data into the search loop. |
| `refreshDirty` | Ch. 8.7 | A dirty list changes the loop length to only the work that must run. |
| `ensureJacobianStorage` | Ch. 3, Ch. 8.8 | Optional work can be represented as a small count or mask before touching large buffers. |
| `prefixStarts` | Ch. 8.9 | Prefix starts are setup work. They make later variable-length reads cheap. |
| `workerSum` and `sum` | Ch. 9.7, Ch. 10.4 | A local accumulator avoids shared writes inside the loop. |
| `sumSelected` | Ch. 9.9 | Random runtime flags still leave branches in the loop. Grouping must happen in data preparation. |

## Contrast Symbols

The chapter notes quote small snippets from these generated files. Use this
table when you want to inspect the whole function instead of only the selected
lines in a chapter.

| Wrong symbol | Better symbol | What to look for |
|---|---|---|
| `sumOpticalDepthScienceLayer` | `sum`, `sumOpticalDepthColumn` | Pointer loads from science rows versus direct numeric-column loads. |
| `prepareEveryProduct` | `runAlreadyPreparedProducts` | A prepare call inside the product loop versus reuse of prepared input. |
| `appendLayerSourceChecked` | `fillLayerSource` | Capacity checks and length stores inside the loop versus direct output slots. |
| `fillReflectanceAllocateLike` | `fillReflectanceNoAlias`, `fillReflectance` | Allocator function calls near the boundary versus a direct input/input/output loop. |
| `integrateLinearSearch` | `integrateIndexed` | Repeated search through wavelengths versus a saved index load. |
| `lookupPayloadLinear` | `lowerBound` | Scanning payload rows versus searching a narrow key table. |
| `lowerBoundInModel` | `lowerBound` | Loading through a model wrapper versus passing the key array directly. |
| `refreshScanAllFlags` | `refreshDirty` | A branch over every row versus a loop over known dirty indexes. |
| `startByResummingCounts` | `prefixStarts` | Re-summing variable-length counts versus prepared prefix starts. |
| `workerWriteEveryItem` | `workerSum` | A shared store inside the loop versus one local accumulator and one final write. |
| `sumSelected` | `sumGroupedValues` | A runtime flag branch per item versus grouped values with no per-item flag check. |

## Row Loop: Read Only The Hot Field

Source shape:

```zig
export fn sumOpticalDepth(layers_ptr: [*]const LayerInput, len: usize) f64 {
    const layers = layers_ptr[0..len];
    var total: f64 = 0.0;
    for (layers) |layer| {
        total += layer.optical_depth;
    }
    return total;
}
```

Selected assembly:

```asm
ldur    d1, [x9, #-48]  ; load optical_depth from an earlier unrolled row
ldur    d2, [x9, #-24]  ; load optical_depth from the next unrolled row
ldr     d3, [x9]        ; load optical_depth from the row at x9
ldr     d4, [x9, #24]   ; load optical_depth from the following 24-byte row
fadd    d0, d0, d1      ; add the first loaded value into running total d0
fadd    d0, d0, d2      ; add the second loaded value into running total d0
fadd    d0, d0, d3      ; add the third loaded value into running total d0
fadd    d0, d0, d4      ; add the fourth loaded value into running total d0
add     x9, x9, #96     ; advance by four 24-byte LayerInput rows
```

What is happening:

- `LayerInput` is 24 bytes in this example.
- The compiler unrolled the loop by 4 rows.
- The four loads are 24 bytes apart, so they read `optical_depth` from four
  different rows.
- It does not load `phase_index`, because the loop does not read that field.

Tie back to the lesson:

- "Make the runtime struct match the loop that reads it" means the compiler
  sees a simple repeated memory pattern.
- If the hot loop only needs optical depth, keeping unrelated names, parser
  state, or debug text out of the row prevents those fields from being dragged
  through the loop.
- This is still an array-of-structs walk. It is clean, but not the same as a
  pure `[]f64` optical-depth column.

## Straight Transform: One Input Row Writes One Output Row

Source shape:

```zig
export fn fillLayerSource(layers_ptr: [*]const LayerInput, out_ptr: [*]f64, len: usize, scale: f64) void {
    const layers = layers_ptr[0..len];
    const out = out_ptr[0..len];
    for (layers, out) |layer, *dst| {
        dst.* = @mulAdd(f64, layer.optical_depth, layer.single_scatter_albedo, scale);
    }
}
```

Selected assembly:

```asm
ld3.2d   { v2, v3, v4 }, [x12]  ; load interleaved struct fields into vector registers
fmla.2d  v22, v3, v2            ; compute two f64 multiply-add lanes
stp      q22, q2, [x9, #-32]    ; store two vector registers to output memory
```

What is happening:

- `ld3.2d` loads fields from interleaved structs into separate vector registers.
- `fmla.2d` performs vector multiply-add on two `f64` lanes.
- `stp q...` stores vector results to the output array.
- Before this vector loop, the compiler emits overlap checks. If input and
  output might overlap in a bad way, it falls back to a simpler scalar loop.

Tie back to the lesson:

- A one-row-to-one-row transform is easy for the compiler to understand.
- Separate input and output slices make the read side and write side visible.
- The compiler can vectorize the straight path, but only after it proves the
  output writes will not clobber unread input.
- This is why the notes keep saying "make reads and writes explicit." It is not
  only for human readability. It affects what the compiler can safely do.

## Reflectance: Read Inputs, Write Output

Source shape:

```zig
for (radiance, irradiance, out) |l, e, *dst| {
    dst.* = if (e != 0.0) l / e else 0.0;
}
```

Selected scalar assembly:

```asm
ldr     d1, [x11], #8  ; load one radiance f64, then advance radiance pointer
ldr     d2, [x10], #8  ; load one irradiance f64, then advance irradiance pointer
fdiv    d1, d1, d2     ; divide radiance by irradiance
fcmp    d2, #0.0       ; compare irradiance with zero
fcsel   d1, d1, d0, ne ; keep division result if nonzero, otherwise choose 0.0
str     d1, [x9], #8   ; store one reflectance f64, then advance output pointer
```

Selected vector assembly:

```asm
ldp       q0, q1, [x10, #-32]  ; load two vectors of radiance values
ldp       q4, q5, [x11, #-32]  ; load two vectors of irradiance values
fcmeq.2d  v16, v4, #0.0        ; build a mask for lanes where irradiance is zero
fdiv.2d   v0, v0, v4           ; divide two f64 radiance lanes by irradiance lanes
bic.16b   v0, v0, v16          ; clear result lanes where the zero mask is set
stp       q0, q1, [x9, #-32]   ; store two output vectors
```

What is happening:

- The scalar path loads one radiance and one irradiance, divides, checks for
  zero, then stores one output.
- The vector path handles several `f64` values at once.
- The zero check becomes a mask in the vector path instead of a normal branch.

Tie back to the lesson:

- Keeping `radiance` and `irradiance` read-only and `out` writable gives a clean
  input/input/output loop.
- The zero rule is still visible in machine code. Data-oriented design does not
  remove physics or correctness rules.
- The benefit is that the data shape lets the compiler express the rule in a
  tight vector loop.

## Saved Index Plan: No Search In The Hot Loop

Source shape:

```zig
const result_index: usize = @intCast(sample_indices_ptr[k]);
integrated += results_ptr[result_index].radiance;
```

Selected assembly:

```asm
ldr     w11, [x1, x9, lsl #2]  ; load one saved u32 result index
lsl     x11, x11, #4           ; multiply index by 16 bytes per ForwardResult row
ldr     d1, [x2, x11]          ; load radiance from the indexed result row
fadd    d0, d0, d1             ; add radiance into the integration total
```

What is happening:

- `x1` is the pointer to `sample_indices`.
- `x9` is the current index into that index list.
- `lsl #2` multiplies by 4 because each `u32` index is 4 bytes.
- `lsl #4` multiplies the loaded result index by 16 because `ForwardResult` is
  16 bytes in this example.
- The final `ldr d1` reads `radiance` from the selected result row.

Tie back to the lesson:

- The hot loop does not search for the matching wavelength or hash anything.
  It follows saved positions.
- That is the win from an index.
- The codegen also shows the cost that remains: this is still an indexed gather.
  The next address depends on the loaded index, so it is less regular than a
  plain `for (values)` stream.
- This is why an index is useful but not magic. It removes lookup work; it does
  not make random memory access sequential.

## Key Lookup: Search The Key Table, Not The Payload

Source shape:

```zig
const mid = low + (high - low) / 2;
if (values[mid] < needle) {
    low = mid + 1;
} else {
    high = mid;
}
```

Selected assembly:

```asm
sub     x9, x1, x8           ; compute high - low
add     x9, x8, x9, lsr #1   ; compute mid = low + ((high - low) / 2)
ldr     d1, [x0, x9, lsl #3] ; load values[mid], using mid * 8 bytes for f64
fcmp    d1, d0               ; compare values[mid] with the needle
csinc   x8, x8, x9, pl       ; keep low, or set low to mid + 1 when value < needle
csel    x1, x1, x9, mi       ; keep high when value < needle, otherwise set high to mid
```

What is happening:

- `sub` and `add ... lsr #1` compute the midpoint.
- `ldr d1, [x0, x9, lsl #3]` loads `values[mid]`.
- The shift by 3 is `mid * 8`, because `f64` is 8 bytes.
- `fcmp` compares the table value with the needle.
- `csinc` and `csel` update `low` and `high` with conditional select
  instructions.

Tie back to the lesson:

- The search only loads the key array.
- The payload table is not touched until after the index is known.
- This is the codegen reason to keep lookup keys separate from large payloads:
  the search loop stays small.

## Dirty List: Loop Only Over Work That Is Dirty

Source shape:

```zig
for (wavelengths, out) |wavelength_nm, *dst| {
    dst.* = wavelength_nm * 2.0 + 1.0;
}
```

Selected assembly:

```asm
ldp       q1, q2, [x10, #-32]  ; load vectors of dirty wavelength values
fadd.2d   v1, v1, v1           ; double two f64 lanes: wavelength * 2.0
fadd.2d   v1, v1, v0           ; add the 1.0 vector to those lanes
stp       q1, q2, [x9, #-32]   ; store refreshed wavelength values
```

What is happening:

- The compiler vectorizes the loop over the dirty wavelength list.
- `fadd.2d v1, v1, v1` doubles the wavelength values.
- The next `fadd.2d` adds `1.0`.
- It stores the refreshed values in order.

Tie back to the lesson:

- The compiler optimizes the loop it is given.
- It does not know about every possible wavelength. The source code already
  narrowed the work to `dirty_len`.
- The DOD move is building the list of dirty rows before this loop.

## Optional Work: Count Or Mask Before Touching Buffers

Source shape:

```zig
if (states_count == 0) {
    return 0;
}
if (capacity >= states_count) {
    return capacity;
}
return states_count;
```

Selected assembly:

```asm
cmp     x1, x0          ; compare capacity with requested state count
csel    x8, x1, x0, hi  ; choose capacity if larger, otherwise choose count
cmp     x0, #0          ; check whether requested state count is zero
csel    x0, xzr, x8, eq ; return 0 for no work, otherwise return chosen size
```

What is happening:

- The compiler turns the small choices into conditional selects.
- There is no loop here and no allocation call in this tiny example.

Tie back to the lesson:

- The important source idea is deciding whether optional work exists before
  touching big storage.
- In real code, this can keep Jacobian buffers, source terms, or scattering
  support out of paths that do not need them.
- Codegen for this tiny function shows the decision is cheap. It does not prove
  the full product run is faster.

## Prefix Starts: Setup For Variable-Length Sets

Source shape:

```zig
starts[0] = 0;
var i: usize = 1;
while (i < len) : (i += 1) {
    starts[i] = starts[i - 1] + counts[i - 1];
}
```

Selected assembly:

```asm
str     wzr, [x1]       ; write 0 to starts[0]
ldr     w11, [x0], #4   ; load the next count, then advance counts pointer
add     w9, w11, w9     ; add count to the running prefix total
str     w9, [x10], #4   ; store the next start, then advance starts pointer
```

What is happening:

- `str wzr, [x1]` writes zero to `starts[0]`.
- Each loop reads the next count, adds it to the running total, and writes one
  start value.
- This loop is scalar because each output depends on the previous sum.

Tie back to the lesson:

- Prefix starts are preparation work for variable-length data.
- The setup loop has a dependency, but after it runs, the hot code can use
  `start` and `count` directly.
- This is a normal DOD trade: pay a simple setup pass so repeated reads do not
  search or resize.

## Worker Local Sum: No Shared Write Inside The Loop

Source shape:

```zig
var local: f64 = 0.0;
var i = start;
while (i < end) : (i += 1) {
    local += values_ptr[i];
}
return local;
```

Selected assembly:

```asm
ldp     q1, q2, [x10, #-32]  ; load two vector registers of input values
ldp     q5, q6, [x10], #64   ; load two more vectors, then advance pointer
fadd    d0, d0, d1           ; add one loaded f64 lane into accumulator d0
fadd    d0, d0, d3           ; add another loaded f64 lane into accumulator d0
fadd    d0, d0, d2           ; add another loaded f64 lane into accumulator d0
fadd    d0, d0, d4           ; add another loaded f64 lane into accumulator d0
```

What is happening:

- The compiler unrolls the loop and loads several values per pass.
- The running total stays in floating-point register `d0`.
- There is no store inside the repeated loop.

Tie back to the lesson:

- For false sharing, the source lesson is "do the repeated accumulation in
  worker-local state."
- Codegen shows the local state is a register, not a shared memory slot.
- A shared write can happen once after the worker returns its final sum.

## Branchy Selection: Runtime Flags Stay Branchy

Source shape:

```zig
for (flags, values) |flag, value| {
    if (flag != 0) {
        selected_total += value;
    }
}
```

Selected assembly:

```asm
ldrb    w10, [x8], #1  ; load one flag byte, then advance flag pointer
cbz     w10, LBB9_5    ; branch over the add when the flag is zero
ldr     w10, [x11]     ; load the value only for a nonzero flag
add     w0, w10, w0    ; add that value into the selected total
```

What is happening:

- `ldrb` loads one flag byte.
- `cbz` branches when the flag is zero.
- Only when the flag is nonzero does the code load the value and add it.
- The compiler unrolls parts of this loop, but the per-flag branches remain.

Tie back to the lesson:

- If flags are random, the CPU may guess these branches badly.
- The compiler cannot know the future flag pattern.
- The DOD fix is to group rows before the hot loop when that grouping is worth
  its cost. Then the hot loop can run one path without asking the same question
  for every row.

## When Codegen Is The Wrong Tool

Some study sections are still important, but compiler output is not the first
thing to inspect:

- Ch. 1.5, Ch. 1.6, and Ch. 10.3 are about boundaries: load, prepare, run,
  output. Codegen of the top-level wrapper mostly shows calls. The real check is
  whether setup is outside the repeated boundary.
- Ch. 8.1 and Ch. 8.2 are about measurement. Codegen can show whether trace or
  telemetry calls remain, but the main lesson is to time the right phase and
  record useful counts.
- Ch. 8.3 is a study method. It does not need assembly. The output is a short
  benchmark note: problem, baseline, prediction, change, result.

Use codegen when the question is concrete:

- Did this hot loop vectorize?
- Is there still a branch inside the per-row loop?
- Did the hot function still call an allocator, formatter, hash map, or parser?
- Does the loop load only the fields it claims to read?
- Did an index remove search work, or did a search remain?
