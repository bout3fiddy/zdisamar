# 08. Assembly Notes

Assembly-level inspection is useful only after the trace has named a primitive worth inspecting.

For the current trace, the candidates are:

```text
smul_12x10
qseriesKnownNonzeroProduct / qseriesFromProduct
smulAddSemul3_12
dotGaussPair
```

The ReleaseFast build inlines much of this code, so function-symbol inspection alone is not a reliable attribution method. The practical path is:

1. use the trace counters to pick a primitive;
2. use `zig build bench` to isolate it;
3. use a debug or noinline research build only when the assembly for that primitive needs to be read directly;
4. confirm any assembly-level change against the full trace, because the full wall is dominated by repetition counts.

Useful commands:

```sh
zig build bench
zig build -Dtrace-optimize=Debug labos-bottleneck-trace-bin
xcrun llvm-objdump -d --demangle zig-out/bin/labos-bottleneck-trace
```

The current evidence does not justify an assembly-first rewrite. The larger question is still whether the exact O2 A route can reduce the number of wavelength, Fourier, layer, doubling, or order iterations without changing the result.
