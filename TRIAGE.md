# Triage Notes

## Zig 0.16 Toolchain Regression

Status: do not treat Zig 0.16.0 as a consequence-free upgrade for zdisamar
ReleaseFast builds.

Observed while testing the 0.15.2 to 0.16.0 migration on 2026-06-05. The
migration is source-compatible after API fixes, but the generated code changes
enough to affect the forward model. The root cause is in the Zig compiler
optimization pipeline, not in mutexes, work partitioning, or Jacobian-only code.

### Exact Compiler Change

Zig 0.15.2 enables LLVM loop vectorization in optimized builds:

```cpp
pipeline_opts.LoopVectorization = !options->is_debug;
```

Zig 0.16.0 disables it globally:

```cpp
pipeline_opts.LoopVectorization = false; // https://github.com/llvm/llvm-project/issues/186922
```

The tested Zig 0.17.0-dev.690 source still had the same global disable.
Official Codeberg master was also checked on 2026-06-05 at
`5434f85c47f6412a8d5faf681419c15533bb388c` and still had the same setting. The
compiler comment points at an LLVM miscompilation workaround, so this is an
intentional compiler-side safety tradeoff, not an accidental local flag.

### Product Path Affected

The measured regression is in the forward-model LABOS path:

```text
prefetchSimulationPlan
  -> prefetchForwardSamples
  -> computeForwardSampleAtWavelengthWithScratch
  -> LABOS rt_layer_build
  -> calcRTlayersIntoWithBasisTimed
  -> doDouble12x10
  -> doDouble12x10Step
  -> qseriesKnownNonzeroProductInto
  -> qseriesFromProduct12x10Into
```

The hot source loop is the fixed 10x10 q-series triangular solve in
`src/rtm/matrix_12x10.zig`:

```zig
for (0..i) |j| s -= one_minus_ab_gg[row_offset + j] * y[j];
for (ii + 1..10) |j| s -= one_minus_ab_gg[row_offset + j] * x[j];
x[ii] = s * inverse_diag[ii];
```

This is forward-model work. It is not limited to Jacobian calculations. The
forward path reaches it while constructing layer reflectance/transmittance
during fixed 12x10 LABOS layer doubling.

### Evidence

The focused q-series reproducer mirrors only the two triangular-solve loops.
With Zig 0.15.2, optimized IR contains vector operations such as
`fmul <2 x double>` and `fsub <2 x double>`, and the AArch64 assembly contains
paired operations such as `fmul.2d` and `fsub.2d`.

With Zig 0.16.0, the same source emits scalar `fmul double` and `fsub double`
for the same loop shape. Running the Zig 0.16 unoptimized IR through LLVM 21
with loop vectorization enabled restores the `<2 x double>` operations; running
the same IR with loop vectorization disabled preserves the scalar form. That
isolates the difference to LLVM loop-vectorization being disabled by Zig 0.16.

In the product `doDouble12x10` IR, debug-source mapping points the lost vector
operations back to the same lines in `matrix.zig`. The fixed helper bodies
around the q-series path, such as the straight fixed matrix multiply/add
kernels, did not show equivalent normalized instruction-stream changes. The
regression mechanism is the scalarized q-series triangular solve inlined into
the measured layer-doubling path.

Trace attribution is useful for locating the work, but trace-enabled binaries
must not be used as product timing. The retained trace evidence showed
`fixed_qseries_work` under `rt_layer_doubling` at high call count, which explains
why a small fixed-size loop regression is visible in the full forward model.

### Consequence

Stock Zig 0.16.0 gives the project newer Zig APIs and compiler fixes, but also
removes a vectorization optimization that this LABOS hot path was relying on.
The upgrade therefore has a real ReleaseFast performance cost unless we add a
mitigation or accept slower forward-model builds.

The same warning applies to any later Zig snapshot until the official upstream
source in Codeberg `src/zig_llvm.cpp` again enables loop vectorization for
optimized builds and the retained forward benchmarks confirm parity.

### Workaround Options

1. Keep Zig 0.15.2 for product ReleaseFast builds until upstream re-enables loop
   vectorization or we have a local mitigation. This is the lowest engineering
   risk and preserves current performance.

2. Use Zig 0.16.0 only where the new APIs are needed, but keep the release
   compiler pinned to 0.15.2. This avoids the runtime regression but creates a
   two-toolchain maintenance burden because the migrated branch no longer builds
   cleanly with 0.15.2 without compatibility work.

3. Build a patched Zig 0.16.0 or 0.17-dev compiler that restores optimized loop
   vectorization. This is the most direct performance experiment, but it opts
   out of Zig's LLVM miscompilation workaround. It needs full correctness gates,
   DISAMAR residual checks, and retained benchmarks before it can be trusted.

4. Rewrite the affected tiny fixed kernels so they do not depend on LLVM's loop
   vectorizer. For this case that likely means explicit `@Vector(2, f64)` or
   carefully split fixed-size arithmetic in the q-series triangular solve. This
   keeps stock Zig 0.16, but it increases source complexity in a numerically
   sensitive path and must be justified by full workload timing.

5. Compile a small external helper for the q-series kernel with a toolchain that
   still vectorizes the loop, then call it from Zig. This should be treated as a
   last resort because it adds ABI and build-system complexity around a core RTM
   kernel.

6. Wait for upstream Zig to re-enable loop vectorization after the LLVM issue is
   fixed, then rerun the retained benchmark and focused codegen checks. Do not
   assume a newer Zig snapshot has fixed this; inspect official Codeberg
   `src/zig_llvm.cpp` first.

Any accepted workaround needs the same gate: `zig build check`, relevant
validation or DISAMAR residuals, retained forward benchmark timing, and focused
codegen proof on `qseriesFromProduct12x10Into` or its inlined caller.
