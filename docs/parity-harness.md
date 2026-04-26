# Parity Harness

The parity harness is separate from the product API. It keeps the retained
DISAMAR comparison workflow available without shaping the core O2A package
around vendored global-state or file-driven execution.

Useful commands:

```bash
zig build test-validation-o2a
zig build test-validation-o2a-vendor
zig build test-validation-o2a-function-diff
zig build o2a-function-diff
zig build o2a-parity-diagnostics
```

`scripts/testing_harness/o2a_function_trace.zig` and
`scripts/testing_harness/build_options_test_support.zig` are harness inputs
used by `scripts/testing_harness/o2a_function_diff.py`; they are intentionally
not product build roots.

Tracked plot bundle refreshes should use:

```bash
zig build o2a-plot-bundle
```

That command uses the committed vendor reference unless
The tracked plot bundle uses the committed vendor reference in `validation/`.
