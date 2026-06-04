# Ch. 1.2 - Data Is Not The Problem Domain (p6)

Source: [Data-Oriented Design online book, "Data is not the problem domain"](https://www.dataorienteddesign.com/dodbook/node2.html#SECTION00220000000000000000) (printed-book p6).

Summary: Fabian's lesson is that a program should not be shaped only around the
names people use for a problem. Those names help humans explain the work, but
the computer still runs on plain values arranged in memory.

He gets there from shipping-game failures where grid-like worlds were stored as
large collections of objects. The team then had to add neighbor links, scan
long lists, and build extra maps just to answer simple questions such as
"what is nearby?" The story of the world was clear, but the data had hidden the
shape the program needed.

Take home: Keep the human story separate from the small pieces of data the
program repeatedly uses. Use domain names when reading or explaining input, then
let repeated work run on simple, direct values.

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

  fn buildRtmInput(scene: SceneInput, config: SolveConfig) RtmInput {
      // Pull only the already prepared runtime values out of the larger scene.
      return .{
          .wavelength_nm = scene.wavelength_nm,
          .layers = scene.prepared_layers,
          .config = config,
      };
  }
  ```

  Notice that `buildRtmInput` is the handoff. It reads the larger scene, then
  returns only the values the solver will read.

  Passing `wavelength_nm`, `layers`, and `config` separately would work for one
  call. As more functions join the run, it becomes easier to pass
  `wavelength_nm` from one scene with `layers` from another, or to forget one
  setting. `RtmInput` keeps the prepared run input together and keeps the larger
  scene out of solver code.


- The solver should not need to know where the numbers came from.
  The wavelength may have come from an O2 A setup file, a test, or a Python API
  call. The solver should just receive `wavelength_nm` and the prepared layer
  values.

  ```zig
  fn solve(input: RtmInput, workspace: *Workspace) ForwardResult {
      return runLayerMath(
          input.layers,
          input.wavelength_nm,
          input.config,
          workspace,
      );
  }
  ```

  Notice that `solve` reads already prepared layer data. The code that
  loads or interprets O2 A input has already run before this function is called.


- If the code loops over layers, store the layers as a list.
  A list makes the work visible: for each layer, read the values needed by the
  math.

  ```zig
  for (input.layers) |layer| {
      optical_depth_sum += layer.optical_depth;
  }
  ```

  Notice that the loop says the real work directly: visit each layer and
  read its optical depth.

## Code Material

The runtime entry point keeps prepared input separate from reusable workspace:

```zig
const RuntimeInput = struct {
    // Runtime data is already shaped for the RTM loop.
    layers: []const LayerInput,
    wavelength_nm: f64,
    config: SolveConfig,
};

pub fn prepareRuntimeInput(scene: SceneInput, config: SolveConfig) RuntimeInput {
    return .{
        .layers = scene.prepared_layers,
        .wavelength_nm = scene.wavelength_nm,
        .config = config,
    };
}

pub fn solve(input: RuntimeInput, workspace: *Workspace) ForwardResult {
    // The RTM sees prepared data, not control-file text or DISAMAR objects.
    return radiativeTransfer(
        input.layers,
        input.wavelength_nm,
        input.config,
        workspace,
    );
}
```

Notice that `prepareRuntimeInput` is where the larger scene becomes runtime
data. `solve` then passes only `layers`, `wavelength_nm`, `config`, and
workspace memory into the RTM math.

The alternative is to pass `layers`, `wavelength_nm`, and `config` separately
through every function. That makes it easier to mix values from different
prepared scenes. `RuntimeInput` keeps the input group together, while workspace
stays separate because it is reusable memory, not input data.

## Practical Example

Here is a pattern that stores each layer as a larger science row, then reads
only one number from each row inside the repeated sum.

```zig
for (case.layers) |layer| {
    optical_depth_sum += layer.physics.optical_depth;
}
```

The compiler output below is generated machine code. It makes the pointer loads
and field loads from the code above visible.

```asm
ldur    x11, [x9, #-64]  ; load a physics pointer from a layer row
ldur    x12, [x9, #-32]  ; load the next physics pointer from another row
ldr     d1, [x11]        ; follow the pointer and load optical_depth
ldr     d2, [x12]        ; follow another pointer and load optical_depth
add     x9, x9, #128     ; advance by four 32-byte ScienceLayer rows
```

The loop first loads pointers from the layer rows, then follows those pointers
to load `optical_depth`. That is extra memory work before the actual add.

A better approach is to form the numeric column first and let the loop walk
that column.

```zig
for (optical_depths) |tau| {
    optical_depth_sum += tau;
}
```

The first loop walks through a larger row to read one number. The better loop
receives only the numbers it uses.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d3          ; add another loaded lane into the running total
```

The better loop walks one numeric column. It does not first load a layer row or
follow a pointer to find the number.

A benchmark for the numeric-column layout showed a plain `[]f64` optical-depth column was
`1.49x` faster than reading the same field out of full layer rows, with the
same checksum. So the chapter lesson is not just style: smaller runtime data
can produce simpler and faster memory access.

## zdisamar Reading Notes

- Read [`src/forward_model/radiative_transfer/root.zig`](../../../src/forward_model/radiative_transfer/root.zig)
  as the place where scientific inputs have already been formed into RTM
  data.
- This aligns with the repo rule that DISAMAR is a validation reference family,
  not the code architecture.
