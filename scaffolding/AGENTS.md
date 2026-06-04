# Scaffolding

- Use this tree for retained construction tooling: instrumentation harnesses, capture scripts, exploratory kernels, and performance notes.
- Keep product code under `src/forward_model/` limited to narrow instrumentation facades. Do not put capture scripts, file formats, report generation, or profiler setup in RTM routines.
- Generated telemetry, perturbation, and raw trace output should go under `out/` unless a compact summary is intentionally retained under `scaffolding/instrumentation/trace/evidence/`.
- Do not use scaffolding outputs as contract evidence. Run `benchmark/` and `validation/` gates when the claim is performance or scientific correctness.
- `scaffolding/experiments/` is for exploratory kernels and codegen probes, not asserting tests.
