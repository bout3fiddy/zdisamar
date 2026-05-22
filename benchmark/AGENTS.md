# Benchmarks

- `run_benchmark.py` is the retained truth benchmark. Use it before claiming or committing a performance win; it writes the full tracked `benchmark/results.json`.
- `run_benchmark_fast.py` is a faster production-path canary for agent inner loops. It writes ignored `benchmark/fast_results.json` with a concise schema and can reject a change, but it does not prove a win by itself.
- Keep benchmark controls as constants in the benchmark scripts. Do not add CLI knobs unless the user explicitly asks for parameterization.
- Keep `fast_results.json` small and diffable by eye: status, worker cap, total wall/CPU, and one compact timing/residual object per covered path. Do not add raw samples, prose reports, memory-layout tables, git metadata, or wide retained artifacts to the fast payload.
- Keep the fast canary on public production paths: ReleaseFast native sync, session/no-session forward, selected fast-mode spectra scenes, and selected OE retrieval cases. Do not substitute isolated kernel microbenchmarks for this gate.
- Leaf or kernel benchmark wins are exploratory. Treat them as unproven until a public-path benchmark and caller-level evidence agree.
