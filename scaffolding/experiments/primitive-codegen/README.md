# Primitive Codegen Harness

This folder is a research-only assembly inspection harness. It is deliberately
kept under `scaffolding/reports/performance/forward/` so it cannot become part of the
normal forward model, the LABOS trace build, or validation infrastructure.

The Zig program mirrors the fixed-shape LABOS primitive loops with deterministic mock matrices:

- `codegen_smul12x10`
- `codegen_smul_add_semul3_12`
- `codegen_qseries_nonzero_12x10`
- `codegen_dot_gauss_pair`

Run it from the repository root with:

```sh
scaffolding/experiments/primitive-codegen/run-primitive-codegen.sh
```

The retained compact outputs are written beside the harness under `primitive-codegen/outputs/`:

- `timings.csv`
- `codegen-summary.md`

The script also regenerates `bench-primitives.asm` and one extracted `codegen_*.asm` file per inspected primitive for local inspection. Those disassembly files are intentionally ignored because they are large and fully reproducible from the harness.

These outputs answer a narrower question than the full LABOS trace: once the trace has named an expensive primitive class, what does the generated machine code for that primitive shape look like, and which operation classes dominate the isolated loop?
