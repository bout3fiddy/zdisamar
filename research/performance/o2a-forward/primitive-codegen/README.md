# Primitive Codegen Evidence

This folder keeps retained outputs from the earlier research-only assembly
inspection harness. The executable harness was tied to the retired
source-specific build surface and was removed during the Rust port cleanup.

The retained outputs cover these fixed-shape LABOS primitive loops:

- `codegen_smul12x10`
- `codegen_smul_add_semul3_12`
- `codegen_qseries_nonzero_12x10`
- `codegen_dot_gauss_pair`

The retained compact outputs live under `primitive-codegen/outputs/`:

- `timings.csv`
- `codegen-summary.md`

These outputs answer a narrower question than the full LABOS trace: once the trace has named an expensive primitive class, what does the generated machine code for that primitive shape look like, and which operation classes dominate the isolated loop?
