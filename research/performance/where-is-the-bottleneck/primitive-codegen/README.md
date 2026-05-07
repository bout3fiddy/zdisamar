# Primitive Codegen Harness

This folder is a research-only assembly inspection harness. It is deliberately kept under `research/performance/where-is-the-bottleneck/` so it cannot become part of the normal forward model, the LABOS trace build, or validation infrastructure.

The Zig program mirrors the fixed-shape LABOS primitive loops with deterministic mock matrices:

- `codegen_smul12x10`
- `codegen_smul_add_semul3_12`
- `codegen_qseries_nonzero_12x10`
- `codegen_dot_gauss_pair`

Run it from the repository root with:

```sh
research/performance/where-is-the-bottleneck/run-primitive-codegen.sh
```

The retained outputs are written beside the harness under `primitive-codegen/outputs/`:

- `timings.csv`
- `bench-primitives.asm`
- `codegen-summary.md`
- one extracted `codegen_*.asm` file per inspected primitive

These outputs answer a narrower question than the full LABOS trace: once the trace has named an expensive primitive class, what does the generated machine code for that primitive shape look like, and which operation classes dominate the isolated loop?
