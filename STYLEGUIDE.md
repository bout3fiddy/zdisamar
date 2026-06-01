# Zig Style Guide

For dense Zig files where math, data layout, instrumentation, or hot paths are
hard to follow.

## Basic Rules

- Use `zig fmt`.
- Use simple language and correct domain names.
- Keep comments close to the code they explain.
- Do not use labels like `Purpose:`, `Data:`, `Flow:`, or `Boundary:`.
- Do not use bare `//` spacer comments.
- Generated docs are not the goal; readability in the source file is.

## Boxes

Use boxes for file maps, function maps, layout maps, and instrumentation blocks.
Pick one readable rail width in a file and keep the right `|` aligned. It is fine
to go past 100 columns when alignment makes the block easier to scan.

```zig
// name -------------------------------------------------------------------------------------------------------|
// Short explanation.                                                                                          |
// ------------------------------------------------------------------------------------------------------------|
```

Close general boxes with a plain fence, not `end name`.

## Line Length

Keep ordinary code and prose within the readable width. Box rails are allowed to
be wider so the `|` stays aligned.

- Default soft limit for non-box lines: 120 columns.
- Wrap long calls by putting one argument per line.
- If a named value block makes `break :label` too wide, shorten the label
  without making it vague.

## File Maps

At the top of dense files, show what the file coordinates, who calls it, the
main paths, important names, and memory ownership.

## File Order

Put the reader's path near the top:

- imports, file map, constants, and small data structs needed for signatures
- public entry points and major stage functions, ordered by importance
- public support helpers
- private helpers, small math/indexing routines, and local cache helpers

Zig lets top-level functions call helpers written later in the same file. Use
that freedom to keep important routines easy to find.

If a private optimized kernel is the real implementation behind a public entry
point, keep it close to that entry point. Do not make readers scroll through
minor helpers before they see the main path.

## Function Maps

Put function maps inside the function body, after the argument list. Never put
explanatory comments above `fn`, even for small private helpers or methods.
For methods inside a struct, title the box `StructName.fnName`.

```zig
fn layerResolvedSolveWithWorkspace(...) Result {
    // layerResolvedSolveWithWorkspace ------------------------------------------------------------------------|
    // Runs layer-resolved transport for one high-resolution sample. Steps:                                    |
    //                                                                                                         |
    //   1. build attenuation for this geometry and correction setting                                         |
    //   2. loop retained Fourier terms:                                                                       |
    //        basis                                                                                            |
    //          -> layer matrices                                                                              |
    //          -> transported fields                                                                          |
    //          -> Fourier reflectance term                                                                    |
    //   3. add Fourier weight * Fourier reflectance term into total reflectance                               |
    //   4. add requested surface, aerosol-depth, and pressure Jacobians                                       |
    //   5. stop when the Fourier tail is below the threshold                                                  |
    //                                                                                                         |
    // hot path                                                                                                |
    //   repeated : every retained Fourier term                                                                |
    //   costly   : basis build                                                                                |
    //              layer-matrix build                                                                         |
    //              scattering-order propagation                                                               |
    //              reflectance integral                                                                       |
    //   Jacobian : aerosol weighting, only when requested                                                     |
    //   memory   : workspace buffers reused when this route allows                                            |
    //                                                                                                         |
    // calls                                                                                                   |
    //   buildLayerMatrices                                                                                    |
    //   propagateScatteringOrders                                                                             |
    //   integrateReflectance                                                                                  |
    //                                                                                                         |
    // math                                                                                                    |
    //   total reflectance += Fourier weight * Fourier reflectance term                                        |
    //                                                                                                         |
    //   Fourier weight                                                                                        |
    //     = 1                                      when m = 0                                                 |
    //     = 2 * cos(m * relative_azimuth)          when m > 0                                                 |
    //                                                                                                         |
    //   m : Fourier index                                                                                     |
    // --------------------------------------------------------------------------------------------------------|
```

Use sections only when they help. Good sections are `hot path`, `calls`, and
`math`.

## Value Blocks

When a block chooses one value from several paths, name the block after the
choice. Avoid `blk` for non-trivial decisions.

```zig
const phase_limit = choose_phase_limit: {
    if (has_cached_limit) break :choose_phase_limit cached_limit;
    if (has_grid_limit) break :choose_phase_limit grid_limit;
    break :choose_phase_limit layer_limit;
};
```

Good labels start with the job: `choose_`, `build_`, `find_`, `compute_`,
`reuse_`, or `load_`. Keep `blk` only for tiny local blocks where the label
would not make the code clearer.

## Math

Write formulas like a person will read them:

- `2 * cos(m * relative_azimuth)`, not `2*cos(m*relative_azimuth)`.
- `total += Fourier weight * Fourier reflectance term`, not compressed
  summation notation unless the surrounding code already uses it.
- Use a small ASCII fraction when a ratio is the main idea.
- Define symbols near the formula when the names are not obvious.
- Include units when units matter.
- If a formula follows a reference implementation, name the routine or source
  when known.

## Numbers

- Keep obvious literals inline: `0.0`, `1.0`, `2.0`.
- Name numbers that decide tolerances, pruning, division floors, unit
  conversions, physical constants, or shortcut branches.
- Explain the origin nearby: reference routine, shared cutoff, unit conversion,
  paper/equation, measurement, or numerical guard.
- Prefer names that say the job of the number, such as
  `direction_cosine_floor`.

```zig
// spherical slant optical depth adds this fraction:
//              tau_sample * r_sample
//   -------------------------------------------
//   sqrt(r_sample^2 - r_level^2 * sin(theta)^2)
```

## Layout

Box structs when memory shape matters. Include the struct in the box. Show small
memory slots, unused bits, and footprint in B and KiB.

```zig
// Result -----------------------------------------------------------------------------------------------------|
// Stores one solve before it is copied into the public output.                                                |
//                                                                                                             |
// layout(64-bit)                                                                                              |
// size: 32 B (0.031 KiB), align: 8 B                                                                          |
//                                                                                                             |
// memory                                                                                                      |
// [ 0.. 7] reflectance : f64                                                                                  |
// [ 8..31] jacobian    : [3]f64                                                                               |
//          |----- [ 8..15] jacobian[0]                                                                        |
//          |----- [16..23] jacobian[1]                                                                        |
//          |----- [24..31] jacobian[2]                                                                        |
//                                                                                                             |
// unused bits: 0 padding + 0 bool-storage slack = 0 bits                                                      |
// footprint: per instance = 32 B (0.031 KiB); total = per instance * live instance count                      |
const Result = struct {
    reflectance: f64,
    jacobian: [3]f64,
};
// ------------------------------------------------------------------------------------------------------------|
```

## Instrumentation

Only box real instrumentation code. Leave a blank line before the
`instrumentation:` header. Put trace details next to the trace, not in a hot-path
summary.

```zig
// instrumentation: trace zone: cache lookup ------------------------------------------------------------------|
// captures: setup and cache lookup before the main loop                                                       |
// why: separates cache misses from steady-state compute.                                                      |
const zone = Trace.deepStaticZone(@src(), "path.cache_lookup");
defer zone.end();
// end instrumentation: trace zone: cache lookup --------------------------------------------------------------|
```

## Whitespace

Use blank lines between different ideas: setup, guard, cache branch, major loop,
formula block, and output write. Do not add comments just to create space.
