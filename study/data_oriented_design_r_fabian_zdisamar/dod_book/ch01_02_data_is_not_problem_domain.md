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

- Do not pass a large domain object into a calculation if the calculation only
  reads a few values.
  Use domain names while reading and preparing the input. Once the data reaches
  the repeated calculation, give it a small struct that says exactly what that
  calculation reads.

  ```zig
  const RunInput = struct {
      threshold: f64,
      records: []const PreparedRecord,
      config: RunConfig,
  };

  fn buildRunInput(request: RequestInput, config: RunConfig) RunInput {
      // Pull only the prepared values out of the larger request.
      return .{
          .threshold = request.threshold,
          .records = request.prepared_records,
          .config = config,
      };
  }
  ```

  Notice that `buildRunInput` is the handoff. It reads the larger request, then
  returns only the values the repeated calculation will read.

  Passing `threshold`, `records`, and `config` separately would work for one
  call. As more functions join the run, it becomes easier to pass `threshold`
  from one request with `records` from another, or to forget one setting.
  `RunInput` keeps the prepared run input together and keeps the larger request
  out of calculation code.


- The repeated calculation should not need to know where the values came from.
  The request may have come from a file, a test, or an API call. The calculation
  should just receive `threshold` and the prepared record values.

  ```zig
  fn countPassing(input: RunInput) usize {
      var count: usize = 0;
      for (input.records) |record| {
          if (record.score >= input.threshold and
              record.category == input.config.category)
          {
              count += 1;
          }
      }
      return count;
  }
  ```

  Notice that `countPassing` does the repeated work from prepared record data.
  The code that loads or interprets the original request has already run before
  this function is called.


- If the code loops over records, store the records as a list.
  A list makes the work visible: for each record, read the values needed by the
  repeated calculation.

  ```zig
  for (input.records) |record| {
      total_score += record.score;
  }
  ```

  Notice that the loop says the real work directly: visit each record and read
  its score.

## Practical Example

Here is a pattern that stores each record as a larger domain row, then reads
only one score from each row inside the repeated sum.

```zig
for (request.records) |record| {
    total_score += record.stats.score;
}
```

The compiler output below is generated machine code. It makes the pointer loads
and field loads from the code above visible.

```asm
ldur    x11, [x9, #-64]  ; load a stats pointer from a record row
ldur    x12, [x9, #-32]  ; load the next stats pointer from another row
ldr     d1, [x11]        ; follow the pointer and load score
ldr     d2, [x12]        ; follow another pointer and load score
add     x9, x9, #128     ; advance by four larger record rows
```

The loop first loads pointers from the record rows, then follows those pointers
to load `score`. That is extra memory work before the actual add.

A better approach is to form the numeric column first and let the loop walk
that column.

```zig
for (scores) |score| {
    total_score += score;
}
```

The first loop walks through a larger row to read one number. The better loop
receives only the numbers it uses.

The generated output for the better approach is easier to read.

```asm
ldp     q1, q2, [x9, #-32]  ; load four adjacent f64 values
ldp     q5, q6, [x9], #64   ; load four more and advance by 64 bytes
fadd    d0, d0, d1          ; add one loaded lane into the running total
fadd    d0, d0, d2          ; add another loaded lane into the running total
```

The better loop walks one numeric column. It does not first load a record row or
follow a pointer to find the number.

A benchmark for the numeric-column layout showed a plain `[]f64` score column
was `1.49x` faster than reading the same field out of full rows, with the same
checksum. So the chapter lesson is not just style: smaller runtime data can
produce simpler and faster memory access.

## zdisamar Reading Notes

- Read [`src/forward_model/radiative_transfer/root.zig`](../../../src/forward_model/radiative_transfer/root.zig)
  as the place where scientific inputs have already been formed into RTM
  data.
- This aligns with the repo rule that DISAMAR is a validation reference family,
  not the code architecture.
