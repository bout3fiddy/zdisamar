# Parity Harness

The parity harness is separate from the product API. It keeps the retained
DISAMAR comparison workflow available without shaping the core O2A package
around vendored global-state or file-driven execution.

Useful commands:

```bash
zig build test-validation-o2a
zig build test-validation-o2a-vendor
zig build test-validation-o2a-vendor-line-list
zig build test-validation-o2a-plot-bundle
```

Tracked plot bundle refreshes should use:

```bash
zig build o2a-plot-bundle
```

The tracked plot bundle uses the committed vendor reference in `validation/`.
