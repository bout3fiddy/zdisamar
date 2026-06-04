# Ch. 9.2 - Reducing Memory Dependency (p164)

Source: [Data-Oriented Design online book, "Reducing memory dependency"](https://www.dataorienteddesign.com/dodbook/node10.html#SECTION001020000000000000000) (printed-book p164).

Summary: Fabian's memory-dependency lesson is that repeated work can stall when
each memory read must finish before the program knows the next address to read.
The bad case is not "the compiler knows where the next read is". The bad case is
"the next address is stored inside the object we are still waiting to load".

The concrete cases are linked lists, tree-shaped maps or sets, and systems that
connect objects through many pointers. The lesson is not that every lookup is
bad; it is that a long chain of "load this object before you can find the next
object" gives the machine little room to get ahead.

Take home: Avoid long chains of pointers in repeated work. Prefer simple lists
and saved positions when the program needs to visit many related values.

## Main Lessons

- Avoid "go here, then go there, then go somewhere else" in loops that run many
  times.
  A pointer chain makes the CPU wait for one memory load before it knows the
  address of the next load.

  ```zig
  const value = rows[index].score;
  ```

  Notice that the code uses one array and one index. It does not follow a
  pointer to another object before finding `score`.

- Save positions into arrays when you can.
  Then the repeated loop can jump straight to the result it needs.

  ```zig
  const result_index = plan.result_indices[i];
  sum += results[result_index].score;
  ```

  Notice that `result_indices` stores the result position. The next line uses
  that position to read `results` directly.


- If a loop reads the same field from many rows, consider storing that field
  together.
  This can be easier for the CPU than reading full rows with many unused fields.

  ```zig
  var total: f64 = 0;
  for (scores) |score| {
      // The loop walks one plain score list.
      total += score;
  }
  ```

  Notice that the loop reads the score list directly. A struct with only
  `values: []const f64` would add a name, but it would not keep any related
  fields together. Use a wrapper only when there is more context that must
  travel with the values, such as indexes or matching keys.

## Practical Example

Here is a pattern where a key search must finish before a score can be read.

```zig
const result_key = plan.result_keys[i];
const result_index = findResultIndex(results, result_key);
sum += results[result_index].score;
```

The compiler output below is generated machine code. It makes the repeated
search and comparison from the code above visible.

```asm
ldr     d1, [x1, x9, lsl #3]   ; load requested key
ldr     d2, [x2, x11, lsl #3]  ; load candidate result key
fcmp    d2, d1                 ; compare before the score can be read
b.eq    LBB11_7                ; branch when the search finds a match
```

This shows that the result address depends on a repeated search, not just a
saved index.

A better approach stores the result index before the repeated read.

```zig
const result_index = plan.result_indices[i];
sum += results[result_index].score;
```

The first version depends on a search before it can read a score. The better
version keeps one dependent load, but removes the search chain from the repeated
loop.

The generated output for the better approach is easier to read.

```llvm
%10 = load i32, ptr %scevgep
%13 = load double, ptr %12
```

The loop follows a saved index and then reads the result. The search is gone,
but the result address still depends on the loaded index.

A benchmark for prepared indexes showed they were `803.65x` faster than
linear search, with the same checksum.

## zdisamar Reading Notes

- Read [`src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig`](../../../src/forward_model/instrument_grid/grid_calculation/spectral_eval.zig).
- The key study question is whether a loop that runs many times is doing direct
  indexed reads or repeated dependent lookups.
