# Ch. 1.2 - Data Is Not The Problem Domain (p6)

Source: [Data-Oriented Design online book, "Data is not the problem domain"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00220000000000000000) (printed-book p6).

Summary: Prepare science input into small runtime data so solver loops do not drag parser or domain state through hot math.

## Main Lessons

- Do not pass a big science object into the solver if the solver only reads a
  few numbers.
  Use the science names while reading and preparing the input. Once the data
  reaches the solver, give it a small struct that says exactly what the math
  code reads.

  ```zig
  const RtmInput = struct {
      wavelength_nm: f64,
      layers: []const LayerInput,
      config: SolveConfig,
  };
  ```

  What to notice: this struct names the values the solver reads. It does not
  include the whole O2 A case, the input file, or a DISAMAR-style control
  object.

  Zig syntax note: `const RtmInput = struct { ... };` defines a new struct type.
  `[]const LayerInput` means a read-only slice of `LayerInput` rows.

- The solver should not need to know where the numbers came from.
  The wavelength may have come from an O2 A setup file, a test, or a Python API
  call. The solver should just receive `wavelength_nm` and the prepared layer
  values.

  ```zig
  fn solve(input: RtmInput, workspace: *Workspace) ForwardResult {
      return runLayerMath(input.layers, input.wavelength_nm, workspace);
  }
  ```

  What to notice: `solve` reads already prepared layer data. The code that
  loads or interprets O2 A input has already run before this function is called.

  Zig syntax note: `*Workspace` means "pointer to a `Workspace`." Passing a
  pointer lets the function reuse or change workspace memory.

- If the code loops over layers, store the layers as a list.
  A list makes the work visible: for each layer, read the values needed by the
  math.

  ```zig
  for (input.layers) |layer| {
      optical_depth_sum += layer.optical_depth;
  }
  ```

  What to notice: the loop says the real work directly: visit each layer and
  read its optical depth.

## Code Material

Fabian's section is mainly conceptual. The code lesson for `zdisamar` is this
shape:

```zig
const RuntimeInput = struct {
    layers: []const LayerInput,
    wavelength_nm: f64,
    config: SolveConfig,
};

pub fn solve(input: RuntimeInput, workspace: *Workspace) ForwardResult {
    // The RTM sees prepared data, not control-file text or DISAMAR objects.
    return radiativeTransfer(input.layers, input.config, workspace);
}
```

What to notice: the code that calls `radiativeTransfer` passes `layers`,
`config`, and workspace memory. It does not pass a parser result or a full
science case object into the RTM math.

## Compiler Note

Chapter example tied to this note:

```zig
for (input.layers) |layer| {
    optical_depth_sum += layer.optical_depth;
}
```

Wrong pattern:

```zig
for (case.layers) |layer| {
    optical_depth_sum += layer.physics.optical_depth;
}
```

Better pattern:

```zig
for (optical_depths) |tau| {
    optical_depth_sum += tau;
}
```

Why this contrast matters: the wrong version makes the hot loop walk through a
larger science-shaped row to read one number. The better version gives the loop
only the numbers it uses.

Wrong-pattern compiler artifact from
[`sumOpticalDepthScienceLayer`](codegen/dod_codegen_examples.zig):

```asm
ldur    x11, [x9, #-64]  ; load a physics pointer from a science-shaped row
ldur    x12, [x9, #-32]  ; load the next physics pointer from another row
ldr     d1, [x11]        ; follow the pointer and load optical_depth
ldr     d2, [x12]        ; follow another pointer and load optical_depth
add     x9, x9, #128     ; advance by four 32-byte ScienceLayer rows
```

What goes wrong: the loop first loads pointers from the science-shaped rows,
then follows those pointers to load the number. That is extra memory work before
the actual add.

Better-pattern compiler artifact from [`sum`](codegen/dod_codegen_examples.zig):

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

What this proves: the better loop walks one numeric column. It does not first
load a science row or follow a pointer to find the number.

Benchmark evidence from [`benchmark_results.md`](codegen/benchmark_results.md):
reading a plain `[]f64` optical-depth column was `1.49x` faster than reading the
same field out of full layer rows, with the same checksum. So the chapter
lesson is not just style: smaller runtime data can produce simpler and faster
memory access.

## zdisamar Reading Notes

- Read [`src/forward_model/radiative_transfer/root.zig`](../../../src/forward_model/radiative_transfer/root.zig)
  as the place where scientific inputs have already been formed into RTM
  data.
- This aligns with the repo rule that DISAMAR is a validation reference family,
  not the code architecture.
